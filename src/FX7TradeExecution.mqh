bool OpenManagedPosition(const int symbol_idx,
                         const int dir,
                         const FXRCExecutionSnapshot &snapshot)
{
   string symbol = g_symbols[symbol_idx];
   FXRCTradePlan plan;
   ResetTradePlan(plan);
   string reason;
   if(!BuildTradePlan(symbol_idx, symbol, dir, g_atr_pct[symbol_idx], snapshot, plan, reason))
   {
      PrintFormat("Open skipped on %s: %s", symbol, reason);
      return false;
   }

   PrintFormat("FXRC %s entry plan on %s: volume=%.2f risk=%.2f cash notional=%.2f EUR target_risk=%.3f%% score=%.3f vol_mult=%.3f cov_mult=%.3f",
               EnumToString(Trade_Model),
               symbol,
               plan.volume,
               plan.risk_cash,
               plan.notional_eur,
               plan.target_risk_pct,
               plan.sizing_score,
               plan.volatility_multiplier,
               plan.covariance_multiplier);

   ENUM_ORDER_TYPE_FILLING filling;
   if(!ResolveFillingType(symbol, filling))
   {
      PrintFormat("Open skipped on %s: unable to resolve a valid filling mode.", symbol);
      return false;
   }

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = plan.symbol;
   request.volume = plan.volume;
   request.type = (dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   request.price = plan.entry_price;
   request.magic = InpMagicNumber;
   request.sl = plan.stop_price;
   request.tp = 0.0;
   request.deviation = InpSlippagePoints;
   request.type_filling = filling;
   request.type_time = ORDER_TIME_GTC;
   request.comment = "FXRC entry";

   MqlTradeResult result;
   if(!SendTradeRequestWithRetry(request, "entry", true, result))
      return false;

   QueueManagedStateVerification(symbol, dir, "entry");
   ProcessPendingTradeVerifications(true);

   if(!ManagedStateMatchesExpectation(symbol, dir))
   {
      int actual_dir, actual_count;
      double actual_volume;
      bool mixed;
      GetManagedPositionState(symbol, actual_dir, actual_count, actual_volume, mixed);

      int idx = FindTrackedSymbolIndex(symbol);
      int symbol_active_orders = (idx >= 0 ? g_exec_symbol_state[idx].account_active_orders : 0);

      if((!mixed && actual_count >= 1 && actual_dir == dir) || symbol_active_orders > 0)
      {
         PrintFormat("Entry verification is pending on %s after dispatch; current state dir=%d count=%d mixed=%s active=%d.",
                     symbol, actual_dir, actual_count, (mixed ? "true" : "false"), symbol_active_orders);
         RecordBacktestEntryTime(SafeNow());
         return true;
      }
   }

   RecordBacktestEntryTime(SafeNow());
   return true;
}

bool BuildTradePlan(const int symbol_idx,
                    const string symbol,
                    const int dir,
                    const double atr_pct,
                    const FXRCExecutionSnapshot &snapshot,
                    FXRCTradePlan &plan,
                    string &reason)
{
   ResetTradePlan(plan);
   plan.symbol = symbol;
   plan.dir = dir;
   reason = "";

   if(symbol_idx < 0 || symbol_idx >= g_num_symbols)
   {
      reason = "symbol index is invalid";
      return false;
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= EPS())
   {
      reason = "equity unavailable";
      return false;
   }

   if(!BuildProtectiveStop(symbol, dir, atr_pct, plan.entry_price, plan.stop_price))
   {
      reason = "failed to build protective stop";
      return false;
   }

   double one_lot_notional_eur = 0.0;
   if(!EstimateNotionalEUR(symbol, 1.0, one_lot_notional_eur) || one_lot_notional_eur <= EPS())
   {
      reason = "EUR notional conversion unavailable";
      return false;
   }

   double risk_per_lot = 0.0;
   ENUM_ORDER_TYPE order_type = (dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!OrderCalcProfit(order_type, symbol, 1.0, plan.entry_price, plan.stop_price, risk_per_lot))
   {
      reason = "OrderCalcProfit failed for stop risk";
      return false;
   }
   risk_per_lot = MathAbs(risk_per_lot);
   if(risk_per_lot <= EPS())
   {
      reason = "risk per lot <= 0";
      return false;
   }

   double target_volume = 0.0;
   if(IsModernTradeModel())
   {
      double sizing_score = 0.0;
      double vol_mult = 1.0;
      double cov_mult = 1.0;
      double target_risk_pct = ModernTargetRiskPct(symbol_idx, dir, atr_pct, sizing_score, vol_mult, cov_mult);
      double target_risk_cash = equity * target_risk_pct / 100.0;
      if(target_risk_cash <= EPS())
      {
         reason = "modern target risk cash <= 0";
         return false;
      }

      target_volume = target_risk_cash / risk_per_lot;
      plan.target_risk_pct = target_risk_pct;
      plan.sizing_score = sizing_score;
      plan.volatility_multiplier = vol_mult;
      plan.covariance_multiplier = cov_mult;
   }
   else
   {
      target_volume = ReferenceEURNotional() / one_lot_notional_eur;
      plan.target_risk_pct = InpRiskPerTradePct;
      plan.sizing_score = 1.0;
      plan.volatility_multiplier = 1.0;
      plan.covariance_multiplier = 1.0;
   }

   if(target_volume <= 0.0)
   {
      reason = "target volume <= 0";
      return false;
   }

   double cap_volume = target_volume;

   double per_trade_risk_cash = equity * InpRiskPerTradePct / 100.0;
   cap_volume = MathMin(cap_volume, per_trade_risk_cash / risk_per_lot);

   double risk_room_cash = equity * InpMaxPortfolioRiskPct / 100.0 - snapshot.open_risk_cash;
   if(risk_room_cash <= EPS())
   {
      reason = "portfolio risk cap reached";
      return false;
   }
   cap_volume = MathMin(cap_volume, risk_room_cash / risk_per_lot);

   string account_ccy = AccountInfoString(ACCOUNT_CURRENCY);
   double equity_eur = 0.0;
   if(!TryConvertCash(account_ccy, "EUR", equity, equity_eur))
   {
      reason = "currency conversion unavailable for EUR exposure normalization";
      return false;
   }
   double exposure_room_eur = equity_eur * InpMaxPortfolioExposurePct / 100.0 - snapshot.open_exposure_eur;
   if(exposure_room_eur <= EPS())
   {
      reason = "exposure cap reached";
      return false;
   }
   cap_volume = MathMin(cap_volume, exposure_room_eur / one_lot_notional_eur);

   double margin_per_lot = 0.0;
   if(!OrderCalcMargin(order_type, symbol, 1.0, plan.entry_price, margin_per_lot))
   {
      reason = "OrderCalcMargin failed";
      return false;
   }
   if(margin_per_lot > EPS())
   {
      double margin_room_cash = equity * InpMaxMarginUsagePct / 100.0 - snapshot.current_margin_cash;
      if(margin_room_cash <= EPS())
      {
         reason = "margin usage cap reached";
         return false;
      }
      cap_volume = MathMin(cap_volume, margin_room_cash / margin_per_lot);
   }

   double normalized = NormalizeVolume(symbol, cap_volume);
   double minv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   if(normalized < minv - EPS())
   {
      reason = "normalized volume below broker minimum";
      return false;
   }

   plan.volume = normalized;
   plan.risk_cash = risk_per_lot * plan.volume;
   plan.notional_eur = one_lot_notional_eur * plan.volume;
   plan.margin_cash = margin_per_lot * plan.volume;

   if(IsModernTradeModel())
      plan.target_risk_pct = 100.0 * plan.risk_cash / MathMax(equity, EPS());

   return ValidateTradePlan(plan, reason);
}

bool ValidateTradePlan(const FXRCTradePlan &plan, string &reason)
{
   reason = "";

   if(StringLen(plan.symbol) == 0)
   {
      reason = "trade plan has empty symbol";
      return false;
   }
   if(plan.dir != 1 && plan.dir != -1)
   {
      reason = "trade plan direction is invalid";
      return false;
   }
   if(plan.volume <= EPS())
   {
      reason = "trade plan volume is not tradable";
      return false;
   }
   if(plan.stop_price <= EPS())
   {
      reason = "trade plan stop price is invalid";
      return false;
   }
   if(plan.entry_price <= EPS())
   {
      reason = "trade plan entry price is invalid";
      return false;
   }

   return true;
}

double ModernTargetRiskPct(const int idx, const int dir, const double atr_pct, double &score_out, double &vol_mult_out, double &cov_mult_out)
{
   score_out = ModernSizingScore(idx, dir, atr_pct);
   vol_mult_out = ModernVolatilityMultiplier(atr_pct);
   cov_mult_out = ActivePortfolioCorrelationPenalty(idx, dir);

   double target_risk_pct = InpModernBaseTargetRiskPct
                          * (0.35 + 0.65 * score_out)
                          * vol_mult_out
                          * cov_mult_out;

   target_risk_pct = MathMax(target_risk_pct, InpModernMinTargetRiskPct);
   target_risk_pct = MathMin(target_risk_pct, InpRiskPerTradePct);
   return target_risk_pct;
}

double ModernVolatilityMultiplier(const double atr_pct)
{
   if(atr_pct <= EPS())
      return 1.0;

   return Clip(InpModernTargetATRPct / atr_pct, InpModernVolAdjustMin, InpModernVolAdjustMax);
}

double ModernSizingScore(const int idx, const int dir, const double atr_pct)
{
   if(idx < 0 || idx >= g_num_symbols)
      return 0.0;

   double entry_threshold = MathMax(BuildEntryThresholdDirectional(idx, dir), MathMax(InpBaseEntryThreshold, 0.01));
   double abs_s = MathAbs(g_S[idx]);
   double excess_strength = MathMax(0.0, abs_s - entry_threshold);
   double threshold_edge = TanhLikePositive(excess_strength / MathMax(entry_threshold, 0.01));
   double confidence = Clip(g_Conf[idx], 0.0, 1.0);
   double regime = Clip(g_G[idx], 0.0, 1.0);
   double exec_gate = Clip(DirectionalExecGate(idx, dir), 0.0, 1.0);
   double novelty = Clip(g_Omega[idx] / MathMax(InpNoveltyCap, 1.0), 0.0, 1.0);
   double forecast_to_risk = TanhLikePositive(abs_s / MathMax(atr_pct * InpModernForecastRiskATRScale, 0.01));

   return Clip(0.28 * threshold_edge
             + 0.22 * confidence
             + 0.18 * regime
             + 0.16 * exec_gate
             + 0.10 * forecast_to_risk
             + 0.06 * novelty, 0.0, 1.0);
}

double ActivePortfolioCorrelationPenalty(const int idx, const int dir)
{
   if(idx < 0 || idx >= g_num_symbols)
      return 1.0;

   double positive_sum = 0.0;
   int count = 0;

   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(!IsSelectedFXRCPosition())
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      int other_idx = FindTrackedSymbolIndex(symbol);
      if(other_idx < 0 || other_idx == idx)
         continue;

      int other_dir = PositionDirFromType(PositionGetInteger(POSITION_TYPE));
      if(other_dir == 0)
         continue;

      double rho = g_corr_eff[MatIdx(idx, other_idx, g_num_symbols)];
      double same_way_corr = (double)(dir * other_dir) * rho;
      if(same_way_corr > 0.0)
      {
         positive_sum += same_way_corr;
         count++;
      }
   }

   if(count <= 0)
      return 1.0;

   double avg_positive_corr = positive_sum / (double)count;
   return Clip(1.0 - 0.60 * avg_positive_corr, InpModernCovariancePenaltyFloor, 1.0);
}

void CloseAllManagedPositions(const string reason)
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(!IsSelectedFXRCPosition())
         continue;

      CloseManagedPositionTicket(ticket, reason);
   }
}

bool CleanupUnexpectedManagedPendingOrders(const string reason)
{
   int pending = CountManagedPendingOrders();
   if(pending <= 0)
      return false;

   PrintFormat("FXRC market-order mode detected %d unexpected managed pending order(s). Removing them. reason=%s",
               pending,
               reason);
   DeleteAllManagedPendingOrders(reason);
   return true;
}

bool DeleteAllManagedPendingOrders(const string reason)
{
   ulong tickets[];
   int count = CollectManagedPendingOrders(tickets);
   if(count <= 0)
      return true;

   bool ok = true;
   for(int i=0; i<count; ++i)
   {
      if(!DeleteManagedPendingOrder(tickets[i], reason))
         ok = false;
   }

   return (ok && CountManagedPendingOrders() == 0);
}

bool CloseManagedPositionsForSymbol(const string symbol, const string reason)
{
   ulong tickets[];
   int count = CollectManagedTickets(symbol, tickets);
   if(count <= 0)
      return true;

   bool ok = true;
   for(int i=0; i<count; ++i)
   {
      if(!CloseManagedPositionTicket(tickets[i], reason))
         ok = false;
   }

   if(!ok)
      return false;

   if(VerifyManagedState(symbol, 0))
      return true;

   PrintFormat("Close verification is pending on %s after %s. Further actions on the symbol will wait for trade-event confirmation.",
               symbol, reason);
   return false;
}

bool DeleteManagedPendingOrder(const ulong ticket, const string reason)
{
   if(ticket == 0 || !OrderSelect(ticket) || !IsSelectedFXRCOrder())
      return false;

   string symbol = OrderGetString(ORDER_SYMBOL);
   if(!IsForexPairSymbol(symbol))
      return false;

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_REMOVE;
   request.order = ticket;
   request.symbol = symbol;
   request.magic = InpMagicNumber;
   request.comment = reason;

   MqlTradeResult result;
   if(!SendTradeRequestWithRetry(request, reason, false, result))
      return false;

   MarkExecutionStateDirty();
   return true;
}

bool CloseManagedPositionTicket(const ulong ticket, const string reason)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsSelectedFXRCPosition())
      return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   if(!IsForexPositionSymbol(symbol))
      return false;

   long type = PositionGetInteger(POSITION_TYPE);
   double volume = PositionGetDouble(POSITION_VOLUME);
   ENUM_ORDER_TYPE close_type = (type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   ENUM_ORDER_TYPE_FILLING filling;
   if(!ResolveFillingType(symbol, filling))
   {
      PrintFormat("Close skipped on %s: unable to resolve a valid filling mode.", symbol);
      return false;
   }

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.position = ticket;
   request.volume = NormalizeVolume(symbol, volume);
   request.type = close_type;
   request.magic = InpMagicNumber;
   request.deviation = InpSlippagePoints;
   request.type_filling = filling;
   request.type_time = ORDER_TIME_GTC;
   request.comment = reason;

   MqlTradeResult result;
   if(!SendTradeRequestWithRetry(request, reason, true, result))
      return false;

   QueueManagedStateVerification(symbol, 0, reason);
   return true;
}

bool BuildProtectiveStop(const string symbol, const int dir, const double atr_pct, double &entry_price, double &stop_price)
{
   MqlTick tick;
   double mid;
   if(!GetMidPrice(symbol, tick, mid))
      return false;

   double distance = MathMax(InpCatastrophicStopATR * atr_pct * mid, MinStopDistancePrice(symbol));
   if(dir > 0)
   {
      entry_price = tick.ask;
      stop_price = NormalizePrice(symbol, tick.bid - distance);
      if(stop_price >= tick.bid - MinStopDistancePrice(symbol))
         stop_price = NormalizePrice(symbol, tick.bid - (MinStopDistancePrice(symbol) + SymbolInfoDouble(symbol, SYMBOL_POINT)));
   }
   else
   {
      entry_price = tick.bid;
      stop_price = NormalizePrice(symbol, tick.ask + distance);
      if(stop_price <= tick.ask + MinStopDistancePrice(symbol))
         stop_price = NormalizePrice(symbol, tick.ask + (MinStopDistancePrice(symbol) + SymbolInfoDouble(symbol, SYMBOL_POINT)));
   }

   return (stop_price > 0.0);
}

double MinStopDistancePrice(const string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   long stops_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_points = (double)MathMax(stops_level, freeze_level);
   return MathMax(min_points * point, point);
}

bool SendTradeRequestWithRetry(MqlTradeRequest &request, const string context, const bool use_check, MqlTradeResult &result)
{
   for(int attempt=0; attempt<=InpTradeRetryCount; ++attempt)
   {
      if(!RefreshRequestPrice(request))
      {
         PrintFormat("%s: failed to refresh quote for %s", context, request.symbol);
         return false;
      }

      if(use_check)
      {
         MqlTradeCheckResult check;
         ZeroMemory(check);
         ResetLastError();
         if(!OrderCheck(request, check))
         {
            PrintFormat("%s: OrderCheck call failed on %s. err=%d volume=%.2f price=%.5f sl=%.5f type=%d filling=%d",
                        context, request.symbol, GetLastError(), request.volume, request.price, request.sl,
                        (int)request.type, (int)request.type_filling);
            return false;
         }
         if(!IsTradeCheckRetcodeSuccess(check.retcode))
         {
            PrintFormat("%s: OrderCheck rejected on %s. retcode=%u comment=%s volume=%.2f price=%.5f sl=%.5f margin_free=%.2f",
                        context, request.symbol, check.retcode, check.comment, request.volume, request.price,
                        request.sl, check.margin_free);
            return false;
         }
      }

      ZeroMemory(result);
      ResetLastError();
      if(OrderSend(request, result) && IsTradeRetcodeSuccess(result.retcode))
         return true;

      PrintFormat("%s: OrderSend failed on %s. retcode=%u comment=%s err=%d volume=%.2f price=%.5f sl=%.5f type=%d",
                  context, request.symbol, result.retcode, result.comment, GetLastError(),
                  request.volume, request.price, request.sl, (int)request.type);
      if(attempt >= InpTradeRetryCount || !IsTradeRetcodeRetryable(result.retcode))
         break;
   }

   return false;
}

void RefreshEntryRequestStop(MqlTradeRequest &request,
                             const MqlTick &tick,
                             const double previous_price,
                             const double previous_stop)
{
   if(request.position != 0 || previous_stop <= 0.0)
      return;
   if(request.type != ORDER_TYPE_BUY && request.type != ORDER_TYPE_SELL)
      return;

   double point = SymbolInfoDouble(request.symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;

   double min_distance = MinStopDistancePrice(request.symbol);
   double entry_distance = 0.0;
   if(previous_price > 0.0)
      entry_distance = MathAbs(previous_price - previous_stop);
   if(entry_distance <= EPS())
   {
      if(request.type == ORDER_TYPE_BUY)
         entry_distance = MathAbs(tick.ask - previous_stop);
      else
         entry_distance = MathAbs(previous_stop - tick.bid);
   }

   entry_distance = MathMax(entry_distance, min_distance + point);
   if(request.type == ORDER_TYPE_BUY)
   {
      double max_valid_stop = tick.bid - (min_distance + point);
      request.sl = NormalizePrice(request.symbol, request.price - entry_distance);
      if(request.sl > max_valid_stop)
         request.sl = NormalizePrice(request.symbol, max_valid_stop);
   }
   else
   {
      double min_valid_stop = tick.ask + (min_distance + point);
      request.sl = NormalizePrice(request.symbol, request.price + entry_distance);
      if(request.sl < min_valid_stop)
         request.sl = NormalizePrice(request.symbol, min_valid_stop);
   }
}

bool RefreshRequestPrice(MqlTradeRequest &request)
{
   if(request.action != TRADE_ACTION_DEAL)
      return true;

   MqlTick tick;
   double mid;
   if(!GetMidPrice(request.symbol, tick, mid))
      return false;

   double previous_price = request.price;
   double previous_stop = request.sl;
   request.price = (request.type == ORDER_TYPE_BUY ? tick.ask : tick.bid);
   RefreshEntryRequestStop(request, tick, previous_price, previous_stop);
   return true;
}

bool ResolveFillingType(const string symbol, ENUM_ORDER_TYPE_FILLING &filling)
{
   long filling_mode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   ENUM_SYMBOL_TRADE_EXECUTION exec_mode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);

   // ORDER_FILLING_RETURN is not valid for market execution requests.
   if(exec_mode == SYMBOL_TRADE_EXECUTION_MARKET)
   {
      if((filling_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK || filling_mode == 0)
      {
         filling = ORDER_FILLING_FOK;
         return true;
      }
      if((filling_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      {
         filling = ORDER_FILLING_IOC;
         return true;
      }
      return false;
   }

   if((filling_mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
   {
      filling = ORDER_FILLING_FOK;
      return true;
   }
   if((filling_mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
   {
      filling = ORDER_FILLING_IOC;
      return true;
   }

   filling = ORDER_FILLING_RETURN;
   return true;
}

//------------------------- Execution State And Ownership -------------------------//
void MarkExecutionStateDirty()
{
   g_execution_state_dirty = true;
}

int FindManagedStateVerification(const string symbol)
{
   for(int i=0; i<ArraySize(g_pending_state_verifications); ++i)
   {
      if(g_pending_state_verifications[i].symbol == symbol)
         return i;
   }
   return -1;
}

void RemoveManagedStateVerificationAt(const int idx)
{
   int count = ArraySize(g_pending_state_verifications);
   if(idx < 0 || idx >= count)
      return;

   for(int i=idx; i<count-1; ++i)
      g_pending_state_verifications[i] = g_pending_state_verifications[i + 1];

   ArrayResize(g_pending_state_verifications, count - 1);
}

void MarkPendingVerificationUrgent(const string symbol)
{
   int idx = FindManagedStateVerification(symbol);
   if(idx < 0)
      return;

   g_pending_state_verifications[idx].next_check_time = 0;
}

void QueueManagedStateVerification(const string symbol, const int expected_dir, const string context)
{
   if(!IsForexPairSymbol(symbol))
      return;

   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();

   int idx = FindManagedStateVerification(symbol);
   if(idx < 0)
   {
      int new_size = ArraySize(g_pending_state_verifications) + 1;
      ArrayResize(g_pending_state_verifications, new_size);
      idx = new_size - 1;
   }

   g_pending_state_verifications[idx].symbol = symbol;
   g_pending_state_verifications[idx].expected_dir = expected_dir;
   g_pending_state_verifications[idx].attempts = 0;
   g_pending_state_verifications[idx].created_time = now;
   g_pending_state_verifications[idx].next_check_time = now;
   g_pending_state_verifications[idx].context = (StringLen(context) > 0 ? context : "managed state");
   MarkExecutionStateDirty();
}

bool ManagedStateMatchesExpectation(const string symbol, const int expected_dir)
{
   int dir = 0;
   int count = 0;
   double volume = 0.0;
   bool mixed = false;
   GetManagedPositionState(symbol, dir, count, volume, mixed);

   if(expected_dir == 0)
      return (count == 0);

   return (!mixed && count == 1 && dir == expected_dir);
}

void ProcessPendingTradeVerifications(const bool force_refresh)
{
   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();

   bool needs_refresh = force_refresh || g_execution_state_dirty;
   for(int i=0; i<ArraySize(g_pending_state_verifications) && !needs_refresh; ++i)
   {
      if(g_pending_state_verifications[i].next_check_time <= now)
         needs_refresh = true;
   }

   if(!needs_refresh)
      return;

   FXRCExecutionSnapshot snapshot;
   RefreshExecutionSnapshot(snapshot);
   g_execution_state_dirty = false;

   for(int i=ArraySize(g_pending_state_verifications)-1; i>=0; --i)
   {
      FXRCManagedStateVerification verification = g_pending_state_verifications[i];
      if(ManagedStateMatchesExpectation(verification.symbol, verification.expected_dir))
      {
         if(verification.attempts > 0)
         {
            PrintFormat("FXRC execution verification completed on %s after %d timed check(s). context=%s expected_dir=%d",
                        verification.symbol, verification.attempts, verification.context, verification.expected_dir);
         }
         RemoveManagedStateVerificationAt(i);
         continue;
      }

      if(verification.next_check_time > now)
         continue;

      g_pending_state_verifications[i].attempts++;
      if(g_pending_state_verifications[i].attempts >= InpTradeVerifyAttempts)
      {
         PrintFormat("FXRC execution verification timed out on %s after %d timed check(s). context=%s expected_dir=%d",
                     verification.symbol, g_pending_state_verifications[i].attempts, verification.context, verification.expected_dir);
         RemoveManagedStateVerificationAt(i);
         continue;
      }

      g_pending_state_verifications[i].next_check_time = now + 1;
   }
}

bool VerifyManagedState(const string symbol, const int expected_dir)
{
   ProcessPendingTradeVerifications(true);
   if(ManagedStateMatchesExpectation(symbol, expected_dir))
   {
      int idx = FindManagedStateVerification(symbol);
      if(idx >= 0)
         RemoveManagedStateVerificationAt(idx);
      return true;
   }

   int idx = FindManagedStateVerification(symbol);
   if(idx < 0)
      QueueManagedStateVerification(symbol, expected_dir, "managed state");
   else
   {
      g_pending_state_verifications[idx].expected_dir = expected_dir;
      g_pending_state_verifications[idx].next_check_time = 0;
      MarkExecutionStateDirty();
   }

   return false;
}

void GetManagedPositionState(const string symbol, int &dir, int &count, double &volume, bool &mixed)
{
   dir = 0;
   count = 0;
   volume = 0.0;
   mixed = false;
   if(!IsForexPairSymbol(symbol))
      return;

   int seen_dir = 0;

   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(!IsSelectedFXRCPosition())
         continue;

      string position_symbol = PositionGetString(POSITION_SYMBOL);
      if(position_symbol != symbol || !IsForexPositionSymbol(position_symbol))
         continue;

      int pdir = PositionDirFromType(PositionGetInteger(POSITION_TYPE));

      count++;
      volume += PositionGetDouble(POSITION_VOLUME);
      if(seen_dir == 0)
         seen_dir = pdir;
      else if(seen_dir != pdir)
         mixed = true;
   }

   dir = (mixed ? 0 : seen_dir);
}

int CountManagedPendingOrders()
{
   ulong tickets[];
   return CollectManagedPendingOrders(tickets);
}

int CountManagedOpenPositions()
{
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(IsSelectedFXRCPosition())
         count++;
   }
   return count;
}

int CollectManagedPendingOrdersForSymbol(const string symbol, ulong &tickets[])
{
   ArrayResize(tickets, 0);
   if(!IsForexPairSymbol(symbol))
      return 0;

   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(!IsSelectedFXRCOrder())
         continue;

      string order_symbol = OrderGetString(ORDER_SYMBOL);
      if(order_symbol != symbol || !IsForexPairSymbol(order_symbol))
         continue;

      int new_size = ArraySize(tickets) + 1;
      ArrayResize(tickets, new_size);
      tickets[new_size - 1] = ticket;
   }

   return ArraySize(tickets);
}

int CollectManagedPendingOrders(ulong &tickets[])
{
   ArrayResize(tickets, 0);

   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(!IsSelectedFXRCOrder())
         continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      if(!IsForexPairSymbol(symbol))
         continue;

      int new_size = ArraySize(tickets) + 1;
      ArrayResize(tickets, new_size);
      tickets[new_size - 1] = ticket;
   }

   return ArraySize(tickets);
}

int CollectManagedTickets(const string symbol, ulong &tickets[])
{
   ArrayResize(tickets, 0);
   if(!IsForexPairSymbol(symbol))
      return 0;

   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(!IsSelectedFXRCPosition())
         continue;

      string position_symbol = PositionGetString(POSITION_SYMBOL);
      if(position_symbol != symbol || !IsForexPositionSymbol(position_symbol))
         continue;

      int new_size = ArraySize(tickets) + 1;
      ArrayResize(tickets, new_size);
      tickets[new_size - 1] = ticket;
   }

   return ArraySize(tickets);
}

void RefreshExecutionSnapshot(FXRCExecutionSnapshot &snapshot)
{
   ResetExecutionSnapshot(snapshot);
   snapshot.current_margin_cash = AccountInfoDouble(ACCOUNT_MARGIN);

   for(int i=0; i<g_num_symbols; ++i)
      ResetSymbolExecutionState(g_exec_symbol_state[i]);

   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(!IsSelectedFXRCPosition())
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(!IsForexPositionSymbol(symbol))
         continue;

      snapshot.account_active_orders++;

      long type = PositionGetInteger(POSITION_TYPE);
      int dir = PositionDirFromType(type);
      double volume = PositionGetDouble(POSITION_VOLUME);
      AccumulateTrackedPositionState(symbol, dir, volume);

      double notional_eur = 0.0;
      if(EstimateNotionalEUR(symbol, volume, notional_eur))
         snapshot.open_exposure_eur += MathAbs(notional_eur);

      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0)
      {
         snapshot.all_protected = false;
         snapshot.open_risk_cash = DBL_MAX / 4.0;
         continue;
      }

      MqlTick tick;
      double mid;
      if(!GetMidPrice(symbol, tick, mid))
      {
         snapshot.all_protected = false;
         snapshot.open_risk_cash = DBL_MAX / 4.0;
         continue;
      }

      double current_price = (type == POSITION_TYPE_BUY ? tick.bid : tick.ask);
      double risk_cash = 0.0;
      ENUM_ORDER_TYPE order_type = (type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      if(!OrderCalcProfit(order_type, symbol, volume, current_price, sl, risk_cash))
      {
         snapshot.all_protected = false;
         snapshot.open_risk_cash = DBL_MAX / 4.0;
         continue;
      }

      if(risk_cash < 0.0)
         snapshot.open_risk_cash += -risk_cash;
   }

   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      if(!IsSelectedFXRCOrder())
         continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      if(!IsForexPairSymbol(symbol))
         continue;

      snapshot.account_active_orders++;
      AccumulateTrackedOrderState(symbol);
   }
}

void AccumulateTrackedOrderState(const string symbol)
{
   int idx = FindTrackedSymbolIndex(symbol);
   if(idx >= 0)
      g_exec_symbol_state[idx].account_active_orders++;
}

void AccumulateTrackedPositionState(const string symbol, const int dir, const double volume)
{
   int idx = FindTrackedSymbolIndex(symbol);
   if(idx < 0)
      return;

   g_exec_symbol_state[idx].count++;
   g_exec_symbol_state[idx].account_active_orders++;
   g_exec_symbol_state[idx].volume += volume;

   if(g_exec_symbol_state[idx].dir == 0)
      g_exec_symbol_state[idx].dir = dir;
   else if(g_exec_symbol_state[idx].dir != dir)
   {
      g_exec_symbol_state[idx].mixed = true;
      g_exec_symbol_state[idx].dir = 0;
   }
}

bool HasManagedExposureOrOrders()
{
   return (CountManagedOpenPositions() > 0 || CountManagedPendingOrders() > 0);
}

bool SymbolHasForeignActiveState(const string symbol)
{
   if(!IsForexPairSymbol(symbol))
      return false;

   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      string position_symbol = PositionGetString(POSITION_SYMBOL);
      if(position_symbol != symbol || !IsForexPositionSymbol(position_symbol))
         continue;

      if(!IsFXRCMagic(PositionGetInteger(POSITION_MAGIC)))
         return true;
   }

   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;

      string order_symbol = OrderGetString(ORDER_SYMBOL);
      if(order_symbol != symbol || !IsForexPairSymbol(order_symbol))
         continue;

      if(!IsFXRCMagic(OrderGetInteger(ORDER_MAGIC)))
         return true;
   }

   return false;
}

bool IsSelectedFXRCOrder()
{
   string symbol = OrderGetString(ORDER_SYMBOL);
   if(!IsForexPairSymbol(symbol))
      return false;

   return IsFXRCMagic(OrderGetInteger(ORDER_MAGIC));
}

bool IsSelectedFXRCPosition()
{
   string symbol = PositionGetString(POSITION_SYMBOL);
   if(!IsForexPositionSymbol(symbol))
      return false;

   return IsFXRCMagic(PositionGetInteger(POSITION_MAGIC));
}

bool IsFXRCOrderOwnedTicket(const ulong ticket)
{
   if(ticket == 0 || !OrderSelect(ticket))
      return false;

   string symbol = OrderGetString(ORDER_SYMBOL);
   if(!IsForexPairSymbol(symbol))
      return false;

   return IsFXRCMagic(OrderGetInteger(ORDER_MAGIC));
}

bool IsFXRCPositionOwnedTicket(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   string symbol = PositionGetString(POSITION_SYMBOL);
   if(!IsForexPositionSymbol(symbol))
      return false;

   return IsFXRCMagic(PositionGetInteger(POSITION_MAGIC));
}

bool IsFXRCMagic(const long magic)
{
   return (magic == InpMagicNumber);
}

