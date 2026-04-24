//------------------------- Meta Allocation Overlay -------------------------//

// Resets a meta-allocation decision to neutral behavior.
void FXRCResetMetaDecision(FXRCMetaDecision &decision)
{
   decision.allow_entry = true;
   decision.risk_multiplier = 1.0;
   decision.priority_multiplier = 1.0;
   decision.momentum_multiplier = 1.0;
   decision.carry_multiplier = 1.0;
   decision.value_multiplier = 1.0;
   decision.context_key = "";
   decision.reason = "";
}

// Initializes meta-allocation runtime state.
void FXRCInitMetaAllocatorState()
{
   ArrayResize(g_meta_stats, 0);
   ArrayResize(g_meta_open_contexts, 0);
   ArrayResize(g_meta_entry_risk_multiplier, g_num_symbols);
   ArrayResize(g_meta_entry_priority_multiplier, g_num_symbols);
   ArrayResize(g_meta_entry_context_key, g_num_symbols);
   ArrayResize(g_meta_entry_reason, g_num_symbols);
   FXRCResetMetaCycleState();
   g_meta_stats_dirty = false;
   g_meta_last_flush_time = 0;
}

// Resets per-cycle meta decisions used by candidate and trade-plan hooks.
void FXRCResetMetaCycleState()
{
   ArrayInitialize(g_meta_entry_risk_multiplier, 1.0);
   ArrayInitialize(g_meta_entry_priority_multiplier, 1.0);

   for(int i=0; i<ArraySize(g_meta_entry_context_key); ++i)
   {
      g_meta_entry_context_key[i] = "";
      g_meta_entry_reason[i] = "";
   }
}

// Returns a coarse trading-session bucket from server time.
string FXRCMetaSessionBucket(const datetime when)
{
   MqlDateTime tm;
   TimeToStruct(when, tm);

   if(tm.hour >= 22 || tm.hour < 1)
      return "ROLLOVER";
   if(tm.hour < 7)
      return "ASIA";
   if(tm.hour < 13)
      return "LONDON";
   if(tm.hour < 17)
      return "LONDON_NY";
   if(tm.hour < 22)
      return "NY";

   return "OTHER";
}

// Returns a coarse market-regime bucket for meta learning.
string FXRCMetaRegimeBucket(const int idx)
{
   if(idx < 0 || idx >= g_num_symbols)
      return "UNKNOWN";

   if(g_PG[idx] < 0.50 || g_G[idx] < InpHardMinRegimeGate)
      return "PANIC";
   if(g_V[idx] > InpV0 * 1.25)
      return "HIGH_VOL";
   if(g_G[idx] >= 0.65)
      return "TREND_NORMAL_VOL";
   if(g_G[idx] >= 0.35)
      return "MIXED";

   return "LOW_REGIME";
}

// Returns a confidence bucket for meta context keys.
string FXRCMetaConfidenceBucket(const int idx)
{
   if(idx < 0 || idx >= g_num_symbols)
      return "UNKNOWN";

   if(g_Conf[idx] >= 0.70)
      return "HIGH";
   if(g_Conf[idx] >= 0.45)
      return "MID";

   return "LOW";
}

// Returns a directional cost bucket using the existing execution gate.
string FXRCMetaCostBucket(const int idx, const int dir)
{
   double gate = DirectionalExecGate(idx, dir);
   if(gate >= 0.75)
      return "LOW";
   if(gate >= 0.45)
      return "MID";

   return "HIGH";
}

// Returns a volatility bucket for meta context keys.
string FXRCMetaVolatilityBucket(const int idx)
{
   if(idx < 0 || idx >= g_num_symbols)
      return "UNKNOWN";

   if(g_atr_pct[idx] <= EPS())
      return "UNKNOWN";
   if(g_V[idx] > InpV0 * 1.25)
      return "HIGH";
   if(g_V[idx] < InpV0 * 0.75)
      return "LOW";

   return "NORMAL";
}

// Returns the dominant alpha sleeve name without changing the alpha signal.
string FXRCMetaDominantSleeveBucket(const int idx)
{
   if(idx < 0 || idx >= g_num_symbols)
      return "UNKNOWN";

   double momentum = MathAbs(InpWeightMomentum * g_M[idx]);
   double carry = MathAbs(InpWeightCarry * g_Carry[idx]);
   double value = MathAbs(InpWeightValue * g_Value[idx]);

   if(momentum >= carry && momentum >= value)
      return "MOMENTUM_DOM";
   if(carry >= momentum && carry >= value)
      return "CARRY_DOM";
   if(value >= momentum && value >= carry)
      return "VALUE_DOM";

   return "BALANCED";
}

// Builds exact and parent context keys for a candidate.
void FXRCBuildMetaContextKeys(const int idx,
                              const int dir,
                              string &context_key,
                              string &symbol_key,
                              string &symbol_dir_key,
                              string &session_key,
                              string &regime_session_key,
                              string &dominant_sleeve)
{
   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();

   string symbol = (idx >= 0 && idx < g_num_symbols ? g_symbols[idx] : "UNKNOWN");
   string dir_text = (dir > 0 ? "LONG" : "SHORT");
   string session = FXRCMetaSessionBucket(now);
   string regime = FXRCMetaRegimeBucket(idx);
   string confidence = FXRCMetaConfidenceBucket(idx);
   string cost = FXRCMetaCostBucket(idx, dir);
   string volatility = FXRCMetaVolatilityBucket(idx);
   dominant_sleeve = FXRCMetaDominantSleeveBucket(idx);

   symbol_key = "SYMBOL|" + symbol;
   symbol_dir_key = "SYMBOL_DIR|" + symbol + "|" + dir_text;
   session_key = "SESSION|" + session;
   regime_session_key = "REGIME_SESSION|" + regime + "|" + session;
   context_key = (
      "META|symbol=" + symbol
      + "|dir=" + dir_text
      + "|session=" + session
      + "|regime=" + regime
      + "|conf=" + confidence
      + "|cost=" + cost
      + "|sleeve=" + dominant_sleeve
      + "|vol=" + volatility
   );
}

// Returns the index of a meta stats bucket.
int FXRCFindMetaStatsIndex(const string key)
{
   for(int i=0; i<ArraySize(g_meta_stats); ++i)
   {
      if(g_meta_stats[i].key == key)
         return i;
   }

   return -1;
}

// Creates or finds a meta stats bucket.
int FXRCEnsureMetaStatsBucket(const string key, const string parent_key)
{
   int idx = FXRCFindMetaStatsIndex(key);
   if(idx >= 0)
   {
      if(StringLen(g_meta_stats[idx].parent_key) == 0)
         g_meta_stats[idx].parent_key = parent_key;
      return idx;
   }

   int new_size = ArraySize(g_meta_stats) + 1;
   ArrayResize(g_meta_stats, new_size);
   idx = new_size - 1;
   g_meta_stats[idx].key = key;
   g_meta_stats[idx].parent_key = parent_key;
   g_meta_stats[idx].samples = 0;
   g_meta_stats[idx].ewma_r = 0.0;
   g_meta_stats[idx].ewma_abs_r = 0.0;
   g_meta_stats[idx].ewma_r2 = 0.0;
   g_meta_stats[idx].last_update_time = 0;
   return idx;
}

// Returns a shrunk mean estimate for a bucket and fallback mean.
double FXRCMetaShrunkMean(const string key, const double fallback_mean)
{
   int idx = FXRCFindMetaStatsIndex(key);
   if(idx < 0 || g_meta_stats[idx].samples <= 0)
      return fallback_mean;

   double prior = MathMax(0.0, InpMetaPriorWeight);
   double samples = (double)MathMax(0, g_meta_stats[idx].samples);
   return (
      samples * g_meta_stats[idx].ewma_r
      + prior * fallback_mean
   ) / MathMax(samples + prior, EPS());
}

// Returns the EWMA variance estimate for a stats key.
double FXRCMetaVarianceForKey(const string key)
{
   int idx = FXRCFindMetaStatsIndex(key);
   if(idx < 0 || g_meta_stats[idx].samples <= 1)
      return 1.0;

   double mean = g_meta_stats[idx].ewma_r;
   return MathMax(0.0, g_meta_stats[idx].ewma_r2 - mean * mean);
}

// Returns the sample count for a stats key.
int FXRCMetaSamplesForKey(const string key)
{
   int idx = FXRCFindMetaStatsIndex(key);
   if(idx < 0)
      return 0;

   return g_meta_stats[idx].samples;
}

// Applies sleeve-aware bounded priority adjustment to the meta decision.
void FXRCApplyMetaSleeveBias(const string dominant_sleeve,
                             const double conservative_edge,
                             FXRCMetaDecision &decision)
{
   double sleeve_multiplier = 1.0;
   if(conservative_edge < 0.0)
      sleeve_multiplier = 0.85;
   else if(conservative_edge >= InpMetaBoostAboveR)
      sleeve_multiplier = 1.10;

   sleeve_multiplier = Clip(sleeve_multiplier, 0.75, 1.20);
   if(dominant_sleeve == "MOMENTUM_DOM")
      decision.momentum_multiplier = sleeve_multiplier;
   else if(dominant_sleeve == "CARRY_DOM")
      decision.carry_multiplier = sleeve_multiplier;
   else if(dominant_sleeve == "VALUE_DOM")
      decision.value_multiplier = sleeve_multiplier;

   decision.priority_multiplier = Clip(
      decision.priority_multiplier * sleeve_multiplier,
      0.50,
      1.25
   );
}

// Evaluates the meta allocator for an already-qualified candidate.
bool FXRCEvaluateMetaDecision(const int idx,
                              const int dir,
                              FXRCMetaDecision &decision)
{
   FXRCResetMetaDecision(decision);
   if(!InpUseMetaAllocator)
      return true;

   string symbol_key, symbol_dir_key, session_key, regime_session_key, sleeve;
   FXRCBuildMetaContextKeys(
      idx,
      dir,
      decision.context_key,
      symbol_key,
      symbol_dir_key,
      session_key,
      regime_session_key,
      sleeve
   );

   double global_mean = FXRCMetaShrunkMean("GLOBAL", 0.0);
   double session_mean = FXRCMetaShrunkMean(session_key, global_mean);
   double regime_session_mean = FXRCMetaShrunkMean(regime_session_key, session_mean);
   double symbol_mean = FXRCMetaShrunkMean(symbol_key, regime_session_mean);
   double symbol_dir_mean = FXRCMetaShrunkMean(symbol_dir_key, symbol_mean);
   double exact_mean = FXRCMetaShrunkMean(decision.context_key, symbol_dir_mean);

   int exact_samples = FXRCMetaSamplesForKey(decision.context_key);
   int parent_samples = FXRCMetaSamplesForKey(symbol_dir_key);
   int effective_samples = exact_samples + parent_samples / 2;
   if(effective_samples < InpMetaMinSamplesForThrottle)
      return true;

   double variance = FXRCMetaVarianceForKey(decision.context_key);
   if(exact_samples <= 1)
      variance = FXRCMetaVarianceForKey(symbol_dir_key);

   double uncertainty = MathSqrt(MathMax(variance, EPS()))
                      / MathSqrt((double)MathMax(1, effective_samples));
   double conservative_edge = exact_mean - InpMetaConservativeZ * uncertainty;

   if(conservative_edge <= InpMetaBlockBelowR)
   {
      decision.allow_entry = false;
      decision.risk_multiplier = 0.0;
      decision.priority_multiplier = 0.0;
      decision.reason = StringFormat(
         "meta allocator blocked weak context edge %.3f samples=%d",
         conservative_edge,
         effective_samples
      );
      return true;
   }

   if(conservative_edge < 0.0)
   {
      double span = MathMax(MathAbs(InpMetaBlockBelowR), EPS());
      double frac = Clip((conservative_edge - InpMetaBlockBelowR) / span, 0.0, 1.0);
      decision.risk_multiplier = InpMetaMinRiskMultiplier
                               + frac * (InpMetaBadContextMultiplier - InpMetaMinRiskMultiplier);
      decision.priority_multiplier = Clip(0.65 + 0.35 * frac, 0.50, 1.0);
      decision.reason = StringFormat(
         "meta allocator reduced weak context edge %.3f samples=%d",
         conservative_edge,
         effective_samples
      );
   }
   else
   {
      decision.risk_multiplier = InpMetaNeutralRiskMultiplier;
      decision.priority_multiplier = 1.0;
   }

   if(conservative_edge >= InpMetaBoostAboveR
      && effective_samples >= InpMetaMinSamplesForBoost)
   {
      decision.risk_multiplier = InpMetaNeutralRiskMultiplier
                               + InpMetaGain * (conservative_edge - InpMetaBoostAboveR);
      decision.priority_multiplier = Clip(1.0 + 0.50 * (conservative_edge - InpMetaBoostAboveR),
                                          1.0,
                                          1.20);
   }

   decision.risk_multiplier = Clip(
      decision.risk_multiplier,
      InpMetaMinRiskMultiplier,
      InpMetaMaxRiskMultiplier
   );
   FXRCApplyMetaSleeveBias(sleeve, conservative_edge, decision);
   return true;
}

// Applies meta allocator priority and permission to a candidate.
bool FXRCApplyMetaAllocationToCandidate(FXRCCandidate &candidate)
{
   if(!InpUseMetaAllocator)
      return true;

   FXRCMetaDecision decision;
   if(!FXRCEvaluateMetaDecision(candidate.symbol_idx, candidate.dir, decision))
      return true;

   if(candidate.symbol_idx >= 0 && candidate.symbol_idx < g_num_symbols)
   {
      g_meta_entry_risk_multiplier[candidate.symbol_idx] = decision.risk_multiplier;
      g_meta_entry_priority_multiplier[candidate.symbol_idx] = decision.priority_multiplier;
      g_meta_entry_context_key[candidate.symbol_idx] = decision.context_key;
      g_meta_entry_reason[candidate.symbol_idx] = decision.reason;
   }

   if(!decision.allow_entry || decision.risk_multiplier <= EPS())
   {
      PrintFormat(
         "Skipping %s %s because %s.",
         g_symbols[candidate.symbol_idx],
         (candidate.dir > 0 ? "long" : "short"),
         decision.reason
      );
      return false;
   }

   if(decision.risk_multiplier < 0.90 && StringLen(decision.reason) > 0)
   {
      PrintFormat(
         "Meta allocator reducing %s %s risk multiplier to %.2f: %s.",
         g_symbols[candidate.symbol_idx],
         (candidate.dir > 0 ? "long" : "short"),
         decision.risk_multiplier,
         decision.reason
      );
   }

   candidate.priority *= decision.priority_multiplier;
   return (candidate.priority > EPS());
}

// Returns the current meta risk multiplier for trade planning.
double FXRCMetaRiskMultiplierForEntry(const int symbol_idx, const int dir)
{
   if(!InpUseMetaAllocator)
      return 1.0;
   if(symbol_idx < 0 || symbol_idx >= ArraySize(g_meta_entry_risk_multiplier))
      return 1.0;

   if(g_meta_entry_context_key[symbol_idx] == "")
   {
      FXRCMetaDecision decision;
      FXRCEvaluateMetaDecision(symbol_idx, dir, decision);
      return decision.risk_multiplier;
   }

   return Clip(g_meta_entry_risk_multiplier[symbol_idx],
               InpMetaMinRiskMultiplier,
               InpMetaMaxRiskMultiplier);
}

// Returns a stable filename for persisted meta stats.
string FXRCMetaStatsFileName()
{
   long hash = 17;
   string universe = "";
   for(int i=0; i<g_num_symbols; ++i)
      universe += "|" + NormalizedSymbolName(g_symbols[i]);

   for(int j=0; j<StringLen(universe); ++j)
      hash = (hash * 31 + (long)StringGetCharacter(universe, j)) % 1000000007;

   return StringFormat(
      "FX7_meta_stats_%d_%d_%d.csv",
      (int)InpMagicNumber,
      (int)InpSignalTF,
      (int)MathAbs(hash)
   );
}

// Loads persisted meta stats from common terminal storage.
bool FXRCLoadMetaStats()
{
   if(!InpUseMetaAllocator || !InpMetaPersistStats)
      return true;

   string filename = FXRCMetaStatsFileName();
   ResetLastError();
   int handle = FileOpen(filename, FILE_READ | FILE_CSV | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      if(err != 5004)
         PrintFormat("FXRC meta stats load skipped for %s err=%d", filename, err);
      return false;
   }

   int ignored = 0;
   while(!FileIsEnding(handle))
   {
      string key = FileReadString(handle);
      if(FileIsEnding(handle) && StringLen(key) == 0)
         break;

      string parent_key = FileReadString(handle);
      int samples = (int)FileReadNumber(handle);
      double ewma_r = FileReadNumber(handle);
      double ewma_abs_r = FileReadNumber(handle);
      double ewma_r2 = FileReadNumber(handle);
      datetime last_update = (datetime)(long)FileReadNumber(handle);

      if(StringLen(key) == 0 || samples < 0 || ewma_r != ewma_r)
      {
         ignored++;
         continue;
      }

      int idx = FXRCEnsureMetaStatsBucket(key, parent_key);
      g_meta_stats[idx].samples = samples;
      g_meta_stats[idx].ewma_r = ewma_r;
      g_meta_stats[idx].ewma_abs_r = ewma_abs_r;
      g_meta_stats[idx].ewma_r2 = ewma_r2;
      g_meta_stats[idx].last_update_time = last_update;
   }

   FileClose(handle);
   if(ignored > 0)
      PrintFormat("FXRC meta stats ignored %d invalid row(s) from %s.", ignored, filename);

   g_meta_stats_dirty = false;
   g_meta_last_flush_time = SafeNow();
   return true;
}

// Persists meta stats to common terminal storage.
bool FXRCFlushMetaStats(const bool force)
{
   if(!InpUseMetaAllocator || !InpMetaPersistStats)
      return true;
   if(!force && !g_meta_stats_dirty)
      return true;

   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();

   if(!force && g_meta_last_flush_time > 0)
   {
      int flush_seconds = MathMax(1, InpMetaStatsFlushMinutes) * 60;
      if((now - g_meta_last_flush_time) < flush_seconds)
         return true;
   }

   string filename = FXRCMetaStatsFileName();
   ResetLastError();
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("FXRC meta stats save failed for %s err=%d", filename, GetLastError());
      return false;
   }

   for(int i=0; i<ArraySize(g_meta_stats); ++i)
   {
      FileWrite(
         handle,
         g_meta_stats[i].key,
         g_meta_stats[i].parent_key,
         g_meta_stats[i].samples,
         g_meta_stats[i].ewma_r,
         g_meta_stats[i].ewma_abs_r,
         g_meta_stats[i].ewma_r2,
         (long)g_meta_stats[i].last_update_time
      );
   }

   FileClose(handle);
   g_meta_stats_dirty = false;
   g_meta_last_flush_time = now;
   return true;
}

// Updates one meta stats bucket with a realized R observation.
void FXRCUpdateMetaBucket(const string key,
                          const string parent_key,
                          const double realized_r,
                          const datetime update_time)
{
   int idx = FXRCEnsureMetaStatsBucket(key, parent_key);
   double alpha = 1.0 - MathExp(-MathLog(2.0) / MathMax(1.0, (double)InpMetaUpdateHalfLifeTrades));
   if(g_meta_stats[idx].samples <= 0)
   {
      g_meta_stats[idx].ewma_r = realized_r;
      g_meta_stats[idx].ewma_abs_r = MathAbs(realized_r);
      g_meta_stats[idx].ewma_r2 = realized_r * realized_r;
   }
   else
   {
      g_meta_stats[idx].ewma_r = (1.0 - alpha) * g_meta_stats[idx].ewma_r
                               + alpha * realized_r;
      g_meta_stats[idx].ewma_abs_r = (1.0 - alpha) * g_meta_stats[idx].ewma_abs_r
                                   + alpha * MathAbs(realized_r);
      g_meta_stats[idx].ewma_r2 = (1.0 - alpha) * g_meta_stats[idx].ewma_r2
                                + alpha * realized_r * realized_r;
   }

   g_meta_stats[idx].samples++;
   g_meta_stats[idx].last_update_time = update_time;
   g_meta_stats_dirty = true;
}

// Finds an open meta context by position id or symbol fallback.
int FXRCFindMetaOpenContext(const long position_id, const string symbol)
{
   for(int i=0; i<ArraySize(g_meta_open_contexts); ++i)
   {
      if(position_id > 0 && g_meta_open_contexts[i].position_id == position_id)
         return i;
   }

   for(int i=0; i<ArraySize(g_meta_open_contexts); ++i)
   {
      if(g_meta_open_contexts[i].symbol == symbol)
         return i;
   }

   return -1;
}

// Removes an open meta context by index.
void FXRCRemoveMetaOpenContextAt(const int idx)
{
   int last = ArraySize(g_meta_open_contexts) - 1;
   if(idx < 0 || idx > last)
      return;

   if(idx != last)
      g_meta_open_contexts[idx] = g_meta_open_contexts[last];

   ArrayResize(g_meta_open_contexts, last);
}

// Attempts to resolve the position identifier for a just-sent entry.
long FXRCResolveEntryPositionId(const string symbol, const MqlTradeResult &result)
{
   if(result.deal > 0 && HistoryDealSelect(result.deal))
   {
      long deal_position_id = HistoryDealGetInteger(result.deal, DEAL_POSITION_ID);
      if(deal_position_id > 0)
         return deal_position_id;
   }

   if(PositionSelect(symbol) && IsSelectedFXRCPosition())
   {
      long position_id = PositionGetInteger(POSITION_IDENTIFIER);
      if(position_id > 0)
         return position_id;
   }

   return 0;
}

// Registers the context used by a successfully dispatched entry.
void FXRCRegisterMetaOpenContextFromPlan(const int symbol_idx,
                                         const int dir,
                                         const FXRCTradePlan &plan,
                                         const MqlTradeResult &result)
{
   if(!InpUseMetaAllocator)
      return;
   if(symbol_idx < 0 || symbol_idx >= g_num_symbols || plan.risk_cash <= EPS())
      return;

   string context_key, symbol_key, symbol_dir_key, session_key, regime_session_key, sleeve;
   FXRCBuildMetaContextKeys(
      symbol_idx,
      dir,
      context_key,
      symbol_key,
      symbol_dir_key,
      session_key,
      regime_session_key,
      sleeve
   );

   long position_id = FXRCResolveEntryPositionId(plan.symbol, result);
   int idx = FXRCFindMetaOpenContext(position_id, plan.symbol);
   if(idx < 0)
   {
      int new_size = ArraySize(g_meta_open_contexts) + 1;
      ArrayResize(g_meta_open_contexts, new_size);
      idx = new_size - 1;
   }

   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();

   g_meta_open_contexts[idx].symbol = plan.symbol;
   g_meta_open_contexts[idx].position_id = position_id;
   g_meta_open_contexts[idx].symbol_idx = symbol_idx;
   g_meta_open_contexts[idx].dir = dir;
   g_meta_open_contexts[idx].entry_risk_cash = plan.risk_cash;
   g_meta_open_contexts[idx].entry_volume = plan.volume;
   g_meta_open_contexts[idx].remaining_risk_cash = plan.risk_cash;
   g_meta_open_contexts[idx].remaining_volume = plan.volume;
   g_meta_open_contexts[idx].entry_price = plan.entry_price;
   g_meta_open_contexts[idx].context_key = context_key;
   g_meta_open_contexts[idx].symbol_key = symbol_key;
   g_meta_open_contexts[idx].symbol_dir_key = symbol_dir_key;
   g_meta_open_contexts[idx].session_key = session_key;
   g_meta_open_contexts[idx].regime_session_key = regime_session_key;
   g_meta_open_contexts[idx].entry_time = now;
}

// Updates all relevant meta stats buckets for a closed trade context.
void FXRCUpdateMetaStatsFromContext(const FXRCMetaOpenContext &context,
                                    const double realized_r,
                                    const datetime close_time)
{
   string global_key = "GLOBAL";
   FXRCUpdateMetaBucket(global_key, "", realized_r, close_time);
   FXRCUpdateMetaBucket(context.session_key, global_key, realized_r, close_time);
   FXRCUpdateMetaBucket(context.regime_session_key, context.session_key, realized_r, close_time);
   FXRCUpdateMetaBucket(context.symbol_key, context.regime_session_key, realized_r, close_time);
   FXRCUpdateMetaBucket(context.symbol_dir_key, context.symbol_key, realized_r, close_time);
   FXRCUpdateMetaBucket(context.context_key, context.symbol_dir_key, realized_r, close_time);
}

// Learns from an FX7-owned closing deal if an entry context is known.
void FXRCProcessMetaClosingDeal(const ulong deal_ticket)
{
   if(!InpUseMetaAllocator || deal_ticket == 0 || !HistoryDealSelect(deal_ticket))
      return;

   long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
   if(!IsFXRCMagic(magic))
      return;

   long entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   string symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
   long position_id = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
   int idx = FXRCFindMetaOpenContext(position_id, symbol);
   if(idx < 0)
      return;

   double close_volume = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
   double volume_base = MathMax(g_meta_open_contexts[idx].remaining_volume, EPS());
   double close_fraction = Clip(close_volume / volume_base, 0.0, 1.0);
   double risk_cash = g_meta_open_contexts[idx].remaining_risk_cash * close_fraction;
   if(risk_cash <= EPS())
      return;

   double net_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT)
                     + HistoryDealGetDouble(deal_ticket, DEAL_SWAP)
                     + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION)
                     + HistoryDealGetDouble(deal_ticket, DEAL_FEE);
   double realized_r = net_profit / MathMax(risk_cash, EPS());
   datetime close_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
   if(close_time <= 0)
      close_time = SafeNow();

   FXRCUpdateMetaStatsFromContext(g_meta_open_contexts[idx], realized_r, close_time);

   g_meta_open_contexts[idx].remaining_volume -= close_volume;
   g_meta_open_contexts[idx].remaining_risk_cash -= risk_cash;
   if(g_meta_open_contexts[idx].remaining_volume <= EPS()
      || g_meta_open_contexts[idx].remaining_risk_cash <= EPS())
   {
      FXRCRemoveMetaOpenContextAt(idx);
   }
}

// Lets the meta allocator observe FX7-owned trade transactions.
void FXRCHandleMetaTradeTransaction(const MqlTradeTransaction &trans,
                                    const MqlTradeRequest &request,
                                    const MqlTradeResult &result)
{
   if(!InpUseMetaAllocator)
      return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;

   FXRCProcessMetaClosingDeal(trans.deal);
   FXRCFlushMetaStats(false);
}
