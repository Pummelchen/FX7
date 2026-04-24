//------------------------- Cross-Sectional Currency Momentum -------------------------//

// Returns the maximum of three integer lookbacks for cross-sectional momentum.
int FXRCXMomMax3Int(const int a, const int b, const int c)
{
   return MathMax(a, MathMax(b, c));
}

// Adds a currency code to the cross-sectional currency list if absent.
void FXRCXMomAppendCurrency(string &currencies[], const string currency)
{
   string ccy = NormalizeCurrencyCode(currency);
   if(StringLen(ccy) != 3)
      return;

   for(int i=0; i<ArraySize(currencies); ++i)
   {
      if(currencies[i] == ccy)
         return;
   }

   int new_size = ArraySize(currencies) + 1;
   ArrayResize(currencies, new_size);
   currencies[new_size - 1] = ccy;
}

// Returns the currency-list index for a code.
int FXRCXMomCurrencyIndex(const string currency, const string &currencies[])
{
   string ccy = NormalizeCurrencyCode(currency);
   for(int i=0; i<ArraySize(currencies); ++i)
   {
      if(currencies[i] == ccy)
         return i;
   }

   return -1;
}

// Builds the currency list implied by the active FX universe.
int FXRCXMomBuildCurrencyList(string &currencies[])
{
   ArrayResize(currencies, 0);
   for(int i=0; i<g_num_symbols; ++i)
   {
      FXRCXMomAppendCurrency(currencies, g_base_ccy[i]);
      FXRCXMomAppendCurrency(currencies, g_quote_ccy[i]);
   }

   return ArraySize(currencies);
}

// Loads a closed-bar log return for a pair and lookback.
bool FXRCXMomPairReturn(const string symbol,
                        const int lookback,
                        double &ret)
{
   ret = 0.0;
   if(lookback <= 1)
      return false;

   if(InpXMomRequireSynchronizedBars
      && !IsHistorySeriesSynchronized(symbol, InpXMomTF))
   {
      return false;
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   ResetLastError();
   int copied = CopyRates(symbol, InpXMomTF, 0, lookback + 2, rates);
   if(copied < lookback + 2)
      return false;

   double close_now = rates[1].close;
   double close_then = rates[lookback + 1].close;
   if(close_now <= 0.0 || close_then <= 0.0)
      return false;

   ret = MathLog(close_now / close_then);
   return (ret == ret);
}

// Solves a small dense linear system with partial-pivot Gaussian elimination.
bool FXRCXMomSolveLinear(double &normal_matrix[],
                         double &rhs[],
                         const int n,
                         double &solution[])
{
   ArrayResize(solution, n);
   if(n <= 0 || ArraySize(normal_matrix) < n * n || ArraySize(rhs) < n)
      return false;

   for(int col=0; col<n; ++col)
   {
      int pivot = col;
      double pivot_abs = MathAbs(normal_matrix[col * n + col]);
      for(int row=col+1; row<n; ++row)
      {
         double candidate = MathAbs(normal_matrix[row * n + col]);
         if(candidate > pivot_abs)
         {
            pivot = row;
            pivot_abs = candidate;
         }
      }

      if(pivot_abs <= 1e-12)
         return false;

      if(pivot != col)
      {
         for(int k=col; k<n; ++k)
         {
            double tmp = normal_matrix[col * n + k];
            normal_matrix[col * n + k] = normal_matrix[pivot * n + k];
            normal_matrix[pivot * n + k] = tmp;
         }
         double rhs_tmp = rhs[col];
         rhs[col] = rhs[pivot];
         rhs[pivot] = rhs_tmp;
      }

      double diag = normal_matrix[col * n + col];
      for(int row=col+1; row<n; ++row)
      {
         double factor = normal_matrix[row * n + col] / diag;
         normal_matrix[row * n + col] = 0.0;
         for(int k=col+1; k<n; ++k)
            normal_matrix[row * n + k] -= factor * normal_matrix[col * n + k];
         rhs[row] -= factor * rhs[col];
      }
   }

   for(int row=n-1; row>=0; --row)
   {
      double sum = rhs[row];
      for(int k=row+1; k<n; ++k)
         sum -= normal_matrix[row * n + k] * solution[k];

      double diag = normal_matrix[row * n + row];
      if(MathAbs(diag) <= 1e-12)
         return false;

      solution[row] = sum / diag;
   }

   return true;
}

// Enforces zero-sum currency scores.
void FXRCXMomCenterScores(double &scores[])
{
   int n = ArraySize(scores);
   if(n <= 0)
      return;

   double mean = 0.0;
   for(int i=0; i<n; ++i)
      mean += scores[i];
   mean /= (double)n;

   for(int i=0; i<n; ++i)
      scores[i] -= mean;
}

// Computes currency scores by simple base/quote contribution fallback.
bool FXRCXMomContributionScores(const int lookback,
                                const string &currencies[],
                                double &scores[],
                                int &valid_symbols)
{
   int n = ArraySize(currencies);
   ArrayResize(scores, n);
   ArrayInitialize(scores, 0.0);
   int counts[];
   ArrayResize(counts, n);
   ArrayInitialize(counts, 0);
   valid_symbols = 0;

   for(int i=0; i<g_num_symbols; ++i)
   {
      if(!IsCrossSectionallyEligibleSymbol(i))
         continue;

      double ret = 0.0;
      if(!FXRCXMomPairReturn(g_symbols[i], lookback, ret))
         continue;

      int base_idx = FXRCXMomCurrencyIndex(g_base_ccy[i], currencies);
      int quote_idx = FXRCXMomCurrencyIndex(g_quote_ccy[i], currencies);
      if(base_idx < 0 || quote_idx < 0)
         continue;

      scores[base_idx] += ret;
      scores[quote_idx] -= ret;
      counts[base_idx]++;
      counts[quote_idx]++;
      valid_symbols++;
   }

   for(int c=0; c<n; ++c)
   {
      if(counts[c] > 0)
         scores[c] /= (double)counts[c];
   }

   FXRCXMomCenterScores(scores);
   return (valid_symbols >= (int)MathMax(2.0, InpXMomMinSymbols));
}

// Computes latent currency momentum scores with ridge-regularized least squares.
bool FXRCXMomLeastSquaresScores(const int lookback,
                                const string &currencies[],
                                double &scores[],
                                int &valid_symbols)
{
   int n = ArraySize(currencies);
   ArrayResize(scores, n);
   ArrayInitialize(scores, 0.0);
   valid_symbols = 0;

   if(n < 2 || !InpXMomUseCurrencyDecomposition)
      return FXRCXMomContributionScores(lookback, currencies, scores, valid_symbols);

   double normal_matrix[];
   double rhs[];
   ArrayResize(normal_matrix, n * n);
   ArrayResize(rhs, n);
   ArrayInitialize(normal_matrix, 0.0);
   ArrayInitialize(rhs, 0.0);

   for(int i=0; i<g_num_symbols; ++i)
   {
      if(!IsCrossSectionallyEligibleSymbol(i))
         continue;

      double ret = 0.0;
      if(!FXRCXMomPairReturn(g_symbols[i], lookback, ret))
         continue;

      int base_idx = FXRCXMomCurrencyIndex(g_base_ccy[i], currencies);
      int quote_idx = FXRCXMomCurrencyIndex(g_quote_ccy[i], currencies);
      if(base_idx < 0 || quote_idx < 0 || base_idx == quote_idx)
         continue;

      normal_matrix[base_idx * n + base_idx] += 1.0;
      normal_matrix[quote_idx * n + quote_idx] += 1.0;
      normal_matrix[base_idx * n + quote_idx] -= 1.0;
      normal_matrix[quote_idx * n + base_idx] -= 1.0;
      rhs[base_idx] += ret;
      rhs[quote_idx] -= ret;
      valid_symbols++;
   }

   if(valid_symbols < (int)MathMax(2.0, InpXMomMinSymbols))
      return false;

   double ridge = MathMax(0.0, InpXMomRidgeLambda);
   for(int i=0; i<n; ++i)
      normal_matrix[i * n + i] += ridge;

   double solution[];
   if(!FXRCXMomSolveLinear(normal_matrix, rhs, n, solution))
      return FXRCXMomContributionScores(lookback, currencies, scores, valid_symbols);

   ArrayCopy(scores, solution);
   FXRCXMomCenterScores(scores);
   return true;
}

// Estimates the ex-ante volatility scale for a pair on the cross-sectional timeframe.
double FXRCXMomPairVolScale(const string symbol, const double effective_lookback)
{
   if(!InpXMomVolNormalize)
      return 1.0;

   int max_lookback = FXRCXMomMax3Int(
      InpXMomLookback1,
      InpXMomLookback2,
      InpXMomLookback3
   );
   int bars_needed = max_lookback + 40;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   ResetLastError();
   int copied = CopyRates(symbol, InpXMomTF, 0, bars_needed, rates);
   if(copied < max_lookback + 2)
      return 1.0;

   double close[];
   ArrayResize(close, copied);
   ArraySetAsSeries(close, true);
   for(int i=0; i<copied; ++i)
      close[i] = rates[i].close;

   double sigma = EWMAStdFromCloses(close, MathMin(copied - 2, max_lookback + 20), 40);
   if(sigma <= EPS())
      return 1.0;

   return sigma * MathSqrt(MathMax(1.0, effective_lookback));
}

// Logs the startup cross-sectional momentum universe summary.
void FXRCLogCrossSectionalMomentumStartup()
{
   if(!InpUseCrossSectionalMomentum || MathAbs(InpXMomCompositeWeight) <= EPS())
      return;

   string currencies[];
   int currency_count = FXRCXMomBuildCurrencyList(currencies);
   PrintFormat(
      "FXRC cross-sectional momentum enabled: symbols=%d currencies=%d tf=%s",
      g_num_symbols,
      currency_count,
      EnumToString(InpXMomTF)
   );

   if(g_num_symbols < (int)MathMax(2.0, InpXMomMinSymbols))
   {
      PrintFormat(
         "FXRC cross-sectional momentum warning: universe has %d symbols, "
         + "minimum requested is %.0f.",
         g_num_symbols,
         InpXMomMinSymbols
      );
   }
}

// Rebuilds cross-sectional currency momentum scores for the current closed-bar cycle.
bool FXRCRefreshCrossSectionalMomentumForCycle()
{
   ArrayInitialize(g_XMomScore, 0.0);
   ArrayInitialize(g_XMomValid, false);

   if(!InpUseCrossSectionalMomentum || MathAbs(InpXMomCompositeWeight) <= EPS())
      return true;

   string currencies[];
   int currency_count = FXRCXMomBuildCurrencyList(currencies);
   if(currency_count < 2)
      return false;

   double scores1[], scores2[], scores3[];
   int valid1 = 0, valid2 = 0, valid3 = 0;
   bool ok1 = FXRCXMomLeastSquaresScores(InpXMomLookback1, currencies, scores1, valid1);
   bool ok2 = FXRCXMomLeastSquaresScores(InpXMomLookback2, currencies, scores2, valid2);
   bool ok3 = FXRCXMomLeastSquaresScores(InpXMomLookback3, currencies, scores3, valid3);

   double w1 = (ok1 ? MathMax(0.0, InpXMomWeight1) : 0.0);
   double w2 = (ok2 ? MathMax(0.0, InpXMomWeight2) : 0.0);
   double w3 = (ok3 ? MathMax(0.0, InpXMomWeight3) : 0.0);
   double wsum = w1 + w2 + w3;
   if(wsum <= EPS())
      return false;

   double effective_lookback = (
      w1 * (double)InpXMomLookback1
      + w2 * (double)InpXMomLookback2
      + w3 * (double)InpXMomLookback3
   ) / wsum;

   for(int i=0; i<g_num_symbols; ++i)
   {
      if(!IsCrossSectionallyEligibleSymbol(i))
         continue;

      int base_idx = FXRCXMomCurrencyIndex(g_base_ccy[i], currencies);
      int quote_idx = FXRCXMomCurrencyIndex(g_quote_ccy[i], currencies);
      if(base_idx < 0 || quote_idx < 0)
         continue;

      double raw = 0.0;
      if(ok1)
         raw += w1 * (scores1[base_idx] - scores1[quote_idx]);
      if(ok2)
         raw += w2 * (scores2[base_idx] - scores2[quote_idx]);
      if(ok3)
         raw += w3 * (scores3[base_idx] - scores3[quote_idx]);
      raw /= wsum;

      double scale = FXRCXMomPairVolScale(g_symbols[i], effective_lookback);
      double normalized = (InpXMomVolNormalize ? raw / (scale + EPS()) : raw);
      g_XMomScore[i] = MathTanh(Clip(normalized, -8.0, 8.0) / InpXMomTanhScale);
      g_XMomValid[i] = true;
   }

   return true;
}
