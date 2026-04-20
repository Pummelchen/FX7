// Updates symbol features.
bool UpdateSymbolFeatures(const int i, const bool allow_stale_dependency_values = false)
{
   string sym = g_symbols[i];
   if(ArraySize(g_symbol_history_ready) == g_num_symbols && !g_symbol_history_ready[i])
      return false;

   int bars_needed = SignalBarsNeeded();

   MqlRates rates[];
   int copied = 0;
   string history_reason;
   if(!LoadRatesWindow(sym, InpSignalTF, bars_needed, rates, copied, history_reason))
   {
      if(!MQLInfoInteger(MQL_TESTER) || g_tester_diag_logs < 20)
      {
         Print(history_reason);
      }
      if(MQLInfoInteger(MQL_TESTER))
         g_tester_diag_logs++;
      return false;
   }

   double close[];
   ArrayResize(close, copied);
   ArraySetAsSeries(close, true);
   for(int k=0; k<copied; ++k)
      close[k] = rates[k].close;

   if(close[1] <= 0.0 || close[2] <= 0.0)
      return false;

   g_sigma_short[i] = EWMAStdFromCloses(close, MathMin(g_ret_hist_len, copied - 2), InpVolShortHalfLife);
   g_sigma_long[i]  = EWMAStdFromCloses(close, MathMin(g_ret_hist_len, copied - 2), InpVolLongHalfLife);
   g_atr_pct[i]     = ATRPctFromRates(rates, InpATRWindow);

   double z1 = MathLog(close[1] / close[InpH1 + 1]) / (g_sigma_long[i] * MathSqrt((double)InpH1) + EPS());
   double z2 = MathLog(close[1] / close[InpH2 + 1]) / (g_sigma_long[i] * MathSqrt((double)InpH2) + EPS());
   double z3 = MathLog(close[1] / close[InpH3 + 1]) / (g_sigma_long[i] * MathSqrt((double)InpH3) + EPS());

   z1 = Clip(z1, -6.0, 6.0);
   z2 = Clip(z2, -6.0, 6.0);
   z3 = Clip(z3, -6.0, 6.0);

   g_M[i] = g_w1 * MathTanh(z1 / InpTanhScale)
          + g_w2 * MathTanh(z2 / InpTanhScale)
          + g_w3 * MathTanh(z3 / InpTanhScale);

   g_A[i] = MathAbs(g_w1 * (double)SignD(z1)
                  + g_w2 * (double)SignD(z2)
                  + g_w3 * (double)SignD(z3));

   double net_move = MathAbs(MathLog(close[1] / close[InpERWindow + 1]));
   double path_sum = 0.0;
   for(int sh=1; sh<=InpERWindow; ++sh)
      path_sum += MathAbs(MathLog(close[sh] / close[sh + 1]));
   g_ER[i] = net_move / (path_sum + EPS());

   g_V[i] = g_sigma_short[i] / (g_sigma_long[i] + EPS());

   double zrev = MathLog(close[1] / close[InpShortReversalWindow + 1]) / (g_sigma_long[i] * MathSqrt((double)InpShortReversalWindow) + EPS());
   zrev = Clip(zrev, -6.0, 6.0);
   g_D[i] = MathMax(0.0, -(double)SignD(g_M[i]) * zrev);

   double hh = HighestClose(close, 2, InpBreakoutWindow + 1);
   double ll = LowestClose(close,  2, InpBreakoutWindow + 1);
   double mid = 0.5 * (hh + ll);
   double half_range = 0.5 * MathMax(hh - ll, EPS());
   g_BK[i] = 0.5 * (1.0 + MathTanh(((double)SignD(g_M[i]) * (close[1] - mid)) / half_range));

   g_G[i] = MathPow(MathMax(g_A[i], 0.0), InpGammaA)
          * MathPow(MathMax(g_ER[i], 0.0), InpGammaER)
          * MathExp(-InpGammaV * PosPart(g_V[i] - InpV0))
          * MathExp(-InpGammaD * g_D[i] * PosPart(g_V[i] - InpV0));

   double mid_px;
   if(!GetAnalyticalMidPrice(sym, mid_px))
      return false;

   MqlTick tick;
   double spread_frac = 0.0;
   if(GetMidPrice(sym, tick, mid_px))
      spread_frac = (tick.ask - tick.bid) / MathMax(mid_px, EPS());
   else
   {
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      long spread_points = SymbolInfoInteger(sym, SYMBOL_SPREAD);
      if(point > 0.0 && spread_points > 0.0)
         spread_frac = ((double)spread_points * point) / MathMax(mid_px, EPS());
   }
   double slip_frac = SlippageFracEstimate(sym, spread_frac);
   double total_cost_frac_long = EstimateRoundTripCostFraction(sym, 1, mid_px, spread_frac, slip_frac);
   double total_cost_frac_short = EstimateRoundTripCostFraction(sym, -1, mid_px, spread_frac, slip_frac);
   if(g_conversion_error_active)
      return false;

   double signal_px = close[1];
   if(signal_px <= 0.0)
      signal_px = mid_px;
   // Use the decision timestamp at the new-bar open, not the prior bar's open time.
   datetime signal_time = rates[0].time;
   if(signal_time <= 0)
      signal_time = rates[1].time;

   double carry_signal = 0.0;
   double carry_spread = 0.0;
   datetime carry_macro_date = 0;
   string carry_reason;
   bool carry_ok = true;
   if(CarrySleeveEnabled())
      carry_ok = ComputeCarrySignal(sym, signal_px, signal_time, carry_signal, carry_spread, carry_macro_date, carry_reason);

   if(!carry_ok)
   {
      if(CarrySignalRequiresExternalData())
      {
         if(!allow_stale_dependency_values || !g_symbol_data_ok[i])
         {
            if(!MQLInfoInteger(MQL_TESTER) || g_tester_diag_logs < 20)
               PrintFormat("Carry signal unavailable for %s: %s", sym, carry_reason);
            if(MQLInfoInteger(MQL_TESTER))
               g_tester_diag_logs++;
            return false;
         }

         carry_signal = g_Carry[i];
         carry_spread = g_CarryAnnualSpread[i];
      }
   }
   g_Carry[i] = carry_signal;
   g_CarryAnnualSpread[i] = carry_spread;

   double value_signal = 0.0;
   double value_gap = 0.0;
   double value_proxy_signal = 0.0;
   double value_ppp_signal = 0.0;
   double value_fair_px = 0.0;
   datetime value_macro_date = 0;
   double value_ppp_weight = 0.0;
   double value_reliability = 0.0;
   string value_reason;
   bool value_ok = true;
   if(ValueSleeveEnabled())
      value_ok = ResolveValueSignal(sym, signal_px, signal_time,
                                    value_signal, value_gap, value_proxy_signal, value_ppp_signal,
                                    value_fair_px, value_macro_date, value_ppp_weight, value_reliability, value_reason, g_V[i]);

   if(!value_ok)
   {
      if(ValueSignalRequiresPPPData())
      {
         if(!allow_stale_dependency_values || !g_symbol_data_ok[i])
         {
            if(!MQLInfoInteger(MQL_TESTER) || g_tester_diag_logs < 20)
               PrintFormat("Value signal unavailable for %s: %s", sym, value_reason);
            if(MQLInfoInteger(MQL_TESTER))
               g_tester_diag_logs++;
            return false;
         }

         value_signal = g_Value[i];
         value_gap = g_ValueGap[i];
         value_proxy_signal = g_ValueProxy[i];
         value_ppp_signal = g_ValuePPP[i];
         value_fair_px = g_ValueFairValue[i];
         value_macro_date = g_ValueMacroDate[i];
         value_ppp_weight = g_ValuePPPWeight[i];
         value_reliability = g_ValueReliability[i];
      }
   }
   g_Value[i] = value_signal;
   g_ValueProxy[i] = value_proxy_signal;
   g_ValuePPP[i] = value_ppp_signal;
   g_ValueFairValue[i] = value_fair_px;
   g_ValuePPPWeight[i] = value_ppp_weight;
   g_ValueReliability[i] = value_reliability;
   g_ValueGap[i] = value_gap;
   g_ValueMacroDate[i] = value_macro_date;
   g_CompositeCore[i] = BuildCompositePremiaAlpha(i);

   g_K_long[i] = total_cost_frac_long / (g_atr_pct[i] + EPS());
   g_K_short[i] = total_cost_frac_short / (g_atr_pct[i] + EPS());
   g_Q_long[i] = MathExp(-InpGammaCost * g_K_long[i]);
   g_Q_short[i] = MathExp(-InpGammaCost * g_K_short[i]);
   g_K[i] = MathMax(g_K_long[i], g_K_short[i]);
   g_Q[i] = MathMin(g_Q_long[i], g_Q_short[i]);

   for(int lag=0; lag<g_ret_hist_len; ++lag)
   {
      double r = MathLog(close[lag + 1] / close[lag + 2]);
      g_stdret_hist[i * g_ret_hist_len + lag] = r / (g_sigma_long[i] + EPS());
   }
   NoteSymbolFeatureRefreshSuccess(i);
   return true;
}

// Neutralizes the symbol state for the current model cycle.
void NeutralizeSymbol(const int i)
{
   g_symbol_data_ok[i] = false;
   g_symbol_data_stale[i] = false;
   g_M[i] = g_A[i] = g_ER[i] = g_V[i] = g_D[i] = g_BK[i] = 0.0;
   g_Carry[i] = g_Value[i] = g_CompositeCore[i] = 0.0;
   g_ValueProxy[i] = g_ValuePPP[i] = g_ValueFairValue[i] = g_ValuePPPWeight[i] = g_ValueReliability[i] = 0.0;
   g_CarryAnnualSpread[i] = g_ValueGap[i] = 0.0;
   g_ValueMacroDate[i] = 0;
   g_G[i] = g_K[i] = g_K_long[i] = g_K_short[i] = 0.0;
   g_Q[i] = g_Q_long[i] = g_Q_short[i] = 0.0;
   g_PG[i] = 1.0;
   g_E[i] = 0.0;
   g_Conf[i] = 0.0;
   g_Omega[i] = 1.0;
   g_Rank[i] = 0.0;
   g_theta_in_eff[i] = 0.0;
   g_theta_out_eff[i] = 0.0;
   g_entry_dir_raw[i] = 0;
   g_persist_count[i] = 0;
   g_symbol_feature_failures[i] = 0;

   for(int lag=0; lag<g_ret_hist_len; ++lag)
      g_stdret_hist[i * g_ret_hist_len + lag] = 0.0;
}

// Marks symbol data stale.
void MarkSymbolDataStale(const int i)
{
   if(i < 0 || i >= g_num_symbols)
      return;

   g_symbol_data_ok[i] = true;
   g_symbol_data_stale[i] = true;
   g_symbol_feature_failures[i]++;
   g_entry_dir_raw[i] = 0;
   g_persist_count[i] = 0;
}

// Records symbol feature refresh success.
void NoteSymbolFeatureRefreshSuccess(const int i)
{
   if(i < 0 || i >= g_num_symbols)
      return;

   g_symbol_data_ok[i] = true;
   g_symbol_data_stale[i] = false;
   g_symbol_feature_failures[i] = 0;
   g_symbol_last_feature_success[i] = SafeNow();
}

// Computes an EWMA standard deviation from a newest-first series.
double EWMAStdFromSeriesNewestFirst(const double &series[], const int count, const int half_life)
{
   double lambda = MathExp(-MathLog(2.0) / MathMax(1.0, (double)half_life));
   double var = 0.0;
   bool seeded = false;

   for(int lag = count - 1; lag >= 0; --lag)
   {
      double r = series[lag];
      if(!seeded)
      {
         var = r * r;
         seeded = true;
      }
      else
      {
         var = lambda * var + (1.0 - lambda) * r * r;
      }
   }

   return MathSqrt(MathMax(var, EPS()));
}

// Estimates round trip cost fraction.
double EstimateRoundTripCostFraction(const string symbol,
                                     const int dir,
                                     const double mid_px,
                                     const double spread_frac,
                                     const double slip_frac)
{
   double notional_eur = 0.0;
   if(!EstimateNotionalEUR(symbol, 1.0, notional_eur) || notional_eur <= EPS())
      return spread_frac + 2.0 * slip_frac + InpAssumedRoundTripFeePct;

   double commission_frac = InpCommissionRoundTripPerLotEUR / notional_eur;
   double swap_long_frac = MathAbs(EstimateSwapCashEURPerDay(symbol, 1, 1.0, mid_px)) * InpExpectedHoldingDays / notional_eur;
   double swap_short_frac = MathAbs(EstimateSwapCashEURPerDay(symbol, -1, 1.0, mid_px)) * InpExpectedHoldingDays / notional_eur;
   double swap_frac = DirectionalValue(dir, swap_long_frac, swap_short_frac, MathMax(swap_long_frac, swap_short_frac));

   return spread_frac + 2.0 * slip_frac + InpAssumedRoundTripFeePct + commission_frac + swap_frac;
}

// Estimates swap cash EUR per day.
double EstimateSwapCashEURPerDay(const string symbol, const int dir, const double volume, const double ref_price)
{
   double swap_value = (dir > 0 ? SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG) : SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT));
   ENUM_SYMBOL_SWAP_MODE swap_mode = (ENUM_SYMBOL_SWAP_MODE)SymbolInfoInteger(symbol, SYMBOL_SWAP_MODE);
   string base_ccy = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string quote_ccy = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   string margin_ccy = SymbolInfoString(symbol, SYMBOL_CURRENCY_MARGIN);
   string account_ccy = AccountInfoString(ACCOUNT_CURRENCY);
   double contract = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   switch(swap_mode)
   {
      case SYMBOL_SWAP_MODE_DISABLED:
         return 0.0;

      case SYMBOL_SWAP_MODE_POINTS:
      {
         double price_from = ref_price;
         double price_to = ref_price + swap_value * point;
         double cash_account = 0.0;
         ENUM_ORDER_TYPE order_type = (dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
         if(OrderCalcProfit(order_type, symbol, volume, price_from, price_to, cash_account))
            return ConvertCashToEUR(account_ccy, cash_account);
         return 0.0;
      }

      case SYMBOL_SWAP_MODE_CURRENCY_SYMBOL:
         return ConvertCashToEUR(base_ccy, swap_value * volume);

      case SYMBOL_SWAP_MODE_CURRENCY_MARGIN:
         return ConvertCashToEUR(margin_ccy, swap_value * volume);

      case SYMBOL_SWAP_MODE_CURRENCY_DEPOSIT:
         return ConvertCashToEUR(account_ccy, swap_value * volume);

      case SYMBOL_SWAP_MODE_CURRENCY_PROFIT:
         return ConvertCashToEUR(quote_ccy, swap_value * volume);

      case SYMBOL_SWAP_MODE_INTEREST_CURRENT:
      case SYMBOL_SWAP_MODE_INTEREST_OPEN:
      {
         if(contract <= 0.0 || ref_price <= 0.0)
            return 0.0;

         double yearly_quote_cash = volume * contract * ref_price * (swap_value / 100.0);
         double daily_quote_cash = yearly_quote_cash / 360.0;
         return ConvertCashToEUR(quote_ccy, daily_quote_cash);
      }
   }

   return 0.0;
}

// Estimates slippage as a fraction of price.
double SlippageFracEstimate(const string symbol, const double spread_frac)
{
   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);

   if(StringLen(base) == 3 && StringLen(quote) == 3)
   {
      bool base_major = (base == "USD" || base == "EUR" || base == "JPY" || base == "GBP" || base == "CHF" || base == "AUD" || base == "CAD" || base == "NZD");
      bool quote_major = (quote == "USD" || quote == "EUR" || quote == "JPY" || quote == "GBP" || quote == "CHF" || quote == "AUD" || quote == "CAD" || quote == "NZD");
      return spread_frac * ((base_major && quote_major) ? 0.25 : 0.50);
   }

   return spread_frac * 0.50;
}

// Builds composite premia alpha.
double BuildCompositePremiaAlpha(const int idx)
{
   double w_m, w_c, w_v;
   ComputeCompositeAllocatorWeights(idx, w_m, w_c, w_v);
   // Value is intentionally treated as a slow, reliability-scaled bias in the composite.
   return w_m * g_M[idx] + w_c * g_Carry[idx] + w_v * g_Value[idx];
}

// Computes composite allocator weights.
void ComputeCompositeAllocatorWeights(const int idx, double &w_m, double &w_c, double &w_v)
{
   w_m = InpWeightMomentum;
   w_c = InpWeightCarry;
   w_v = InpWeightValue;
   NormalizePremiaWeights(w_m, w_c, w_v);

   if(!InpUseDynamicAllocator)
      return;

   double momentum_mult = 1.0 + InpAllocatorMomentumBoost * Clip(g_BK[idx], 0.0, 1.0) * MathMax(g_A[idx], 0.0);
   double carry_mult = MathExp(-InpAllocatorCarryVolPenalty * PosPart(g_V[idx] - InpCarryVolCutoff));
   double value_mult = 1.0 + InpAllocatorValueBoost * MathMin(MathAbs(g_Value[idx]), 1.0);

   w_m *= momentum_mult;
   w_c *= carry_mult;
   w_v *= value_mult;
   NormalizePremiaWeights(w_m, w_c, w_v);
}

// Resolves value signal.
bool ResolveValueSignal(const string symbol,
                        const double current_mid_px,
                        const datetime asof_time,
                        double &signal,
                        double &value_gap,
                        double &proxy_signal,
                        double &ppp_signal,
                        double &fair_value,
                        datetime &macro_date,
                        double &ppp_weight,
                        double &reliability,
                        string &reason,
                        const double intraday_vol_ratio)
{
   signal = 0.0;
   value_gap = 0.0;
   proxy_signal = 0.0;
   ppp_signal = 0.0;
   fair_value = 0.0;
   macro_date = 0;
   ppp_weight = 0.0;
   reliability = 0.0;
   reason = "";

   double proxy_gap = 0.0;
   bool proxy_ok = false;
   if(InpValueModel != FXRC_VALUE_MODEL_PPP || InpPPPAllowProxyFallback)
      proxy_ok = ComputeProxyValueSignal(symbol, current_mid_px, proxy_signal, proxy_gap);

   double ppp_gap = 0.0;
   bool ppp_ok = false;
   string ppp_reason = "";
   if(ValueModelUsesPPP())
      ppp_ok = ComputePPPValueSignal(symbol, current_mid_px, asof_time, ppp_signal, ppp_gap, fair_value, macro_date, ppp_reason);

   if(InpValueModel == FXRC_VALUE_MODEL_PROXY)
   {
      if(!proxy_ok)
      {
         reason = "statistical-anchor value signal unavailable";
         return false;
      }
      signal = proxy_signal;
      value_gap = proxy_gap;
      reliability = BuildValueInfluenceScale(asof_time, macro_date, proxy_ok, proxy_signal, ppp_ok, ppp_signal, intraday_vol_ratio);
      signal *= reliability;
      return true;
   }

   if(InpValueModel == FXRC_VALUE_MODEL_PPP)
   {
      if(ppp_ok)
      {
         signal = ppp_signal;
         value_gap = ppp_gap;
         ppp_weight = 1.0;
         reliability = BuildValueInfluenceScale(asof_time, macro_date, proxy_ok, proxy_signal, ppp_ok, ppp_signal, intraday_vol_ratio);
         signal *= reliability;
         return true;
      }

      if(InpPPPAllowProxyFallback && proxy_ok)
      {
         signal = proxy_signal;
         value_gap = proxy_gap;
         reliability = BuildValueInfluenceScale(asof_time, macro_date, proxy_ok, proxy_signal, ppp_ok, ppp_signal, intraday_vol_ratio);
         signal *= reliability;
         return true;
      }

      reason = (StringLen(ppp_reason) > 0 ? ppp_reason : "PPP value signal unavailable");
      return false;
   }

   if(ppp_ok && proxy_ok)
   {
      double proxy_weight = InpProxyBlendWeight;
      double ppp_blend_weight = InpPPPBlendWeight;
      double freshness = 1.0;
      if(macro_date > 0 && asof_time > macro_date)
      {
         double age_frac = (double)(asof_time - macro_date) / (double)MathMax(1, InpPPPMaxDataAgeDays * 24 * 60 * 60);
         freshness = 1.0 - Clip(age_frac, 0.0, 1.0);
      }

      ppp_blend_weight *= (0.50 + 0.50 * freshness) * (0.50 + 0.50 * MathMin(MathAbs(ppp_signal), 1.0));
      proxy_weight *= (0.50 + 0.50 * MathMin(MathAbs(proxy_signal), 1.0));
      NormalizeValueBlendWeights(proxy_weight, ppp_blend_weight);

      signal = proxy_weight * proxy_signal + ppp_blend_weight * ppp_signal;
      value_gap = proxy_weight * proxy_gap + ppp_blend_weight * ppp_gap;
      ppp_weight = ppp_blend_weight;
      reliability = BuildValueInfluenceScale(asof_time, macro_date, proxy_ok, proxy_signal, ppp_ok, ppp_signal, intraday_vol_ratio);
      signal *= reliability;
      return true;
   }

   if(ppp_ok)
   {
      signal = ppp_signal;
      value_gap = ppp_gap;
      ppp_weight = 1.0;
      reliability = BuildValueInfluenceScale(asof_time, macro_date, proxy_ok, proxy_signal, ppp_ok, ppp_signal, intraday_vol_ratio);
      signal *= reliability;
      return true;
   }

   if(proxy_ok)
   {
      signal = proxy_signal;
      value_gap = proxy_gap;
      reliability = BuildValueInfluenceScale(asof_time, macro_date, proxy_ok, proxy_signal, ppp_ok, ppp_signal, intraday_vol_ratio);
      signal *= reliability;
      return true;
   }

   if(StringLen(ppp_reason) > 0)
      reason = ppp_reason;
   else if(InpPPPAllowProxyFallback)
      reason = "value signal unavailable for both PPP and statistical-anchor proxy";
   else
      reason = "value signal unavailable";

   return false;
}

// Normalizes value blend weights.
void NormalizeValueBlendWeights(double &proxy_weight, double &ppp_weight)
{
   double sum = MathMax(proxy_weight + ppp_weight, EPS());
   proxy_weight /= sum;
   ppp_weight /= sum;
}

// Value is a slow contextual bias here, so attenuate it when the sources are weak,
// Builds value influence scale.
double BuildValueInfluenceScale(const datetime asof_time,
                                const datetime macro_date,
                                const bool proxy_ok,
                                const double proxy_signal,
                                const bool ppp_ok,
                                const double ppp_signal,
                                const double intraday_vol_ratio)
{
   double source_scale = 0.0;
   if(ppp_ok && proxy_ok)
   {
      int proxy_dir = SignD(proxy_signal);
      int ppp_dir = SignD(ppp_signal);
      source_scale = ((proxy_dir == 0 || ppp_dir == 0 || proxy_dir == ppp_dir) ? 0.85 : 0.35);
   }
   else if(ppp_ok)
   {
      source_scale = 0.60;
   }
   else if(proxy_ok)
   {
      source_scale = 0.35;
   }
   else
   {
      return 0.0;
   }

   double freshness_scale = 1.0;
   if(ppp_ok && macro_date > 0 && asof_time > macro_date)
   {
      double age_frac = (double)(asof_time - macro_date) / (double)MathMax(1, InpPPPMaxDataAgeDays * 24 * 60 * 60);
      freshness_scale = 1.0 - 0.60 * Clip(age_frac, 0.0, 1.0);
   }

   double timescale_scale = 1.0;
   int signal_seconds = PeriodSeconds(InpSignalTF);
   int value_seconds = PeriodSeconds(InpValueTF);
   if(signal_seconds > 0 && value_seconds > signal_seconds)
   {
      double ratio = (double)signal_seconds / (double)value_seconds;
      timescale_scale = Clip(MathPow(MathMax(ratio, EPS()), 0.20), 0.30, 1.0);
   }

   double regime_scale = Clip(MathExp(-0.75 * PosPart(intraday_vol_ratio - 1.0)), 0.35, 1.0);
   return Clip(source_scale * freshness_scale * timescale_scale * regime_scale, 0.0, 1.0);
}

// Computes PPP value signal.
bool ComputePPPValueSignal(const string symbol,
                           const double current_mid_px,
                           const datetime asof_time,
                           double &signal,
                           double &value_gap,
                           double &fair_value,
                           datetime &macro_date,
                           string &reason)
{
   signal = 0.0;
   value_gap = 0.0;
   fair_value = 0.0;
   macro_date = 0;
   reason = "";
   if(!BuildPPPFairValue(symbol, current_mid_px, asof_time, fair_value, value_gap, macro_date, reason))
      return false;

   signal = MathTanh(value_gap / InpPPPGapScale);
   return true;
}

// Builds PPP fair value.
bool BuildPPPFairValue(const string symbol,
                       const double current_mid_px,
                       const datetime asof_time,
                       double &fair_value,
                       double &value_gap,
                       datetime &macro_date,
                       string &reason)
{
   fair_value = 0.0;
   value_gap = 0.0;
   macro_date = 0;
   reason = "";

   if(!EnsurePPPDataCache(false) || !g_ppp_cache.available)
   {
      reason = "PPP cache unavailable";
      return false;
   }

   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   if(StringLen(base) != 3 || StringLen(quote) != 3)
   {
      reason = "PPP requires FX base/quote currencies";
      return false;
   }

   double base_latest = 0.0, quote_latest = 0.0;
   datetime base_latest_date = 0, quote_latest_date = 0;
   if(!GetPPPRecordAtOrBefore(base, asof_time, base_latest, base_latest_date)
      || !GetPPPRecordAtOrBefore(quote, asof_time, quote_latest, quote_latest_date))
   {
      reason = "PPP data missing at signal time";
      return false;
   }

   macro_date = (datetime)MathMin((long)base_latest_date, (long)quote_latest_date);
   if(macro_date <= 0)
   {
      reason = "PPP latest macro date is invalid";
      return false;
   }

   if((asof_time - macro_date) > (datetime)(InpPPPMaxDataAgeDays * 24 * 60 * 60))
   {
      reason = "PPP data is stale";
      return false;
   }

   if(!GetPPPRecordAtOrBefore(base, macro_date, base_latest, base_latest_date)
      || !GetPPPRecordAtOrBefore(quote, macro_date, quote_latest, quote_latest_date))
   {
      reason = "PPP latest macro alignment failed";
      return false;
   }

   datetime base_first = 0, quote_first = 0;
   if(!GetPPPFirstRecordDate(base, base_first) || !GetPPPFirstRecordDate(quote, quote_first))
   {
      reason = "PPP anchor dates unavailable";
      return false;
   }

   datetime anchor_time = 0;
   if(!GetRollingValueAnchorTime(symbol, asof_time, anchor_time))
   {
      reason = "PPP rolling anchor unavailable";
      return false;
   }
   anchor_time = (datetime)MathMax((long)anchor_time, (long)MathMax((long)base_first, (long)quote_first));
   double base_anchor = 0.0, quote_anchor = 0.0;
   datetime base_anchor_date = 0, quote_anchor_date = 0;
   if(!GetPPPRecordAtOrBefore(base, anchor_time, base_anchor, base_anchor_date)
      || !GetPPPRecordAtOrBefore(quote, anchor_time, quote_anchor, quote_anchor_date))
   {
      reason = "PPP anchor CPI values unavailable";
      return false;
   }

   double anchor_close = 0.0;
   datetime anchor_bar_time = 0;
   if(!GetSeriesCloseAtOrBefore(symbol, InpValueTF, anchor_time, anchor_close, anchor_bar_time))
   {
      reason = "PPP anchor spot unavailable";
      return false;
   }

   if(current_mid_px <= 0.0 || base_anchor <= 0.0 || quote_anchor <= 0.0 || base_latest <= 0.0 || quote_latest <= 0.0)
   {
      reason = "PPP inputs are invalid";
      return false;
   }

   fair_value = anchor_close * ((base_latest / base_anchor) / (quote_latest / quote_anchor));
   if(fair_value <= EPS())
   {
      reason = "PPP fair value is invalid";
      return false;
   }

   value_gap = Clip(MathLog(fair_value / current_mid_px), -2.0, 2.0);
   return true;
}

// Computes proxy value signal.
bool ComputeProxyValueSignal(const string symbol, const double current_mid_px, double &signal, double &value_gap)
{
   signal = 0.0;
   value_gap = 0.0;

   int bars_needed = InpValueLookbackBars + 5;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   ResetLastError();
   int copied = CopyRates(symbol, InpValueTF, 0, bars_needed, rates);
   if(copied < InpValueLookbackBars + 2)
      return false;

   double close[];
   ArrayResize(close, copied);
   ArraySetAsSeries(close, true);
   for(int i=0; i<copied; ++i)
      close[i] = rates[i].close;

   if(current_mid_px <= 0.0 || close[1] <= 0.0)
      return false;

   int oldest_shift = MathMin(InpValueLookbackBars + 1, copied - 1);
   double anchor_log = SlowEWMALogAnchorNewestFirst(close, 1, oldest_shift, InpValueHalfLifeBars);
   double value_vol = EWMAStdFromCloses(close, MathMin(InpValueLookbackBars, copied - 2), InpValueHalfLifeBars);
   if(value_vol <= EPS())
      return false;

   value_gap = (anchor_log - MathLog(current_mid_px)) / value_vol;
   value_gap = Clip(value_gap, -8.0, 8.0);
   signal = MathTanh(value_gap / InpValueSignalScale);
   return true;
}

// Computes carry signal.
bool ComputeCarrySignal(const string symbol,
                        const double mid_px,
                        const datetime asof_time,
                        double &signal,
                        double &annual_spread_frac,
                        datetime &macro_date,
                        string &reason)
{
   signal = 0.0;
   annual_spread_frac = 0.0;
   macro_date = 0;
   reason = "";

   if(InpCarryModel == FXRC_CARRY_MODEL_RATE_DIFF)
   {
      if(ComputeRateCarrySignal(symbol, asof_time, signal, annual_spread_frac, macro_date, reason))
         return true;

      if(InpCarryAllowBrokerFallback)
      {
         string external_reason = reason;
         if(ComputeBrokerCarrySignal(symbol, mid_px, signal, annual_spread_frac))
         {
            reason = "broker fallback after external carry failure: " + external_reason;
            return true;
         }
      }

      return false;
   }

   if(ComputeBrokerCarrySignal(symbol, mid_px, signal, annual_spread_frac))
      return true;

   reason = "broker carry unavailable";
   return false;
}

// Computes rate carry signal.

bool ComputeRateCarrySignal(const string symbol,
                            const datetime asof_time,
                            double &signal,
                            double &annual_spread_frac,
                            datetime &macro_date,
                            string &reason)
{
   signal = 0.0;
   annual_spread_frac = 0.0;
   macro_date = 0;
   reason = "";

   if(!EnsureCarryDataCache(false) || !g_carry_cache.available)
   {
      reason = "carry cache unavailable";
      return false;
   }

   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   if(StringLen(base) != 3 || StringLen(quote) != 3)
   {
      reason = "external carry requires FX base/quote currencies";
      return false;
   }

   double base_rate = 0.0, quote_rate = 0.0;
   datetime base_date = 0, quote_date = 0;
   if(!GetCarryRecordAtOrBefore(base, asof_time, base_rate, base_date)
      || !GetCarryRecordAtOrBefore(quote, asof_time, quote_rate, quote_date))
   {
      reason = "carry data missing at signal time";
      return false;
   }

   macro_date = (datetime)MathMin((long)base_date, (long)quote_date);
   if(macro_date <= 0)
   {
      reason = "carry latest macro date is invalid";
      return false;
   }

   if((asof_time - macro_date) > (datetime)(InpCarryMaxDataAgeDays * 24 * 60 * 60))
   {
      reason = "carry data is stale";
      return false;
   }

   if(!GetCarryRecordAtOrBefore(base, macro_date, base_rate, base_date)
      || !GetCarryRecordAtOrBefore(quote, macro_date, quote_rate, quote_date))
   {
      reason = "carry latest macro alignment failed";
      return false;
   }

   annual_spread_frac = base_rate - quote_rate;
   signal = MathTanh(annual_spread_frac / InpCarrySignalScale);
   return true;
}

// Computes broker carry signal.
bool ComputeBrokerCarrySignal(const string symbol, const double mid_px, double &signal, double &annual_spread_frac)
{
   signal = 0.0;
   annual_spread_frac = 0.0;

   double notional_eur = 0.0;
   if(!EstimateNotionalEUR(symbol, 1.0, notional_eur) || notional_eur <= EPS())
      return false;

   double long_swap_day = EstimateSwapCashEURPerDay(symbol, 1, 1.0, mid_px);
   double short_swap_day = EstimateSwapCashEURPerDay(symbol, -1, 1.0, mid_px);
   annual_spread_frac = (long_swap_day - short_swap_day) * 365.0 / notional_eur;
   signal = MathTanh(annual_spread_frac / InpCarrySignalScale);
   return true;
}

// Computes the slow EWMA log-price anchor from a newest-first close series.
double SlowEWMALogAnchorNewestFirst(const double &close[], const int newest_shift, const int oldest_shift, const int half_life)
{
   double lambda = MathExp(-MathLog(2.0) / MathMax(1.0, (double)half_life));
   double anchor = 0.0;
   bool seeded = false;

   for(int sh = oldest_shift; sh >= newest_shift; --sh)
   {
      if(close[sh] <= 0.0)
         continue;

      double lx = MathLog(close[sh]);
      if(!seeded)
      {
         anchor = lx;
         seeded = true;
      }
      else
      {
         anchor = lambda * anchor + (1.0 - lambda) * lx;
      }
   }

   return anchor;
}
