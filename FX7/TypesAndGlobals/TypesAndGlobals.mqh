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

struct FXRCMetaBucketStats
{
   string   key;
   string   parent_key;
   int      samples;
   double   ewma_r;
   double   ewma_abs_r;
   double   ewma_r2;
   datetime last_update_time;
};

struct FXRCMetaDecision
{
   bool   allow_entry;
   double risk_multiplier;
   double priority_multiplier;
   double momentum_multiplier;
   double carry_multiplier;
   double value_multiplier;
   string context_key;
   string reason;
};

struct FXRCMetaOpenContext
{
   string   symbol;
   long     position_id;
   int      symbol_idx;
   int      dir;
   double   entry_risk_cash;
   double   entry_volume;
   double   remaining_risk_cash;
   double   remaining_volume;
   double   entry_price;
   string   context_key;
   string   symbol_key;
   string   symbol_dir_key;
   string   session_key;
   string   regime_session_key;
   datetime entry_time;
};

struct FXRCCurrencyExposure
{
   string currency;
   double net_eur;
   double gross_eur;
};

struct FXRCCurrencyExposureCheck
{
   bool   allowed;
   double max_allowed_volume;
   string reason;
};

struct FXRCExecutionQualityDecision
{
   bool   allow_entry;
   double risk_multiplier;
   string reason;
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

FXRCMetaBucketStats g_meta_stats[];
FXRCMetaOpenContext g_meta_open_contexts[];
double   g_meta_entry_risk_multiplier[];
double   g_meta_entry_priority_multiplier[];
string   g_meta_entry_context_key[];
string   g_meta_entry_reason[];
bool     g_meta_stats_dirty = false;
datetime g_meta_last_flush_time = 0;

double   g_exec_quality_spread_samples[];
int      g_exec_quality_sample_count[];
int      g_exec_quality_next_slot[];
double   g_exec_quality_last_bid[];
double   g_exec_quality_last_ask[];
double   g_exec_quality_last_spread_points[];
datetime g_exec_quality_last_quote_time[];
datetime g_exec_quality_stable_since[];

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
   double meta_risk_multiplier;
   double execution_quality_multiplier;
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
