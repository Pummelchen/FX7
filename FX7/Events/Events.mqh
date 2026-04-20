// Runs the modular EA initialization flow.
int FX7HandleInit()
{
   const int total_steps = 12;
   ResetRuntimeState(g_runtime_state);
   ResetDependencyRuntimeState(g_dependency_state);
   g_hard_stop_active = false;
   g_hard_stop_reason = "";
   ResetCarryCacheState(g_carry_cache);
   ResetPPPCacheState(g_ppp_cache);
   LogStartupStep(1, total_steps, "Reset runtime state", "Done");

   if(!ValidateInputs())
   {
      LogStartupStep(2, total_steps, "Validate inputs", "Failed");
      return INIT_FAILED;
   }
   LogStartupStep(2, total_steps, "Validate inputs", "Done");

   if(!IsForexPairSymbol(_Symbol))
   {
      LogStartupStep(3, total_steps, "Validate chart symbol", "Failed", _Symbol);
      PrintFormat("FXRC only supports FX symbols. Current chart/test symbol %s is not forex.", _Symbol);
      return INIT_FAILED;
   }
   LogStartupStep(3, total_steps, "Validate chart symbol", "Done", _Symbol);

   if(!ParseSymbols())
   {
      LogStartupStep(4, total_steps, "Parse analysis universe", "Failed");
      Print("Failed to parse at least one valid symbol.");
      return INIT_FAILED;
   }
   LogStartupStep(4, total_steps, "Parse analysis universe", "Done", StringFormat("%d symbols", g_num_symbols));

   if(!InitArrays())
   {
      LogStartupStep(5, total_steps, "Initialize arrays", "Failed");
      Print("Failed to initialize arrays.");
      return INIT_FAILED;
   }
   LogStartupStep(5, total_steps, "Initialize arrays", "Done", StringFormat("ret_hist_len=%d", g_ret_hist_len));

   if(!InitTradableSymbols())
   {
      LogStartupStep(6, total_steps, "Initialize tradable filter", "Failed");
      Print("Failed to initialize tradable symbol filter.");
      return INIT_FAILED;
   }
   LogStartupStep(6, total_steps, "Initialize tradable filter", "Done");

   if(!EnsureReferenceEURNotional())
   {
      LogStartupStep(7, total_steps, "Build EUR reference notional", "Failed");
      Print("Failed to compute EUR reference notional.");
      return INIT_FAILED;
   }
   LogStartupStep(7, total_steps, "Build EUR reference notional", "Done", DoubleToString(g_reference_eur_notional, 2));

   if(CarrySleeveEnabled() && (InpCarryModel != FXRC_CARRY_MODEL_RATE_DIFF || InpCarryAllowBrokerFallback))
   {
      PrintFormat("FXRC startup warning: carry model is %s with broker fallback=%s. Pure external carry is not enforced.",
                  EnumToString(InpCarryModel),
                  (InpCarryAllowBrokerFallback ? "true" : "false"));
   }
   if(ValueSleeveEnabled() && (InpValueModel != FXRC_VALUE_MODEL_PPP || InpPPPAllowProxyFallback))
   {
      PrintFormat("FXRC startup warning: value model is %s with PPP proxy fallback=%s. Pure PPP value is not enforced, the proxy leg is only a statistical anchor, and value is treated as a slow reliability-scaled bias rather than a primary intraday alpha.",
                  EnumToString(InpValueModel),
                  (InpPPPAllowProxyFallback ? "true" : "false"));
   }
   if(DependenciesRequiredAtRuntime() && !InpFreezeEntriesOnDependencyFailure)
      Print("FXRC startup warning: degraded dependency mode will keep entries enabled and continue on stale carry/PPP inputs until grace expiry.");

   if(CarryModelUsesExternal())
   {
      bool carry_ok = EnsureCarryDataCache(true);
      string carry_detail = (carry_ok
                             ? StringFormat("%d rows via %s", g_carry_cache.record_count, g_carry_cache.source_file)
                             : g_carry_cache.reason);
      string carry_status = (carry_ok ? "Done" : "Failed");

      if(CarrySignalRequiresExternalData())
      {
         if(!carry_ok)
         {
            LogStartupStep(8, total_steps, "Build carry macro cache", "Failed", carry_detail);
            PrintFormat("Required startup-built carry data is unavailable. %s", carry_detail);
            return INIT_FAILED;
         }

         string coverage_reason;
         if(!ValidateRequiredCarryCoverage(coverage_reason))
         {
            LogStartupStep(8, total_steps, "Build carry macro cache", "Failed", coverage_reason);
            PrintFormat("Required startup-built carry data coverage failed: %s", coverage_reason);
            return INIT_FAILED;
         }
      }

      LogStartupStep(8, total_steps, "Build carry macro cache", carry_status, carry_detail);
   }
   else
   {
      LogStartupStep(8, total_steps, "Build carry macro cache", "Skipped", "broker-swap carry model");
   }

   if(ValueModelUsesPPP())
   {
      bool ppp_ok = EnsurePPPDataCache(true);
      string ppp_detail = (ppp_ok
                           ? StringFormat("%d rows via %s", g_ppp_cache.record_count, g_ppp_cache.source_file)
                           : g_ppp_cache.reason);
      string ppp_status = (ppp_ok ? "Done" : "Failed");

      if(ValueSignalRequiresPPPData())
      {
         if(!ppp_ok)
         {
            LogStartupStep(9, total_steps, "Build PPP macro cache", "Failed", ppp_detail);
            PrintFormat("Required startup-built PPP data is unavailable. %s", ppp_detail);
            return INIT_FAILED;
         }

         string coverage_reason;
         if(!ValidateRequiredPPPCoverage(coverage_reason))
         {
            LogStartupStep(9, total_steps, "Build PPP macro cache", "Failed", coverage_reason);
            PrintFormat("Required startup-built PPP data coverage failed: %s", coverage_reason);
            return INIT_FAILED;
         }
      }

      LogStartupStep(9, total_steps, "Build PPP macro cache", ppp_status, ppp_detail);
   }
   else
   {
      LogStartupStep(9, total_steps, "Build PPP macro cache", "Skipped", "statistical-anchor proxy value model");
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   ClearConversionFailureState();
   if(!TryConvertCash(AccountInfoString(ACCOUNT_CURRENCY), "USD", equity, g_session_start_equity_usd))
   {
      LogStartupStep(10, total_steps, "Seed session state", "Failed", g_conversion_error_reason);
      PrintFormat("Unable to seed session baseline: %s", g_conversion_error_reason);
      return INIT_FAILED;
   }
   g_equi_max = equity;
   g_backtest_start_time = 0;
   g_tester_diag_logs = 0;
   ArrayResize(g_trail_tickets, 0);
   ArrayResize(g_trail_peak_profit_usd, 0);
   ArrayResize(g_recent_entry_times, 0);
   ArrayResize(g_pending_state_verifications, 0);
   g_execution_state_dirty = true;
   LogStartupStep(10, total_steps, "Seed session state", "Done", StringFormat("equity=%.2f", equity));

   RefreshRuntimeState(true);
   LogStartupStep(11, total_steps, "Refresh runtime state", "Done",
                  StringFormat("status=%s ready=%d", RuntimeStatusToString(g_runtime_state.status), g_runtime_state.ready_symbols));

   int tradable_count = 0;
   for(int i=0; i<g_num_symbols; ++i)
   {
      if(IsTradeAllowed(i))
         tradable_count++;
   }

   if(g_num_symbols == 1)
      PrintFormat("FXRC startup warning: only one analysis symbol is available (%s). Cross-symbol ranking will be effectively disabled.", g_symbols[0]);

   PrintFormat("FXRC initialized with %d analysis symbols and %d tradable symbols on %s. trade_model=%s Reference EUR notional=%.2f Session baseline=%.2f USD runtime=%s ready_symbols=%d",
               g_num_symbols,
               tradable_count,
               EnumToString(InpSignalTF),
               EnumToString(Trade_Model),
               g_reference_eur_notional,
               g_session_start_equity_usd,
               RuntimeStatusToString(g_runtime_state.status),
               g_runtime_state.ready_symbols);
   if(IsModernTradeModel())
      Print("FXRC modern trade model active: exits are signal-driven and classic overlays (fixed TP, trailing, session reset) are disabled.");
   else if(InpClassicUseTrailingStop == 1)
      Print("FXRC classic trade model active with trailing stop enabled: trailing activation uses InpClassicSinglePositionTakeProfitUSD as the profit anchor and the fixed hard TP is disabled.");
   ResetLastError();
   if(!EventSetTimer(1))
   {
      LogStartupStep(12, total_steps, "Activate execution timer", "Failed", IntegerToString(GetLastError()));
      Print("Failed to activate the execution-state timer.");
      return INIT_FAILED;
   }
   LogStartupStep(12, total_steps, "Activate execution timer", "Done", "1 second");
   return INIT_SUCCEEDED;
}

// Runs the modular tick-processing flow.
void FX7HandleTick()
{
   ClearConversionFailureState();
   ProcessPendingTradeVerifications(false);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double equity_usd = 0.0;
   string hard_stop_reason = "";
   if(!TryConvertCash(AccountInfoString(ACCOUNT_CURRENCY), "USD", equity, equity_usd))
      hard_stop_reason = g_conversion_error_reason;

   // EA HARD STOP - STOP EA WHEN MINIMUM EQUITY IS REACHED
   if(StringLen(hard_stop_reason) == 0 && EAStopMinEqui > 0 && equity_usd < (double)EAStopMinEqui)
   {
      hard_stop_reason = StringFormat("equity %.2f USD is below minimum %.2f USD", equity_usd, (double)EAStopMinEqui);
   }

   // EA HARD STOP - STOP EA WHEN DD IS > X %
   if(g_equi_max <= EPS() || equity > g_equi_max)
      g_equi_max = equity;

   if(StringLen(hard_stop_reason) == 0 && EAStopMaxDD > 0.0 && g_equi_max > EPS())
   {
      double drawdown_pct = 100.0 - ((equity / g_equi_max) * 100.0);
      if(drawdown_pct > EAStopMaxDD)
         hard_stop_reason = StringFormat("drawdown %.2f%% exceeded maximum %.2f%%", drawdown_pct, EAStopMaxDD);
   }

   if(g_hard_stop_active || StringLen(hard_stop_reason) > 0)
   {
      if(HandleHardStopEmergencyShutdown(hard_stop_reason))
      {
         ExpertRemove();
      }
      return;
   }

   bool entries_allowed = true;
   bool must_flatten = false;
   bool disable_after_flatten = false;
   string dependency_reason = "";
   RefreshDependencyRuntimeState(entries_allowed, must_flatten, disable_after_flatten, dependency_reason);

   EnsureProtectiveStops();

   if(CleanupUnexpectedManagedPendingOrders("FXRC unexpected pending cleanup"))
      return;

   if(must_flatten)
   {
      bool flatten_complete = HandleDependencyEmergencyFlatten(dependency_reason);
      if(flatten_complete)
      {
         bool post_entries_allowed = false;
         bool post_must_flatten = false;
         bool post_disable_after_flatten = false;
         string post_reason = dependency_reason;
         RefreshDependencyRuntimeState(post_entries_allowed, post_must_flatten, post_disable_after_flatten, post_reason);
         if(post_disable_after_flatten)
         {
            ExpertRemove();
            return;
         }
      }
      return;
   }

   if(HandleSessionProfitReset())
      return;

   if(HandleSinglePositionTakeProfits())
      return;

   if(HandleTrailingStopExits())
      return;

   if(HandleBacktestInactivityStop())
      return;

   if(g_dependency_state.status == FXRC_DEPENDENCY_DISABLED)
      return;

   if(!EnsureRuntimeReady(false))
      return;

   if(!NewBarDetected())
      return;

   if(!RefreshRuntimeState(false))
      return;

   if(InpRequireSynchronizedSignalBars && !AreSignalBarsSynchronized())
      return;

   ExecuteModel(entries_allowed);
}

// Runs the modular EA deinitialization flow.
void FX7HandleDeinit(const int reason)
{
   EventKillTimer();
   ArrayResize(g_pending_state_verifications, 0);
   g_execution_state_dirty = false;
}

// Runs the timer-driven verification flow.
void FX7HandleTimer()
{
   ProcessPendingTradeVerifications(true);
}

// Processes trade-transaction callbacks in the modular runtime.
void FX7HandleTradeTransaction(const MqlTradeTransaction& trans,
                               const MqlTradeRequest& request,
                               const MqlTradeResult& result)
{
   string symbol = trans.symbol;
   if(StringLen(symbol) == 0)
      symbol = request.symbol;

   if(StringLen(symbol) == 0 || !IsForexPairSymbol(symbol))
      return;

   MarkExecutionStateDirty();
   MarkPendingVerificationUrgent(symbol);
   ProcessPendingTradeVerifications(true);
}

//------------------------- Runtime Flow -------------------------//
// Executes model.
void ExecuteModel(const bool allow_new_entries = true)
{
   bool allow_stale_dependency_values = (g_dependency_state.status == FXRC_DEPENDENCY_DEGRADED
                                      && (!allow_new_entries || !InpFreezeEntriesOnDependencyFailure));

   bool any_ok = false;
   int feature_failure_grace = MathMax(0, InpSymbolDataFailureGraceBars);
   for(int i=0; i<g_num_symbols; ++i)
   {
      if(UpdateSymbolFeatures(i, allow_stale_dependency_values))
      {
         any_ok = true;
      }
      else
      {
         bool can_hold_stale_state = (g_symbol_data_ok[i] && g_symbol_feature_failures[i] < feature_failure_grace);
         if(can_hold_stale_state)
         {
            MarkSymbolDataStale(i);
            any_ok = true;
            if(!MQLInfoInteger(MQL_TESTER) || g_tester_diag_logs < 20)
               PrintFormat("Feature refresh failed on %s. Freezing new entries and keeping prior state (%d/%d grace bars).",
                           g_symbols[i], g_symbol_feature_failures[i], feature_failure_grace);
            if(MQLInfoInteger(MQL_TESTER))
               g_tester_diag_logs++;
         }
         else
         {
            NeutralizeSymbol(i);
         }
      }
   }

   if(!any_ok && MQLInfoInteger(MQL_TESTER) && g_tester_diag_logs < 5)
   {
      Print("FXRC tester diag: no symbols produced valid features on this cycle.");
      g_tester_diag_logs++;
   }

   if(g_conversion_error_active)
      return;

   if(!any_ok)
      return;

   UpdatePanicGateAndScores();
   BuildCorrelationMatrices();
   EnsureProtectiveStops();
   FXRCExecutionSnapshot cycle_snapshot;
   RefreshExecutionSnapshot(cycle_snapshot);

   int candidates[];
   ArrayResize(candidates, 0);
   for(int i=0; i<g_num_symbols; ++i)
   {
      if(g_symbol_data_ok[i]
         && g_entry_dir_raw[i] != 0
         && g_persist_count[i] >= InpPersistenceBars
         && CandidateMeetsMinimumGates(i, g_entry_dir_raw[i]))
      {
         int new_size = ArraySize(candidates) + 1;
         ArrayResize(candidates, new_size);
         candidates[new_size - 1] = i;
      }
   }

   if(ArraySize(candidates) == 0 && MQLInfoInteger(MQL_TESTER) && g_tester_diag_logs < 5)
   {
      int best_idx = -1;
      double best_abs_s = -1.0;
      for(int i=0; i<g_num_symbols; ++i)
      {
         if(!g_symbol_data_ok[i])
            continue;
         if(MathAbs(g_S[i]) > best_abs_s)
         {
            best_abs_s = MathAbs(g_S[i]);
            best_idx = i;
         }
      }

      if(best_idx >= 0)
      {
         PrintFormat("FXRC tester diag: no candidates. best=%s S=%.4f theta_in=%.4f conf=%.4f G=%.4f Q=%.4f/%.4f M=%.4f C=%.4f V=%.4f VA=%.4f VPPP=%.4f WPPP=%.2f VR=%.2f BK=%.4f",
                     g_symbols[best_idx], g_S[best_idx], g_theta_in_eff[best_idx], g_Conf[best_idx],
                     g_G[best_idx], g_Q_long[best_idx], g_Q_short[best_idx], g_M[best_idx], g_Carry[best_idx], g_Value[best_idx],
                     g_ValueProxy[best_idx], g_ValuePPP[best_idx], g_ValuePPPWeight[best_idx], g_ValueReliability[best_idx], g_BK[best_idx]);
      }
      else
      {
         Print("FXRC tester diag: no candidates and no symbols have valid data.");
      }
      g_tester_diag_logs++;
   }

   ComputeNoveltyOverlay(candidates);

   int target_dir[];
   BuildTradeTargets(candidates, target_dir);

   if(MQLInfoInteger(MQL_TESTER) && g_tester_diag_logs < 5)
   {
      int target_count = 0;
      int best_idx = -1;
      double best_priority = -1.0;

      for(int c=0; c<ArraySize(candidates); ++c)
      {
         int i = candidates[c];
         if(target_dir[i] != 0)
            target_count++;

         double priority = BuildCandidatePriority(i, g_entry_dir_raw[i]);
         if(priority > best_priority)
         {
            best_priority = priority;
            best_idx = i;
         }
      }

      if(target_count == 0 && best_idx >= 0)
      {
         PrintFormat("FXRC tester diag: candidates built but no trade targets. best=%s dir=%d priority=%.4f S=%.4f conf=%.4f G=%.4f Q=%.4f/%.4f rank=%.4f M=%.4f C=%.4f VA=%.4f VPPP=%.4f WPPP=%.2f VR=%.2f",
                     g_symbols[best_idx], g_entry_dir_raw[best_idx], best_priority, g_S[best_idx], g_Conf[best_idx],
                     g_G[best_idx], g_Q_long[best_idx], g_Q_short[best_idx], g_Rank[best_idx], g_M[best_idx], g_Carry[best_idx], g_Value[best_idx],
                     g_ValueProxy[best_idx], g_ValuePPP[best_idx], g_ValuePPPWeight[best_idx], g_ValueReliability[best_idx]);
         g_tester_diag_logs++;
      }
   }

   int active_orders_total = cycle_snapshot.account_active_orders;

   for(int i=0; i<g_num_symbols; ++i)
   {
      string sym = g_symbols[i];
      bool foreign_active = SymbolHasForeignActiveState(sym);

      int symbol_account_orders = g_exec_symbol_state[i].account_active_orders;
      int cur_dir = g_exec_symbol_state[i].dir;
      int cur_count = g_exec_symbol_state[i].count;
      bool mixed = g_exec_symbol_state[i].mixed;

      if(mixed || cur_count > 1)
      {
         if(CloseManagedPositionsForSymbol(sym, "FXRC normalize managed state"))
            RefreshCycleExecutionState(cycle_snapshot, active_orders_total);
         continue;
      }

      if(symbol_account_orders > cur_count)
      {
         PrintFormat("Skipping %s because another active account order/position already exists on the symbol.", sym);
         continue;
      }

      bool trade_allowed = IsTradeAllowed(i);

      int target = target_dir[i];

      if(cur_dir == 1)
      {
         if(target == -1)
         {
            if(CloseManagedPositionsForSymbol(sym, "FXRC transition to short"))
            {
               RefreshCycleExecutionState(cycle_snapshot, active_orders_total);
               if(allow_new_entries && trade_allowed && !foreign_active)
               {
                  if(OpenManagedPosition(i, -1, cycle_snapshot))
                     RefreshCycleExecutionState(cycle_snapshot, active_orders_total);
               }
            }
         }
         else if(target == 0 && ShouldExitManagedDirection(i, 1))
         {
            if(CloseManagedPositionsForSymbol(sym, "FXRC exit long"))
               RefreshCycleExecutionState(cycle_snapshot, active_orders_total);
         }
      }
      else if(cur_dir == -1)
      {
         if(target == 1)
         {
            if(CloseManagedPositionsForSymbol(sym, "FXRC transition to long"))
            {
               RefreshCycleExecutionState(cycle_snapshot, active_orders_total);
               if(allow_new_entries && trade_allowed && !foreign_active)
               {
                  if(OpenManagedPosition(i, 1, cycle_snapshot))
                     RefreshCycleExecutionState(cycle_snapshot, active_orders_total);
               }
            }
         }
         else if(target == 0 && ShouldExitManagedDirection(i, -1))
         {
            if(CloseManagedPositionsForSymbol(sym, "FXRC exit short"))
               RefreshCycleExecutionState(cycle_snapshot, active_orders_total);
         }
      }
      else if(cur_count == 0)
      {
         if(!allow_new_entries || !trade_allowed)
            continue;

         if(foreign_active)
         {
            if(target != 0)
               PrintFormat("Skipping %s because a non-FXRC active order/position already exists on the symbol.", sym);
            continue;
         }

         if(target == 1)
         {
            if(active_orders_total >= InpMaxAccountOrders)
            {
               PrintFormat("Skipping %s long entry because account active order cap %d is reached.", sym, InpMaxAccountOrders);
               continue;
            }

            if(OpenManagedPosition(i, 1, cycle_snapshot))
               RefreshCycleExecutionState(cycle_snapshot, active_orders_total);
         }
         else if(target == -1)
         {
            if(active_orders_total >= InpMaxAccountOrders)
            {
               PrintFormat("Skipping %s short entry because account active order cap %d is reached.", sym, InpMaxAccountOrders);
               continue;
            }

            if(OpenManagedPosition(i, -1, cycle_snapshot))
               RefreshCycleExecutionState(cycle_snapshot, active_orders_total);
         }
      }
   }

   ClearSignalBarAdvanceFlags();
}

// Returns whether a new closed signal bar was detected.
bool NewBarDetected()
{
   bool changed = false;
   for(int i=0; i<g_num_symbols; ++i)
   {
      datetime t = iTime(g_symbols[i], InpSignalTF, 1);
      if(t <= 0)
         continue;

      if(g_last_closed_bar[i] == 0)
      {
         g_last_closed_bar[i] = t;
         if(InpProcessCurrentClosedBarOnAttach)
         {
            g_symbol_bar_advanced[i] = true;
            changed = true;
         }
      }
      else if(t != g_last_closed_bar[i])
      {
         g_last_closed_bar[i] = t;
         g_symbol_bar_advanced[i] = true;
         changed = true;
      }
      else if(ArraySize(g_symbol_bar_advanced) == g_num_symbols && g_symbol_bar_advanced[i])
      {
         changed = true;
      }
   }
   return changed;
}

// Clears signal bar advance flags.
void ClearSignalBarAdvanceFlags()
{
   if(ArraySize(g_symbol_bar_advanced) == g_num_symbols)
      ArrayInitialize(g_symbol_bar_advanced, false);
}

// Returns whether all signal bars are synchronized across the universe.
bool AreSignalBarsSynchronized()
{
   datetime reference_bar = 0;
   int ready_count = 0;
   for(int i=0; i<g_num_symbols; ++i)
   {
      if(ArraySize(g_symbol_history_ready) == g_num_symbols && !g_symbol_history_ready[i])
         continue;

      datetime bar_time = (ArraySize(g_last_closed_bar) == g_num_symbols ? g_last_closed_bar[i] : 0);
      if(bar_time <= 0)
         return false;

      if(reference_bar == 0)
         reference_bar = bar_time;
      else if(bar_time != reference_bar)
         return false;

      ready_count++;
   }

   return (ready_count > 0);
}

//------------------------- EA Events --------------------------------//

// Ensures runtime ready.
bool EnsureRuntimeReady(const bool force_log)
{
   if(g_runtime_state.status == FXRC_RUNTIME_READY && !force_log)
      return true;

   if(g_runtime_state.status == FXRC_RUNTIME_FATAL)
   {
      LogRuntimeStateIfNeeded(force_log);
      return false;
   }

   return RefreshRuntimeState(force_log);
}

// Refreshes runtime state.
bool RefreshRuntimeState(const bool force_log)
{
   if(g_num_symbols <= 0)
   {
      SetRuntimeStatus(FXRC_RUNTIME_FATAL, "analysis universe is empty", 0, false, 0);
      LogRuntimeStateIfNeeded(force_log);
      return false;
   }

   FXRCHistoryCheck chart_check;
   bool chart_ready = InspectSymbolHistory(_Symbol, (ENUM_TIMEFRAMES)_Period, 1, true, chart_check);
   int ready_symbols = 0;
   int bars_needed = SignalBarsNeeded();
   int value_bars_needed = ValueBarsNeeded();

   for(int i=0; i<g_num_symbols; ++i)
   {
      FXRCHistoryCheck symbol_check;
      bool signal_ready = InspectSymbolHistory(g_symbols[i], InpSignalTF, bars_needed, MQLInfoInteger(MQL_TESTER), symbol_check);

      bool symbol_ready = signal_ready;
      string history_reason = symbol_check.reason;
      datetime latest_history_bar = symbol_check.latest_bar;
      int bars_available = symbol_check.bars_available;

      if(symbol_ready && ValueSleeveEnabled())
      {
         FXRCHistoryCheck value_check;
         bool value_ready = InspectSymbolHistory(g_symbols[i], InpValueTF, value_bars_needed, MQLInfoInteger(MQL_TESTER), value_check);
         if(!value_ready)
         {
            symbol_ready = false;
            history_reason = value_check.reason;
            latest_history_bar = value_check.latest_bar;
            bars_available = value_check.bars_available;
         }
      }

      g_symbol_history_ready[i] = symbol_ready;
      g_symbol_latest_history_bar[i] = latest_history_bar;
      g_symbol_history_bars[i] = bars_available;
      g_symbol_history_reason[i] = history_reason;
      if(symbol_ready)
         ready_symbols++;
   }

   if(!chart_ready)
   {
      SetRuntimeStatus(FXRC_RUNTIME_WAITING_DATA, chart_check.reason, ready_symbols, false, chart_check.latest_bar);
      LogRuntimeStateIfNeeded(force_log);
      return false;
   }

   if(ready_symbols <= 0)
   {
      string reason = "No analysis symbols are ready for the configured signal timeframe.";
      for(int i=0; i<g_num_symbols; ++i)
      {
         if(StringLen(g_symbol_history_reason[i]) > 0)
         {
            reason = g_symbol_history_reason[i];
            break;
         }
      }
      SetRuntimeStatus(FXRC_RUNTIME_WAITING_DATA, reason, ready_symbols, true, chart_check.latest_bar);
      LogRuntimeStateIfNeeded(force_log);
      return false;
   }

   SetRuntimeStatus(FXRC_RUNTIME_READY, "", ready_symbols, true, chart_check.latest_bar);
   LogRuntimeStateIfNeeded(force_log);
   return true;
}

// Refreshes dependency runtime state.
bool RefreshDependencyRuntimeState(bool &entries_allowed, bool &must_flatten, bool &disable_after_flatten, string &reason)
{
   entries_allowed = true;
   must_flatten = false;
   disable_after_flatten = false;
   reason = "";

   if(g_dependency_state.status == FXRC_DEPENDENCY_DISABLED)
   {
      entries_allowed = false;
      reason = g_dependency_state.failure_reason;
      return true;
   }

   if(!DependenciesRequiredAtRuntime())
   {
      if(g_dependency_state.status != FXRC_DEPENDENCY_HEALTHY)
         ResetDependencyRuntimeState(g_dependency_state);
      return true;
   }

   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();

   string dependency_scope;
   string dependency_reason;
   bool healthy = EvaluateRequiredDependencyHealth(now, dependency_scope, dependency_reason);

   if(g_dependency_state.status == FXRC_DEPENDENCY_HEALTHY)
   {
      if(!healthy)
      {
         g_dependency_state.status = FXRC_DEPENDENCY_DEGRADED;
         g_dependency_state.failure_active = true;
         g_dependency_state.first_failure_time = now;
         g_dependency_state.failure_reason = dependency_reason;
         g_dependency_state.dependency_scope = dependency_scope;
         g_dependency_state.flatten_triggered = false;

         entries_allowed = !InpFreezeEntriesOnDependencyFailure;
         reason = dependency_reason;
         LogDependencyTransition(StringFormat("%s became unavailable. state=%s policy=%s reason=%s grace=%d minutes",
                                             dependency_scope,
                                             DependencyStateToString(g_dependency_state.status),
                                             (InpFreezeEntriesOnDependencyFailure ? "freeze_entries" : "continue_on_stale_inputs"),
                                             dependency_reason,
                                             InpDependencyFailureGraceMinutes));
         return true;
      }

      g_dependency_state.last_success_time = now;
      return true;
   }

   if(g_dependency_state.status == FXRC_DEPENDENCY_DEGRADED)
   {
      entries_allowed = !InpFreezeEntriesOnDependencyFailure;
      reason = g_dependency_state.failure_reason;

      if(healthy)
      {
         g_dependency_state.status = FXRC_DEPENDENCY_HEALTHY;
         g_dependency_state.failure_active = false;
         g_dependency_state.last_success_time = now;
         LogDependencyTransition(StringFormat("%s recovered before grace expiry. state=%s",
                                             (StringLen(g_dependency_state.dependency_scope) > 0 ? g_dependency_state.dependency_scope : "dependency"),
                                             DependencyStateToString(g_dependency_state.status)));
         g_dependency_state.failure_reason = "";
         g_dependency_state.dependency_scope = "";
         g_dependency_state.first_failure_time = 0;
         g_dependency_state.flatten_triggered = false;
         entries_allowed = true;
         reason = "";
         return true;
      }

      if(InpFlattenOnPersistentDependencyFailure)
      {
         int grace_seconds = MathMax(0, InpDependencyFailureGraceMinutes) * 60;
         if(grace_seconds == 0 || (now - g_dependency_state.first_failure_time) >= grace_seconds)
         {
            g_dependency_state.status = FXRC_DEPENDENCY_SHUTDOWN_PENDING;
            reason = g_dependency_state.failure_reason;
            must_flatten = true;
            LogDependencyTransition(StringFormat("%s remained unavailable past grace period. state=%s elapsed=%d seconds reason=%s",
                                                (StringLen(g_dependency_state.dependency_scope) > 0 ? g_dependency_state.dependency_scope : "dependency"),
                                                DependencyStateToString(g_dependency_state.status),
                                                (int)MathMax(0, now - g_dependency_state.first_failure_time),
                                                g_dependency_state.failure_reason));
         }
      }

      return true;
   }

   if(g_dependency_state.status == FXRC_DEPENDENCY_SHUTDOWN_PENDING)
   {
      entries_allowed = false;
      reason = g_dependency_state.failure_reason;

      if(HasManagedExposureOrOrders())
      {
         must_flatten = true;
         return true;
      }

      if(InpDisableEAAfterEmergencyFlatten)
      {
         g_dependency_state.status = FXRC_DEPENDENCY_DISABLED;
         g_dependency_state.failure_active = false;
         disable_after_flatten = true;
         LogDependencyTransition(StringFormat("%s emergency flatten completed. state=%s",
                                             (StringLen(g_dependency_state.dependency_scope) > 0 ? g_dependency_state.dependency_scope : "dependency"),
                                             DependencyStateToString(g_dependency_state.status)));
         return true;
      }

      if(healthy)
      {
         g_dependency_state.status = FXRC_DEPENDENCY_HEALTHY;
         g_dependency_state.failure_active = false;
         g_dependency_state.last_success_time = now;
         LogDependencyTransition(StringFormat("%s recovered after emergency flatten. state=%s",
                                             (StringLen(g_dependency_state.dependency_scope) > 0 ? g_dependency_state.dependency_scope : "dependency"),
                                             DependencyStateToString(g_dependency_state.status)));
         g_dependency_state.failure_reason = "";
         g_dependency_state.dependency_scope = "";
         g_dependency_state.first_failure_time = 0;
         g_dependency_state.flatten_triggered = false;
         entries_allowed = true;
         reason = "";
      }

      return true;
   }

   entries_allowed = false;
   reason = g_dependency_state.failure_reason;
   return true;
}

// Refreshes cycle execution state.
void RefreshCycleExecutionState(FXRCExecutionSnapshot &snapshot, int &active_orders_total)
{
   RefreshExecutionSnapshot(snapshot);
   active_orders_total = snapshot.account_active_orders;
}

// Handles dependency emergency flatten.
bool HandleDependencyEmergencyFlatten(const string reason)
{
   if(g_dependency_state.status != FXRC_DEPENDENCY_SHUTDOWN_PENDING)
      return false;

   if(!g_dependency_state.flatten_triggered)
   {
      LogDependencyTransition(StringFormat("initiating emergency flatten. positions=%d pending=%d scope=%s reason=%s",
                                          CountManagedOpenPositions(),
                                          CountManagedPendingOrders(),
                                          (StringLen(g_dependency_state.dependency_scope) > 0 ? g_dependency_state.dependency_scope : "dependency"),
                                          (StringLen(reason) > 0 ? reason : g_dependency_state.failure_reason)));
      g_dependency_state.flatten_triggered = true;
   }

   bool orders_ok = DeleteAllManagedPendingOrders("FXRC dependency emergency flatten");
   CloseAllManagedPositions("FXRC dependency emergency flatten");
   return (orders_ok && !HasManagedExposureOrOrders());
}

// Handles hard stop emergency shutdown.
bool HandleHardStopEmergencyShutdown(const string reason)
{
   if(!g_hard_stop_active)
   {
      g_hard_stop_active = true;
      g_hard_stop_reason = reason;
      PrintFormat("FXRC hard stop triggered: %s. Closing FXRC-owned positions and any unexpected pending orders before removing expert.",
                  g_hard_stop_reason);
   }
   else if(StringLen(g_hard_stop_reason) == 0 && StringLen(reason) > 0)
   {
      g_hard_stop_reason = reason;
   }

   bool orders_ok = DeleteAllManagedPendingOrders("FXRC hard stop");
   CloseAllManagedPositions("FXRC hard stop");

   if(orders_ok && !HasManagedExposureOrOrders())
   {
      PrintFormat("FXRC hard stop flatten complete. Removing expert. reason=%s",
                  (StringLen(g_hard_stop_reason) > 0 ? g_hard_stop_reason : "unspecified"));
      return true;
   }

   return false;
}

// Handles session profit reset.
bool HandleSessionProfitReset()
{
   if(!IsClassicSessionResetActive())
      return false;

   string account_ccy = AccountInfoString(ACCOUNT_CURRENCY);
   double equity_usd = 0.0;
   if(!TryConvertCash(account_ccy, "USD", AccountInfoDouble(ACCOUNT_EQUITY), equity_usd))
      return false;

   double session_gain_usd = equity_usd - g_session_start_equity_usd;
   if(session_gain_usd + EPS() < InpClassicSessionResetProfitUSD)
      return false;

   PrintFormat("Session reset target reached: gain %.2f USD >= %.2f USD. Closing all managed positions and removing any unexpected pending orders.", session_gain_usd, InpClassicSessionResetProfitUSD);

   CloseAllManagedPositions("FXRC session reset");
   DeleteAllManagedPendingOrders("FXRC session reset");

   if(CountManagedOpenPositions() == 0 && CountManagedPendingOrders() == 0)
   {
      ResetStrategyCycleState(true);
      PrintFormat("FXRC cycle reset complete. New session baseline %.2f USD.", g_session_start_equity_usd);
   }
   else
   {
      Print("FXRC session reset attempted but some managed trades/orders remain.");
   }

   return true;
}

// Handles backtest inactivity stop.
bool HandleBacktestInactivityStop()
{
   if(!MQLInfoInteger(MQL_TESTER))
      return false;

   datetime now = SafeNow();
   if(now <= 0)
      return false;

   if(g_backtest_start_time == 0)
   {
      g_backtest_start_time = now;
      return false;
   }

   const int window_seconds = 30 * 24 * 60 * 60;
   if(now - g_backtest_start_time <= window_seconds)
      return false;

   PruneBacktestEntryTimes(now);
   if(ArraySize(g_recent_entry_times) > 0 || CountManagedOpenPositions() > 0)
      return false;

   Print("FXRC tester inactivity stop: no new positions were opened in the last 30 days. Removing expert.");
   ExpertRemove();
   return true;
}

// Handles trailing stop exits.
bool HandleTrailingStopExits()
{
   if(!IsClassicTrailingActive())
   {
      ArrayResize(g_trail_tickets, 0);
      ArrayResize(g_trail_peak_profit_usd, 0);
      return false;
   }

   SyncTrailingState();

   bool closed_any = false;
   double start_profit_usd = InpClassicSinglePositionTakeProfitUSD * (double)InpClassicTrailStartPct / 100.0;
   double giveback_frac = (double)InpClassicTrailSpacingPct / 100.0;

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

      double profit_usd = ManagedPositionProfitUSD(ticket);
      int idx = FindTrailingStateIndex(ticket);

      if(idx < 0 && profit_usd + EPS() >= start_profit_usd)
      {
         int new_size = ArraySize(g_trail_tickets) + 1;
         ArrayResize(g_trail_tickets, new_size);
         ArrayResize(g_trail_peak_profit_usd, new_size);
         g_trail_tickets[new_size - 1] = ticket;
         g_trail_peak_profit_usd[new_size - 1] = profit_usd;
         idx = new_size - 1;
      }

      if(idx < 0)
         continue;

      if(profit_usd > g_trail_peak_profit_usd[idx])
         g_trail_peak_profit_usd[idx] = profit_usd;

      double trail_floor = g_trail_peak_profit_usd[idx] * (1.0 - giveback_frac);
      if(profit_usd + EPS() < g_trail_peak_profit_usd[idx] && profit_usd <= trail_floor + EPS())
      {
         if(CloseManagedPositionTicket(ticket, "FXRC trailing stop"))
         {
            RemoveTrailingStateAt(idx);
            closed_any = true;
         }
      }
   }

   return closed_any;
}

// Handles single position take profits.
bool HandleSinglePositionTakeProfits()
{
   if(!IsClassicTakeProfitActive())
      return false;

   bool closed_any = false;

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

      double profit_usd = ManagedPositionProfitUSD(ticket);
      if(profit_usd + EPS() >= InpClassicSinglePositionTakeProfitUSD)
      {
         if(CloseManagedPositionTicket(ticket, "FXRC single position TP"))
            closed_any = true;
      }
   }

   return closed_any;
}

// Records backtest entry time.
void RecordBacktestEntryTime(const datetime when)
{
   if(!MQLInfoInteger(MQL_TESTER) || when <= 0)
      return;

   int new_size = ArraySize(g_recent_entry_times) + 1;
   ArrayResize(g_recent_entry_times, new_size);
   g_recent_entry_times[new_size - 1] = when;
}

// Prunes backtest entry times.
void PruneBacktestEntryTimes(const datetime now)
{
   const int window_seconds = 30 * 24 * 60 * 60;

   for(int i=ArraySize(g_recent_entry_times)-1; i>=0; --i)
   {
      if(now - g_recent_entry_times[i] <= window_seconds)
         continue;

      int last = ArraySize(g_recent_entry_times) - 1;
      if(i != last)
         g_recent_entry_times[i] = g_recent_entry_times[last];

      ArrayResize(g_recent_entry_times, last);
   }
}

// Synchronizes the trailing-stop state with the currently open positions.
void SyncTrailingState()
{
   for(int i=ArraySize(g_trail_tickets)-1; i>=0; --i)
   {
      if(g_trail_tickets[i] == 0
         || !PositionSelectByTicket(g_trail_tickets[i])
         || !IsSelectedFXRCPosition())
         RemoveTrailingStateAt(i);
   }
}

// Removes trailing state at.
void RemoveTrailingStateAt(const int idx)
{
   int last = ArraySize(g_trail_tickets) - 1;
   if(idx < 0 || idx > last)
      return;

   if(idx != last)
   {
      g_trail_tickets[idx] = g_trail_tickets[last];
      g_trail_peak_profit_usd[idx] = g_trail_peak_profit_usd[last];
   }

   ArrayResize(g_trail_tickets, last);
   ArrayResize(g_trail_peak_profit_usd, last);
}

// Finds trailing state index.
int FindTrailingStateIndex(const ulong ticket)
{
   for(int i=0; i<ArraySize(g_trail_tickets); ++i)
   {
      if(g_trail_tickets[i] == ticket)
         return i;
   }
   return -1;
}

// Returns the managed position profit in USD.
double ManagedPositionProfitUSD(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket) || !IsSelectedFXRCPosition())
      return -DBL_MAX;

   string account_ccy = AccountInfoString(ACCOUNT_CURRENCY);
   double net_profit = PositionGetDouble(POSITION_PROFIT)
                     + PositionGetDouble(POSITION_SWAP)
                     + PositionCommissionCash(ticket);

   double profit_usd = 0.0;
   if(!TryConvertCash(account_ccy, "USD", net_profit, profit_usd))
      return -DBL_MAX;

   return profit_usd;
}

// Returns the commission cash booked against the position.
double PositionCommissionCash(const ulong ticket)
{
   if(ticket == 0)
      return 0.0;

   if(!HistorySelectByPosition(ticket))
      return 0.0;

   double total_commission = 0.0;
   int deals = HistoryDealsTotal();
   for(int i=0; i<deals; ++i)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0)
         continue;

      total_commission += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
   }

   return total_commission;
}

// Ensures protective stops.
void EnsureProtectiveStops()
{
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

      int idx = FindTrackedSymbolIndex(symbol);
      EnsureStopOnTicket(ticket, idx);
   }
}

// Ensures stop on ticket.
bool EnsureStopOnTicket(const ulong ticket, const int symbol_idx)
{
   if(ticket == 0)
      return false;

   if(!PositionSelectByTicket(ticket) || !IsSelectedFXRCPosition())
      return false;

   double sl = PositionGetDouble(POSITION_SL);
   if(sl > 0.0)
      return true;

   string symbol = PositionGetString(POSITION_SYMBOL);
   int dir = PositionDirFromType(PositionGetInteger(POSITION_TYPE));
   double atr_pct = 0.0;
   if(symbol_idx >= 0 && symbol_idx < g_num_symbols)
      atr_pct = g_atr_pct[symbol_idx];
   if(atr_pct <= EPS() && !EstimateEmergencyATRPct(symbol, atr_pct))
      return false;

   double entry_price, stop_price;
   if(!BuildProtectiveStop(symbol, dir, atr_pct, entry_price, stop_price))
      return false;

   MqlTradeRequest request;
   ZeroMemory(request);
   request.action = TRADE_ACTION_SLTP;
   request.symbol = symbol;
   request.position = ticket;
   request.magic = InpMagicNumber;
   request.sl = stop_price;
   request.tp = 0.0;

   MqlTradeResult result;
   return SendTradeRequestWithRetry(request, "protective stop", false, result);
}

// Resets strategy cycle state.
void ResetStrategyCycleState(const bool reset_session_baseline)
{
   ArrayInitialize(g_E, 0.0);
   ArrayInitialize(g_S, 0.0);
   ArrayInitialize(g_Conf, 0.0);
   ArrayInitialize(g_Omega, 1.0);
   ArrayInitialize(g_Rank, 0.0);
   ArrayInitialize(g_Carry, 0.0);
   ArrayInitialize(g_Value, 0.0);
   ArrayInitialize(g_ValueProxy, 0.0);
   ArrayInitialize(g_ValuePPP, 0.0);
   ArrayInitialize(g_ValueFairValue, 0.0);
   ArrayInitialize(g_ValuePPPWeight, 0.0);
   ArrayInitialize(g_ValueReliability, 0.0);
   ArrayInitialize(g_CompositeCore, 0.0);
   ArrayInitialize(g_CarryAnnualSpread, 0.0);
   ArrayInitialize(g_ValueGap, 0.0);
   ArrayInitialize(g_ValueMacroDate, 0);
   ArrayInitialize(g_K, 0.0);
   ArrayInitialize(g_K_long, 0.0);
   ArrayInitialize(g_K_short, 0.0);
   ArrayInitialize(g_Q, 0.0);
   ArrayInitialize(g_Q_long, 0.0);
   ArrayInitialize(g_Q_short, 0.0);
   ArrayInitialize(g_symbol_data_stale, false);
   ArrayInitialize(g_symbol_feature_failures, 0);
   ArrayInitialize(g_symbol_last_feature_success, 0);
   ArrayInitialize(g_theta_in_eff, 0.0);
   ArrayInitialize(g_theta_out_eff, 0.0);
   ArrayInitialize(g_persist_count, 0);
   ArrayInitialize(g_entry_dir_raw, 0);
   ArrayResize(g_trail_tickets, 0);
   ArrayResize(g_trail_peak_profit_usd, 0);

   if(reset_session_baseline)
   {
      string account_ccy = AccountInfoString(ACCOUNT_CURRENCY);
      double baseline_usd = 0.0;
      if(TryConvertCash(account_ccy, "USD", AccountInfoDouble(ACCOUNT_EQUITY), baseline_usd))
         g_session_start_equity_usd = baseline_usd;
      else
         g_session_start_equity_usd = 0.0;
   }
}
