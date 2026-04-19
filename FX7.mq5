//+------------------------------------------------------------------+
//|                                                          FX7.mq5 |
//| Regime-Conditioned Time-Series Momentum with Novelty Overlay     |
//| Single-file multi-symbol EA for MetaTrader 5                     |
//|                                                                  |
//| Notes                                                            |
//| - Core alpha: absolute time-series momentum                      |
//| - Overlay: candidate-subset novelty orthogonalization            |
//| - Execution: one managed position per symbol                     |
//| - Uses closed bars only for signal generation                    |
//+------------------------------------------------------------------+
#property strict
#property version   "7.00"

//------------------------- Inputs -----------------------------------//
input group "=== Universe / Schedule ==="
input string             InpSymbols                   = "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,USDCHF,EURJPY,GBPJPY,EURGBP,AUDNZD"; 
input string             InpTradableSymbols           = "";
input ENUM_TIMEFRAMES    InpSignalTF                  = PERIOD_M15;
input bool               InpDebugStartupSequence      = false;
input bool               InpProcessCurrentClosedBarOnAttach = false;
input bool               InpRequireSynchronizedSignalBars = true;
input bool               InpAllowLong                 = true;
input bool               InpAllowShort                = true;
input int                InpMaxAcceptedSignals        = 5;
input int                InpMaxAccountOrders          = 5;

input group "=== FX Premia Composite ==="
input double             InpWeightMomentum            = 0.50;
input double             InpWeightCarry               = 0.25;
input double             InpWeightValue               = 0.25;
input bool               InpUseDynamicAllocator       = true;
enum ENUM_FXRC_CARRY_MODEL
{
   FXRC_CARRY_MODEL_BROKER_SWAP = 0,
   FXRC_CARRY_MODEL_RATE_DIFF = 1
};
enum ENUM_FXRC_VALUE_MODEL
{
   FXRC_VALUE_MODEL_PROXY = 0,
   FXRC_VALUE_MODEL_PPP = 1,
   FXRC_VALUE_MODEL_HYBRID = 2
};
input ENUM_FXRC_CARRY_MODEL InpCarryModel             = FXRC_CARRY_MODEL_RATE_DIFF;
input string             InpCarryDataFile             = "FXRC_CarryRates.csv";
input bool               InpCarryUseCommonFile        = false;
input bool               InpCarryAllowBrokerFallback  = false;
input int                InpCarryMaxDataAgeDays       = 35;
input int                InpCarryReloadHours          = 12;
input ENUM_FXRC_VALUE_MODEL InpValueModel             = FXRC_VALUE_MODEL_PPP;
input ENUM_TIMEFRAMES    InpValueTF                   = PERIOD_D1;
input int                InpValueLookbackBars         = 252;
input int                InpValueHalfLifeBars         = 63;
input double             InpValueSignalScale          = 1.50;
input string             InpPPPDataFile               = "FXRC_PPP_CPI.csv";
input bool               InpPPPUseCommonFile          = false;
input bool               InpPPPAllowProxyFallback     = false;
input int                InpPPPMaxDataAgeDays         = 92;
input int                InpPPPReloadHours            = 12;
input double             InpPPPGapScale               = 0.15;
input double             InpPPPBlendWeight            = 0.65;
input double             InpProxyBlendWeight          = 0.35;
input double             InpCarrySignalScale          = 0.04;
input double             InpAllocatorMomentumBoost    = 0.35;
input double             InpAllocatorValueBoost       = 0.25;
input double             InpAllocatorCarryVolPenalty  = 1.00;
input double             InpCarryVolCutoff            = 1.25;

input group "=== Trend Core ==="
input int                InpH1                        = 8;
input int                InpH2                        = 24;
input int                InpH3                        = 72;
input double             InpW1                        = 0.45;
input double             InpW2                        = 0.35;
input double             InpW3                        = 0.20;
input double             InpTanhScale                 = 2.0;
input int                InpERWindow                  = 12;
input int                InpBreakoutWindow            = 12;
input int                InpShortReversalWindow       = 4;

input group "=== Volatility / Regime ==="
input int                InpVolShortHalfLife          = 8;
input int                InpVolLongHalfLife           = 32;
input int                InpATRWindow                 = 14;
input double             InpGammaA                    = 0.8;
input double             InpGammaER                   = 0.8;
input double             InpGammaV                    = 0.6;
input double             InpGammaD                    = 0.4;
input double             InpV0                        = 1.50;
input double             InpGammaB                    = 0.5;
input double             InpGammaP                    = 0.4;
input double             InpVPanic                    = 1.80;

input group "=== Cost / Thresholds ==="
input double             InpBaseEntryThreshold        = 0.02;
input double             InpBaseExitThreshold         = 0.01;
input double             InpReversalThreshold         = 0.04;
input double             InpTheta0                    = 0.05;
input double             InpConfSlope                 = 6.0;
input double             InpAlphaSmooth               = 0.55;
input double             InpEtaCost                   = 0.05;
input double             InpEtaVol                    = 0.02;
input double             InpEtaBreakout               = 0.02;
input double             InpGammaCost                 = 0.50;
input double             InpAssumedRoundTripFeePct    = 0.00000;
input double             InpCommissionRoundTripPerLotEUR = 0.00;
input double             InpExpectedHoldingDays       = 5.0;

enum ENUM_FXRC_TRADE_MODEL
{
   FXRC_TRADE_MODEL_CLASSIC = 0,
   FXRC_TRADE_MODEL_MODERN = 1
};

input group "=== Trade Model / Sizing ==="
input ENUM_FXRC_TRADE_MODEL Trade_Model    = FXRC_TRADE_MODEL_CLASSIC;
input double             InpModernBaseTargetRiskPct = 0.20;
input double             InpModernMinTargetRiskPct  = 0.05;
input double             InpModernTargetATRPct      = 0.0060;
input double             InpModernVolAdjustMin      = 0.60;
input double             InpModernVolAdjustMax      = 1.60;
input double             InpModernCovariancePenaltyFloor = 0.50;
input double             InpModernForecastRiskATRScale   = 1.00;

input group "=== Risk / Execution ==="
input long               InpMagicNumber              = 420004;
input double             InpClassicReferenceEURUSDLots       = 0.01;
input double             InpRiskPerTradePct           = 0.35;
input double             InpMaxPortfolioRiskPct       = 1.75;
input double             InpMaxPortfolioExposurePct   = 100.0;
input double             InpMaxMarginUsagePct         = 35.0;
input double             InpCatastrophicStopATR       = 3.0;
input double             InpClassicSinglePositionTakeProfitUSD = 5.0;
input double             InpClassicSessionResetProfitUSD     = 10.0;
input int                InpClassicUseTrailingStop              = 1;
input int                InpClassicTrailStartPct                = 50;
input int                InpClassicTrailSpacingPct              = 20;
input int                EAStopMinEqui                = 0;
input double             EAStopMaxDD                  = 0.0;
input double             InpMinConfidence             = 0.30;
input double             InpMinRegimeGate             = 0.02;
input double             InpHardMinRegimeGate         = 0.01;
input double             InpMinExecGate               = 0.02;
input int                InpPersistenceBars           = 1;
input int                InpSlippagePoints            = 20;
input int                InpTradeRetryCount           = 2;
input int                InpTradeVerifyAttempts       = 3;

input group "=== Dependency Failure Policy ==="
input bool               InpFreezeEntriesOnDependencyFailure = true;
input bool               InpFlattenOnPersistentDependencyFailure = true;
input int                InpDependencyFailureGraceMinutes = 60;
input bool               InpDisableEAAfterEmergencyFlatten = true;

input group "=== Symbol Data Failure Handling ==="
input int                InpSymbolDataFailureGraceBars = 2;

input group "=== Correlation / Novelty Overlay ==="
input int                InpCorrLookback              = 40;
input double             InpShrinkageLambda           = 0.25;
input double             InpNoveltyFloorWeight        = 0.50;
input double             InpNoveltyCap                = 2.00;
input int                InpMinCandidatesForOrtho     = 2;
input double             InpUniquenessMin             = 0.15;
input double             InpCrowdingMax               = 0.90;
input double             InpFXOverlapFloor            = 0.35;
input double             InpClassOverlapFloor         = 0.20;

struct FXRCSymbolExecutionState
{
   int    dir;
   int    count;
   double volume;
   bool   mixed;
   int    account_active_orders;
};

struct FXRCExecutionSnapshot
{
   double open_risk_cash;
   double open_exposure_eur;
   double current_margin_cash;
   int    account_active_orders;
   bool   all_protected;
};

struct FXRCPPPCacheState
{
   bool     loaded;
   bool     available;
   datetime last_load_time;
   datetime last_success_time;
   int      record_count;
   int      currency_count;
   string   source_file;
   string   reason;
};

struct FXRCCarryCacheState
{
   bool     loaded;
   bool     available;
   datetime last_load_time;
   datetime last_success_time;
   int      record_count;
   int      currency_count;
   string   source_file;
   string   reason;
};

//------------------------- Globals ----------------------------------//
string   g_symbols[];
bool     g_trade_allowed[];
string   g_base_ccy[];
string   g_quote_ccy[];
datetime g_last_closed_bar[];
datetime g_last_processed_signal_bar[];
bool     g_symbol_bar_advanced[];

double   g_sigma_short[];
double   g_sigma_long[];
double   g_atr_pct[];
double   g_M[];
double   g_A[];
double   g_ER[];
double   g_V[];
double   g_D[];
double   g_BK[];
double   g_G[];
double   g_K[];
double   g_K_long[];
double   g_K_short[];
double   g_Q[];
double   g_Q_long[];
double   g_Q_short[];
double   g_PG[];
double   g_E[];
double   g_S[];
double   g_Conf[];
double   g_Omega[];
double   g_Rank[];
double   g_Carry[];
double   g_Value[];
double   g_ValueProxy[];
double   g_ValuePPP[];
double   g_ValueFairValue[];
double   g_ValuePPPWeight[];
double   g_ValueReliability[];
double   g_CompositeCore[];
double   g_CarryAnnualSpread[];
double   g_ValueGap[];
datetime g_ValueMacroDate[];
double   g_theta_in_eff[];
double   g_theta_out_eff[];
int      g_persist_count[];
int      g_entry_dir_raw[];
bool     g_symbol_data_ok[];
bool     g_symbol_data_stale[];
int      g_symbol_feature_failures[];
datetime g_symbol_last_feature_success[];
bool     g_symbol_history_ready[];
datetime g_symbol_latest_history_bar[];
int      g_symbol_history_bars[];
string   g_symbol_history_reason[];
FXRCSymbolExecutionState g_exec_symbol_state[];

int      g_num_symbols = 0;
int      g_ret_hist_len = 0;
double   g_stdret_hist[];
double   g_corr_matrix[];
double   g_corr_eff[];

double   g_universe_stdret_hist[];

double   g_w1 = 0.45;
double   g_w2 = 0.35;
double   g_w3 = 0.20;
double   g_reference_eur_notional = 0.0;
double   g_session_start_equity_usd = 0.0;
double   g_equi_max = 0.0;
bool     g_conversion_error_logged = false;
bool     g_conversion_error_active = false;
string   g_conversion_error_reason = "";
string   g_conversion_cache_from[];
string   g_conversion_cache_to[];
double   g_conversion_cache_rate[];
datetime g_conversion_cache_time[];
ulong    g_trail_tickets[];
double   g_trail_peak_profit_usd[];
datetime g_backtest_start_time = 0;
datetime g_recent_entry_times[];
int      g_tester_diag_logs = 0;
string   g_carry_record_ccy[];
datetime g_carry_record_date[];
double   g_carry_record_rate[];
string   g_carry_index_ccy[];
int      g_carry_index_start[];
int      g_carry_index_count[];
FXRCCarryCacheState g_carry_cache;
string   g_ppp_record_ccy[];
datetime g_ppp_record_date[];
double   g_ppp_record_cpi[];
string   g_ppp_index_ccy[];
int      g_ppp_index_start[];
int      g_ppp_index_count[];
FXRCPPPCacheState g_ppp_cache;

struct FXRCTradePlan
{
   string symbol;
   int    dir;
   double volume;
   double entry_price;
   double stop_price;
   double risk_cash;
   double notional_eur;
   double margin_cash;
   double target_risk_pct;
   double sizing_score;
   double volatility_multiplier;
   double covariance_multiplier;
};

struct FXRCCandidate
{
   int    symbol_idx;
   int    dir;
   double priority;
   double score;
   double confidence;
   double entry_threshold;
   double regime_gate;
   double exec_gate;
   double novelty_rank;
};

enum ENUM_FXRC_RUNTIME_STATUS
{
   FXRC_RUNTIME_STARTING = 0,
   FXRC_RUNTIME_WAITING_DATA = 1,
   FXRC_RUNTIME_READY = 2,
   FXRC_RUNTIME_FATAL = 3
};

enum ENUM_FXRC_DEPENDENCY_STATE
{
   FXRC_DEPENDENCY_HEALTHY = 0,
   FXRC_DEPENDENCY_DEGRADED = 1,
   FXRC_DEPENDENCY_SHUTDOWN_PENDING = 2,
   FXRC_DEPENDENCY_DISABLED = 3
};

struct FXRCHistoryCheck
{
   bool     feed_ready;
   bool     enough_bars;
   datetime latest_bar;
   int      bars_available;
   string   reason;
};

struct FXRCRuntimeState
{
   ENUM_FXRC_RUNTIME_STATUS status;
   int      ready_symbols;
   bool     chart_feed_ready;
   datetime latest_chart_bar;
   datetime last_log_time;
   string   reason;
   string   last_log_key;
};

FXRCRuntimeState g_runtime_state;

struct FXRCDependencyRuntimeState
{
   ENUM_FXRC_DEPENDENCY_STATE status;
   bool     failure_active;
   datetime first_failure_time;
   datetime last_success_time;
   string   failure_reason;
   string   dependency_scope;
   bool     flatten_triggered;
};

FXRCDependencyRuntimeState g_dependency_state;
bool     g_hard_stop_active = false;
string   g_hard_stop_reason = "";

struct FXRCManagedStateVerification
{
   string   symbol;
   int      expected_dir;
   int      attempts;
   datetime created_time;
   datetime next_check_time;
   string   context;
};

FXRCManagedStateVerification g_pending_state_verifications[];
bool     g_execution_state_dirty = false;

//------------------------- Read Path -------------------------------//
// 1. EA entry points
// 2. Runtime flow and risk orchestration
// 3. Trade planning and execution plumbing
// 4. Signal construction and portfolio selection
// 5. Feature pipeline and external data layers
// 6. Pricing, startup, and core helpers

//------------------------- EA Entry Points -------------------------//
int OnInit()
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

   if(InpCarryModel != FXRC_CARRY_MODEL_RATE_DIFF || InpCarryAllowBrokerFallback)
   {
      PrintFormat("FXRC startup warning: carry model is %s with broker fallback=%s. Pure external carry is not enforced.",
                  EnumToString(InpCarryModel),
                  (InpCarryAllowBrokerFallback ? "true" : "false"));
   }
   if(InpValueModel != FXRC_VALUE_MODEL_PPP || InpPPPAllowProxyFallback)
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
      string carry_detail = (carry_ok ? StringFormat("%d rows", g_carry_cache.record_count) : g_carry_cache.reason);
      string carry_status = (carry_ok ? "Done" : "Fallback");

      if(CarrySignalRequiresExternalData())
      {
         if(!carry_ok)
         {
            LogStartupStep(8, total_steps, "Load carry macro cache", "Failed", carry_detail);
            PrintFormat("Required external carry data is unavailable. %s", carry_detail);
            return INIT_FAILED;
         }

         string coverage_reason;
         if(!ValidateRequiredCarryCoverage(coverage_reason))
         {
            LogStartupStep(8, total_steps, "Load carry macro cache", "Failed", coverage_reason);
            PrintFormat("Required external carry data coverage failed: %s", coverage_reason);
            return INIT_FAILED;
         }
      }

      LogStartupStep(8, total_steps, "Load carry macro cache", carry_status, carry_detail);
   }
   else
   {
      LogStartupStep(8, total_steps, "Load carry macro cache", "Skipped", "broker-swap carry model");
   }

   if(ValueModelUsesPPP())
   {
      bool ppp_ok = EnsurePPPDataCache(true);
      string ppp_detail = (ppp_ok ? StringFormat("%d rows", g_ppp_cache.record_count) : g_ppp_cache.reason);
      string ppp_status = (ppp_ok ? "Done" : "Fallback");

      if(ValueSignalRequiresPPPData())
      {
         if(!ppp_ok)
         {
            LogStartupStep(9, total_steps, "Load PPP macro cache", "Failed", ppp_detail);
            PrintFormat("Required PPP data is unavailable. %s", ppp_detail);
            return INIT_FAILED;
         }

         string coverage_reason;
         if(!ValidateRequiredPPPCoverage(coverage_reason))
         {
            LogStartupStep(9, total_steps, "Load PPP macro cache", "Failed", coverage_reason);
            PrintFormat("Required PPP data coverage failed: %s", coverage_reason);
            return INIT_FAILED;
         }
      }

      LogStartupStep(9, total_steps, "Load PPP macro cache", ppp_status, ppp_detail);
   }
   else
   {
      LogStartupStep(9, total_steps, "Load PPP macro cache", "Skipped", "statistical-anchor proxy value model");
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

void OnTick()
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

void OnDeinit(const int reason)
{
   EventKillTimer();
   ArrayResize(g_pending_state_verifications, 0);
   g_execution_state_dirty = false;
}

void OnTimer()
{
   ProcessPendingTradeVerifications(true);
}

void OnTradeTransaction(const MqlTradeTransaction& trans,
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

void ClearSignalBarAdvanceFlags()
{
   if(ArraySize(g_symbol_bar_advanced) == g_num_symbols)
      ArrayInitialize(g_symbol_bar_advanced, false);
}

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

   for(int i=0; i<g_num_symbols; ++i)
   {
      FXRCHistoryCheck symbol_check;
      bool symbol_ready = InspectSymbolHistory(g_symbols[i], InpSignalTF, bars_needed, MQLInfoInteger(MQL_TESTER), symbol_check);
      g_symbol_history_ready[i] = symbol_ready;
      g_symbol_latest_history_bar[i] = symbol_check.latest_bar;
      g_symbol_history_bars[i] = symbol_check.bars_available;
      g_symbol_history_reason[i] = symbol_check.reason;
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

void RefreshCycleExecutionState(FXRCExecutionSnapshot &snapshot, int &active_orders_total)
{
   RefreshExecutionSnapshot(snapshot);
   active_orders_total = snapshot.account_active_orders;
}

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

void RecordBacktestEntryTime(const datetime when)
{
   if(!MQLInfoInteger(MQL_TESTER) || when <= 0)
      return;

   int new_size = ArraySize(g_recent_entry_times) + 1;
   ArrayResize(g_recent_entry_times, new_size);
   g_recent_entry_times[new_size - 1] = when;
}

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

int FindTrailingStateIndex(const ulong ticket)
{
   for(int i=0; i<ArraySize(g_trail_tickets); ++i)
   {
      if(g_trail_tickets[i] == ticket)
         return i;
   }
   return -1;
}

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

//------------------------- Trade Planning And Execution -------------------------//
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

//------------------------- Signal Construction And Selection -------------------------//
double PortfolioCrowdingIfAdded(const int idx, const int dir, const int &accepted[], const int accepted_count)
{
   if(accepted_count <= 0)
      return 0.0;

   double sum = 0.0;
   int pairs = 0;

   for(int a=0; a<accepted_count; ++a)
   {
      int ia = accepted[a];
      int da = g_entry_dir_raw[ia];
      for(int b=a+1; b<accepted_count; ++b)
      {
         int ib = accepted[b];
         int db = g_entry_dir_raw[ib];
         double rho = g_corr_eff[MatIdx(ia, ib, g_num_symbols)];
         double same_way = (double)(da * db) * rho;
         if(same_way > 0.0)
            sum += same_way;
         pairs++;
      }
   }

   for(int a=0; a<accepted_count; ++a)
   {
      int ia = accepted[a];
      int da = g_entry_dir_raw[ia];
      double rho = g_corr_eff[MatIdx(idx, ia, g_num_symbols)];
      double same_way = (double)(dir * da) * rho;
      if(same_way > 0.0)
         sum += same_way;
      pairs++;
   }

   if(pairs <= 0)
      return 0.0;
   return sum / (double)pairs;
}

double CandidateUniqueness(const int idx, const int dir, const int &accepted[], const int accepted_count)
{
   double sum_pos = 0.0;
   for(int k=0; k<accepted_count; ++k)
   {
      int j = accepted[k];
      int dj = g_entry_dir_raw[j];
      double rho = g_corr_eff[MatIdx(idx, j, g_num_symbols)];
      double same_way = (double)(dir * dj) * rho;
      if(same_way > 0.0)
         sum_pos += same_way;
   }
   return 1.0 / (1.0 + sum_pos);
}

void ComputeNoveltyOverlay(const int &candidates[])
{
   for(int i=0; i<g_num_symbols; ++i)
   {
      g_Omega[i] = 1.0;
      g_Rank[i] = MathAbs(g_S[i]) * g_Conf[i];
   }

   int n = ArraySize(candidates);
   if(n < InpMinCandidatesForOrtho)
      return;

   double A[];
   double rhs[];
   double sol[];
   ArrayResize(A, n * n);
   ArrayResize(rhs, n);

   for(int row=0; row<n; ++row)
   {
      int i = candidates[row];
      rhs[row] = g_S[i];
      for(int col=0; col<n; ++col)
      {
         int j = candidates[col];
         double v = g_corr_matrix[MatIdx(i, j, g_num_symbols)];
         if(row == col)
            v = (1.0 - InpShrinkageLambda) * v + InpShrinkageLambda;
         else
            v = (1.0 - InpShrinkageLambda) * v;
         A[MatIdx(row, col, n)] = v;
      }
   }

   if(!SolveLinearSystem(A, rhs, sol, n))
   {
      Print("Candidate novelty overlay solve failed; falling back to raw ranking.");
      return;
   }

   for(int row=0; row<n; ++row)
   {
      int idx = candidates[row];
      double psi = (double)SignD(g_S[idx]) * sol[row];
      double omega = Clip(psi / (MathAbs(g_S[idx]) + EPS()), 0.0, InpNoveltyCap);
      g_Omega[idx] = omega;
      g_Rank[idx] = MathAbs(g_S[idx]) * g_Conf[idx] * (InpNoveltyFloorWeight + (1.0 - InpNoveltyFloorWeight) * omega);
   }
}

void BuildCorrelationMatrices()
{
   for(int i=0; i<g_num_symbols; ++i)
   {
      for(int j=0; j<g_num_symbols; ++j)
      {
         double rho = 0.0;
         if(i == j)
            rho = 1.0;
         else if(IsCrossSectionallyEligibleSymbol(i) && IsCrossSectionallyEligibleSymbol(j))
            rho = PearsonCorrFlat(g_stdret_hist, i, j, InpCorrLookback, g_ret_hist_len);

         g_corr_matrix[MatIdx(i, j, g_num_symbols)] = rho;

         double eff = rho;
         if(i == j)
            eff = 1.0;
         else if(IsCrossSectionallyEligibleSymbol(i) && IsCrossSectionallyEligibleSymbol(j))
         {
            if(SharesCurrency(i, j))
               eff = MathMax(eff, InpFXOverlapFloor);
            else if(SameClassOverlap(i, j))
               eff = MathMax(eff, InpClassOverlapFloor);
         }

         g_corr_eff[MatIdx(i, j, g_num_symbols)] = Clip(eff, -1.0, 1.0);
      }
   }
}

void UpdatePanicGateAndScores()
{
   BuildUniverseStdRet();

   double zu5_sum = 0.0;
   int zu_count = MathMin(5, g_ret_hist_len);
   for(int k=0; k<zu_count; ++k)
      zu5_sum += g_universe_stdret_hist[k];
   double Zu5 = zu5_sum / MathSqrt((double)MathMax(zu_count, 1));

   double su = EWMAStdFromSeriesNewestFirst(g_universe_stdret_hist, MathMin(20, g_ret_hist_len), 20);
   double lu = EWMAStdFromSeriesNewestFirst(g_universe_stdret_hist, MathMin(100, g_ret_hist_len), 100);
   double Vu = su / (lu + EPS());

   for(int i=0; i<g_num_symbols; ++i)
   {
      if(!g_symbol_data_ok[i])
      {
         g_PG[i] = 1.0;
         g_E[i] = 0.0;
         g_Conf[i] = 0.0;
         g_theta_in_eff[i] = 0.0;
         g_theta_out_eff[i] = 0.0;
         g_entry_dir_raw[i] = 0;
         g_persist_count[i] = 0;
         continue;
      }

      if(IsSymbolDataStale(i))
      {
         g_Conf[i] = 0.0;
         g_theta_in_eff[i] = BuildEntryThreshold(i);
         g_theta_out_eff[i] = BuildExitThreshold(i);
         g_entry_dir_raw[i] = 0;
         g_persist_count[i] = 0;
         continue;
      }

      bool bar_advanced = (ArraySize(g_symbol_bar_advanced) == g_num_symbols && g_symbol_bar_advanced[i]);

      int alpha_dir = SignD(g_CompositeCore[i]);
      if(alpha_dir == 0)
         alpha_dir = SignD(g_M[i]);
      g_PG[i] = MathExp(-InpGammaP * PosPart(Vu - InpVPanic) * PosPart(-(double)alpha_dir * Zu5));
      // Regime/cost remain hard gates below; keep the score focused on directional conviction.
      g_E[i] = BuildSignalCoreScore(i);
      if(bar_advanced || g_last_processed_signal_bar[i] == 0)
      {
         g_S[i] = InpAlphaSmooth * g_E[i] + (1.0 - InpAlphaSmooth) * g_S[i];
         g_last_processed_signal_bar[i] = g_last_closed_bar[i];
      }
      g_Conf[i] = BuildSignalConfidence(i);

      g_theta_in_eff[i] = BuildEntryThreshold(i);

      g_theta_out_eff[i] = BuildExitThreshold(i);

      int dir = 0;
      bool has_raw_direction = BuildSignalDirection(i, dir);

      if(has_raw_direction)
      {
         if(bar_advanced || g_last_processed_signal_bar[i] == 0)
         {
            if(g_entry_dir_raw[i] == dir)
               g_persist_count[i]++;
            else
               g_persist_count[i] = 1;
         }
         else if(g_entry_dir_raw[i] != dir)
         {
            g_persist_count[i] = 0;
         }

         g_entry_dir_raw[i] = dir;
      }
      else
      {
         g_entry_dir_raw[i] = 0;
         g_persist_count[i] = 0;
      }
   }
}

bool ShouldExitManagedDirection(const int idx, const int current_dir)
{
   if(idx < 0 || idx >= g_num_symbols || current_dir == 0)
      return false;
   if(!g_symbol_data_ok[idx])
      return true;
   if(IsSymbolDataStale(idx))
      return false;

   double exec_floor = InpMinExecGate;
   if(g_G[idx] < InpHardMinRegimeGate || DirectionalExecGate(idx, current_dir) < exec_floor)
      return true;

   double exit_threshold = BuildExitThresholdDirectional(idx, current_dir);
   if(current_dir > 0)
      return (g_S[idx] <= exit_threshold);

   return (g_S[idx] >= -exit_threshold);
}

void BuildTradeTargets(const int &candidate_indices[], int &target_dir[])
{
   ArrayResize(target_dir, g_num_symbols);
   ArrayInitialize(target_dir, 0);

   FXRCCandidate ranked[];
   ArrayResize(ranked, 0);

   for(int i=0; i<ArraySize(candidate_indices); ++i)
   {
      FXRCCandidate candidate;
      if(!BuildCandidateRecord(candidate_indices[i], candidate))
         continue;

      int new_size = ArraySize(ranked) + 1;
      ArrayResize(ranked, new_size);
      ranked[new_size - 1] = candidate;
   }

   if(ArraySize(ranked) == 0)
      return;

   SortCandidateRecords(ranked);

   int accepted[];
   ArrayResize(accepted, 0);

   for(int i=0; i<ArraySize(ranked); ++i)
   {
      if(ArraySize(accepted) >= InpMaxAcceptedSignals)
         break;

      int idx = ranked[i].symbol_idx;
      int dir = ranked[i].dir;
      if(!IsTradeAllowed(idx))
         continue;
      if(!CandidatePassesReversalThreshold(idx, dir))
         continue;

      double uniqueness = CandidateUniqueness(idx, dir, accepted, ArraySize(accepted));
      if(uniqueness + EPS() < InpUniquenessMin)
         continue;

      double crowding = PortfolioCrowdingIfAdded(idx, dir, accepted, ArraySize(accepted));
      if(crowding - EPS() > InpCrowdingMax)
         continue;

      target_dir[idx] = dir;

      int new_size = ArraySize(accepted) + 1;
      ArrayResize(accepted, new_size);
      accepted[new_size - 1] = idx;
   }
}

bool CandidatePassesReversalThreshold(const int idx, const int target_dir)
{
   if(idx < 0 || idx >= g_num_symbols || target_dir == 0)
      return false;

   if(ArraySize(g_exec_symbol_state) != g_num_symbols)
      return true;

   if(g_exec_symbol_state[idx].mixed || g_exec_symbol_state[idx].count <= 0)
      return true;

   int current_dir = g_exec_symbol_state[idx].dir;
   if(current_dir == 0 || current_dir == target_dir)
      return true;

   return (MathAbs(g_S[idx]) + EPS() >= InpReversalThreshold);
}

void SortCandidateRecords(FXRCCandidate &candidates[])
{
   int n = ArraySize(candidates);
   for(int i=0; i<n-1; ++i)
   {
      int best = i;
      for(int j=i+1; j<n; ++j)
      {
         if(candidates[j].priority > candidates[best].priority)
            best = j;
      }

      if(best != i)
      {
         FXRCCandidate tmp = candidates[i];
         candidates[i] = candidates[best];
         candidates[best] = tmp;
      }
   }
}

bool BuildCandidateRecord(const int idx, FXRCCandidate &candidate)
{
   ResetCandidate(candidate);

   if(idx < 0 || idx >= g_num_symbols)
      return false;
   if(!g_symbol_data_ok[idx])
      return false;
   if(g_entry_dir_raw[idx] == 0 || g_persist_count[idx] < InpPersistenceBars)
      return false;
   if(!CandidateMeetsMinimumGates(idx, g_entry_dir_raw[idx]))
      return false;

   candidate.symbol_idx = idx;
   candidate.dir = g_entry_dir_raw[idx];
   candidate.priority = BuildCandidatePriority(idx, candidate.dir);
   candidate.score = g_S[idx];
   candidate.confidence = g_Conf[idx];
   candidate.entry_threshold = BuildEntryThresholdDirectional(idx, candidate.dir);
   candidate.regime_gate = g_G[idx];
   candidate.exec_gate = DirectionalExecGate(idx, candidate.dir);
   candidate.novelty_rank = g_Rank[idx];

   return (candidate.priority > EPS());
}

double BuildCandidatePriority(const int idx, const int dir = 0)
{
   double base_rank = MathMax(g_Rank[idx], MathAbs(g_S[idx]) * g_Conf[idx]);
   double gate_weight = 0.50 + 0.25 * Clip(g_G[idx], 0.0, 1.0) + 0.25 * Clip(DirectionalExecGate(idx, dir), 0.0, 1.0);
   double momentum_weight = 0.60 + 0.40 * MathMin(MathAbs(g_M[idx]), 1.0);
   return base_rank * gate_weight * momentum_weight;
}

bool BuildSignalDirection(const int idx, int &dir)
{
   dir = 0;
   if(idx < 0 || idx >= g_num_symbols || !g_symbol_data_ok[idx] || IsSymbolDataStale(idx))
      return false;

   double long_threshold = MathMax(BuildEntryThresholdDirectional(idx, 1), InpBaseEntryThreshold);
   double short_threshold = MathMax(BuildEntryThresholdDirectional(idx, -1), InpBaseEntryThreshold);

   if(g_S[idx] >= long_threshold && InpAllowLong)
      dir = 1;
   else if(g_S[idx] <= -short_threshold && InpAllowShort)
      dir = -1;
   else
   {
      int alpha_dir = SignD(g_CompositeCore[idx]);
      if(alpha_dir > 0 && InpAllowLong)
      {
         double soft_threshold = 0.60 * long_threshold;
         if(g_S[idx] >= soft_threshold && g_E[idx] > 0.0)
            dir = 1;
      }
      else if(alpha_dir < 0 && InpAllowShort)
      {
         double soft_threshold = 0.60 * short_threshold;
         if(g_S[idx] <= -soft_threshold && g_E[idx] < 0.0)
            dir = -1;
      }
   }

   return (dir != 0);
}

bool CandidateMeetsMinimumGates(const int idx, const int dir = 0)
{
   if(idx < 0 || idx >= g_num_symbols || !g_symbol_data_ok[idx] || IsSymbolDataStale(idx))
      return false;

   double conf_floor = InpMinConfidence;
   double regime_floor = InpMinRegimeGate;
   double exec_floor = InpMinExecGate;

   return (g_Conf[idx] >= conf_floor
        && g_G[idx] >= regime_floor
        && DirectionalExecGate(idx, dir) >= exec_floor);
}

void ResetCandidate(FXRCCandidate &candidate)
{
   candidate.symbol_idx = -1;
   candidate.dir = 0;
   candidate.priority = 0.0;
   candidate.score = 0.0;
   candidate.confidence = 0.0;
   candidate.entry_threshold = 0.0;
   candidate.regime_gate = 0.0;
   candidate.exec_gate = 0.0;
   candidate.novelty_rank = 0.0;
}

double BuildExitThreshold(const int idx)
{
   double long_threshold = BuildExitThresholdDirectional(idx, 1);
   double short_threshold = BuildExitThresholdDirectional(idx, -1);
   return MathMax(long_threshold, short_threshold);
}

double BuildExitThresholdDirectional(const int idx, const int dir)
{
   return InpBaseExitThreshold
        + 0.10 * InpEtaCost * DirectionalCostPenaltyTerm(idx, dir);
}

double BuildEntryThreshold(const int idx)
{
   double long_threshold = BuildEntryThresholdDirectional(idx, 1);
   double short_threshold = BuildEntryThresholdDirectional(idx, -1);
   return MathMax(long_threshold, short_threshold);
}

double BuildEntryThresholdDirectional(const int idx, const int dir)
{
   return InpBaseEntryThreshold
        + 0.20 * InpEtaCost * DirectionalCostPenaltyTerm(idx, dir)
        + 0.20 * InpEtaVol * RegimePenaltyTerm(idx)
        + 0.10 * InpEtaBreakout * (1.0 - Clip(g_BK[idx], 0.0, 1.0));
}

double BuildSignalConfidence(const int idx)
{
   double signal_mag = MathMax(MathAbs(g_S[idx]), MathAbs(g_E[idx]));
   return Sigmoid(InpConfSlope * (signal_mag - InpTheta0));
}

double BuildSignalCoreScore(const int idx)
{
   return g_CompositeCore[idx] * g_PG[idx] * BreakoutParticipationWeight(idx);
}

double CostPenaltyTerm(const int idx)
{
   return DirectionalCostPenaltyTerm(idx, 0);
}

double DirectionalCostPenaltyTerm(const int idx, const int dir)
{
   if(idx < 0 || idx >= g_num_symbols)
      return 0.0;

   double k_value = DirectionalValue(dir, g_K_long[idx], g_K_short[idx], g_K[idx]);
   return PosPart(k_value - 1.0);
}

double DirectionalExecGate(const int idx, const int dir)
{
   if(idx < 0 || idx >= g_num_symbols)
      return 0.0;
   return DirectionalValue(dir, g_Q_long[idx], g_Q_short[idx], g_Q[idx]);
}

double RegimePenaltyTerm(const int idx)
{
   return PosPart(g_V[idx] - 1.0);
}

double BreakoutParticipationWeight(const int idx)
{
   double breakout = Clip(g_BK[idx], 0.0, 1.0);
   return 0.50 + 0.50 * MathPow(breakout, InpGammaB);
}

void BuildUniverseStdRet()
{
   for(int lag=0; lag<g_ret_hist_len; ++lag)
   {
      double s = 0.0;
      int valid = 0;
      for(int i=0; i<g_num_symbols; ++i)
      {
         if(!IsCrossSectionallyEligibleSymbol(i))
            continue;

         s += g_stdret_hist[i * g_ret_hist_len + lag];
         valid++;
      }

      g_universe_stdret_hist[lag] = (valid > 0 ? s / (double)valid : 0.0);
   }
}

//------------------------- Feature Pipeline -------------------------//
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
   datetime signal_time = rates[1].time;

   double carry_signal = 0.0;
   double carry_spread = 0.0;
   datetime carry_macro_date = 0;
   string carry_reason;
   bool carry_ok = ComputeCarrySignal(sym, signal_px, signal_time, carry_signal, carry_spread, carry_macro_date, carry_reason);
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
   bool value_ok = ResolveValueSignal(sym, signal_px, signal_time,
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

void NoteSymbolFeatureRefreshSuccess(const int i)
{
   if(i < 0 || i >= g_num_symbols)
      return;

   g_symbol_data_ok[i] = true;
   g_symbol_data_stale[i] = false;
   g_symbol_feature_failures[i] = 0;
   g_symbol_last_feature_success[i] = SafeNow();
}

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

double BuildCompositePremiaAlpha(const int idx)
{
   double w_m, w_c, w_v;
   ComputeCompositeAllocatorWeights(idx, w_m, w_c, w_v);
   // Value is intentionally treated as a slow, reliability-scaled bias in the composite.
   return w_m * g_M[idx] + w_c * g_Carry[idx] + w_v * g_Value[idx];
}

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

void NormalizeValueBlendWeights(double &proxy_weight, double &ppp_weight)
{
   double sum = MathMax(proxy_weight + ppp_weight, EPS());
   proxy_weight /= sum;
   ppp_weight /= sum;
}

// Value is a slow contextual bias here, so attenuate it when the sources are weak,
// stale, disagree, or live on a much slower horizon than the execution model.
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

// Statistical-anchor proxy: pair-level mean-reversion anchor, used only as a conservative slow bias.

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

//------------------------- External Data And Dependencies -------------------------//
bool EvaluateRequiredDependencyHealth(const datetime asof_time, string &scope, string &reason)
{
   scope = "";
   reason = "";

   string carry_reason;
   bool carry_ok = EvaluateCarryDependencyHealth(asof_time, carry_reason);
   if(CarrySignalRequiresExternalData())
      scope = "carry";

   string value_reason;
   bool value_ok = EvaluatePPPDependencyHealth(asof_time, value_reason);
   if(ValueSignalRequiresPPPData())
      scope = (StringLen(scope) > 0 ? scope + "+PPP" : "PPP");

   if(carry_ok && value_ok)
      return true;

   if(!carry_ok && !value_ok)
   {
      scope = "carry+PPP";
      reason = "carry: " + carry_reason + "; PPP: " + value_reason;
      return false;
   }

   if(!carry_ok)
   {
      scope = "carry";
      reason = carry_reason;
      return false;
   }

   scope = "PPP";
   reason = value_reason;
   return false;
}

bool DependenciesRequiredAtRuntime()
{
   return (CarrySignalRequiresExternalData() || ValueSignalRequiresPPPData());
}

bool EvaluatePPPDependencyHealth(const datetime asof_time, string &reason)
{
   reason = "";
   if(!ValueSignalRequiresPPPData())
      return true;

   string coverage_reason;
   if(!ValidateRequiredPPPCoverage(coverage_reason))
   {
      reason = coverage_reason;
      return false;
   }

   for(int i=0; i<g_num_symbols; ++i)
   {
      double base_cpi = 0.0, quote_cpi = 0.0;
      datetime base_date = 0, quote_date = 0;
      if(!GetPPPRecordAtOrBefore(g_base_ccy[i], asof_time, base_cpi, base_date)
         || !GetPPPRecordAtOrBefore(g_quote_ccy[i], asof_time, quote_cpi, quote_date))
      {
         reason = StringFormat("PPP data missing at runtime for %s", g_symbols[i]);
         return false;
      }

      datetime macro_date = (datetime)MathMin((long)base_date, (long)quote_date);
      if(macro_date <= 0)
      {
         reason = StringFormat("PPP macro date is invalid for %s", g_symbols[i]);
         return false;
      }

      if((asof_time - macro_date) > (datetime)(InpPPPMaxDataAgeDays * 24 * 60 * 60))
      {
         reason = StringFormat("PPP data is stale for %s", g_symbols[i]);
         return false;
      }

      if(!GetPPPRecordAtOrBefore(g_base_ccy[i], macro_date, base_cpi, base_date)
         || !GetPPPRecordAtOrBefore(g_quote_ccy[i], macro_date, quote_cpi, quote_date))
      {
         reason = StringFormat("PPP date alignment failed for %s", g_symbols[i]);
         return false;
      }
   }

   return true;
}

bool EvaluateCarryDependencyHealth(const datetime asof_time, string &reason)
{
   reason = "";
   if(!CarrySignalRequiresExternalData())
      return true;

   string coverage_reason;
   if(!ValidateRequiredCarryCoverage(coverage_reason))
   {
      reason = coverage_reason;
      return false;
   }

   for(int i=0; i<g_num_symbols; ++i)
   {
      double base_rate = 0.0, quote_rate = 0.0;
      datetime base_date = 0, quote_date = 0;
      if(!GetCarryRecordAtOrBefore(g_base_ccy[i], asof_time, base_rate, base_date)
         || !GetCarryRecordAtOrBefore(g_quote_ccy[i], asof_time, quote_rate, quote_date))
      {
         reason = StringFormat("carry data missing at runtime for %s", g_symbols[i]);
         return false;
      }

      datetime macro_date = (datetime)MathMin((long)base_date, (long)quote_date);
      if(macro_date <= 0)
      {
         reason = StringFormat("carry macro date is invalid for %s", g_symbols[i]);
         return false;
      }

      if((asof_time - macro_date) > (datetime)(InpCarryMaxDataAgeDays * 24 * 60 * 60))
      {
         reason = StringFormat("carry data is stale for %s", g_symbols[i]);
         return false;
      }

      if(!GetCarryRecordAtOrBefore(g_base_ccy[i], macro_date, base_rate, base_date)
         || !GetCarryRecordAtOrBefore(g_quote_ccy[i], macro_date, quote_rate, quote_date))
      {
         reason = StringFormat("carry date alignment failed for %s", g_symbols[i]);
         return false;
      }
   }

   return true;
}

bool ValidateRequiredPPPCoverage(string &reason)
{
   reason = "";
   if(!ValueSignalRequiresPPPData())
      return true;
   if(!EnsurePPPDataCache(false) || !g_ppp_cache.available)
   {
      reason = "required PPP data is unavailable";
      return false;
   }

   for(int i=0; i<g_num_symbols; ++i)
   {
      if(FindPPPCurrencyIndex(g_base_ccy[i]) < 0)
      {
         reason = StringFormat("missing PPP data for base currency %s", g_base_ccy[i]);
         return false;
      }
      if(FindPPPCurrencyIndex(g_quote_ccy[i]) < 0)
      {
         reason = StringFormat("missing PPP data for quote currency %s", g_quote_ccy[i]);
         return false;
      }
   }

   return true;
}

bool ValidateRequiredCarryCoverage(string &reason)
{
   reason = "";
   if(!CarrySignalRequiresExternalData())
      return true;
   if(!EnsureCarryDataCache(false) || !g_carry_cache.available)
   {
      reason = "required external carry data is unavailable";
      return false;
   }

   for(int i=0; i<g_num_symbols; ++i)
   {
      if(FindCarryCurrencyIndex(g_base_ccy[i]) < 0)
      {
         reason = StringFormat("missing carry data for base currency %s", g_base_ccy[i]);
         return false;
      }
      if(FindCarryCurrencyIndex(g_quote_ccy[i]) < 0)
      {
         reason = StringFormat("missing carry data for quote currency %s", g_quote_ccy[i]);
         return false;
      }
   }

   return true;
}

bool EnsurePPPDataCache(const bool force_log)
{
   if(!ValueModelUsesPPP())
      return true;

   datetime now = SafeNow();
   if(!g_ppp_cache.loaded)
      return LoadPPPDataCache(force_log);

   if(MQLInfoInteger(MQL_TESTER))
      return g_ppp_cache.available;

   int reload_seconds = MathMax(1, InpPPPReloadHours) * 3600;
   if(now > 0 && g_ppp_cache.last_load_time > 0 && (now - g_ppp_cache.last_load_time) < reload_seconds)
      return g_ppp_cache.available;

   return LoadPPPDataCache(force_log);
}

bool LoadPPPDataCache(const bool force_log)
{
   FXRCPPPCacheState previous = g_ppp_cache;
   g_ppp_cache.loaded = true;
   g_ppp_cache.last_load_time = SafeNow();
   g_ppp_cache.source_file = InpPPPDataFile;

   int flags = FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
   if(InpPPPUseCommonFile)
      flags |= FILE_COMMON;

   ResetLastError();
   int handle = FileOpen(InpPPPDataFile, flags);
   if(handle == INVALID_HANDLE)
   {
      g_ppp_cache.reason = StringFormat("PPP data file open failed: %s err=%d", InpPPPDataFile, GetLastError());
      if(previous.available)
      {
         g_ppp_cache.available = true;
         g_ppp_cache.last_success_time = previous.last_success_time;
         g_ppp_cache.record_count = previous.record_count;
         g_ppp_cache.currency_count = previous.currency_count;
      }
      if(force_log)
         Print(g_ppp_cache.reason);
      return g_ppp_cache.available;
   }

   string temp_ccy[];
   datetime temp_dates[];
   double temp_cpi[];
   ArrayResize(temp_ccy, 0);
   ArrayResize(temp_dates, 0);
   ArrayResize(temp_cpi, 0);

   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      if(FileIsEnding(handle) && StringLen(line) == 0)
         break;

      string currency;
      datetime record_date;
      double cpi_value;
      if(!ParsePPPDataLine(line, currency, record_date, cpi_value))
         continue;

      int new_size = ArraySize(temp_ccy) + 1;
      ArrayResize(temp_ccy, new_size);
      ArrayResize(temp_dates, new_size);
      ArrayResize(temp_cpi, new_size);
      temp_ccy[new_size - 1] = currency;
      temp_dates[new_size - 1] = record_date;
      temp_cpi[new_size - 1] = cpi_value;
   }
   FileClose(handle);

   if(ArraySize(temp_ccy) <= 0)
   {
      g_ppp_cache.reason = StringFormat("PPP data file %s has no valid rows.", InpPPPDataFile);
      if(force_log)
         Print(g_ppp_cache.reason);
      return previous.available;
   }

   SortPPPRecords(temp_ccy, temp_dates, temp_cpi);

   ArrayCopy(g_ppp_record_ccy, temp_ccy);
   ArrayCopy(g_ppp_record_date, temp_dates);
   ArrayCopy(g_ppp_record_cpi, temp_cpi);
   BuildPPPIndexFromRecords(g_ppp_record_ccy);

   g_ppp_cache.available = (ArraySize(g_ppp_record_ccy) > 0 && ArraySize(g_ppp_index_ccy) > 0);
   g_ppp_cache.last_success_time = g_ppp_cache.last_load_time;
   g_ppp_cache.record_count = ArraySize(g_ppp_record_ccy);
   g_ppp_cache.currency_count = ArraySize(g_ppp_index_ccy);
   g_ppp_cache.reason = "";

   if(force_log)
   {
      PrintFormat("FXRC PPP cache loaded from %s with %d rows across %d currencies.",
                  InpPPPDataFile, g_ppp_cache.record_count, g_ppp_cache.currency_count);
   }

   return g_ppp_cache.available;
}

bool EnsureCarryDataCache(const bool force_log)
{
   if(!CarryModelUsesExternal())
      return true;

   datetime now = SafeNow();
   if(!g_carry_cache.loaded)
      return LoadCarryDataCache(force_log);

   if(MQLInfoInteger(MQL_TESTER))
      return g_carry_cache.available;

   int reload_seconds = MathMax(1, InpCarryReloadHours) * 3600;
   if(now > 0 && g_carry_cache.last_load_time > 0 && (now - g_carry_cache.last_load_time) < reload_seconds)
      return g_carry_cache.available;

   return LoadCarryDataCache(force_log);
}

bool LoadCarryDataCache(const bool force_log)
{
   FXRCCarryCacheState previous = g_carry_cache;
   g_carry_cache.loaded = true;
   g_carry_cache.last_load_time = SafeNow();
   g_carry_cache.source_file = InpCarryDataFile;

   int flags = FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ;
   if(InpCarryUseCommonFile)
      flags |= FILE_COMMON;

   ResetLastError();
   int handle = FileOpen(InpCarryDataFile, flags);
   if(handle == INVALID_HANDLE)
   {
      g_carry_cache.reason = StringFormat("Carry data file open failed: %s err=%d", InpCarryDataFile, GetLastError());
      if(previous.available)
      {
         g_carry_cache.available = true;
         g_carry_cache.last_success_time = previous.last_success_time;
         g_carry_cache.record_count = previous.record_count;
         g_carry_cache.currency_count = previous.currency_count;
      }
      if(force_log)
         Print(g_carry_cache.reason);
      return g_carry_cache.available;
   }

   string temp_ccy[];
   datetime temp_dates[];
   double temp_rates[];
   ArrayResize(temp_ccy, 0);
   ArrayResize(temp_dates, 0);
   ArrayResize(temp_rates, 0);

   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      if(FileIsEnding(handle) && StringLen(line) == 0)
         break;

      string currency;
      datetime record_date;
      double rate_value;
      if(!ParseCarryDataLine(line, currency, record_date, rate_value))
         continue;

      int new_size = ArraySize(temp_ccy) + 1;
      ArrayResize(temp_ccy, new_size);
      ArrayResize(temp_dates, new_size);
      ArrayResize(temp_rates, new_size);
      temp_ccy[new_size - 1] = currency;
      temp_dates[new_size - 1] = record_date;
      temp_rates[new_size - 1] = rate_value;
   }
   FileClose(handle);

   if(ArraySize(temp_ccy) <= 0)
   {
      g_carry_cache.reason = StringFormat("Carry data file %s has no valid rows.", InpCarryDataFile);
      if(force_log)
         Print(g_carry_cache.reason);
      return previous.available;
   }

   SortPPPRecords(temp_ccy, temp_dates, temp_rates);

   ArrayCopy(g_carry_record_ccy, temp_ccy);
   ArrayCopy(g_carry_record_date, temp_dates);
   ArrayCopy(g_carry_record_rate, temp_rates);
   BuildCarryIndexFromRecords(g_carry_record_ccy);

   g_carry_cache.available = (ArraySize(g_carry_record_ccy) > 0 && ArraySize(g_carry_index_ccy) > 0);
   g_carry_cache.last_success_time = g_carry_cache.last_load_time;
   g_carry_cache.record_count = ArraySize(g_carry_record_ccy);
   g_carry_cache.currency_count = ArraySize(g_carry_index_ccy);
   g_carry_cache.reason = "";

   if(force_log)
   {
      PrintFormat("FXRC carry cache loaded from %s with %d rows across %d currencies.",
                  InpCarryDataFile, g_carry_cache.record_count, g_carry_cache.currency_count);
   }

   return g_carry_cache.available;
}

bool GetSeriesCloseAtOrBefore(const string symbol,
                              const ENUM_TIMEFRAMES timeframe,
                              const datetime when,
                              double &close_price,
                              datetime &bar_time)
{
   close_price = 0.0;
   bar_time = 0;

   int shift = iBarShift(symbol, timeframe, when, false);
   if(shift < 0)
      return false;

   bar_time = iTime(symbol, timeframe, shift);
   if(bar_time <= 0)
      return false;

   close_price = iClose(symbol, timeframe, shift);
   return (close_price > 0.0);
}

bool GetRollingValueAnchorTime(const string symbol, const datetime asof_time, datetime &anchor_time)
{
   anchor_time = 0;

   // Rebase PPP to the active value window instead of the oldest shared macro date.
   int bars_needed = InpValueLookbackBars + 5;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   ResetLastError();
   int copied = CopyRates(symbol, InpValueTF, asof_time, bars_needed, rates);
   if(copied < InpValueLookbackBars + 2)
      return false;

   int oldest_shift = MathMin(InpValueLookbackBars + 1, copied - 1);
   anchor_time = rates[oldest_shift].time;
   return (anchor_time > 0);
}

bool GetPPPFirstRecordDate(const string currency, datetime &record_date)
{
   record_date = 0;
   int idx = FindPPPCurrencyIndex(currency);
   if(idx < 0)
      return false;

   int start = g_ppp_index_start[idx];
   if(start < 0 || start >= ArraySize(g_ppp_record_date))
      return false;

   record_date = g_ppp_record_date[start];
   return (record_date > 0);
}

bool GetCarryRecordAtOrBefore(const string currency, const datetime asof_time, double &rate_value, datetime &record_date)
{
   rate_value = 0.0;
   record_date = 0;

   int idx = FindCarryCurrencyIndex(currency);
   if(idx < 0)
      return false;

   int start = g_carry_index_start[idx];
   int count = g_carry_index_count[idx];
   for(int i=start + count - 1; i>=start; --i)
   {
      if(g_carry_record_date[i] <= asof_time)
      {
         rate_value = g_carry_record_rate[i];
         record_date = g_carry_record_date[i];
         return true;
      }
   }

   return false;
}

bool GetPPPRecordAtOrBefore(const string currency, const datetime asof_time, double &cpi_value, datetime &record_date)
{
   cpi_value = 0.0;
   record_date = 0;

   int idx = FindPPPCurrencyIndex(currency);
   if(idx < 0)
      return false;

   int start = g_ppp_index_start[idx];
   int count = g_ppp_index_count[idx];
   for(int i=start + count - 1; i>=start; --i)
   {
      if(g_ppp_record_date[i] <= asof_time)
      {
         cpi_value = g_ppp_record_cpi[i];
         record_date = g_ppp_record_date[i];
         return (cpi_value > 0.0);
      }
   }

   return false;
}

int FindCarryCurrencyIndex(const string currency)
{
   string needle = NormalizeCurrencyCode(currency);
   for(int i=0; i<ArraySize(g_carry_index_ccy); ++i)
   {
      if(g_carry_index_ccy[i] == needle)
         return i;
   }
   return -1;
}

int FindPPPCurrencyIndex(const string currency)
{
   string needle = NormalizeCurrencyCode(currency);
   for(int i=0; i<ArraySize(g_ppp_index_ccy); ++i)
   {
      if(g_ppp_index_ccy[i] == needle)
         return i;
   }
   return -1;
}

void BuildCarryIndexFromRecords(const string &ccy[])
{
   ArrayResize(g_carry_index_ccy, 0);
   ArrayResize(g_carry_index_start, 0);
   ArrayResize(g_carry_index_count, 0);

   int total = ArraySize(ccy);
   if(total <= 0)
      return;

   int start = 0;
   while(start < total)
   {
      string currency = ccy[start];
      int count = 1;
      while(start + count < total && ccy[start + count] == currency)
         count++;

      int new_size = ArraySize(g_carry_index_ccy) + 1;
      ArrayResize(g_carry_index_ccy, new_size);
      ArrayResize(g_carry_index_start, new_size);
      ArrayResize(g_carry_index_count, new_size);
      g_carry_index_ccy[new_size - 1] = currency;
      g_carry_index_start[new_size - 1] = start;
      g_carry_index_count[new_size - 1] = count;

      start += count;
   }
}

void BuildPPPIndexFromRecords(const string &ccy[])
{
   ArrayResize(g_ppp_index_ccy, 0);
   ArrayResize(g_ppp_index_start, 0);
   ArrayResize(g_ppp_index_count, 0);

   int total = ArraySize(ccy);
   if(total <= 0)
      return;

   int start = 0;
   while(start < total)
   {
      string currency = ccy[start];
      int count = 1;
      while(start + count < total && ccy[start + count] == currency)
         count++;

      int new_size = ArraySize(g_ppp_index_ccy) + 1;
      ArrayResize(g_ppp_index_ccy, new_size);
      ArrayResize(g_ppp_index_start, new_size);
      ArrayResize(g_ppp_index_count, new_size);
      g_ppp_index_ccy[new_size - 1] = currency;
      g_ppp_index_start[new_size - 1] = start;
      g_ppp_index_count[new_size - 1] = count;

      start += count;
   }
}

void SortPPPRecords(string &ccy[], datetime &dates[], double &values[])
{
   int n = ArraySize(ccy);
   for(int i=0; i<n-1; ++i)
   {
      int best = i;
      for(int j=i+1; j<n; ++j)
      {
         if(PPPRecordLess(ccy[j], dates[j], ccy[best], dates[best]))
            best = j;
      }

      if(best != i)
      {
         string ccy_tmp = ccy[i];
         ccy[i] = ccy[best];
         ccy[best] = ccy_tmp;

         datetime date_tmp = dates[i];
         dates[i] = dates[best];
         dates[best] = date_tmp;

         double value_tmp = values[i];
         values[i] = values[best];
         values[best] = value_tmp;
      }
   }
}

bool PPPRecordLess(const string ccy_a, const datetime date_a, const string ccy_b, const datetime date_b)
{
   if(ccy_a < ccy_b)
      return true;
   if(ccy_a > ccy_b)
      return false;
   return (date_a < date_b);
}

bool ParseCarryDataLine(const string line, string &currency, datetime &record_date, double &rate_value)
{
   currency = "";
   record_date = 0;
   rate_value = 0.0;

   string work = line;
   StringTrimLeft(work);
   StringTrimRight(work);
   if(StringLen(work) == 0)
      return false;
   if(StringGetCharacter(work, 0) == '#' || StringGetCharacter(work, 0) == ';')
      return false;

   string fields[];
   int count = StringSplit(work, StringGetCharacter(",", 0), fields);
   if(count < 3)
      return false;

   currency = NormalizeCurrencyCode(fields[0]);
   if(StringLen(currency) != 3)
      return false;

   record_date = ParseMacroDateString(fields[1]);
   if(record_date <= 0)
      return false;

   string value_text = fields[2];
   StringTrimLeft(value_text);
   StringTrimRight(value_text);

   double raw_value = StringToDouble(value_text);
   if(!NormalizeCarryRateValue(raw_value, rate_value))
      return false;

   return true;
}

bool NormalizeCarryRateValue(const double raw_value, double &normalized_rate)
{
   normalized_rate = 0.0;
   double abs_value = MathAbs(raw_value);
   if(abs_value <= EPS())
      return true;

   if(abs_value <= 1.0)
   {
      normalized_rate = raw_value;
      return true;
   }

   if(abs_value <= 100.0)
   {
      normalized_rate = raw_value / 100.0;
      return true;
   }

   return false;
}

bool ParsePPPDataLine(const string line, string &currency, datetime &record_date, double &cpi_value)
{
   currency = "";
   record_date = 0;
   cpi_value = 0.0;

   string work = line;
   StringTrimLeft(work);
   StringTrimRight(work);
   if(StringLen(work) == 0)
      return false;
   if(StringGetCharacter(work, 0) == '#' || StringGetCharacter(work, 0) == ';')
      return false;

   string fields[];
   int count = StringSplit(work, StringGetCharacter(",", 0), fields);
   if(count < 3)
      return false;

   currency = NormalizeCurrencyCode(fields[0]);
   if(StringLen(currency) != 3)
      return false;

   record_date = ParseMacroDateString(fields[1]);
   if(record_date <= 0)
      return false;

   string value_text = fields[2];
   StringTrimLeft(value_text);
   StringTrimRight(value_text);
   cpi_value = StringToDouble(value_text);
   if(cpi_value <= 0.0)
      return false;

   return true;
}

datetime ParseMacroDateString(const string raw)
{
   string value = raw;
   StringTrimLeft(value);
   StringTrimRight(value);
   if(StringLen(value) == 0)
      return 0;

   StringReplace(value, "-", ".");
   StringReplace(value, "/", ".");

   if(StringLen(value) == 7)
      value += ".01";

   return StringToTime(value);
}

string NormalizeCurrencyCode(const string value)
{
   string out = value;
   StringTrimLeft(out);
   StringTrimRight(out);
   StringToUpper(out);
   return out;
}

void NormalizePremiaWeights(double &w_m, double &w_c, double &w_v)
{
   double wsum = MathMax(w_m + w_c + w_v, EPS());
   w_m /= wsum;
   w_c /= wsum;
   w_v /= wsum;
}

//------------------------- Pricing Conversion And Math Services -------------------------//
int FindConversionCacheIndex(const string from, const string to)
{
   for(int i=0; i<ArraySize(g_conversion_cache_from); ++i)
   {
      if(g_conversion_cache_from[i] == from && g_conversion_cache_to[i] == to)
         return i;
   }
   return -1;
}

void RememberConversionRate(const string from, const string to, const double rate)
{
   if(rate <= EPS())
      return;

   string norm_from = NormalizeCurrencyCode(from);
   string norm_to = NormalizeCurrencyCode(to);
   int idx = FindConversionCacheIndex(norm_from, norm_to);
   if(idx < 0)
   {
      idx = ArraySize(g_conversion_cache_from);
      ArrayResize(g_conversion_cache_from, idx + 1);
      ArrayResize(g_conversion_cache_to, idx + 1);
      ArrayResize(g_conversion_cache_rate, idx + 1);
      ArrayResize(g_conversion_cache_time, idx + 1);
   }

   g_conversion_cache_from[idx] = norm_from;
   g_conversion_cache_to[idx] = norm_to;
   g_conversion_cache_rate[idx] = rate;
   g_conversion_cache_time[idx] = SafeNow();
}

bool TryGetCachedConversionRate(const string from, const string to, const int max_age_seconds, double &rate)
{
   string norm_from = NormalizeCurrencyCode(from);
   string norm_to = NormalizeCurrencyCode(to);
   if(norm_from == norm_to)
   {
      rate = 1.0;
      return true;
   }

   datetime now = SafeNow();
   int idx = FindConversionCacheIndex(norm_from, norm_to);
   if(idx >= 0 && g_conversion_cache_rate[idx] > EPS())
   {
      if(max_age_seconds <= 0 || now <= 0 || g_conversion_cache_time[idx] <= 0
         || (now - g_conversion_cache_time[idx]) <= max_age_seconds)
      {
         rate = g_conversion_cache_rate[idx];
         return true;
      }
   }

   idx = FindConversionCacheIndex(norm_to, norm_from);
   if(idx >= 0 && g_conversion_cache_rate[idx] > EPS())
   {
      if(max_age_seconds <= 0 || now <= 0 || g_conversion_cache_time[idx] <= 0
         || (now - g_conversion_cache_time[idx]) <= max_age_seconds)
      {
         rate = 1.0 / g_conversion_cache_rate[idx];
         return true;
      }
   }

   return false;
}

bool EnsureReferenceEURNotional()
{
   g_reference_eur_notional = ReferenceEURNotional();
   if(g_reference_eur_notional > EPS())
      return true;

   g_reference_eur_notional = 100000.0 * InpClassicReferenceEURUSDLots;
   if(g_reference_eur_notional > EPS())
   {
      PrintFormat("FXRC reference EUR notional fallback applied: %.2f", g_reference_eur_notional);
      return true;
   }

   return false;
}

double ReferenceEURNotional()
{
   if(g_reference_eur_notional > EPS())
      return g_reference_eur_notional;

   string ref_symbol;
   double contract = 100000.0;
   if(FindReferenceEURUSDSymbol(ref_symbol))
   {
      double found = SymbolInfoDouble(ref_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(found > 0.0)
         contract = found;
   }

   g_reference_eur_notional = contract * InpClassicReferenceEURUSDLots;
   return g_reference_eur_notional;
}

bool FindReferenceEURUSDSymbol(string &symbol)
{
   for(int i=0; i<g_num_symbols; ++i)
   {
      string sym = g_symbols[i];
      if(SymbolInfoString(sym, SYMBOL_CURRENCY_BASE) == "EUR" && SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT) == "USD")
      {
         symbol = sym;
         return true;
      }
   }

   if(FindTrackedSymbolIndex(_Symbol) < 0
      && SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE) == "EUR"
      && SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT) == "USD")
   {
      symbol = _Symbol;
      return true;
   }

   return false;
}

bool EstimateNotionalEUR(const string symbol, const double volume, double &notional_eur)
{
   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   if(StringLen(base) != 3)
      return false;

   double contract = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(contract <= 0.0)
      return false;

   double rate;
   if(!CurrencyToEURRate(base, rate))
      return false;

   notional_eur = volume * contract * rate;
   return (notional_eur > EPS());
}

double ConvertCashToUSD(const string ccy, const double amount)
{
   return ConvertCash(ccy, "USD", amount);
}

double ConvertCashToEUR(const string ccy, const double amount)
{
   return ConvertCash(ccy, "EUR", amount);
}

double ConvertCash(const string from_ccy, const string to_ccy, const double amount)
{
   double converted = 0.0;
   if(TryConvertCash(from_ccy, to_ccy, amount, converted))
      return converted;
   return 0.0;
}

bool CurrencyToEURRate(const string ccy, double &rate)
{
   return GetCurrencyConversionRate(ccy, "EUR", 2, rate);
}

bool GetCurrencyConversionRate(const string from, const string to, const int depth, double &rate)
{
   string norm_from = NormalizeCurrencyCode(from);
   string norm_to = NormalizeCurrencyCode(to);
   if(norm_from == norm_to)
   {
      rate = 1.0;
      return true;
   }

   if(TryGetCachedConversionRate(norm_from, norm_to, 60, rate))
      return true;

   if(FindDirectConversionRate(norm_from, norm_to, rate))
   {
      RememberConversionRate(norm_from, norm_to, rate);
      return true;
   }

   if(depth <= 0)
      return TryGetCachedConversionRate(norm_from, norm_to, 3600, rate);

   string bridges[] = {"USD","EUR","JPY","GBP","CHF","AUD","CAD","NZD"};
   for(int i=0; i<ArraySize(bridges); ++i)
   {
      string mid_ccy = bridges[i];
      if(mid_ccy == norm_from || mid_ccy == norm_to)
         continue;

      double r1, r2;
      if(FindDirectConversionRate(norm_from, mid_ccy, r1) && GetCurrencyConversionRate(mid_ccy, norm_to, depth - 1, r2))
      {
         rate = r1 * r2;
         RememberConversionRate(norm_from, norm_to, rate);
         return true;
      }
   }

   return TryGetCachedConversionRate(norm_from, norm_to, 3600, rate);
}

bool FindDirectConversionRate(const string from, const string to, double &rate)
{
   if(from == to)
   {
      rate = 1.0;
      return true;
   }

   for(int i=0; i<g_num_symbols; ++i)
   {
      if(TryDirectConversionSymbol(g_symbols[i], from, to, rate))
         return true;
   }

   if(FindTrackedSymbolIndex(_Symbol) < 0 && TryDirectConversionSymbol(_Symbol, from, to, rate))
      return true;

   string direct = from + to;
   if(TryDirectConversionSymbol(direct, from, to, rate))
      return true;

   string inverse = to + from;
   if(TryDirectConversionSymbol(inverse, from, to, rate))
      return true;

   int total = SymbolsTotal(false);
   for(int i=0; i<total; ++i)
   {
      string symbol = SymbolName(i, false);
      if(StringLen(symbol) == 0)
         continue;

      if(TryDirectConversionSymbol(symbol, from, to, rate))
         return true;
   }

   return false;
}

bool TryDirectConversionSymbol(const string symbol, const string from, const string to, double &rate)
{
   if(StringLen(symbol) == 0)
      return false;

   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   if(StringLen(base) != 3 || StringLen(quote) != 3)
   {
      if(!SelectAndSyncSymbol(symbol))
         return false;

      base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
      quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
      if(StringLen(base) != 3 || StringLen(quote) != 3)
         return false;
   }

   double mid;

   if(base == from && quote == to)
   {
      if(!SelectAndSyncSymbol(symbol) || !GetAnalyticalMidPrice(symbol, mid))
         return false;

      rate = mid;
      return true;
   }

   if(base == to && quote == from)
   {
      if(!SelectAndSyncSymbol(symbol) || !GetAnalyticalMidPrice(symbol, mid))
         return false;

      if(mid <= EPS())
         return false;

      rate = 1.0 / mid;
      return true;
   }

   return false;
}

bool EstimateEmergencyATRPct(const string symbol, double &atr_pct)
{
   atr_pct = 0.0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int bars_needed = MathMax(InpATRWindow + 2, 20);
   ResetLastError();
   int copied = CopyRates(symbol, InpSignalTF, 0, bars_needed, rates);
   if(copied >= InpATRWindow + 2)
   {
      atr_pct = ATRPctFromRates(rates, InpATRWindow);
      if(atr_pct > EPS())
         return true;
   }

   double mid = 0.0;
   if(!GetAnalyticalMidPrice(symbol, mid) || mid <= 0.0)
      return false;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   long stops_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double fallback_distance = 5.0 * MathMax((double)MathMax(stops_level, freeze_level) * point, point);
   if(fallback_distance <= 0.0)
      return false;

   atr_pct = MathMax(fallback_distance / mid, EPS());
   return true;
}

bool GetAnalyticalMidPrice(const string symbol, double &mid)
{
   MqlTick tick;
   if(GetMidPrice(symbol, tick, mid))
      return true;

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid > 0.0 && ask > 0.0)
   {
      mid = 0.5 * (bid + ask);
      return true;
   }

   double close0 = iClose(symbol, InpSignalTF, 0);
   if(close0 > 0.0)
   {
      mid = close0;
      return true;
   }

   double close1 = iClose(symbol, InpSignalTF, 1);
   if(close1 > 0.0)
   {
      mid = close1;
      return true;
   }

   return false;
}

bool GetMidPrice(const string symbol, MqlTick &tick, double &mid)
{
   if(!SymbolInfoTick(symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return false;

   mid = 0.5 * (tick.bid + tick.ask);
   return (mid > 0.0);
}

bool SolveLinearSystem(const double &Ain[], const double &bin[], double &x[], const int n)
{
   double A[];
   double b[];
   ArrayResize(A, n * n);
   ArrayResize(b, n);
   ArrayCopy(A, Ain);
   ArrayCopy(b, bin);
   ArrayResize(x, n);
   ArrayInitialize(x, 0.0);

   for(int col=0; col<n; ++col)
   {
      int pivot = col;
      double maxabs = MathAbs(A[MatIdx(col, col, n)]);
      for(int row=col+1; row<n; ++row)
      {
         double v = MathAbs(A[MatIdx(row, col, n)]);
         if(v > maxabs)
         {
            maxabs = v;
            pivot = row;
         }
      }

      if(maxabs <= EPS())
         return false;

      if(pivot != col)
      {
         for(int j=col; j<n; ++j)
         {
            double tmp = A[MatIdx(col, j, n)];
            A[MatIdx(col, j, n)] = A[MatIdx(pivot, j, n)];
            A[MatIdx(pivot, j, n)] = tmp;
         }
         double tb = b[col];
         b[col] = b[pivot];
         b[pivot] = tb;
      }

      double diag = A[MatIdx(col, col, n)];
      for(int row=col+1; row<n; ++row)
      {
         double factor = A[MatIdx(row, col, n)] / diag;
         if(factor == 0.0)
            continue;

         A[MatIdx(row, col, n)] = 0.0;
         for(int j=col+1; j<n; ++j)
            A[MatIdx(row, j, n)] -= factor * A[MatIdx(col, j, n)];
         b[row] -= factor * b[col];
      }
   }

   for(int i=n-1; i>=0; --i)
   {
      double rhs = b[i];
      for(int j=i+1; j<n; ++j)
         rhs -= A[MatIdx(i, j, n)] * x[j];

      double diag = A[MatIdx(i, i, n)];
      if(MathAbs(diag) <= EPS())
         return false;

      x[i] = rhs / diag;
   }

   return true;
}

double PearsonCorrFlat(const double &hist[], const int idx1, const int idx2, const int len, const int row_len)
{
   double sum_x = 0.0, sum_y = 0.0;
   double sum_x2 = 0.0, sum_y2 = 0.0, sum_xy = 0.0;

   for(int k=0; k<len; ++k)
   {
      double x = hist[idx1 * row_len + k];
      double y = hist[idx2 * row_len + k];
      sum_x += x;
      sum_y += y;
      sum_x2 += x * x;
      sum_y2 += y * y;
      sum_xy += x * y;
   }

   double n = (double)len;
   double num = n * sum_xy - sum_x * sum_y;
   double denx = n * sum_x2 - sum_x * sum_x;
   double deny = n * sum_y2 - sum_y * sum_y;
   double den = MathSqrt(MathMax(denx, 0.0) * MathMax(deny, 0.0));
   if(den <= EPS())
      return 0.0;

   return Clip(num / den, -1.0, 1.0);
}

double LowestClose(const double &close[], const int from_shift, const int to_shift)
{
   double v = DBL_MAX;
   for(int sh = from_shift; sh <= to_shift; ++sh)
      if(close[sh] < v) v = close[sh];
   return v;
}

double HighestClose(const double &close[], const int from_shift, const int to_shift)
{
   double v = -DBL_MAX;
   for(int sh = from_shift; sh <= to_shift; ++sh)
      if(close[sh] > v) v = close[sh];
   return v;
}

double ATRPctFromRates(const MqlRates &rates[], const int window)
{
   double sum_tr = 0.0;
   int count = 0;

   for(int sh = window; sh >= 1; --sh)
   {
      double high = rates[sh].high;
      double low  = rates[sh].low;
      double prev_close = rates[sh + 1].close;
      double tr = MathMax(high - low, MathMax(MathAbs(high - prev_close), MathAbs(low - prev_close)));
      sum_tr += tr;
      count++;
   }

   if(count <= 0 || rates[1].close <= 0.0)
      return EPS();

   return MathMax((sum_tr / (double)count) / rates[1].close, EPS());
}

double EWMAStdFromCloses(const double &close[], const int returns_count, const int half_life)
{
   double lambda = MathExp(-MathLog(2.0) / MathMax(1.0, (double)half_life));
   double var = 0.0;
   bool seeded = false;

   for(int lag = returns_count - 1; lag >= 0; --lag)
   {
      int idx_newer = lag + 1;
      int idx_older = lag + 2;
      double r = MathLog(close[idx_newer] / close[idx_older]);

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

//------------------------- Startup And Universe Setup -------------------------//
bool InitArrays()
{
   if(g_num_symbols < 1)
      return false;

   g_ret_hist_len = MathMax(InpCorrLookback, MathMax(InpVolLongHalfLife + 10, 110));

   ArrayResize(g_base_ccy, g_num_symbols);
   ArrayResize(g_quote_ccy, g_num_symbols);
   ArrayResize(g_trade_allowed, g_num_symbols);
   ArrayResize(g_last_closed_bar, g_num_symbols);
   ArrayResize(g_last_processed_signal_bar, g_num_symbols);
   ArrayResize(g_symbol_bar_advanced, g_num_symbols);

   ArrayResize(g_sigma_short, g_num_symbols);
   ArrayResize(g_sigma_long,  g_num_symbols);
   ArrayResize(g_atr_pct,     g_num_symbols);
   ArrayResize(g_M,           g_num_symbols);
   ArrayResize(g_A,           g_num_symbols);
   ArrayResize(g_ER,          g_num_symbols);
   ArrayResize(g_V,           g_num_symbols);
   ArrayResize(g_D,           g_num_symbols);
   ArrayResize(g_BK,          g_num_symbols);
   ArrayResize(g_G,           g_num_symbols);
   ArrayResize(g_K,           g_num_symbols);
   ArrayResize(g_K_long,      g_num_symbols);
   ArrayResize(g_K_short,     g_num_symbols);
   ArrayResize(g_Q,           g_num_symbols);
   ArrayResize(g_Q_long,      g_num_symbols);
   ArrayResize(g_Q_short,     g_num_symbols);
   ArrayResize(g_PG,          g_num_symbols);
   ArrayResize(g_E,           g_num_symbols);
   ArrayResize(g_S,           g_num_symbols);
   ArrayResize(g_Conf,        g_num_symbols);
   ArrayResize(g_Omega,       g_num_symbols);
   ArrayResize(g_Rank,        g_num_symbols);
   ArrayResize(g_Carry,       g_num_symbols);
   ArrayResize(g_Value,       g_num_symbols);
   ArrayResize(g_ValueProxy,  g_num_symbols);
   ArrayResize(g_ValuePPP,    g_num_symbols);
   ArrayResize(g_ValueFairValue, g_num_symbols);
   ArrayResize(g_ValuePPPWeight, g_num_symbols);
   ArrayResize(g_ValueReliability, g_num_symbols);
   ArrayResize(g_CompositeCore, g_num_symbols);
   ArrayResize(g_CarryAnnualSpread, g_num_symbols);
   ArrayResize(g_ValueGap,    g_num_symbols);
   ArrayResize(g_ValueMacroDate, g_num_symbols);
   ArrayResize(g_theta_in_eff, g_num_symbols);
   ArrayResize(g_theta_out_eff, g_num_symbols);
   ArrayResize(g_persist_count, g_num_symbols);
   ArrayResize(g_entry_dir_raw, g_num_symbols);
   ArrayResize(g_symbol_data_ok, g_num_symbols);
   ArrayResize(g_symbol_data_stale, g_num_symbols);
   ArrayResize(g_symbol_feature_failures, g_num_symbols);
   ArrayResize(g_symbol_last_feature_success, g_num_symbols);
   ArrayResize(g_symbol_history_ready, g_num_symbols);
   ArrayResize(g_symbol_latest_history_bar, g_num_symbols);
   ArrayResize(g_symbol_history_bars, g_num_symbols);
   ArrayResize(g_symbol_history_reason, g_num_symbols);
   ArrayResize(g_exec_symbol_state, g_num_symbols);

   ArrayResize(g_stdret_hist, g_num_symbols * g_ret_hist_len);
   ArrayResize(g_corr_matrix, g_num_symbols * g_num_symbols);
   ArrayResize(g_corr_eff,    g_num_symbols * g_num_symbols);
   ArrayResize(g_universe_stdret_hist, g_ret_hist_len);

   ArrayInitialize(g_last_closed_bar, 0);
   ArrayInitialize(g_last_processed_signal_bar, 0);
   ArrayInitialize(g_symbol_bar_advanced, false);
   ArrayInitialize(g_sigma_short, 0.0);
   ArrayInitialize(g_sigma_long,  0.0);
   ArrayInitialize(g_atr_pct,     0.0);
   ArrayInitialize(g_M,           0.0);
   ArrayInitialize(g_A,           0.0);
   ArrayInitialize(g_ER,          0.0);
   ArrayInitialize(g_V,           0.0);
   ArrayInitialize(g_D,           0.0);
   ArrayInitialize(g_BK,          0.0);
   ArrayInitialize(g_G,           0.0);
   ArrayInitialize(g_K,           0.0);
   ArrayInitialize(g_K_long,      0.0);
   ArrayInitialize(g_K_short,     0.0);
   ArrayInitialize(g_Q,           0.0);
   ArrayInitialize(g_Q_long,      0.0);
   ArrayInitialize(g_Q_short,     0.0);
   ArrayInitialize(g_PG,          1.0);
   ArrayInitialize(g_E,           0.0);
   ArrayInitialize(g_S,           0.0);
   ArrayInitialize(g_Conf,        0.0);
   ArrayInitialize(g_Omega,       1.0);
   ArrayInitialize(g_Rank,        0.0);
   ArrayInitialize(g_Carry,       0.0);
   ArrayInitialize(g_Value,       0.0);
   ArrayInitialize(g_ValueProxy,  0.0);
   ArrayInitialize(g_ValuePPP,    0.0);
   ArrayInitialize(g_ValueFairValue, 0.0);
   ArrayInitialize(g_ValuePPPWeight, 0.0);
   ArrayInitialize(g_ValueReliability, 0.0);
   ArrayInitialize(g_CompositeCore, 0.0);
   ArrayInitialize(g_CarryAnnualSpread, 0.0);
   ArrayInitialize(g_ValueGap,    0.0);
   ArrayInitialize(g_ValueMacroDate, 0);
   ArrayInitialize(g_theta_in_eff, 0.0);
   ArrayInitialize(g_theta_out_eff, 0.0);
   ArrayInitialize(g_persist_count, 0);
   ArrayInitialize(g_entry_dir_raw, 0);
   ArrayInitialize(g_symbol_data_ok, false);
   ArrayInitialize(g_symbol_data_stale, false);
   ArrayInitialize(g_symbol_feature_failures, 0);
   ArrayInitialize(g_symbol_last_feature_success, 0);
   ArrayInitialize(g_symbol_history_ready, false);
   ArrayInitialize(g_symbol_latest_history_bar, 0);
   ArrayInitialize(g_symbol_history_bars, 0);
   ArrayInitialize(g_trade_allowed, true);
   ArrayInitialize(g_stdret_hist, 0.0);
   ArrayInitialize(g_corr_matrix, 0.0);
   ArrayInitialize(g_corr_eff, 0.0);
   ArrayInitialize(g_universe_stdret_hist, 0.0);

   for(int i=0; i<g_num_symbols; ++i)
   {
      g_base_ccy[i]  = SymbolInfoString(g_symbols[i], SYMBOL_CURRENCY_BASE);
      g_quote_ccy[i] = SymbolInfoString(g_symbols[i], SYMBOL_CURRENCY_PROFIT);
      g_symbol_history_reason[i] = "";
      ResetSymbolExecutionState(g_exec_symbol_state[i]);
   }

   return true;
}

bool InitTradableSymbols()
{
   ArrayResize(g_trade_allowed, g_num_symbols);
   ArrayInitialize(g_trade_allowed, true);

   string tradable_input = InpTradableSymbols;
   StringTrimLeft(tradable_input);
   StringTrimRight(tradable_input);
   if(StringLen(tradable_input) == 0)
      return true;

   ArrayInitialize(g_trade_allowed, false);

   ushort sep = StringGetCharacter(",", 0);
   string raw[];
   int n = StringSplit(tradable_input, sep, raw);
   if(n <= 0)
      return true;

   int matched = 0;
   for(int i=0; i<n; ++i)
   {
      string sym = raw[i];
      StringTrimLeft(sym);
      StringTrimRight(sym);
      if(StringLen(sym) == 0)
         continue;

      int idx = FindTrackedSymbolIndex(sym);
      if(idx < 0)
      {
         PrintFormat("Tradable symbol ignored because it is not in the analysis universe: %s", sym);
         continue;
      }

      if(!g_trade_allowed[idx])
      {
         g_trade_allowed[idx] = true;
         matched++;
      }
   }

   if(matched == 0)
      Print("No tradable symbols matched the analysis universe. Analysis will run, but no new trades can be opened.");

   return true;
}

bool ParseSymbols()
{
   ArrayFree(g_symbols);
   int valid = 0;
   string symbols_input = InpSymbols;
   StringTrimLeft(symbols_input);
   StringTrimRight(symbols_input);

   if(StringLen(symbols_input) == 0 || symbols_input == "*")
   {
      int total = SymbolsTotal(false);
      for(int i=0; i<total; ++i)
      {
         string sym = SymbolName(i, false);
         if(StringLen(sym) == 0 || !IsForexPairSymbol(sym))
            continue;

         if(SymbolAlreadyListed(g_symbols, valid, sym))
            continue;

         if(!SelectAndSyncSymbol(sym))
         {
            PrintFormat("Failed to select symbol %s", sym);
            continue;
         }

         int new_size = valid + 1;
         ArrayResize(g_symbols, new_size);
         g_symbols[valid] = sym;
         valid = new_size;
      }
   }
   else
   {
      ushort sep = StringGetCharacter(",", 0);
      string raw[];
      int n = StringSplit(symbols_input, sep, raw);
      if(n <= 0)
         return false;

      for(int i=0; i<n; ++i)
      {
         string sym = raw[i];
         StringTrimLeft(sym);
         StringTrimRight(sym);
         if(StringLen(sym) == 0)
            continue;

         bool duplicate = SymbolAlreadyListed(g_symbols, valid, sym);
         if(duplicate)
         {
            PrintFormat("Duplicate symbol skipped: %s", sym);
            continue;
         }

         if(!SelectAndSyncSymbol(sym))
         {
            PrintFormat("Failed to select symbol %s", sym);
            continue;
         }

         if(!IsForexPairSymbol(sym))
         {
            PrintFormat("Non-FX symbol skipped from analysis universe: %s", sym);
            continue;
         }

         int new_size = valid + 1;
         ArrayResize(g_symbols, new_size);
         g_symbols[valid] = sym;
         valid = new_size;
      }
   }

   if(valid == 0 && IsForexPairSymbol(_Symbol) && SelectAndSyncSymbol(_Symbol))
   {
      ArrayResize(g_symbols, 1);
      g_symbols[0] = _Symbol;
      valid = 1;
      PrintFormat("Falling back to chart symbol %s as the only available analysis symbol.", _Symbol);
   }

   g_num_symbols = valid;
   return (g_num_symbols >= 1);
}

bool ValidateInputs()
{
   if(InpMagicNumber <= 0)
   {
      Print("InpMagicNumber must be > 0.");
      return false;
   }
   if(InpMaxAcceptedSignals <= 0)
   {
      Print("InpMaxAcceptedSignals must be > 0.");
      return false;
   }
   if(InpWeightMomentum < 0.0 || InpWeightCarry < 0.0 || InpWeightValue < 0.0)
   {
      Print("Premia weights must be >= 0.");
      return false;
   }
   if((InpWeightMomentum + InpWeightCarry + InpWeightValue) <= EPS())
   {
      Print("At least one premia weight must be > 0.");
      return false;
   }
   if(StringLen(InpCarryDataFile) == 0 && CarryModelUsesExternal())
   {
      Print("InpCarryDataFile must not be empty when external carry is enabled.");
      return false;
   }
   if(InpCarryMaxDataAgeDays <= 0 || InpCarryReloadHours <= 0)
   {
      Print("Carry cache freshness inputs must be > 0.");
      return false;
   }
   if(InpValueLookbackBars < 30 || InpValueHalfLifeBars <= 1 || InpValueHalfLifeBars >= InpValueLookbackBars)
   {
      Print("Value lookback inputs are invalid.");
      return false;
   }
   if(StringLen(InpPPPDataFile) == 0 && ValueModelUsesPPP())
   {
      Print("InpPPPDataFile must not be empty when PPP/hybrid value is enabled.");
      return false;
   }
   if(InpPPPMaxDataAgeDays <= 0 || InpPPPReloadHours <= 0)
   {
      Print("PPP cache freshness inputs must be > 0.");
      return false;
   }
   if(InpPPPGapScale <= 0.0)
   {
      Print("InpPPPGapScale must be > 0.");
      return false;
   }
   if(InpPPPBlendWeight < 0.0 || InpProxyBlendWeight < 0.0)
   {
      Print("PPP/proxy blend weights must be >= 0.");
      return false;
   }
   if(InpValueModel == FXRC_VALUE_MODEL_HYBRID && (InpPPPBlendWeight + InpProxyBlendWeight) <= EPS())
   {
      Print("Hybrid value mode requires at least one positive blend weight.");
      return false;
   }
   if(InpValueSignalScale <= 0.0 || InpCarrySignalScale <= 0.0)
   {
      Print("Carry/value signal scales must be > 0.");
      return false;
   }
   if(InpAllocatorMomentumBoost < 0.0 || InpAllocatorValueBoost < 0.0 || InpAllocatorCarryVolPenalty < 0.0 || InpCarryVolCutoff <= 0.0)
   {
      Print("Allocator inputs are invalid.");
      return false;
   }
   if(InpTanhScale <= 0.0)
   {
      Print("InpTanhScale must be > 0.");
      return false;
   }
   if(InpMaxAccountOrders <= 0)
   {
      Print("InpMaxAccountOrders must be > 0.");
      return false;
   }
   if(InpH1 <= 0 || InpH2 <= InpH1 || InpH3 <= InpH2)
   {
      Print("Trend horizons must satisfy 0 < H1 < H2 < H3.");
      return false;
   }
   if(InpERWindow <= 1 || InpBreakoutWindow <= 1 || InpShortReversalWindow <= 1)
   {
      Print("ER, breakout, and short reversal windows must be > 1.");
      return false;
   }
   if(InpVolShortHalfLife <= 0 || InpVolLongHalfLife <= 0 || InpATRWindow <= 1)
   {
      Print("Volatility windows must be positive and ATR window must be > 1.");
      return false;
   }
   if(InpGammaB <= 0.0)
   {
      Print("InpGammaB must be > 0.");
      return false;
   }
   if(InpCorrLookback < 10)
   {
      Print("InpCorrLookback must be at least 10.");
      return false;
   }
   if(InpMinCandidatesForOrtho < 2)
   {
      Print("InpMinCandidatesForOrtho must be at least 2.");
      return false;
   }
   if(InpPersistenceBars <= 0)
   {
      Print("InpPersistenceBars must be > 0.");
      return false;
   }
   if(InpSlippagePoints < 0 || InpTradeRetryCount < 0 || InpTradeVerifyAttempts <= 0)
   {
      Print("Execution inputs are invalid.");
      return false;
   }
   if(InpSymbolDataFailureGraceBars < 0)
   {
      Print("InpSymbolDataFailureGraceBars must be >= 0.");
      return false;
   }
   if(InpClassicReferenceEURUSDLots <= 0.0)
   {
      Print("InpClassicReferenceEURUSDLots must be > 0.");
      return false;
   }
   if(InpRiskPerTradePct <= 0.0 || InpMaxPortfolioRiskPct <= 0.0 || InpMaxPortfolioExposurePct <= 0.0 || InpMaxMarginUsagePct <= 0.0)
   {
      Print("Risk limits must be > 0.");
      return false;
   }
   if(InpCatastrophicStopATR <= 0.0)
   {
      Print("InpCatastrophicStopATR must be > 0.");
      return false;
   }
   if(InpClassicSinglePositionTakeProfitUSD < 0.0 || InpClassicSessionResetProfitUSD < 0.0)
   {
      Print("USD profit targets must be >= 0.");
      return false;
   }
   if(Trade_Model != FXRC_TRADE_MODEL_CLASSIC && Trade_Model != FXRC_TRADE_MODEL_MODERN)
   {
      Print("Trade_Model is invalid.");
      return false;
   }
   if(InpModernBaseTargetRiskPct <= 0.0 || InpModernMinTargetRiskPct <= 0.0)
   {
      Print("Modern risk targets must be > 0.");
      return false;
   }
   if(InpModernMinTargetRiskPct - EPS() > InpModernBaseTargetRiskPct)
   {
      Print("InpModernMinTargetRiskPct must be <= InpModernBaseTargetRiskPct.");
      return false;
   }
   if(InpModernBaseTargetRiskPct - EPS() > InpRiskPerTradePct)
   {
      Print("InpModernBaseTargetRiskPct must be <= InpRiskPerTradePct.");
      return false;
   }
   if(InpModernTargetATRPct <= 0.0 || InpModernVolAdjustMin <= 0.0 || InpModernVolAdjustMax <= 0.0 || InpModernVolAdjustMin - EPS() > InpModernVolAdjustMax)
   {
      Print("Modern volatility targeting inputs are invalid.");
      return false;
   }
   if(InpModernCovariancePenaltyFloor <= 0.0 || InpModernCovariancePenaltyFloor > 1.0)
   {
      Print("InpModernCovariancePenaltyFloor must be in (0,1].");
      return false;
   }
   if(InpModernForecastRiskATRScale <= 0.0)
   {
      Print("InpModernForecastRiskATRScale must be > 0.");
      return false;
   }
   if(EAStopMinEqui < 0 || EAStopMaxDD < 0.0)
   {
      Print("EA hard-stop inputs must be >= 0.");
      return false;
   }
   if(InpClassicUseTrailingStop != 0 && InpClassicUseTrailingStop != 1)
   {
      Print("InpClassicUseTrailingStop must be 0 or 1.");
      return false;
   }
   if(InpClassicUseTrailingStop == 1)
   {
      if(InpClassicTrailStartPct < 10 || InpClassicTrailStartPct > 100 || (InpClassicTrailStartPct % 10) != 0)
      {
         Print("InpClassicTrailStartPct must be between 10 and 100 in 10% steps.");
         return false;
      }
      if(InpClassicTrailSpacingPct < 10 || InpClassicTrailSpacingPct > 100 || (InpClassicTrailSpacingPct % 10) != 0)
      {
         Print("InpClassicTrailSpacingPct must be between 10 and 100 in 10% steps.");
         return false;
      }
   }
   if(IsClassicTradeModel() && InpClassicUseTrailingStop == 1 && InpClassicSinglePositionTakeProfitUSD <= 0.0)
   {
      Print("Classic mode with trailing enabled requires InpClassicSinglePositionTakeProfitUSD > 0 as the trailing activation anchor.");
      return false;
   }
   if(InpBaseEntryThreshold < 0.0 || InpBaseExitThreshold < 0.0 || InpReversalThreshold < 0.0 || InpTheta0 < 0.0)
   {
      Print("Threshold inputs must be >= 0.");
      return false;
   }
   if(InpAlphaSmooth < 0.0 || InpAlphaSmooth > 1.0)
   {
      Print("InpAlphaSmooth must be in [0, 1].");
      return false;
   }
   if(InpConfSlope <= 0.0)
   {
      Print("InpConfSlope must be > 0.");
      return false;
   }
   if(InpEtaCost < 0.0 || InpEtaVol < 0.0 || InpEtaBreakout < 0.0 || InpGammaCost < 0.0)
   {
      Print("Threshold penalty inputs must be >= 0.");
      return false;
   }
   if(InpBaseExitThreshold > InpBaseEntryThreshold)
   {
      Print("InpBaseExitThreshold should not exceed InpBaseEntryThreshold.");
      return false;
   }
   if(InpMinConfidence < 0.0 || InpMinConfidence > 1.0)
   {
      Print("InpMinConfidence must be in [0, 1].");
      return false;
   }
   if(InpMinRegimeGate < 0.0 || InpHardMinRegimeGate < 0.0 || InpMinExecGate < 0.0)
   {
      Print("Gate thresholds must be >= 0.");
      return false;
   }
   if(InpUniquenessMin < 0.0 || InpUniquenessMin > 1.0 || InpCrowdingMax < 0.0 || InpCrowdingMax > 1.0)
   {
      Print("Uniqueness and crowding thresholds must be in [0, 1].");
      return false;
   }
   if(InpShrinkageLambda < 0.0 || InpShrinkageLambda > 1.0)
   {
      Print("InpShrinkageLambda must be in [0, 1].");
      return false;
   }
   if(InpNoveltyFloorWeight < 0.0 || InpNoveltyFloorWeight > 1.0 || InpNoveltyCap <= 0.0)
   {
      Print("Novelty overlay inputs are invalid.");
      return false;
   }
   if(InpFXOverlapFloor < -1.0 || InpFXOverlapFloor > 1.0 || InpClassOverlapFloor < -1.0 || InpClassOverlapFloor > 1.0)
   {
      Print("Overlap floors must be in [-1, 1].");
      return false;
   }
   if(InpExpectedHoldingDays < 0.0 || InpCommissionRoundTripPerLotEUR < 0.0 || InpAssumedRoundTripFeePct < 0.0)
   {
      Print("Cost inputs must be >= 0.");
      return false;
   }
   if(InpDependencyFailureGraceMinutes < 0)
   {
      Print("InpDependencyFailureGraceMinutes must be >= 0.");
      return false;
   }
   double wsum = InpW1 + InpW2 + InpW3;
   if(wsum <= EPS())
   {
      Print("Trend weights must sum to a positive value.");
      return false;
   }

   g_w1 = InpW1 / wsum;
   g_w2 = InpW2 / wsum;
   g_w3 = InpW3 / wsum;
   return true;
}

bool InspectSymbolHistory(const string symbol,
                         const ENUM_TIMEFRAMES timeframe,
                         const int bars_needed,
                         const bool require_fresh_feed,
                         FXRCHistoryCheck &check)
{
   ResetHistoryCheck(check);

   if(!GetLatestSeriesBarTime(symbol, timeframe, check.latest_bar))
   {
      check.reason = StringFormat("No history is available for %s on %s.",
                                  symbol, EnumToString(timeframe));
      return false;
   }

   check.feed_ready = true;
   if(require_fresh_feed && MQLInfoInteger(MQL_TESTER))
   {
      // In the Strategy Tester, startup preflight can run before the first simulated
      // tick advances the visible series. Existing history is sufficient here; the
      // actual tick stream is validated implicitly by OnTick execution.
   }

   MqlRates rates[];
   string load_reason;
   int copied = 0;
   if(!LoadRatesWindow(symbol, timeframe, bars_needed, rates, copied, load_reason))
   {
      check.bars_available = MathMax(copied, 0);
      check.reason = load_reason;
      return false;
   }

   check.bars_available = copied;
   check.enough_bars = true;
   return true;
}

bool LoadRatesWindow(const string symbol,
                     const ENUM_TIMEFRAMES timeframe,
                     const int bars_needed,
                     MqlRates &rates[],
                     int &copied,
                     string &reason)
{
   reason = "";
   copied = 0;
   ArraySetAsSeries(rates, true);

   ResetLastError();
   copied = CopyRates(symbol, timeframe, 0, bars_needed, rates);
   if(copied < bars_needed)
   {
      reason = StringFormat("CopyRates insufficient for %s on %s. needed=%d got=%d err=%d",
                            symbol, EnumToString(timeframe), bars_needed, copied, GetLastError());
      return false;
   }

   return true;
}

bool GetLatestSeriesBarTime(const string symbol, const ENUM_TIMEFRAMES timeframe, datetime &bar_time)
{
   bar_time = 0;

   MqlRates latest[];
   ArraySetAsSeries(latest, true);

   ResetLastError();
   int copied = CopyRates(symbol, timeframe, 0, 1, latest);
   if(copied < 1)
      return false;

   bar_time = latest[0].time;
   return (bar_time > 0);
}

void LogStartupStep(const int step,
                    const int total_steps,
                    const string label,
                    const string status,
                    const string detail = "")
{
   if(!StartupDebugEnabled())
      return;

   if(StringLen(detail) > 0)
      PrintFormat("FXRC startup Step %d/%d - %s - %s (%s)", step, total_steps, label, status, detail);
   else
      PrintFormat("FXRC startup Step %d/%d - %s - %s", step, total_steps, label, status);
}

bool StartupDebugEnabled()
{
   return (InpDebugStartupSequence && !MQLInfoInteger(MQL_TESTER));
}

bool RuntimeCanProcessModel()
{
   return (g_runtime_state.status == FXRC_RUNTIME_READY && g_runtime_state.ready_symbols > 0);
}

//------------------------- Core Helpers -------------------------//
bool SameClassOverlap(const int i,const int j)
{
   if(i == j || SharesCurrency(i, j))
      return false;

   // FX-only universe: use broad macro/funding blocs rather than repeated base/quote equality.
   for(int bloc_id=1; bloc_id<=3; ++bloc_id)
   {
      if(PairTouchesCurrencyBloc(i, bloc_id) && PairTouchesCurrencyBloc(j, bloc_id))
         return true;
   }

   return false;
}

bool PairTouchesCurrencyBloc(const int idx, const int bloc_id)
{
   if(!IsForexSymbolIndex(idx))
      return false;

   string base = g_base_ccy[idx];
   string quote = g_quote_ccy[idx];

   if(bloc_id == 1)
      return (IsCommodityBlocCurrency(base) || IsCommodityBlocCurrency(quote));
   if(bloc_id == 2)
      return (IsEuropeanBlocCurrency(base) || IsEuropeanBlocCurrency(quote));
   if(bloc_id == 3)
      return (IsFundingBlocCurrency(base) || IsFundingBlocCurrency(quote));

   return false;
}

bool IsFundingBlocCurrency(const string ccy)
{
   return (ccy == "JPY" || ccy == "CHF" || ccy == "EUR");
}

bool IsEuropeanBlocCurrency(const string ccy)
{
   return (ccy == "EUR" || ccy == "GBP" || ccy == "CHF" || ccy == "SEK" || ccy == "NOK");
}

bool IsCommodityBlocCurrency(const string ccy)
{
   return (ccy == "AUD" || ccy == "NZD" || ccy == "CAD" || ccy == "NOK");
}

bool SharesCurrency(const int i,const int j)
{
   if(!IsForexSymbolIndex(i) || !IsForexSymbolIndex(j))
      return false;

   if(g_base_ccy[i]  == g_base_ccy[j])  return true;
   if(g_base_ccy[i]  == g_quote_ccy[j]) return true;
   if(g_quote_ccy[i] == g_base_ccy[j])  return true;
   if(g_quote_ccy[i] == g_quote_ccy[j]) return true;
   return false;
}

bool IsForexSymbolIndex(const int i)
{
   if(i < 0 || i >= g_num_symbols)
      return false;
   return (StringLen(g_base_ccy[i]) == 3 && StringLen(g_quote_ccy[i]) == 3);
}

bool IsTradeAllowed(const int idx)
{
   if(idx < 0 || idx >= g_num_symbols)
      return false;
   if(ArraySize(g_trade_allowed) != g_num_symbols)
      return true;
   return g_trade_allowed[idx];
}

int FindTrackedSymbolIndex(const string symbol)
{
   for(int i=0; i<g_num_symbols; ++i)
   {
      if(SymbolNamesEqual(g_symbols[i], symbol))
         return i;
   }
   return -1;
}

bool SymbolAlreadyListed(const string &symbols[], const int count, const string symbol)
{
   for(int i=0; i<count; ++i)
   {
      if(SymbolNamesEqual(symbols[i], symbol))
         return true;
   }
   return false;
}

bool IsForexPositionSymbol(const string symbol)
{
   return (StringLen(symbol) > 0 && IsForexPairSymbol(symbol));
}

bool IsForexPairSymbol(const string symbol)
{
   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   if(StringLen(base) != 3 || StringLen(quote) != 3)
      return false;

   ENUM_SYMBOL_CALC_MODE calc_mode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_CALC_MODE);
   return (calc_mode == SYMBOL_CALC_MODE_FOREX || calc_mode == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE);
}

bool SymbolNamesEqual(const string a, const string b)
{
   return (NormalizedSymbolName(a) == NormalizedSymbolName(b));
}

string NormalizedSymbolName(const string symbol)
{
   string out = symbol;
   StringTrimLeft(out);
   StringTrimRight(out);
   StringToUpper(out);
   return out;
}

bool SelectAndSyncSymbol(const string symbol)
{
   return SymbolSelect(symbol, true);
}

bool IsTradeRetcodeRetryable(const uint retcode)
{
   return (retcode == TRADE_RETCODE_REQUOTE
        || retcode == TRADE_RETCODE_PRICE_CHANGED
        || retcode == TRADE_RETCODE_PRICE_OFF
        || retcode == TRADE_RETCODE_TIMEOUT
        || retcode == TRADE_RETCODE_CONNECTION
        || retcode == TRADE_RETCODE_TOO_MANY_REQUESTS
        || retcode == TRADE_RETCODE_LOCKED);
}

bool IsTradeCheckRetcodeSuccess(const uint retcode)
{
   // OrderCheck() uses 0 to signal a successful pre-trade validation.
   return (retcode == 0 || IsTradeRetcodeSuccess(retcode));
}

bool IsTradeRetcodeSuccess(const uint retcode)
{
   return (retcode == TRADE_RETCODE_DONE
        || retcode == TRADE_RETCODE_DONE_PARTIAL
        || retcode == TRADE_RETCODE_PLACED
        || retcode == TRADE_RETCODE_NO_CHANGES);
}

double NormalizeVolume(const string symbol, const double requested)
{
   double minv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = minv;
   if(step <= 0.0)
      step = 0.01;

   double v = MathRound(requested / step) * step;
   v = MathMax(minv, MathMin(maxv, v));
   return NormalizeDouble(v, VolumeDigits(step));
}

int VolumeDigits(const double step)
{
   int d = 0;
   double s = step;
   while(d < 8 && MathRound(s) != s)
   {
      s *= 10.0;
      d++;
   }
   return d;
}

double NormalizePrice(const string symbol, const double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

void LogDependencyTransition(const string message)
{
   PrintFormat("FXRC dependency: %s", message);
}

void LogRuntimeStateIfNeeded(const bool force)
{
   string key = RuntimeStatusToString(g_runtime_state.status) + "|" + g_runtime_state.reason;
   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();

   if(!force
      && key == g_runtime_state.last_log_key
      && g_runtime_state.last_log_time > 0
      && (now - g_runtime_state.last_log_time) < 300)
      return;

   PrintFormat("FXRC runtime status=%s ready_symbols=%d/%d chart_feed=%s latest_chart_bar=%s reason=%s",
               RuntimeStatusToString(g_runtime_state.status),
               g_runtime_state.ready_symbols,
               g_num_symbols,
               (g_runtime_state.chart_feed_ready ? "ready" : "waiting"),
               FormatTimeValue(g_runtime_state.latest_chart_bar),
               (StringLen(g_runtime_state.reason) > 0 ? g_runtime_state.reason : "none"));

   g_runtime_state.last_log_key = key;
   g_runtime_state.last_log_time = now;
}

void SetRuntimeStatus(const ENUM_FXRC_RUNTIME_STATUS status,
                      const string reason,
                      const int ready_symbols,
                      const bool chart_feed_ready,
                      const datetime latest_chart_bar)
{
   g_runtime_state.status = status;
   g_runtime_state.reason = reason;
   g_runtime_state.ready_symbols = ready_symbols;
   g_runtime_state.chart_feed_ready = chart_feed_ready;
   g_runtime_state.latest_chart_bar = latest_chart_bar;
}

void ResetDependencyRuntimeState(FXRCDependencyRuntimeState &state)
{
   state.status = FXRC_DEPENDENCY_HEALTHY;
   state.failure_active = false;
   state.first_failure_time = 0;
   state.last_success_time = 0;
   state.failure_reason = "";
   state.dependency_scope = "";
   state.flatten_triggered = false;
}

void ResetRuntimeState(FXRCRuntimeState &state)
{
   state.status = FXRC_RUNTIME_STARTING;
   state.ready_symbols = 0;
   state.chart_feed_ready = false;
   state.latest_chart_bar = 0;
   state.last_log_time = 0;
   state.reason = "";
   state.last_log_key = "";
}

void ResetHistoryCheck(FXRCHistoryCheck &check)
{
   check.feed_ready = false;
   check.enough_bars = false;
   check.latest_bar = 0;
   check.bars_available = 0;
   check.reason = "";
}

string DependencyStateToString(const ENUM_FXRC_DEPENDENCY_STATE status)
{
   switch(status)
   {
      case FXRC_DEPENDENCY_HEALTHY:          return "healthy";
      case FXRC_DEPENDENCY_DEGRADED:         return "degraded";
      case FXRC_DEPENDENCY_SHUTDOWN_PENDING: return "shutdown_pending";
      case FXRC_DEPENDENCY_DISABLED:         return "disabled";
   }
   return "unknown";
}

string RuntimeStatusToString(const ENUM_FXRC_RUNTIME_STATUS status)
{
   switch(status)
   {
      case FXRC_RUNTIME_STARTING:     return "starting";
      case FXRC_RUNTIME_WAITING_DATA: return "waiting_data";
      case FXRC_RUNTIME_READY:        return "ready";
      case FXRC_RUNTIME_FATAL:        return "fatal";
   }
   return "unknown";
}

string FormatTimeValue(const datetime value)
{
   if(value <= 0)
      return "n/a";
   return TimeToString(value, TIME_DATE | TIME_MINUTES);
}

int SignalBarsNeeded()
{
   int ret_hist_len = g_ret_hist_len;
   if(ret_hist_len <= 0)
      ret_hist_len = MathMax(InpCorrLookback, MathMax(InpVolLongHalfLife + 10, 110));

   int trend_max = MathMax(InpH1, MathMax(InpH2, InpH3));
   int bars_needed = MathMax(
      MathMax(trend_max + 3, InpBreakoutWindow + 3),
      MathMax(InpERWindow + 3, ret_hist_len + 3)
   );
   return bars_needed + 100;
}

double TanhLikePositive(const double x)
{
   return (2.0 * Sigmoid(2.0 * MathMax(x, 0.0)) - 1.0);
}

bool IsClassicSessionResetActive()
{
   return (IsClassicTradeModel() && InpClassicSessionResetProfitUSD > 0.0);
}

bool IsClassicTrailingActive()
{
   return (IsClassicTradeModel() && InpClassicUseTrailingStop != 0 && InpClassicSinglePositionTakeProfitUSD > 0.0);
}

bool IsClassicTakeProfitActive()
{
   return (IsClassicTradeModel() && InpClassicUseTrailingStop == 0 && InpClassicSinglePositionTakeProfitUSD > 0.0);
}

bool IsModernTradeModel()
{
   return (Trade_Model == FXRC_TRADE_MODEL_MODERN);
}

bool IsClassicTradeModel()
{
   return (Trade_Model == FXRC_TRADE_MODEL_CLASSIC);
}

bool ValueSignalRequiresPPPData()
{
   return (InpValueModel == FXRC_VALUE_MODEL_PPP && !InpPPPAllowProxyFallback);
}

bool CarrySignalRequiresExternalData()
{
   return (InpCarryModel == FXRC_CARRY_MODEL_RATE_DIFF && !InpCarryAllowBrokerFallback);
}

bool CarryModelUsesExternal()
{
   return (InpCarryModel == FXRC_CARRY_MODEL_RATE_DIFF);
}

bool ValueModelUsesPPP()
{
   return (InpValueModel == FXRC_VALUE_MODEL_PPP || InpValueModel == FXRC_VALUE_MODEL_HYBRID);
}

datetime SafeNow()
{
   datetime now = TimeTradeServer();
   if(now <= 0)
      now = TimeCurrent();
   return now;
}

int PositionDirFromType(const long type)
{
   if(type == POSITION_TYPE_BUY)  return 1;
   if(type == POSITION_TYPE_SELL) return -1;
   return 0;
}

bool IsSymbolDataStale(const int idx)
{
   return (idx >= 0
        && idx < ArraySize(g_symbol_data_stale)
        && g_symbol_data_stale[idx]);
}

bool IsCrossSectionallyEligibleSymbol(const int idx)
{
   return (idx >= 0
        && idx < g_num_symbols
        && g_symbol_data_ok[idx]
        && !IsSymbolDataStale(idx));
}

double DirectionalValue(const int dir, const double long_value, const double short_value, const double fallback_value)
{
   if(dir > 0)
      return long_value;
   if(dir < 0)
      return short_value;
   return fallback_value;
}

bool IsDirectionalLong(const int dir)
{
   return (dir > 0);
}

int SignD(const double x)
{
   if(x > 0.0) return 1;
   if(x < 0.0) return -1;
   return 0;
}

double Sigmoid(const double x)
{
   if(x >= 0.0)
   {
      double e = MathExp(-x);
      return 1.0 / (1.0 + e);
   }

   double e = MathExp(x);
   return e / (1.0 + e);
}

double PosPart(const double x)
{
   return (x > 0.0 ? x : 0.0);
}

double Clip(const double x,const double lo,const double hi)
{
   if(x < lo) return lo;
   if(x > hi) return hi;
   return x;
}

int MatIdx(const int i,const int j,const int n)
{
   return i * n + j;
}

void ResetExecutionSnapshot(FXRCExecutionSnapshot &snapshot)
{
   snapshot.open_risk_cash = 0.0;
   snapshot.open_exposure_eur = 0.0;
   snapshot.current_margin_cash = 0.0;
   snapshot.account_active_orders = 0;
   snapshot.all_protected = true;
}

void ResetSymbolExecutionState(FXRCSymbolExecutionState &state)
{
   state.dir = 0;
   state.count = 0;
   state.volume = 0.0;
   state.mixed = false;
   state.account_active_orders = 0;
}

void ResetTradePlan(FXRCTradePlan &plan)
{
   plan.symbol = "";
   plan.dir = 0;
   plan.volume = 0.0;
   plan.entry_price = 0.0;
   plan.stop_price = 0.0;
   plan.risk_cash = 0.0;
   plan.notional_eur = 0.0;
   plan.margin_cash = 0.0;
   plan.target_risk_pct = 0.0;
   plan.sizing_score = 0.0;
   plan.volatility_multiplier = 1.0;
   plan.covariance_multiplier = 1.0;
}

void ResetPPPCacheState(FXRCPPPCacheState &state)
{
   state.loaded = false;
   state.available = false;
   state.last_load_time = 0;
   state.last_success_time = 0;
   state.record_count = 0;
   state.currency_count = 0;
   state.source_file = "";
   state.reason = "";
}

void ResetCarryCacheState(FXRCCarryCacheState &state)
{
   state.loaded = false;
   state.available = false;
   state.last_load_time = 0;
   state.last_success_time = 0;
   state.record_count = 0;
   state.currency_count = 0;
   state.source_file = "";
   state.reason = "";
}

bool TryConvertCash(const string from_ccy, const string to_ccy, const double amount, double &converted)
{
   converted = 0.0;

   if(StringLen(from_ccy) == 0 || StringLen(to_ccy) == 0)
   {
      ActivateConversionFailure(from_ccy, to_ccy);
      return false;
   }

   if(from_ccy == to_ccy)
   {
      converted = amount;
      return true;
   }

   double rate;
   if(GetCurrencyConversionRate(from_ccy, to_ccy, 2, rate))
   {
      converted = amount * rate;
      return true;
   }

   ActivateConversionFailure(from_ccy, to_ccy);
   return false;
}

void ClearConversionFailureState()
{
   g_conversion_error_active = false;
   g_conversion_error_reason = "";
   g_conversion_error_logged = false;
}

void ActivateConversionFailure(const string from_ccy, const string to_ccy)
{
   g_conversion_error_active = true;
   g_conversion_error_reason = StringFormat("currency conversion unavailable from %s to %s", from_ccy, to_ccy);
   if(!g_conversion_error_logged)
   {
      PrintFormat("Currency conversion unavailable from %s to %s. Failing closed.", from_ccy, to_ccy);
      g_conversion_error_logged = true;
   }
}

double EPS() { return 1e-10; }
