// Finds conversion cache index.
int FindConversionCacheIndex(const string from, const string to)
{
   for(int i=0; i<ArraySize(g_conversion_cache_from); ++i)
   {
      if(g_conversion_cache_from[i] == from && g_conversion_cache_to[i] == to)
         return i;
   }
   return -1;
}

// Stores a currency-conversion rate in the cache.
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

// Attempts to get cached conversion rate.
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

// Ensures reference EUR notional.
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

// Returns the reference EUR notional used by the strategy.
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

// Finds the reference EURUSD symbol in the tracked universe.
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

// Estimates notional EUR.
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

// Converts cash to USD.
double ConvertCashToUSD(const string ccy, const double amount)
{
   return ConvertCash(ccy, "USD", amount);
}

// Converts cash to EUR.
double ConvertCashToEUR(const string ccy, const double amount)
{
   return ConvertCash(ccy, "EUR", amount);
}

// Converts cash.
double ConvertCash(const string from_ccy, const string to_ccy, const double amount)
{
   double converted = 0.0;
   if(TryConvertCash(from_ccy, to_ccy, amount, converted))
      return converted;
   return 0.0;
}

// Gets the currency-to-EUR conversion rate.
bool CurrencyToEURRate(const string ccy, double &rate)
{
   return GetCurrencyConversionRate(ccy, "EUR", 2, rate);
}

// Gets a currency-conversion rate from cached, direct, or bridged paths.
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

// Finds direct conversion rate.
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

// Attempts to resolve conversion symbol directly.
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

// Estimates emergency ATR percentage.
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

// Gets the best analytical mid price for the symbol.
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

// Gets the live mid price from the current tick.
bool GetMidPrice(const string symbol, MqlTick &tick, double &mid)
{
   if(!SymbolInfoTick(symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return false;

   mid = 0.5 * (tick.bid + tick.ask);
   return (mid > 0.0);
}

// Solves a dense linear system with Gaussian elimination.
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

// Computes a Pearson correlation from flattened return history.
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

// Returns the lowest close in the requested range.
double LowestClose(const double &close[], const int from_shift, const int to_shift)
{
   double v = DBL_MAX;
   for(int sh = from_shift; sh <= to_shift; ++sh)
      if(close[sh] < v) v = close[sh];
   return v;
}

// Returns the highest close in the requested range.
double HighestClose(const double &close[], const int from_shift, const int to_shift)
{
   double v = -DBL_MAX;
   for(int sh = from_shift; sh <= to_shift; ++sh)
      if(close[sh] > v) v = close[sh];
   return v;
}

// Calculates ATR as a fraction of price from the supplied rates.
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

// Computes an EWMA standard deviation from close-to-close returns.
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
// Initializes arrays.
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
   ArrayResize(g_XMomScore, g_num_symbols);
   ArrayResize(g_XMomValid, g_num_symbols);
   ArrayResize(g_MediumTrendScore, g_num_symbols);
   ArrayResize(g_MediumTrendValid, g_num_symbols);
   ArrayResize(g_RegimePTrend, g_num_symbols);
   ArrayResize(g_RegimePChoppy, g_num_symbols);
   ArrayResize(g_RegimePStress, g_num_symbols);
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
   ArrayResize(g_probability_p_up, g_num_symbols);
   ArrayResize(g_probability_risk_multiplier, g_num_symbols);
   ArrayResize(g_probability_reason, g_num_symbols);

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
   ArrayInitialize(g_XMomScore, 0.0);
   ArrayInitialize(g_XMomValid, false);
   ArrayInitialize(g_MediumTrendScore, 0.0);
   ArrayInitialize(g_MediumTrendValid, false);
   ArrayInitialize(g_RegimePTrend, 0.0);
   ArrayInitialize(g_RegimePChoppy, 0.0);
   ArrayInitialize(g_RegimePStress, 0.0);
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
   ArrayInitialize(g_probability_p_up, 0.5);
   ArrayInitialize(g_probability_risk_multiplier, 1.0);

   for(int i=0; i<g_num_symbols; ++i)
   {
      g_base_ccy[i]  = SymbolInfoString(g_symbols[i], SYMBOL_CURRENCY_BASE);
      g_quote_ccy[i] = SymbolInfoString(g_symbols[i], SYMBOL_CURRENCY_PROFIT);
      g_symbol_history_reason[i] = "";
      g_probability_reason[i] = "";
      ResetSymbolExecutionState(g_exec_symbol_state[i]);
   }

   FXRCInitMetaAllocatorState();
   FXRCInitExecutionQualityState();
   return true;
}

// Initializes tradable symbols.
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

// Parses symbols.
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

// Prints the validation error and returns false.
bool FailInputValidation(const string message)
{
   Print(message);
   return false;
}

// Validates premia, macro, and allocator inputs.
bool ValidatePremiaInputs()
{
   if(InpMagicNumber <= 0)
      return FailInputValidation("InpMagicNumber must be > 0.");
   if(InpMaxAcceptedSignals <= 0)
      return FailInputValidation("InpMaxAcceptedSignals must be > 0.");
   if(InpWeightMomentum < 0.0 || InpWeightCarry < 0.0 || InpWeightValue < 0.0)
      return FailInputValidation("Premia weights must be >= 0.");
   if((InpWeightMomentum + InpWeightCarry + InpWeightValue) <= EPS())
      return FailInputValidation("At least one premia weight must be > 0.");
   if(InpCarryModel != FXRC_CARRY_MODEL_BROKER_SWAP
      && InpCarryModel != FXRC_CARRY_MODEL_RATE_DIFF
      && InpCarryModel != FXRC_CARRY_MODEL_FORWARD_POINTS_CSV
      && InpCarryModel != FXRC_CARRY_MODEL_HYBRID_BEST_AVAILABLE)
   {
      return FailInputValidation("InpCarryModel is invalid.");
   }
   if(InpValueModel != FXRC_VALUE_MODEL_PROXY
      && InpValueModel != FXRC_VALUE_MODEL_PPP
      && InpValueModel != FXRC_VALUE_MODEL_HYBRID)
   {
      return FailInputValidation("InpValueModel is invalid.");
   }
   if(InpCarryMaxDataAgeDays <= 0 || InpCarryReloadHours <= 0)
      return FailInputValidation("Carry cache freshness inputs must be > 0.");
   if(InpUseForwardPointsCarry
      && (StringLen(InpForwardPointsFile) == 0 || InpForwardPointsMaxStaleDays <= 0))
   {
      return FailInputValidation("Forward-points carry inputs are invalid.");
   }
   if(InpCarryModel == FXRC_CARRY_MODEL_FORWARD_POINTS_CSV
      && !InpUseForwardPointsCarry
      && !InpCarryFallbackToRateDifferential
      && !InpCarryFallbackToBrokerSwap)
   {
      return FailInputValidation(
         "Forward-points carry model requires forward data or an enabled fallback."
      );
   }
   if(InpValueLookbackBars < 30
      || InpValueHalfLifeBars <= 1
      || InpValueHalfLifeBars >= InpValueLookbackBars)
   {
      return FailInputValidation("Value lookback inputs are invalid.");
   }
   if(InpPPPMaxDataAgeDays <= 0 || InpPPPReloadHours <= 0)
      return FailInputValidation("PPP cache freshness inputs must be > 0.");
   if(InpPPPGapScale <= 0.0)
      return FailInputValidation("InpPPPGapScale must be > 0.");
   if(InpPPPBlendWeight < 0.0 || InpProxyBlendWeight < 0.0)
      return FailInputValidation("PPP/proxy blend weights must be >= 0.");
   if(InpValueModel == FXRC_VALUE_MODEL_HYBRID
      && (InpPPPBlendWeight + InpProxyBlendWeight) <= EPS())
   {
      return FailInputValidation(
         "Hybrid value mode requires at least one positive blend weight."
      );
   }
   if(InpValueSignalScale <= 0.0 || InpCarrySignalScale <= 0.0)
      return FailInputValidation("Carry/value signal scales must be > 0.");
   if(InpAllocatorMomentumBoost < 0.0
      || InpAllocatorValueBoost < 0.0
      || InpAllocatorCarryVolPenalty < 0.0
      || InpCarryVolCutoff <= 0.0)
   {
      return FailInputValidation("Allocator inputs are invalid.");
   }
   if(InpTanhScale <= 0.0)
      return FailInputValidation("InpTanhScale must be > 0.");

   return true;
}

// Validates signal-window, ranking, and execution preconditions.
bool ValidateSignalAndExecutionInputs()
{
   if(InpMaxAccountOrders <= 0)
      return FailInputValidation("InpMaxAccountOrders must be > 0.");
   if(InpH1 <= 0 || InpH2 <= InpH1 || InpH3 <= InpH2)
      return FailInputValidation("Trend horizons must satisfy 0 < H1 < H2 < H3.");
   if(InpERWindow <= 1 || InpBreakoutWindow <= 1 || InpShortReversalWindow <= 1)
      return FailInputValidation("ER, breakout, and short reversal windows must be > 1.");
   if(InpVolShortHalfLife <= 0 || InpVolLongHalfLife <= 0 || InpATRWindow <= 1)
   {
      return FailInputValidation(
         "Volatility windows must be positive and ATR window must be > 1."
      );
   }
   if(InpGammaB <= 0.0)
      return FailInputValidation("InpGammaB must be > 0.");
   if(InpCorrLookback < 10)
      return FailInputValidation("InpCorrLookback must be at least 10.");
   if(InpMinCandidatesForOrtho < 2)
      return FailInputValidation("InpMinCandidatesForOrtho must be at least 2.");
   if(InpPersistenceBars <= 0)
      return FailInputValidation("InpPersistenceBars must be > 0.");
   if(InpSlippagePoints < 0
      || InpTradeRetryCount < 0
      || InpTradeVerifyAttempts <= 0)
   {
      return FailInputValidation("Execution inputs are invalid.");
   }
   if(InpSymbolDataFailureGraceBars < 0)
      return FailInputValidation("InpSymbolDataFailureGraceBars must be >= 0.");
   if(InpClassicReferenceEURUSDLots <= 0.0)
      return FailInputValidation("InpClassicReferenceEURUSDLots must be > 0.");

   return true;
}

// Validates risk limits and trade-model settings.
bool ValidateRiskAndModelInputs()
{
   if(InpRiskPerTradePct <= 0.0
      || InpMaxPortfolioRiskPct <= 0.0
      || InpMaxPortfolioExposurePct <= 0.0
      || InpMaxMarginUsagePct <= 0.0)
   {
      return FailInputValidation("Risk limits must be > 0.");
   }
   if(InpCatastrophicStopATR <= 0.0)
      return FailInputValidation("InpCatastrophicStopATR must be > 0.");
   if(InpClassicSinglePositionTakeProfitUSD < 0.0
      || InpClassicSessionResetProfitUSD < 0.0)
   {
      return FailInputValidation("USD profit targets must be >= 0.");
   }
   if(Trade_Model != FXRC_TRADE_MODEL_CLASSIC
      && Trade_Model != FXRC_TRADE_MODEL_MODERN)
   {
      return FailInputValidation("Trade_Model is invalid.");
   }
   if(InpModernBaseTargetRiskPct <= 0.0 || InpModernMinTargetRiskPct <= 0.0)
      return FailInputValidation("Modern risk targets must be > 0.");
   if(InpModernMinTargetRiskPct - EPS() > InpModernBaseTargetRiskPct)
   {
      return FailInputValidation(
         "InpModernMinTargetRiskPct must be <= InpModernBaseTargetRiskPct."
      );
   }
   if(InpModernBaseTargetRiskPct - EPS() > InpRiskPerTradePct)
      return FailInputValidation("InpModernBaseTargetRiskPct must be <= InpRiskPerTradePct.");
   if(InpModernTargetATRPct <= 0.0
      || InpModernVolAdjustMin <= 0.0
      || InpModernVolAdjustMax <= 0.0
      || InpModernVolAdjustMin - EPS() > InpModernVolAdjustMax)
   {
      return FailInputValidation("Modern volatility targeting inputs are invalid.");
   }
   if(InpModernCovariancePenaltyFloor <= 0.0 || InpModernCovariancePenaltyFloor > 1.0)
      return FailInputValidation("InpModernCovariancePenaltyFloor must be in (0,1].");
   if(InpModernForecastRiskATRScale <= 0.0)
      return FailInputValidation("InpModernForecastRiskATRScale must be > 0.");
   if(EAStopMinEqui < 0 || EAStopMaxDD < 0.0)
      return FailInputValidation("EA hard-stop inputs must be >= 0.");

   return true;
}

// Validates optional adaptive overlay inputs.
bool ValidateAdaptiveOverlayInputs()
{
   if(InpUseMetaAllocator
      && (InpMetaMinSamplesForThrottle < 0
          || InpMetaMinSamplesForBoost < 0
          || InpMetaUpdateHalfLifeTrades <= 0
          || InpMetaPriorWeight < 0.0
          || InpMetaStatsFlushMinutes <= 0))
   {
      return FailInputValidation("Meta allocator sample and persistence inputs are invalid.");
   }
   if(InpUseMetaAllocator
      && (InpMetaMinRiskMultiplier < 0.0
          || InpMetaBadContextMultiplier < 0.0
          || InpMetaNeutralRiskMultiplier < 0.0
          || InpMetaNeutralRiskMultiplier < InpMetaMinRiskMultiplier
          || InpMetaBadContextMultiplier < InpMetaMinRiskMultiplier
          || InpMetaBadContextMultiplier > InpMetaNeutralRiskMultiplier
          || InpMetaMaxRiskMultiplier < InpMetaNeutralRiskMultiplier
          || InpMetaMaxRiskMultiplier < InpMetaMinRiskMultiplier))
   {
      return FailInputValidation("Meta allocator risk multipliers are invalid.");
   }
   if(InpUseMetaAllocator && InpMetaConservativeZ < 0.0)
      return FailInputValidation("InpMetaConservativeZ must be >= 0.");

   if(InpUseCurrencyFactorExposureControl
      && (InpMaxNetSingleCurrencyExposurePct < 0.0
          || InpMaxGrossSingleCurrencyExposurePct < 0.0
          || InpMaxCurrencyBlocNetExposurePct < 0.0
          || InpMaxCurrencyFactorConcentrationPct < 0.0
          || InpMaxCurrencyFactorConcentrationPct > 100.0))
   {
      return FailInputValidation("Currency factor exposure limits are invalid.");
   }

   if(InpUseExecutionQualityGovernor
      && (InpExecQualitySpreadLookbackSamples < 20
          || InpExecQualityMaxSpreadPercentile <= 0.0
          || InpExecQualityMaxSpreadPercentile >= 1.0
          || InpExecQualityAbnormalSpreadMultiple <= 1.0
          || InpExecQualityStableQuoteSeconds < 0
          || InpExecQualityRolloverSkipMinutes < 0
          || InpExecQualityElevatedCostRiskMultiplier < 0.0
          || InpExecQualityElevatedCostRiskMultiplier > 1.0
          || InpExecQualityNewsMinutesBefore < 0
          || InpExecQualityNewsMinutesAfter < 0))
   {
      return FailInputValidation("Execution quality governor inputs are invalid.");
   }

   if(InpUseCrossSectionalMomentum
      && (InpXMomLookback1 <= 1
          || InpXMomLookback2 <= 1
          || InpXMomLookback3 <= 1
          || InpXMomWeight1 < 0.0
          || InpXMomWeight2 < 0.0
          || InpXMomWeight3 < 0.0
          || (InpXMomWeight1 + InpXMomWeight2 + InpXMomWeight3) <= EPS()
          || InpXMomTanhScale <= 0.0
          || InpXMomMinSymbols < 2.0
          || InpXMomRidgeLambda < 0.0))
   {
      return FailInputValidation("Cross-sectional momentum inputs are invalid.");
   }

   if(InpUseMediumTermTrend
      && (InpMediumTrendTF1Lookback1 <= 1
          || InpMediumTrendTF1Lookback2 <= 1
          || InpMediumTrendTF1Lookback3 <= 1
          || InpMediumTrendTF2Lookback1 <= 1
          || InpMediumTrendTF2Lookback2 <= 1
          || InpMediumTrendTF2Lookback3 <= 1
          || InpMediumTrendTF1Weight < 0.0
          || InpMediumTrendTF2Weight < 0.0
          || (InpMediumTrendTF1Weight + InpMediumTrendTF2Weight) <= EPS()
          || InpMediumTrendTanhScale <= 0.0
          || InpMediumTrendAlignmentPenalty < 0.0
          || InpMediumTrendAlignmentPenalty > 1.0))
   {
      return FailInputValidation("Medium-term trend inputs are invalid.");
   }

   if(InpUseResearchFeatureExport
      && (StringLen(InpResearchExportFile) == 0 || InpResearchExportSchemaVersion <= 0))
   {
      return FailInputValidation("Research feature export inputs are invalid.");
   }

   if(InpUseProbabilityModel
      && (StringLen(InpProbabilityModelFile) == 0
          || InpProbabilityHorizonDays <= 0
          || InpProbabilityMinEdge < 0.0
          || InpProbabilityMinRiskScale < 0.0
          || InpProbabilityMaxRiskScale < InpProbabilityMinRiskScale))
   {
      return FailInputValidation("Probability model inputs are invalid.");
   }

   if(InpUseRegimeStateFilter
      && (InpRegimeStressBlockThreshold < 0.0
          || InpRegimeStressBlockThreshold > 1.0
          || InpRegimeCarryStressPenalty < 0.0
          || InpRegimeCarryStressPenalty > 1.0
          || InpRegimeTrendChopPenalty < 0.0
          || InpRegimeTrendChopPenalty > 1.0))
   {
      return FailInputValidation("Regime state filter inputs are invalid.");
   }

   return true;
}

// Validates classic overlay behavior and trailing configuration.
bool ValidateClassicOverlayInputs()
{
   if(InpClassicUseTrailingStop != 0 && InpClassicUseTrailingStop != 1)
      return FailInputValidation("InpClassicUseTrailingStop must be 0 or 1.");
   if(InpClassicUseTrailingStop == 1)
   {
      if(InpClassicTrailStartPct < 10
         || InpClassicTrailStartPct > 100
         || (InpClassicTrailStartPct % 10) != 0)
      {
         return FailInputValidation(
            "InpClassicTrailStartPct must be between 10 and 100 in 10% steps."
         );
      }
      if(InpClassicTrailSpacingPct < 10
         || InpClassicTrailSpacingPct > 100
         || (InpClassicTrailSpacingPct % 10) != 0)
      {
         return FailInputValidation(
            "InpClassicTrailSpacingPct must be between 10 and 100 in 10% steps."
         );
      }
   }
   if(IsClassicTradeModel()
      && InpClassicUseTrailingStop == 1
      && InpClassicSinglePositionTakeProfitUSD <= 0.0)
   {
      return FailInputValidation(
         "Classic mode with trailing enabled requires "
         + "InpClassicSinglePositionTakeProfitUSD > 0 as the trailing "
         + "activation anchor."
      );
   }

   return true;
}

// Validates threshold, gating, and ranking controls.
bool ValidateThresholdInputs()
{
   if(InpBaseEntryThreshold < 0.0
      || InpBaseExitThreshold < 0.0
      || InpReversalThreshold < 0.0
      || InpTheta0 < 0.0)
   {
      return FailInputValidation("Threshold inputs must be >= 0.");
   }
   if(InpAlphaSmooth < 0.0 || InpAlphaSmooth > 1.0)
      return FailInputValidation("InpAlphaSmooth must be in [0, 1].");
   if(InpConfSlope <= 0.0)
      return FailInputValidation("InpConfSlope must be > 0.");
   if(InpEtaCost < 0.0
      || InpEtaVol < 0.0
      || InpEtaBreakout < 0.0
      || InpGammaCost < 0.0)
   {
      return FailInputValidation("Threshold penalty inputs must be >= 0.");
   }
   if(InpBaseExitThreshold > InpBaseEntryThreshold)
      return FailInputValidation("InpBaseExitThreshold should not exceed InpBaseEntryThreshold.");
   if(InpMinConfidence < 0.0 || InpMinConfidence > 1.0)
      return FailInputValidation("InpMinConfidence must be in [0, 1].");
   if(InpMinRegimeGate < 0.0
      || InpMinRegimeGate > 1.0
      || InpHardMinRegimeGate < 0.0
      || InpHardMinRegimeGate > 1.0
      || InpMinExecGate < 0.0
      || InpMinExecGate > 1.0)
   {
      return FailInputValidation("Gate thresholds must be in [0, 1].");
   }
   if(InpUniquenessMin < 0.0
      || InpUniquenessMin > 1.0
      || InpCrowdingMax < 0.0
      || InpCrowdingMax > 1.0)
   {
      return FailInputValidation(
         "Uniqueness and crowding thresholds must be in [0, 1]."
      );
   }
   if(InpShrinkageLambda < 0.0 || InpShrinkageLambda > 1.0)
      return FailInputValidation("InpShrinkageLambda must be in [0, 1].");
   if(InpNoveltyFloorWeight < 0.0
      || InpNoveltyFloorWeight > 1.0
      || InpNoveltyCap <= 0.0)
   {
      return FailInputValidation("Novelty overlay inputs are invalid.");
   }
   if(InpFXOverlapFloor < -1.0
      || InpFXOverlapFloor > 1.0
      || InpClassOverlapFloor < -1.0
      || InpClassOverlapFloor > 1.0)
   {
      return FailInputValidation("Overlap floors must be in [-1, 1].");
   }

   return true;
}

// Validates cost inputs and initializes normalized trend weights.
bool ValidateCostInputsAndTrendWeights()
{
   if(InpExpectedHoldingDays < 0.0 || InpCommissionRoundTripPerLotEUR < 0.0 || InpAssumedRoundTripFeePct < 0.0)
      return FailInputValidation("Cost inputs must be >= 0.");
   if(InpDependencyFailureGraceMinutes < 0)
      return FailInputValidation("InpDependencyFailureGraceMinutes must be >= 0.");

   double wsum = InpW1 + InpW2 + InpW3;
   if(wsum <= EPS())
      return FailInputValidation("Trend weights must sum to a positive value.");

   g_w1 = InpW1 / wsum;
   g_w2 = InpW2 / wsum;
   g_w3 = InpW3 / wsum;
   return true;
}

// Validates inputs.
bool ValidateInputs()
{
   return (
      ValidatePremiaInputs()
      && ValidateSignalAndExecutionInputs()
      && ValidateRiskAndModelInputs()
      && ValidateAdaptiveOverlayInputs()
      && ValidateClassicOverlayInputs()
      && ValidateThresholdInputs()
      && ValidateCostInputsAndTrendWeights()
   );
}

// Returns whether the symbol series is synchronized with the terminal feed.
bool IsHistorySeriesSynchronized(const string symbol,
                                 const ENUM_TIMEFRAMES timeframe)
{
   if(!SymbolIsSynchronized(symbol))
      return false;

   long synchronized = 0;
   if(!SeriesInfoInteger(symbol, timeframe, SERIES_SYNCHRONIZED, synchronized))
      return false;

   return (synchronized != 0);
}

// Inspects history readiness for the requested symbol and timeframe.
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
   if(require_fresh_feed && !MQLInfoInteger(MQL_TESTER))
   {
      if(!IsHistorySeriesSynchronized(symbol, timeframe))
      {
         check.feed_ready = false;
         check.reason = StringFormat(
            "History is not synchronized yet for %s on %s.",
            symbol,
            EnumToString(timeframe)
         );
         return false;
      }
   }
   else if(require_fresh_feed && MQLInfoInteger(MQL_TESTER))
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

// Loads rates window.
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

// Gets the latest available bar time for the series.
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

// Logs startup step.
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

// Returns whether startup-step logging is enabled.
bool StartupDebugEnabled()
{
   return (InpDebugStartupSequence && !MQLInfoInteger(MQL_TESTER));
}

// Returns whether the runtime is ready to process the model.
bool RuntimeCanProcessModel()
{
   return (g_runtime_state.status == FXRC_RUNTIME_READY && g_runtime_state.ready_symbols > 0);
}

//------------------------- Core Helpers -------------------------//
// Returns whether two symbols share the same class overlap.
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

// Returns whether the pair touches the requested currency bloc.
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

// Returns whether the currency belongs to the funding bloc.
bool IsFundingBlocCurrency(const string ccy)
{
   return (ccy == "JPY" || ccy == "CHF" || ccy == "EUR");
}

// Returns whether the currency belongs to the European bloc.
bool IsEuropeanBlocCurrency(const string ccy)
{
   return (ccy == "EUR" || ccy == "GBP" || ccy == "CHF" || ccy == "SEK" || ccy == "NOK");
}

// Returns whether the currency belongs to the commodity bloc.
bool IsCommodityBlocCurrency(const string ccy)
{
   return (ccy == "AUD" || ccy == "NZD" || ccy == "CAD" || ccy == "NOK");
}

// Returns whether two tracked symbols share a currency.
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

// Returns whether the tracked index points to a forex symbol.
bool IsForexSymbolIndex(const int i)
{
   if(i < 0 || i >= g_num_symbols)
      return false;
   return (StringLen(g_base_ccy[i]) == 3 && StringLen(g_quote_ccy[i]) == 3);
}

// Returns whether trading is allowed for the tracked symbol index.
bool IsTradeAllowed(const int idx)
{
   if(idx < 0 || idx >= g_num_symbols)
      return false;
   if(ArraySize(g_trade_allowed) != g_num_symbols)
      return true;
   return g_trade_allowed[idx];
}

// Finds tracked symbol index.
int FindTrackedSymbolIndex(const string symbol)
{
   for(int i=0; i<g_num_symbols; ++i)
   {
      if(SymbolNamesEqual(g_symbols[i], symbol))
         return i;
   }
   return -1;
}

// Returns whether the symbol already exists in the list.
bool SymbolAlreadyListed(const string &symbols[], const int count, const string symbol)
{
   for(int i=0; i<count; ++i)
   {
      if(SymbolNamesEqual(symbols[i], symbol))
         return true;
   }
   return false;
}

// Returns whether the symbol represents a forex position.
bool IsForexPositionSymbol(const string symbol)
{
   return (StringLen(symbol) > 0 && IsForexPairSymbol(symbol));
}

// Returns whether the symbol represents a forex pair.
bool IsForexPairSymbol(const string symbol)
{
   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   if(StringLen(base) != 3 || StringLen(quote) != 3)
      return false;

   ENUM_SYMBOL_CALC_MODE calc_mode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_CALC_MODE);
   return (calc_mode == SYMBOL_CALC_MODE_FOREX || calc_mode == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE);
}

// Returns whether two symbol names normalize to the same value.
bool SymbolNamesEqual(const string a, const string b)
{
   return (NormalizedSymbolName(a) == NormalizedSymbolName(b));
}

// Returns normalized symbol name.
string NormalizedSymbolName(const string symbol)
{
   string out = symbol;
   StringTrimLeft(out);
   StringTrimRight(out);
   StringToUpper(out);
   return out;
}

// Selects and sync symbol.
bool SelectAndSyncSymbol(const string symbol)
{
   return SymbolSelect(symbol, true);
}

// Returns whether the trade retcode should be retried.
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

// Returns whether the trade-check retcode indicates success.
bool IsTradeCheckRetcodeSuccess(const uint retcode)
{
   // OrderCheck() uses 0 to signal a successful pre-trade validation.
   return (retcode == 0 || IsTradeRetcodeSuccess(retcode));
}

// Returns whether the trade retcode indicates success.
bool IsTradeRetcodeSuccess(const uint retcode)
{
   return (retcode == TRADE_RETCODE_DONE
        || retcode == TRADE_RETCODE_DONE_PARTIAL
        || retcode == TRADE_RETCODE_PLACED);
}

// Returns whether the retcode is successful for the requested trade action.
bool IsTradeRetcodeSuccessForAction(const ENUM_TRADE_REQUEST_ACTIONS action,
                                    const uint retcode)
{
   if(IsTradeRetcodeSuccess(retcode))
      return true;

   return (action == TRADE_ACTION_SLTP && retcode == TRADE_RETCODE_NO_CHANGES);
}

// Normalizes volume by broker step while optionally enforcing FX7's entry floor.
double NormalizeVolume(const string symbol,
                       const double requested,
                       const bool enforce_project_min = true)
{
   double minv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxv = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(enforce_project_min)
      minv = MathMax(minv, 0.01);
   if(step <= 0.0)
      step = minv;
   if(step <= 0.0)
      step = 0.01;
   if(requested <= 0.0 || maxv <= 0.0)
      return 0.0;

   double capped = MathMin(requested, maxv);
   double steps = MathFloor((capped / step) + 1e-6);
   double v = steps * step;
   if(v + EPS() < minv)
      return 0.0;

   return NormalizeDouble(v, VolumeDigits(step));
}

// Returns the amount of decimal digits needed for the volume step.
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

// Normalizes price.
double NormalizePrice(const string symbol, const double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

// Logs dependency transition.
void LogDependencyTransition(const string message)
{
   PrintFormat("FXRC dependency: %s", message);
}

// Returns a readable dependency scope label for logs.
string DependencyScopeLabel()
{
   if(StringLen(g_dependency_state.dependency_scope) > 0)
      return g_dependency_state.dependency_scope;

   return "dependency";
}

// Logs runtime state if needed.
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

// Sets the runtime status and reason fields.
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

// Resets dependency runtime state.
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

// Resets runtime state.
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

// Resets history check.
void ResetHistoryCheck(FXRCHistoryCheck &check)
{
   check.feed_ready = false;
   check.enough_bars = false;
   check.latest_bar = 0;
   check.bars_available = 0;
   check.reason = "";
}

// Formats a dependency runtime state as text.
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

// Formats a runtime status as text.
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

// Formats a datetime value for logging.
string FormatTimeValue(const datetime value)
{
   if(value <= 0)
      return "n/a";
   return TimeToString(value, TIME_DATE | TIME_MINUTES);
}

// Returns the amount of signal-bar history required by the model.
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

// Returns the amount of value-timeframe history required by the model.
int ValueBarsNeeded()
{
   return MathMax(InpValueLookbackBars + 5, 3);
}

// Returns the positive-only tanh-like transform.
double TanhLikePositive(const double x)
{
   return (2.0 * Sigmoid(2.0 * MathMax(x, 0.0)) - 1.0);
}

// Returns whether classic session reset active.
bool IsClassicSessionResetActive()
{
   return (IsClassicTradeModel() && InpClassicSessionResetProfitUSD > 0.0);
}

// Returns whether classic trailing active.
bool IsClassicTrailingActive()
{
   return (IsClassicTradeModel() && InpClassicUseTrailingStop != 0 && InpClassicSinglePositionTakeProfitUSD > 0.0);
}

// Returns whether classic take profit active.
bool IsClassicTakeProfitActive()
{
   return (IsClassicTradeModel() && InpClassicUseTrailingStop == 0 && InpClassicSinglePositionTakeProfitUSD > 0.0);
}

// Returns whether modern trade model.
bool IsModernTradeModel()
{
   return (Trade_Model == FXRC_TRADE_MODEL_MODERN);
}

// Returns whether classic trade model.
bool IsClassicTradeModel()
{
   return (Trade_Model == FXRC_TRADE_MODEL_CLASSIC);
}

// Returns whether the carry sleeve is enabled.
bool CarrySleeveEnabled()
{
   return (InpWeightCarry > EPS());
}

// Returns whether the value sleeve is enabled.
bool ValueSleeveEnabled()
{
   return (InpWeightValue > EPS());
}

// Returns whether value signal requires PPP data.
bool ValueSignalRequiresPPPData()
{
   if(!ValueSleeveEnabled())
      return false;

   if(InpValueModel == FXRC_VALUE_MODEL_PPP)
      return !InpPPPAllowProxyFallback;

   if(InpValueModel == FXRC_VALUE_MODEL_HYBRID)
      return (InpPPPBlendWeight > EPS() && InpProxyBlendWeight <= EPS());

   return false;
}

// Returns whether carry signal requires external data.
bool CarrySignalRequiresExternalData()
{
   if(!CarrySleeveEnabled())
      return false;

   if(InpCarryModel == FXRC_CARRY_MODEL_RATE_DIFF)
      return !InpCarryAllowBrokerFallback;

   if(InpCarryModel == FXRC_CARRY_MODEL_FORWARD_POINTS_CSV)
      return (!InpCarryFallbackToRateDifferential && !InpCarryFallbackToBrokerSwap);

   if(InpCarryModel == FXRC_CARRY_MODEL_HYBRID_BEST_AVAILABLE)
      return (
         InpUseForwardPointsCarry
         && !InpCarryFallbackToRateDifferential
         && !InpCarryFallbackToBrokerSwap
      );

   return false;
}

// Returns whether carry model uses external.
bool CarryModelUsesExternal()
{
   return (
      CarrySleeveEnabled()
      && (InpCarryModel == FXRC_CARRY_MODEL_RATE_DIFF
          || InpCarryModel == FXRC_CARRY_MODEL_FORWARD_POINTS_CSV
          || InpCarryModel == FXRC_CARRY_MODEL_HYBRID_BEST_AVAILABLE)
   );
}

// Returns whether the carry path needs the startup-built rate-differential cache.
bool CarryModelUsesRateDifferentialData()
{
   if(!CarrySleeveEnabled())
      return false;
   if(InpCarryModel == FXRC_CARRY_MODEL_RATE_DIFF)
      return true;
   if(InpCarryModel == FXRC_CARRY_MODEL_FORWARD_POINTS_CSV)
      return InpCarryFallbackToRateDifferential;
   if(InpCarryModel == FXRC_CARRY_MODEL_HYBRID_BEST_AVAILABLE)
      return InpCarryFallbackToRateDifferential;

   return false;
}

// Returns whether value model uses PPP.
bool ValueModelUsesPPP()
{
   if(!ValueSleeveEnabled())
      return false;

   if(InpValueModel == FXRC_VALUE_MODEL_PPP)
      return true;

   if(InpValueModel == FXRC_VALUE_MODEL_HYBRID)
      return (InpPPPBlendWeight > EPS());

   return false;
}

// Returns the best available server-aligned timestamp.
datetime SafeNow()
{
   datetime now = TimeTradeServer();
   if(now <= 0)
      now = TimeCurrent();
   return now;
}

// Maps a position type into a signed direction.
int PositionDirFromType(const long type)
{
   if(type == POSITION_TYPE_BUY)  return 1;
   if(type == POSITION_TYPE_SELL) return -1;
   return 0;
}

// Returns whether symbol data stale.
bool IsSymbolDataStale(const int idx)
{
   return (idx >= 0
        && idx < ArraySize(g_symbol_data_stale)
        && g_symbol_data_stale[idx]);
}

// Returns whether cross sectionally eligible symbol.
bool IsCrossSectionallyEligibleSymbol(const int idx)
{
   return (idx >= 0
        && idx < g_num_symbols
        && g_symbol_data_ok[idx]
        && !IsSymbolDataStale(idx));
}

// Returns the long, short, or fallback value for the requested direction.
double DirectionalValue(const int dir, const double long_value, const double short_value, const double fallback_value)
{
   if(dir > 0)
      return long_value;
   if(dir < 0)
      return short_value;
   return fallback_value;
}

// Returns whether directional long.
bool IsDirectionalLong(const int dir)
{
   return (dir > 0);
}

// Returns the sign of the supplied double value.
int SignD(const double x)
{
   if(x > 0.0) return 1;
   if(x < 0.0) return -1;
   return 0;
}

// Returns the sigmoid transform of the supplied value.
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

// Returns the positive part of the supplied value.
double PosPart(const double x)
{
   return (x > 0.0 ? x : 0.0);
}

// Clamps a value into the requested range.
double Clip(const double x,const double lo,const double hi)
{
   if(x < lo) return lo;
   if(x > hi) return hi;
   return x;
}

// Returns the flattened matrix index for row-major storage.
int MatIdx(const int i,const int j,const int n)
{
   return i * n + j;
}

// Resets execution snapshot.
void ResetExecutionSnapshot(FXRCExecutionSnapshot &snapshot)
{
   snapshot.open_risk_cash = 0.0;
   snapshot.open_exposure_eur = 0.0;
   snapshot.current_margin_cash = 0.0;
   snapshot.account_active_orders = 0;
   snapshot.all_protected = true;
}

// Resets symbol execution state.
void ResetSymbolExecutionState(FXRCSymbolExecutionState &state)
{
   state.dir = 0;
   state.count = 0;
   state.volume = 0.0;
   state.mixed = false;
   state.account_active_orders = 0;
}

// Resets trade plan.
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
   plan.meta_risk_multiplier = 1.0;
   plan.execution_quality_multiplier = 1.0;
}

// Resets PPP cache state.
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

// Resets carry cache state.
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

// Attempts to convert cash.
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

// Clears conversion failure state.
void ClearConversionFailureState()
{
   g_conversion_error_active = false;
   g_conversion_error_reason = "";
   g_conversion_error_logged = false;
}

// Activates the conversion-failure state for the requested currencies.
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

// Returns the small epsilon used for numeric guards.
double EPS() { return 1e-10; }
