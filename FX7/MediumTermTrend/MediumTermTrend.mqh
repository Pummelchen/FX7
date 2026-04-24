//------------------------- Medium-Term Trend Layer -------------------------//

// Returns the maximum of three integer lookbacks.
int FXRCMax3Int(const int a, const int b, const int c)
{
   return MathMax(a, MathMax(b, c));
}

// Loads closed-bar closes for a medium-term trend block.
bool FXRCLoadMediumTrendCloses(const string symbol,
                               const ENUM_TIMEFRAMES timeframe,
                               const int bars_needed,
                               double &close[])
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   ResetLastError();
   int copied = CopyRates(symbol, timeframe, 0, bars_needed, rates);
   if(copied < bars_needed)
      return false;

   ArrayResize(close, copied);
   ArraySetAsSeries(close, true);
   for(int i=0; i<copied; ++i)
      close[i] = rates[i].close;

   return (close[1] > 0.0);
}

// Computes one medium-term trend block from closed bars only.
bool FXRCComputeMediumTrendBlock(const string symbol,
                                 const ENUM_TIMEFRAMES timeframe,
                                 const int lookback1,
                                 const int lookback2,
                                 const int lookback3,
                                 double &score)
{
   score = 0.0;
   int max_lookback = FXRCMax3Int(lookback1, lookback2, lookback3);
   if(max_lookback <= 1)
      return false;

   int bars_needed = max_lookback + MathMax(30, max_lookback / 2) + 5;
   double close[];
   if(!FXRCLoadMediumTrendCloses(symbol, timeframe, bars_needed, close))
      return false;

   double sigma = 1.0;
   if(InpMediumTrendVolNormalize)
   {
      int returns_count = MathMin(max_lookback + 20, ArraySize(close) - 2);
      sigma = EWMAStdFromCloses(close, returns_count, MathMax(5, returns_count / 3));
      if(sigma <= EPS())
         return false;
   }

   double weights[3] = {0.50, 0.30, 0.20};
   int lookbacks[3] = {lookback1, lookback2, lookback3};
   double total = 0.0;
   double wsum = 0.0;
   for(int i=0; i<3; ++i)
   {
      int lb = lookbacks[i];
      if(lb <= 1 || lb + 1 >= ArraySize(close) || close[lb + 1] <= 0.0)
         continue;

      double raw = MathLog(close[1] / close[lb + 1]);
      if(InpMediumTrendVolNormalize)
         raw /= (sigma * MathSqrt((double)lb) + EPS());

      total += weights[i] * MathTanh(Clip(raw, -6.0, 6.0) / InpMediumTrendTanhScale);
      wsum += weights[i];
   }

   if(wsum <= EPS())
      return false;

   score = Clip(total / wsum, -1.0, 1.0);
   return true;
}

// Computes medium-term H4/D1 trend for one symbol.
bool FXRCRefreshMediumTermTrendForSymbol(const int idx)
{
   if(idx < 0 || idx >= g_num_symbols)
      return false;

   g_MediumTrendScore[idx] = 0.0;
   g_MediumTrendValid[idx] = false;

   if(!InpUseMediumTermTrend || MathAbs(InpMediumTrendCompositeWeight) <= EPS())
      return true;

   double tf1_score = 0.0;
   double tf2_score = 0.0;
   bool tf1_ok = FXRCComputeMediumTrendBlock(
      g_symbols[idx],
      InpMediumTrendTF1,
      InpMediumTrendTF1Lookback1,
      InpMediumTrendTF1Lookback2,
      InpMediumTrendTF1Lookback3,
      tf1_score
   );
   bool tf2_ok = FXRCComputeMediumTrendBlock(
      g_symbols[idx],
      InpMediumTrendTF2,
      InpMediumTrendTF2Lookback1,
      InpMediumTrendTF2Lookback2,
      InpMediumTrendTF2Lookback3,
      tf2_score
   );

   if(!tf1_ok && !tf2_ok)
      return false;

   double w1 = (tf1_ok ? MathMax(0.0, InpMediumTrendTF1Weight) : 0.0);
   double w2 = (tf2_ok ? MathMax(0.0, InpMediumTrendTF2Weight) : 0.0);
   double wsum = w1 + w2;
   if(wsum <= EPS())
      return false;

   double score = (w1 * tf1_score + w2 * tf2_score) / wsum;
   if(tf1_ok && tf2_ok && SignD(tf1_score) != 0 && SignD(tf2_score) != 0)
   {
      if(SignD(tf1_score) != SignD(tf2_score))
      {
         double penalty = Clip(InpMediumTrendAlignmentPenalty, 0.0, 1.0);
         score *= (InpMediumTrendRequireAlignment ? penalty : MathMax(penalty, 0.75));
      }
   }

   g_MediumTrendScore[idx] = Clip(score, -1.0, 1.0);
   g_MediumTrendValid[idx] = true;
   return true;
}
