//------------------------- Filtered Regime State Layer -------------------------//

// Applies a stable three-way softmax to transparent regime scores.
void FXRCRegimeSoftmax(const double trend_score,
                       const double choppy_score,
                       const double stress_score,
                       double &p_trend,
                       double &p_choppy,
                       double &p_stress)
{
   double m = MathMax(trend_score, MathMax(choppy_score, stress_score));
   double et = MathExp(trend_score - m);
   double ec = MathExp(choppy_score - m);
   double es = MathExp(stress_score - m);
   double sum = MathMax(et + ec + es, EPS());
   p_trend = et / sum;
   p_choppy = ec / sum;
   p_stress = es / sum;
}

// Computes filtered regime probabilities from current-information features only.
void FXRCRefreshRegimeStateForSymbol(const int idx)
{
   if(idx < 0 || idx >= g_num_symbols)
      return;

   if(!InpUseRegimeStateFilter)
   {
      g_RegimePTrend[idx] = 0.0;
      g_RegimePChoppy[idx] = 0.0;
      g_RegimePStress[idx] = 0.0;
      return;
   }

   double vol_pressure = Clip(PosPart(g_V[idx] - 1.0), 0.0, 3.0);
   double trend_quality = Clip(0.50 * g_ER[idx] + 0.50 * g_A[idx], 0.0, 1.0);
   double breakout = Clip(g_BK[idx], 0.0, 1.0);
   double panic_pressure = 1.0 - Clip(g_PG[idx], 0.0, 1.0);
   double reversal = Clip(g_D[idx], 0.0, 3.0);

   double trend_score = 1.20 * trend_quality + 0.60 * breakout - 0.80 * vol_pressure;
   double choppy_score = 1.00 * (1.0 - trend_quality) + 0.35 * reversal;
   double stress_score = 1.40 * panic_pressure + 0.85 * vol_pressure + 0.35 * reversal;

   FXRCRegimeSoftmax(
      trend_score,
      choppy_score,
      stress_score,
      g_RegimePTrend[idx],
      g_RegimePChoppy[idx],
      g_RegimePStress[idx]
   );
}

// Refreshes filtered regime probabilities for all symbols in the current cycle.
void FXRCRefreshRegimeStateForCycle()
{
   for(int i=0; i<g_num_symbols; ++i)
      FXRCRefreshRegimeStateForSymbol(i);
}

// Returns whether the regime filter blocks new entries.
bool FXRCRegimeStateBlocksEntry(const int idx)
{
   if(!InpUseRegimeStateFilter || InpRegimeStateUseAsFeatureOnly)
      return false;
   if(idx < 0 || idx >= g_num_symbols)
      return false;

   return (g_RegimePStress[idx] >= InpRegimeStressBlockThreshold);
}

// Returns the carry multiplier implied by the filtered regime state.
double FXRCRegimeCarryMultiplier(const int idx)
{
   if(!InpUseRegimeStateFilter
      || InpRegimeStateUseAsFeatureOnly
      || !InpRegimeStateGateCarry)
   {
      return 1.0;
   }

   double penalty = Clip(InpRegimeCarryStressPenalty, 0.0, 1.0);
   return Clip(1.0 - g_RegimePStress[idx] * (1.0 - penalty), 0.0, 1.0);
}

// Returns the trend multiplier implied by the filtered regime state.
double FXRCRegimeTrendMultiplier(const int idx)
{
   if(!InpUseRegimeStateFilter
      || InpRegimeStateUseAsFeatureOnly
      || !InpRegimeStateGateTrend)
   {
      return 1.0;
   }

   double penalty = Clip(InpRegimeTrendChopPenalty, 0.0, 1.0);
   return Clip(1.0 - g_RegimePChoppy[idx] * (1.0 - penalty), 0.0, 1.0);
}

// Returns the cross-sectional momentum multiplier implied by regime state.
double FXRCRegimeXMomMultiplier(const int idx)
{
   if(!InpUseRegimeStateFilter
      || InpRegimeStateUseAsFeatureOnly
      || !InpRegimeStateGateXMom)
   {
      return 1.0;
   }

   double penalty = Clip(InpRegimeTrendChopPenalty, 0.0, 1.0);
   return Clip(1.0 - g_RegimePChoppy[idx] * (1.0 - penalty), 0.0, 1.0);
}
