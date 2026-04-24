//------------------------- Adaptive Startup Tuning -------------------------//

// Normalizes three non-negative sleeve weights in place.
void FXRCAdaptiveNormalizeWeights(double &w_m, double &w_c, double &w_v)
{
   w_m = MathMax(0.0, w_m);
   w_c = MathMax(0.0, w_c);
   w_v = MathMax(0.0, w_v);

   double total = w_m + w_c + w_v;
   if(total <= EPS())
   {
      w_m = 1.0;
      w_c = 0.0;
      w_v = 0.0;
      return;
   }

   w_m /= total;
   w_c /= total;
   w_v /= total;
}

// Returns the default target trade rate for a strategy profile.
double FXRCAdaptiveProfileDefaultTradesPerDay()
{
   switch(InpStrategyProfile)
   {
      case FXRC_PROFILE_CONSERVATIVE:
         return 1.0;
      case FXRC_PROFILE_BALANCED:
         return 3.0;
      case FXRC_PROFILE_ACTIVE:
         return 6.0;
      case FXRC_PROFILE_RESEARCH:
         return 10.0;
   }

   return 3.0;
}

// Returns the profile-level threshold multiplier before data refinement.
double FXRCAdaptiveProfileEntryThresholdMultiplier()
{
   switch(InpStrategyProfile)
   {
      case FXRC_PROFILE_CONSERVATIVE:
         return 1.0;
      case FXRC_PROFILE_BALANCED:
         return 0.75;
      case FXRC_PROFILE_ACTIVE:
         return 0.50;
      case FXRC_PROFILE_RESEARCH:
         return 0.25;
   }

   return 0.75;
}

// Returns the profile-level exit threshold multiplier.
double FXRCAdaptiveProfileExitThresholdMultiplier()
{
   switch(InpStrategyProfile)
   {
      case FXRC_PROFILE_CONSERVATIVE:
         return 1.0;
      case FXRC_PROFILE_BALANCED:
         return 1.15;
      case FXRC_PROFILE_ACTIVE:
         return 1.35;
      case FXRC_PROFILE_RESEARCH:
         return 1.60;
   }

   return 1.15;
}

// Returns the profile-level reversal threshold multiplier.
double FXRCAdaptiveProfileReversalThresholdMultiplier()
{
   switch(InpStrategyProfile)
   {
      case FXRC_PROFILE_CONSERVATIVE:
         return 1.0;
      case FXRC_PROFILE_BALANCED:
         return 0.85;
      case FXRC_PROFILE_ACTIVE:
         return 0.70;
      case FXRC_PROFILE_RESEARCH:
         return 0.50;
   }

   return 0.85;
}

// Returns the profile-level confidence floor.
double FXRCAdaptiveProfileConfidenceFloor()
{
   switch(InpStrategyProfile)
   {
      case FXRC_PROFILE_CONSERVATIVE:
         return 0.30;
      case FXRC_PROFILE_BALANCED:
         return 0.20;
      case FXRC_PROFILE_ACTIVE:
         return 0.12;
      case FXRC_PROFILE_RESEARCH:
         return 0.05;
   }

   return 0.20;
}

// Returns the profile-level candidate buffer used to convert desired trades into candidate supply.
double FXRCAdaptiveProfileCandidateBuffer()
{
   switch(InpStrategyProfile)
   {
      case FXRC_PROFILE_CONSERVATIVE:
         return 2.0;
      case FXRC_PROFILE_BALANCED:
         return 4.0;
      case FXRC_PROFILE_ACTIVE:
         return 8.0;
      case FXRC_PROFILE_RESEARCH:
         return 12.0;
   }

   return 4.0;
}

// Returns profile sleeve weights before dynamic allocator adjustments.
void FXRCAdaptiveProfileWeights(double &w_m, double &w_c, double &w_v)
{
   switch(InpStrategyProfile)
   {
      case FXRC_PROFILE_CONSERVATIVE:
      {
         w_m = InpWeightMomentum;
         w_c = InpWeightCarry;
         w_v = InpWeightValue;
         break;
      }
      case FXRC_PROFILE_BALANCED:
      {
         w_m = 0.80;
         w_c = 0.10;
         w_v = 0.10;
         break;
      }
      case FXRC_PROFILE_ACTIVE:
      {
         w_m = 1.0;
         w_c = 0.0;
         w_v = 0.0;
         break;
      }
      case FXRC_PROFILE_RESEARCH:
      {
         w_m = 1.0;
         w_c = 0.0;
         w_v = 0.0;
         break;
      }
      default:
      {
         w_m = InpWeightMomentum;
         w_c = InpWeightCarry;
         w_v = InpWeightValue;
         break;
      }
   }

   FXRCAdaptiveNormalizeWeights(w_m, w_c, w_v);
}

// Resets adaptive calibration state to static input behavior.
void FXRCResetAdaptiveCalibrationState()
{
   g_adaptive_calibration.attempted = false;
   g_adaptive_calibration.applied = false;
   g_adaptive_calibration.sample_count = 0;
   g_adaptive_calibration.tradable_symbols = 0;
   g_adaptive_calibration.target_trades_per_day = 0.0;
   g_adaptive_calibration.learned_abs_score_threshold = 0.0;
   g_adaptive_calibration.entry_threshold_multiplier = 1.0;
   g_adaptive_calibration.exit_threshold_multiplier = 1.0;
   g_adaptive_calibration.reversal_threshold_multiplier = 1.0;
   g_adaptive_calibration.min_confidence_floor = InpMinConfidence;
   g_adaptive_calibration.weight_momentum = InpWeightMomentum;
   g_adaptive_calibration.weight_carry = InpWeightCarry;
   g_adaptive_calibration.weight_value = InpWeightValue;
   g_adaptive_calibration.reason = "";

   FXRCAdaptiveNormalizeWeights(
      g_adaptive_calibration.weight_momentum,
      g_adaptive_calibration.weight_carry,
      g_adaptive_calibration.weight_value
   );
}

// Applies bounded profile defaults before historical sample refinement.
void FXRCApplyAdaptiveProfileDefaults()
{
   FXRCResetAdaptiveCalibrationState();
   g_adaptive_calibration.attempted = true;
   g_adaptive_calibration.applied = true;
   g_adaptive_calibration.target_trades_per_day = (
      InpTargetTradesPerDay > EPS()
      ? InpTargetTradesPerDay
      : FXRCAdaptiveProfileDefaultTradesPerDay()
   );
   g_adaptive_calibration.entry_threshold_multiplier = Clip(
      FXRCAdaptiveProfileEntryThresholdMultiplier(),
      InpCalibrationMinEntryThresholdMultiplier,
      InpCalibrationMaxEntryThresholdMultiplier
   );
   g_adaptive_calibration.exit_threshold_multiplier = FXRCAdaptiveProfileExitThresholdMultiplier();
   g_adaptive_calibration.reversal_threshold_multiplier = FXRCAdaptiveProfileReversalThresholdMultiplier();
   g_adaptive_calibration.min_confidence_floor = Clip(
      MathMin(InpMinConfidence, FXRCAdaptiveProfileConfidenceFloor()),
      InpCalibrationMinConfidenceFloor,
      InpCalibrationMaxConfidenceFloor
   );
   FXRCAdaptiveProfileWeights(
      g_adaptive_calibration.weight_momentum,
      g_adaptive_calibration.weight_carry,
      g_adaptive_calibration.weight_value
   );
   g_adaptive_calibration.reason = "profile defaults";
}

// Returns the number of signal cycles per calendar day.
double FXRCAdaptiveSignalCyclesPerDay()
{
   int seconds = PeriodSeconds(InpSignalTF);
   if(seconds <= 0)
      return 24.0;

   return MathMax(1.0, 86400.0 / (double)seconds);
}

// Returns the number of symbols allowed by the tradable-symbol filter.
int FXRCAdaptiveTradableSymbolCount()
{
   int count = 0;
   for(int i=0; i<g_num_symbols; ++i)
   {
      if(ArraySize(g_trade_allowed) == g_num_symbols && !g_trade_allowed[i])
         continue;
      count++;
   }

   return MathMax(count, 1);
}

// Sorts a local double array in ascending order.
void FXRCAdaptiveSortDoubles(double &values[])
{
   ArraySort(values);
}

// Returns a percentile from a sorted double array.
double FXRCAdaptivePercentile(const double &sorted_values[], const double percentile)
{
   int count = ArraySize(sorted_values);
   if(count <= 0)
      return 0.0;

   double clipped = Clip(percentile, 0.0, 1.0);
   int idx = (int)MathFloor(clipped * (double)(count - 1));
   idx = (int)Clip((double)idx, 0.0, (double)(count - 1));
   return sorted_values[idx];
}

// Computes an EWMA return standard deviation at a historical decision shift.
double FXRCAdaptiveEWMAStdAtShift(const double &close[],
                                  const int shift,
                                  const int returns_count,
                                  const int half_life)
{
   int available = ArraySize(close) - shift - 1;
   int count = MathMin(returns_count, available);
   if(shift < 1 || count <= 1)
      return 0.0;

   double lambda = MathExp(-MathLog(2.0) / MathMax(1.0, (double)half_life));
   double var = 0.0;
   bool seeded = false;

   for(int lag=shift + count - 1; lag>=shift; --lag)
   {
      if(close[lag] <= 0.0 || close[lag + 1] <= 0.0)
         continue;

      double r = MathLog(close[lag] / close[lag + 1]);
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

   return (seeded ? MathSqrt(MathMax(var, EPS())) : 0.0);
}

// Returns the highest close in an inclusive historical shift range.
double FXRCAdaptiveHighestClose(const double &close[],
                                const int first_shift,
                                const int last_shift)
{
   double highest = -1.0e100;
   int n = ArraySize(close);
   for(int shift=first_shift; shift<=last_shift && shift<n; ++shift)
   {
      if(close[shift] > highest)
         highest = close[shift];
   }

   return highest;
}

// Returns the lowest close in an inclusive historical shift range.
double FXRCAdaptiveLowestClose(const double &close[],
                               const int first_shift,
                               const int last_shift)
{
   double lowest = 1.0e100;
   int n = ArraySize(close);
   for(int shift=first_shift; shift<=last_shift && shift<n; ++shift)
   {
      if(close[shift] < lowest)
         lowest = close[shift];
   }

   return lowest;
}

// Appends one calibration sample using chunked array growth.
void FXRCAdaptiveAppendOpportunitySample(double &abs_scores[],
                                         double &confidences[],
                                         int &sample_count,
                                         int &capacity,
                                         const double abs_score,
                                         const double confidence)
{
   if(sample_count >= capacity)
   {
      capacity += 1024;
      ArrayResize(abs_scores, capacity);
      ArrayResize(confidences, capacity);
   }

   abs_scores[sample_count] = abs_score;
   confidences[sample_count] = confidence;
   sample_count++;
}

// Computes the closed-bar momentum score used for startup opportunity calibration.
bool FXRCAdaptiveScoreAtShift(const double &close[],
                              const int shift,
                              double &abs_score,
                              double &confidence)
{
   abs_score = 0.0;
   confidence = 0.0;

   int max_lookback = MathMax(
      InpH3,
      MathMax(InpERWindow, MathMax(InpBreakoutWindow, InpShortReversalWindow))
   );
   int n = ArraySize(close);
   if(shift < 1 || shift + max_lookback + 1 >= n)
      return false;
   if(close[shift] <= 0.0
      || close[shift + InpH1] <= 0.0
      || close[shift + InpH2] <= 0.0
      || close[shift + InpH3] <= 0.0
      || close[shift + InpERWindow] <= 0.0
      || close[shift + InpShortReversalWindow] <= 0.0)
   {
      return false;
   }

   int vol_count = MathMin(g_ret_hist_len, n - shift - 1);
   double sigma_short = FXRCAdaptiveEWMAStdAtShift(
      close,
      shift,
      vol_count,
      InpVolShortHalfLife
   );
   double sigma_long = FXRCAdaptiveEWMAStdAtShift(
      close,
      shift,
      vol_count,
      InpVolLongHalfLife
   );
   if(sigma_long <= EPS())
      return false;

   double z1 = MathLog(close[shift] / close[shift + InpH1])
             / (sigma_long * MathSqrt((double)InpH1) + EPS());
   double z2 = MathLog(close[shift] / close[shift + InpH2])
             / (sigma_long * MathSqrt((double)InpH2) + EPS());
   double z3 = MathLog(close[shift] / close[shift + InpH3])
             / (sigma_long * MathSqrt((double)InpH3) + EPS());
   z1 = Clip(z1, -6.0, 6.0);
   z2 = Clip(z2, -6.0, 6.0);
   z3 = Clip(z3, -6.0, 6.0);

   double m = g_w1 * MathTanh(z1 / InpTanhScale)
            + g_w2 * MathTanh(z2 / InpTanhScale)
            + g_w3 * MathTanh(z3 / InpTanhScale);
   double a = MathAbs(g_w1 * (double)SignD(z1)
                    + g_w2 * (double)SignD(z2)
                    + g_w3 * (double)SignD(z3));

   double net_move = MathAbs(MathLog(close[shift] / close[shift + InpERWindow]));
   double path_sum = 0.0;
   for(int sh=shift; sh<shift + InpERWindow; ++sh)
   {
      if(close[sh] <= 0.0 || close[sh + 1] <= 0.0)
         return false;
      path_sum += MathAbs(MathLog(close[sh] / close[sh + 1]));
   }
   double er = net_move / (path_sum + EPS());

   double v = sigma_short / (sigma_long + EPS());
   double zrev = MathLog(close[shift] / close[shift + InpShortReversalWindow])
               / (sigma_long * MathSqrt((double)InpShortReversalWindow) + EPS());
   zrev = Clip(zrev, -6.0, 6.0);
   double d = MathMax(0.0, -(double)SignD(m) * zrev);
   double gate = MathPow(MathMax(a, 0.0), InpGammaA)
               * MathPow(MathMax(er, 0.0), InpGammaER)
               * MathExp(-InpGammaV * PosPart(v - InpV0))
               * MathExp(-InpGammaD * d * PosPart(v - InpV0));
   if(gate < InpMinRegimeGate)
      return false;

   double hh = FXRCAdaptiveHighestClose(close, shift + 1, shift + InpBreakoutWindow);
   double ll = FXRCAdaptiveLowestClose(close, shift + 1, shift + InpBreakoutWindow);
   if(hh <= -5.0e99 || ll >= 5.0e99)
      return false;

   double mid = 0.5 * (hh + ll);
   double half_range = 0.5 * MathMax(hh - ll, EPS());
   double bk = 0.5 * (1.0 + MathTanh(((double)SignD(m) * (close[shift] - mid)) / half_range));
   double breakout_weight = 0.50 + 0.50 * MathPow(Clip(bk, 0.0, 1.0), InpGammaB);
   double score = m * breakout_weight;
   abs_score = MathAbs(score);
   confidence = Sigmoid(InpConfSlope * (abs_score - InpTheta0));
   return (abs_score == abs_score && confidence == confidence);
}

// Collects historical closed-bar opportunity samples across the tradable universe.
int FXRCAdaptiveCollectOpportunitySamples(double &abs_scores[], double &confidences[])
{
   ArrayResize(abs_scores, 0);
   ArrayResize(confidences, 0);
   int sample_count = 0;
   int capacity = 0;

   int seconds = PeriodSeconds(InpSignalTF);
   int bars_per_day = (seconds > 0 ? (int)MathCeil(86400.0 / (double)seconds) : 24);
   int lookback_bars = MathMax(1, InpCalibrationLookbackDays) * bars_per_day;
   int max_lookback = MathMax(
      InpH3,
      MathMax(InpERWindow, MathMax(InpBreakoutWindow, InpShortReversalWindow))
   );
   int bars_needed = lookback_bars + max_lookback + g_ret_hist_len + 5;

   for(int i=0; i<g_num_symbols; ++i)
   {
      if(ArraySize(g_trade_allowed) == g_num_symbols && !g_trade_allowed[i])
         continue;
      if(IsStopped())
         break;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      ResetLastError();
      int copied = CopyRates(g_symbols[i], InpSignalTF, 0, bars_needed, rates);
      if(copied < max_lookback + g_ret_hist_len + 10)
         continue;

      double close[];
      ArrayResize(close, copied);
      ArraySetAsSeries(close, true);
      for(int k=0; k<copied; ++k)
         close[k] = rates[k].close;

      int max_shift = MathMin(lookback_bars, copied - max_lookback - g_ret_hist_len - 2);
      for(int shift=1; shift<=max_shift; ++shift)
      {
         double abs_score = 0.0;
         double confidence = 0.0;
         if(!FXRCAdaptiveScoreAtShift(close, shift, abs_score, confidence))
            continue;

         FXRCAdaptiveAppendOpportunitySample(
            abs_scores,
            confidences,
            sample_count,
            capacity,
            abs_score,
            confidence
         );
      }
   }

   ArrayResize(abs_scores, sample_count);
   ArrayResize(confidences, sample_count);
   return sample_count;
}

// Refines entry threshold and confidence floor from historical opportunity samples.
void FXRCAdaptiveRefineFromSamples(const double &abs_scores[], const double &confidences[])
{
   int sample_count = ArraySize(abs_scores);
   if(sample_count <= 0)
      return;

   double sorted_scores[];
   ArrayResize(sorted_scores, sample_count);
   ArrayCopy(sorted_scores, abs_scores, 0, 0, sample_count);
   FXRCAdaptiveSortDoubles(sorted_scores);

   double cycles_per_day = FXRCAdaptiveSignalCyclesPerDay();
   double tradable = (double)MathMax(1, g_adaptive_calibration.tradable_symbols);
   double target_supply = g_adaptive_calibration.target_trades_per_day
                        * FXRCAdaptiveProfileCandidateBuffer();
   double desired_fraction = Clip(target_supply / (cycles_per_day * tradable), 0.001, 0.60);
   double learned_threshold = FXRCAdaptivePercentile(sorted_scores, 1.0 - desired_fraction);
   double static_threshold = MathMax(InpBaseEntryThreshold, EPS());
   double learned_multiplier = learned_threshold / static_threshold;
   double profile_multiplier = g_adaptive_calibration.entry_threshold_multiplier;
   g_adaptive_calibration.learned_abs_score_threshold = learned_threshold;
   g_adaptive_calibration.entry_threshold_multiplier = Clip(
      MathMin(profile_multiplier, learned_multiplier),
      InpCalibrationMinEntryThresholdMultiplier,
      InpCalibrationMaxEntryThresholdMultiplier
   );

   double selected_confidences[];
   ArrayResize(selected_confidences, 0);
   for(int i=0; i<sample_count; ++i)
   {
      if(abs_scores[i] + EPS() < learned_threshold)
         continue;

      int new_size = ArraySize(selected_confidences) + 1;
      ArrayResize(selected_confidences, new_size);
      selected_confidences[new_size - 1] = confidences[i];
   }

   if(ArraySize(selected_confidences) > 0)
   {
      FXRCAdaptiveSortDoubles(selected_confidences);
      double learned_conf = FXRCAdaptivePercentile(selected_confidences, 0.20);
      g_adaptive_calibration.min_confidence_floor = Clip(
         MathMin(g_adaptive_calibration.min_confidence_floor, learned_conf),
         InpCalibrationMinConfidenceFloor,
         InpCalibrationMaxConfidenceFloor
      );
   }
}

// Runs startup calibration using only closed historical bars.
void FXRCRunAdaptiveStartupCalibration()
{
   FXRCResetAdaptiveCalibrationState();
   if(!InpUseStartupAutoCalibration)
   {
      Print("FXRC startup auto-calibration disabled; using static model inputs.");
      return;
   }

   FXRCApplyAdaptiveProfileDefaults();
   g_adaptive_calibration.tradable_symbols = FXRCAdaptiveTradableSymbolCount();

   double abs_scores[];
   double confidences[];
   int sample_count = FXRCAdaptiveCollectOpportunitySamples(abs_scores, confidences);
   g_adaptive_calibration.sample_count = sample_count;

   if(sample_count >= InpCalibrationMinSamples)
   {
      FXRCAdaptiveRefineFromSamples(abs_scores, confidences);
      g_adaptive_calibration.reason = "closed-bar opportunity calibration";
   }
   else
   {
      g_adaptive_calibration.reason = "profile defaults; insufficient calibration samples";
   }

   PrintFormat(
      "FXRC startup auto-calibration applied: profile=%s target_trades_day=%.2f "
      + "samples=%d entry_mult=%.2f exit_mult=%.2f reversal_mult=%.2f "
      + "conf_floor=%.2f weights[M/C/V]=%.2f/%.2f/%.2f reason=%s",
      EnumToString(InpStrategyProfile),
      g_adaptive_calibration.target_trades_per_day,
      g_adaptive_calibration.sample_count,
      g_adaptive_calibration.entry_threshold_multiplier,
      g_adaptive_calibration.exit_threshold_multiplier,
      g_adaptive_calibration.reversal_threshold_multiplier,
      g_adaptive_calibration.min_confidence_floor,
      g_adaptive_calibration.weight_momentum,
      g_adaptive_calibration.weight_carry,
      g_adaptive_calibration.weight_value,
      g_adaptive_calibration.reason
   );

   if(InpMaxAccountOrders < (int)MathCeil(g_adaptive_calibration.target_trades_per_day))
   {
      PrintFormat(
         "FXRC startup auto-calibration note: InpMaxAccountOrders=%d may cap "
         + "realized trade frequency below target %.2f trades/day.",
         InpMaxAccountOrders,
         g_adaptive_calibration.target_trades_per_day
      );
   }
}

// Returns the effective momentum sleeve weight.
double FXRCAdaptiveMomentumWeight()
{
   return (
      g_adaptive_calibration.applied
      ? g_adaptive_calibration.weight_momentum
      : InpWeightMomentum
   );
}

// Returns the effective carry sleeve weight.
double FXRCAdaptiveCarryWeight()
{
   return (
      g_adaptive_calibration.applied
      ? g_adaptive_calibration.weight_carry
      : InpWeightCarry
   );
}

// Returns the effective value sleeve weight.
double FXRCAdaptiveValueWeight()
{
   return (
      g_adaptive_calibration.applied
      ? g_adaptive_calibration.weight_value
      : InpWeightValue
   );
}

// Returns the effective entry-threshold multiplier.
double FXRCAdaptiveEntryThresholdMultiplier()
{
   return (
      g_adaptive_calibration.applied
      ? g_adaptive_calibration.entry_threshold_multiplier
      : 1.0
   );
}

// Returns the effective exit-threshold multiplier.
double FXRCAdaptiveExitThresholdMultiplier()
{
   return (
      g_adaptive_calibration.applied
      ? g_adaptive_calibration.exit_threshold_multiplier
      : 1.0
   );
}

// Returns the effective reversal-threshold multiplier.
double FXRCAdaptiveReversalThresholdMultiplier()
{
   return (
      g_adaptive_calibration.applied
      ? g_adaptive_calibration.reversal_threshold_multiplier
      : 1.0
   );
}

// Returns the effective minimum confidence floor.
double FXRCAdaptiveMinConfidenceFloor()
{
   return (
      g_adaptive_calibration.applied
      ? g_adaptive_calibration.min_confidence_floor
      : InpMinConfidence
   );
}
