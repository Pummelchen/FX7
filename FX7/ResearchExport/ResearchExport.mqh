//------------------------- Research Feature Export -------------------------//

// Returns whether the symbol index is in the current candidate set.
bool FXRCResearchIsCandidate(const int symbol_idx, const int &candidates[])
{
   for(int i=0; i<ArraySize(candidates); ++i)
   {
      if(candidates[i] == symbol_idx)
         return true;
   }

   return false;
}

// Returns the closed signal-bar close and timestamp used for ex-ante export.
bool FXRCResearchClosedBarSnapshot(const int symbol_idx,
                                   datetime &bar_time,
                                   double &close_price)
{
   bar_time = 0;
   close_price = 0.0;
   if(symbol_idx < 0 || symbol_idx >= g_num_symbols)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   ResetLastError();
   int copied = CopyRates(g_symbols[symbol_idx], InpSignalTF, 0, 2, rates);
   if(copied < 2 || rates[1].close <= 0.0)
      return false;

   bar_time = rates[1].time;
   close_price = rates[1].close;
   return true;
}

// Returns the current broker spread in points for a symbol.
double FXRCResearchSpreadPoints(const string symbol)
{
   long spread_points = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   if(spread_points > 0)
      return (double)spread_points;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick) || tick.ask <= tick.bid)
      return 0.0;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return 0.0;

   return (tick.ask - tick.bid) / point;
}

// Returns a concise blocked-candidate reason for research diagnostics.
string FXRCResearchBlockReasonCode(const int idx, const bool was_candidate)
{
   if(was_candidate)
      return "";
   if(idx < 0 || idx >= g_num_symbols)
      return "invalid_symbol";
   if(!g_symbol_data_ok[idx])
      return "no_feature_state";
   if(IsSymbolDataStale(idx))
      return "stale_feature_state";
   if(g_entry_dir_raw[idx] == 0)
      return "no_direction";
   if(g_persist_count[idx] < InpPersistenceBars)
      return "persistence";
   if(FXRCRegimeStateBlocksEntry(idx))
      return "regime_state_stress";
   if(g_Conf[idx] < FXRCAdaptiveMinConfidenceFloor())
      return "low_confidence";
   if(g_G[idx] < InpMinRegimeGate)
      return "low_regime_gate";
   if(DirectionalExecGate(idx, g_entry_dir_raw[idx]) < InpMinExecGate)
      return "low_execution_gate";

   return "not_selected";
}

// Writes the stable research-export CSV header when the file is new.
bool FXRCEnsureResearchExportHeader()
{
   if(g_research_export_header_checked)
      return true;

   bool exists = FileIsExist(InpResearchExportFile, FILE_COMMON);
   if(exists)
   {
      g_research_export_header_checked = true;
      return true;
   }

   ResetLastError();
   int handle = FileOpen(InpResearchExportFile, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
   {
      PrintFormat(
         "FXRC research export failed to create %s err=%d.",
         InpResearchExportFile,
         GetLastError()
      );
      return false;
   }

   FileWrite(
      handle,
      "schema_version",
      "timestamp_server",
      "timestamp_bar",
      "symbol",
      "base_currency",
      "quote_currency",
      "signal_tf",
      "close",
      "spread_points",
      "atr",
      "realized_vol",
      "short_vol",
      "long_vol",
      "vol_ratio",
      "momentum_score",
      "carry_score",
      "value_score",
      "xmom_score",
      "medium_trend_score",
      "breakout_score_or_participation",
      "efficiency_ratio",
      "reversal_penalty",
      "panic_gate_value",
      "regime_score_or_state_probs",
      "composite_raw",
      "composite_after_gates",
      "confidence_raw_existing",
      "cost_long",
      "cost_short",
      "candidate_direction",
      "candidate_rank",
      "was_candidate",
      "was_blocked",
      "block_reason_code",
      "novelty_score_if_available",
      "correlation_penalty_if_available",
      "currency_exposure_penalty_if_available"
   );
   FileClose(handle);
   g_research_export_header_checked = true;
   return true;
}

// Returns a compact regime-probability export field.
string FXRCResearchRegimeField(const int idx)
{
   if(InpUseRegimeStateFilter)
   {
      return StringFormat(
         "%.6f|%.6f|%.6f",
         g_RegimePTrend[idx],
         g_RegimePChoppy[idx],
         g_RegimePStress[idx]
      );
   }

   return DoubleToString(g_G[idx], 8);
}

// Appends one feature-export row per eligible symbol for offline research.
void FXRCExportResearchFeatures(const int &candidates[])
{
   if(!InpUseResearchFeatureExport)
      return;
   if(StringLen(InpResearchExportFile) == 0)
      return;
   if(!FXRCEnsureResearchExportHeader())
      return;

   datetime server_time = SafeNow();
   if(server_time <= 0)
      server_time = TimeCurrent();

   datetime reference_bar = 0;
   if(g_num_symbols > 0 && ArraySize(g_last_closed_bar) == g_num_symbols)
      reference_bar = g_last_closed_bar[0];
   if(!InpResearchExportFlushEveryBar
      && reference_bar > 0
      && g_research_export_last_bar_time == reference_bar)
   {
      return;
   }

   ResetLastError();
   int handle = FileOpen(InpResearchExportFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
   {
      PrintFormat(
         "FXRC research export failed to append %s err=%d.",
         InpResearchExportFile,
         GetLastError()
      );
      return;
   }
   FileSeek(handle, 0, SEEK_END);

   for(int idx=0; idx<g_num_symbols; ++idx)
   {
      bool was_candidate = FXRCResearchIsCandidate(idx, candidates);
      if(InpResearchExportCandidatesOnly && !was_candidate)
         continue;
      if(!InpResearchExportIncludeNonCandidates && !was_candidate)
         continue;

      datetime bar_time = 0;
      double close_price = 0.0;
      if(!FXRCResearchClosedBarSnapshot(idx, bar_time, close_price))
      {
         bar_time = (ArraySize(g_last_closed_bar) == g_num_symbols ? g_last_closed_bar[idx] : 0);
         close_price = 0.0;
      }

      string block_reason = FXRCResearchBlockReasonCode(idx, was_candidate);
      bool was_blocked = (!was_candidate && StringLen(block_reason) > 0);
      string xmom_value = (g_XMomValid[idx] ? DoubleToString(g_XMomScore[idx], 8) : "");
      string medium_value = (
         g_MediumTrendValid[idx] ? DoubleToString(g_MediumTrendScore[idx], 8) : ""
      );

      FileWrite(
         handle,
         InpResearchExportSchemaVersion,
         TimeToString(server_time, TIME_DATE | TIME_SECONDS),
         TimeToString(bar_time, TIME_DATE | TIME_SECONDS),
         g_symbols[idx],
         g_base_ccy[idx],
         g_quote_ccy[idx],
         EnumToString(InpSignalTF),
         close_price,
         FXRCResearchSpreadPoints(g_symbols[idx]),
         g_atr_pct[idx],
         g_sigma_long[idx],
         g_sigma_short[idx],
         g_sigma_long[idx],
         g_V[idx],
         g_M[idx],
         g_Carry[idx],
         g_Value[idx],
         xmom_value,
         medium_value,
         g_BK[idx],
         g_ER[idx],
         g_D[idx],
         g_PG[idx],
         FXRCResearchRegimeField(idx),
         g_CompositeCore[idx],
         g_S[idx],
         g_Conf[idx],
         g_K_long[idx],
         g_K_short[idx],
         g_entry_dir_raw[idx],
         g_Rank[idx],
         (was_candidate ? 1 : 0),
         (was_blocked ? 1 : 0),
         block_reason,
         g_Rank[idx],
         g_Omega[idx],
         ""
      );
   }

   FileClose(handle);
   g_research_export_last_bar_time = reference_bar;
}
