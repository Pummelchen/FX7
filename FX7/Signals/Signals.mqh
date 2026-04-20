// Calculates portfolio crowding if the candidate is added.
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

// Calculates the candidate uniqueness score against the accepted set.
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

// Computes novelty overlay.
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

// Builds correlation matrices.
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

// Updates panic gate and scores.
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

// Returns whether the managed direction should be exited.
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

// Builds trade targets and preserves the accepted-target priority order.
void BuildTradeTargets(const int &candidate_indices[],
                       int &target_dir[],
                       int &accepted_order[])
{
   ArrayResize(target_dir, g_num_symbols);
   ArrayInitialize(target_dir, 0);
   ArrayResize(accepted_order, 0);

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

   ArrayCopy(accepted_order, accepted);
}

// Returns whether the candidate clears the reversal threshold.
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

// Sorts candidate records.
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

// Builds candidate record.
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

// Builds candidate priority.
double BuildCandidatePriority(const int idx, const int dir = 0)
{
   double base_rank = MathMax(g_Rank[idx], MathAbs(g_S[idx]) * g_Conf[idx]);
   double gate_weight = 0.50 + 0.25 * Clip(g_G[idx], 0.0, 1.0) + 0.25 * Clip(DirectionalExecGate(idx, dir), 0.0, 1.0);
   double momentum_weight = 0.60 + 0.40 * MathMin(MathAbs(g_M[idx]), 1.0);
   return base_rank * gate_weight * momentum_weight;
}

// Builds signal direction.
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

// Returns whether the candidate clears the minimum gating checks.
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

// Resets candidate.
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

// Builds exit threshold.
double BuildExitThreshold(const int idx)
{
   double long_threshold = BuildExitThresholdDirectional(idx, 1);
   double short_threshold = BuildExitThresholdDirectional(idx, -1);
   return MathMax(long_threshold, short_threshold);
}

// Builds exit threshold directional.
double BuildExitThresholdDirectional(const int idx, const int dir)
{
   return InpBaseExitThreshold
        + 0.10 * InpEtaCost * DirectionalCostPenaltyTerm(idx, dir);
}

// Builds entry threshold.
double BuildEntryThreshold(const int idx)
{
   double long_threshold = BuildEntryThresholdDirectional(idx, 1);
   double short_threshold = BuildEntryThresholdDirectional(idx, -1);
   return MathMax(long_threshold, short_threshold);
}

// Builds entry threshold directional.
double BuildEntryThresholdDirectional(const int idx, const int dir)
{
   return InpBaseEntryThreshold
        + 0.20 * InpEtaCost * DirectionalCostPenaltyTerm(idx, dir)
        + 0.20 * InpEtaVol * RegimePenaltyTerm(idx)
        + 0.10 * InpEtaBreakout * (1.0 - Clip(g_BK[idx], 0.0, 1.0));
}

// Builds signal confidence.
double BuildSignalConfidence(const int idx)
{
   double signal_mag = MathMax(MathAbs(g_S[idx]), MathAbs(g_E[idx]));
   return Sigmoid(InpConfSlope * (signal_mag - InpTheta0));
}

// Builds signal core score.
double BuildSignalCoreScore(const int idx)
{
   return g_CompositeCore[idx] * g_PG[idx] * BreakoutParticipationWeight(idx);
}

// Returns the cost-penalty term for the symbol.
double CostPenaltyTerm(const int idx)
{
   return DirectionalCostPenaltyTerm(idx, 0);
}

// Returns the directional cost-penalty term for the symbol.
double DirectionalCostPenaltyTerm(const int idx, const int dir)
{
   if(idx < 0 || idx >= g_num_symbols)
      return 0.0;

   double k_value = DirectionalValue(dir, g_K_long[idx], g_K_short[idx], g_K[idx]);
   return PosPart(k_value - 1.0);
}

// Returns the directional execution gate for the symbol.
double DirectionalExecGate(const int idx, const int dir)
{
   if(idx < 0 || idx >= g_num_symbols)
      return 0.0;
   return DirectionalValue(dir, g_Q_long[idx], g_Q_short[idx], g_Q[idx]);
}

// Returns the regime-penalty term for the symbol.
double RegimePenaltyTerm(const int idx)
{
   return PosPart(g_V[idx] - 1.0);
}

// Returns the breakout participation weight for the symbol.
double BreakoutParticipationWeight(const int idx)
{
   double breakout = Clip(g_BK[idx], 0.0, 1.0);
   return 0.50 + 0.50 * MathPow(breakout, InpGammaB);
}

// Builds universe std ret.
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
