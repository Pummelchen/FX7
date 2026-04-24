//------------------------- Calibrated Probability Model -------------------------//

// Resets a probability-model decision to neutral behavior.
void FXRCResetProbabilityDecision(FXRCProbabilityDecision &decision)
{
   decision.model_available = g_probability_model_available;
   decision.allow_entry = true;
   decision.p_up = 0.5;
   decision.risk_multiplier = 1.0;
   decision.reason = "";
}

// Clears the probability model state.
void FXRCClearProbabilityModel()
{
   ArrayResize(g_probability_coefficients, 0);
   g_probability_model_loaded = false;
   g_probability_model_available = false;
   g_probability_model_reason = "";
}

// Resets per-cycle probability diagnostics without unloading model coefficients.
void FXRCResetProbabilityCycleState()
{
   if(ArraySize(g_probability_p_up) == g_num_symbols)
      ArrayInitialize(g_probability_p_up, 0.5);
   if(ArraySize(g_probability_risk_multiplier) == g_num_symbols)
      ArrayInitialize(g_probability_risk_multiplier, 1.0);

   for(int i=0; i<ArraySize(g_probability_reason); ++i)
      g_probability_reason[i] = "";
}

// Appends one probability-model coefficient.
void FXRCAppendProbabilityCoefficient(const string feature_name,
                                      const double coefficient,
                                      const bool intercept,
                                      const string optional_symbol,
                                      const string optional_base,
                                      const string optional_quote)
{
   int new_size = ArraySize(g_probability_coefficients) + 1;
   ArrayResize(g_probability_coefficients, new_size);
   int idx = new_size - 1;
   g_probability_coefficients[idx].feature_name = feature_name;
   g_probability_coefficients[idx].coefficient = coefficient;
   g_probability_coefficients[idx].intercept = intercept;
   g_probability_coefficients[idx].optional_symbol = NormalizedSymbolName(optional_symbol);
   g_probability_coefficients[idx].optional_base_currency = NormalizeCurrencyCode(optional_base);
   g_probability_coefficients[idx].optional_quote_currency = NormalizeCurrencyCode(optional_quote);
}

// Returns whether a coefficient row applies to the symbol.
bool FXRCProbabilityCoefficientApplies(const FXRCProbabilityCoefficient &coef,
                                       const int idx)
{
   if(idx < 0 || idx >= g_num_symbols)
      return false;

   if(StringLen(coef.optional_symbol) > 0
      && coef.optional_symbol != NormalizedSymbolName(g_symbols[idx]))
   {
      return false;
   }

   if(StringLen(coef.optional_base_currency) > 0
      && coef.optional_base_currency != NormalizeCurrencyCode(g_base_ccy[idx]))
   {
      return false;
   }

   if(StringLen(coef.optional_quote_currency) > 0
      && coef.optional_quote_currency != NormalizeCurrencyCode(g_quote_ccy[idx]))
   {
      return false;
   }

   return true;
}

// Loads probability model coefficients from common terminal storage.
bool FXRCLoadProbabilityModel(const bool force_log)
{
   FXRCClearProbabilityModel();
   if(!InpUseProbabilityModel)
      return true;

   ResetLastError();
   int handle = FileOpen(InpProbabilityModelFile, FILE_READ | FILE_CSV | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
   {
      g_probability_model_loaded = true;
      g_probability_model_reason = StringFormat(
         "probability model file unavailable: %s err=%d",
         InpProbabilityModelFile,
         GetLastError()
      );
      if(force_log)
         Print(g_probability_model_reason);
      return false;
   }

   int rows = 0;
   int ignored = 0;
   while(!FileIsEnding(handle))
   {
      string model_version = FileReadString(handle);
      if(FileIsEnding(handle) && StringLen(model_version) == 0)
         break;

      string horizon_text = FileReadString(handle);
      string feature_name = FileReadString(handle);
      string coefficient_text = FileReadString(handle);
      string intercept_text = FileReadString(handle);
      string optional_symbol = FileReadString(handle);
      string optional_base = FileReadString(handle);
      string optional_quote = FileReadString(handle);

      if(model_version == "model_version")
         continue;

      int horizon = (int)StringToInteger(horizon_text);
      if(horizon != InpProbabilityHorizonDays)
         continue;

      double coefficient = StringToDouble(coefficient_text);
      bool intercept = ((int)StringToInteger(intercept_text) != 0);
      if(StringLen(feature_name) == 0 && !intercept)
      {
         ignored++;
         continue;
      }

      FXRCAppendProbabilityCoefficient(
         feature_name,
         coefficient,
         intercept,
         optional_symbol,
         optional_base,
         optional_quote
      );
      rows++;
   }

   FileClose(handle);
   g_probability_model_loaded = true;
   g_probability_model_available = (rows > 0);
   if(!g_probability_model_available)
      g_probability_model_reason = "probability model has no usable coefficient rows";
   else
      g_probability_model_reason = "";

   if(force_log)
   {
      PrintFormat(
         "FXRC probability model load: available=%s rows=%d ignored=%d file=%s",
         (g_probability_model_available ? "true" : "false"),
         rows,
         ignored,
         InpProbabilityModelFile
      );
   }

   return g_probability_model_available;
}

// Ensures the probability model has been loaded once.
bool FXRCEnsureProbabilityModelLoaded()
{
   if(!InpUseProbabilityModel)
      return true;
   if(g_probability_model_loaded)
      return g_probability_model_available;

   return FXRCLoadProbabilityModel(true);
}

// Returns a probability-model feature value by name.
bool FXRCProbabilityFeatureValue(const int idx,
                                 const int dir,
                                 const string feature_name,
                                 double &value)
{
   value = 0.0;
   if(idx < 0 || idx >= g_num_symbols)
      return false;

   if(feature_name == "momentum_score")
      value = g_M[idx];
   else if(feature_name == "carry_score")
      value = g_Carry[idx];
   else if(feature_name == "value_score")
      value = g_Value[idx];
   else if(feature_name == "xmom_score")
      value = (g_XMomValid[idx] ? g_XMomScore[idx] : 0.0);
   else if(feature_name == "medium_trend_score")
      value = (g_MediumTrendValid[idx] ? g_MediumTrendScore[idx] : 0.0);
   else if(feature_name == "realized_vol")
      value = g_sigma_long[idx];
   else if(feature_name == "vol_ratio")
      value = g_V[idx];
   else if(feature_name == "breakout_score_or_participation")
      value = g_BK[idx];
   else if(feature_name == "efficiency_ratio")
      value = g_ER[idx];
   else if(feature_name == "reversal_penalty")
      value = g_D[idx];
   else if(feature_name == "panic_gate_value")
      value = g_PG[idx];
   else if(feature_name == "cost_long")
      value = g_K_long[idx];
   else if(feature_name == "cost_short")
      value = g_K_short[idx];
   else if(feature_name == "composite_raw")
      value = g_CompositeCore[idx];
   else
      return false;

   return (value == value);
}

// Computes calibrated P(UP) for the symbol from loaded coefficients.
bool FXRCComputeProbabilityUp(const int idx,
                              const int dir,
                              double &p_up,
                              string &reason)
{
   p_up = 0.5;
   reason = "";
   if(!InpUseProbabilityModel)
      return true;
   if(!FXRCEnsureProbabilityModelLoaded())
   {
      reason = g_probability_model_reason;
      return false;
   }

   double logit = 0.0;
   int used = 0;
   for(int i=0; i<ArraySize(g_probability_coefficients); ++i)
   {
      if(!FXRCProbabilityCoefficientApplies(g_probability_coefficients[i], idx))
         continue;

      if(g_probability_coefficients[i].intercept)
      {
         logit += g_probability_coefficients[i].coefficient;
         used++;
         continue;
      }

      double feature_value = 0.0;
      if(!FXRCProbabilityFeatureValue(
         idx,
         dir,
         g_probability_coefficients[i].feature_name,
         feature_value))
      {
         continue;
      }

      logit += g_probability_coefficients[i].coefficient * feature_value;
      used++;
   }

   if(used <= 0)
   {
      reason = "probability model has no applicable coefficients";
      return false;
   }

   p_up = Sigmoid(Clip(logit, -30.0, 30.0));
   return true;
}

// Evaluates probability filter and risk scaler for an already-qualified candidate.
bool FXRCEvaluateProbabilityDecision(const int idx,
                                     const int dir,
                                     FXRCProbabilityDecision &decision)
{
   FXRCResetProbabilityDecision(decision);
   if(!InpUseProbabilityModel)
      return true;

   double p_up = 0.5;
   string reason = "";
   if(!FXRCComputeProbabilityUp(idx, dir, p_up, reason))
   {
      decision.model_available = false;
      decision.reason = reason;
      return false;
   }

   decision.model_available = true;
   decision.p_up = p_up;

   if(InpProbabilityBlockContradiction)
   {
      if((dir > 0 && p_up < 0.5) || (dir < 0 && p_up > 0.5))
      {
         decision.allow_entry = false;
         decision.reason = StringFormat("probability contradiction p_up=%.3f", p_up);
      }
   }

   if(decision.allow_entry && InpProbabilityUseAsFilter)
   {
      if(dir > 0 && p_up < 0.5 + InpProbabilityMinEdge)
      {
         decision.allow_entry = false;
         decision.reason = StringFormat("buy probability edge too small p_up=%.3f", p_up);
      }
      if(dir < 0 && p_up > 0.5 - InpProbabilityMinEdge)
      {
         decision.allow_entry = false;
         decision.reason = StringFormat("sell probability edge too small p_up=%.3f", p_up);
      }
   }

   if(InpProbabilityUseAsRiskScaler)
   {
      double edge = MathAbs(p_up - 0.5);
      double edge_unit = Clip(edge / MathMax(InpProbabilityMinEdge, 0.01), 0.0, 1.0);
      decision.risk_multiplier = InpProbabilityMinRiskScale
                               + edge_unit * (InpProbabilityMaxRiskScale - InpProbabilityMinRiskScale);
      decision.risk_multiplier = Clip(
         decision.risk_multiplier,
         InpProbabilityMinRiskScale,
         InpProbabilityMaxRiskScale
      );
   }

   return true;
}

// Applies the probability model to an already-qualified candidate.
bool FXRCApplyProbabilityModelToCandidate(FXRCCandidate &candidate)
{
   if(!InpUseProbabilityModel)
      return true;

   FXRCProbabilityDecision decision;
   if(!FXRCEvaluateProbabilityDecision(candidate.symbol_idx, candidate.dir, decision))
   {
      if(StringLen(decision.reason) > 0)
         PrintFormat("Probability model disabled for this cycle: %s", decision.reason);
      return true;
   }

   int idx = candidate.symbol_idx;
   g_probability_p_up[idx] = decision.p_up;
   g_probability_risk_multiplier[idx] = decision.risk_multiplier;
   g_probability_reason[idx] = decision.reason;

   if(!decision.allow_entry)
   {
      PrintFormat(
         "Skipping %s %s because probability model blocked entry: %s.",
         g_symbols[idx],
         (candidate.dir > 0 ? "long" : "short"),
         decision.reason
      );
      return false;
   }

   return true;
}

// Returns the probability-model risk multiplier for trade planning.
double FXRCProbabilityRiskMultiplierForEntry(const int symbol_idx,
                                             const int dir)
{
   if(!InpUseProbabilityModel || !InpProbabilityUseAsRiskScaler)
      return 1.0;
   if(symbol_idx < 0 || symbol_idx >= ArraySize(g_probability_risk_multiplier))
      return 1.0;

   if(g_probability_p_up[symbol_idx] <= 0.0)
   {
      FXRCProbabilityDecision decision;
      if(FXRCEvaluateProbabilityDecision(symbol_idx, dir, decision))
         return decision.risk_multiplier;
      return 1.0;
   }

   return Clip(
      g_probability_risk_multiplier[symbol_idx],
      InpProbabilityMinRiskScale,
      InpProbabilityMaxRiskScale
   );
}
