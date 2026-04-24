//------------------------- Forward-Points Carry Support -------------------------//

// Clears the forward-points carry cache.
void FXRCClearForwardPointsCache()
{
   ArrayResize(g_forward_points_records, 0);
   g_forward_points_loaded = false;
   g_forward_points_last_load_time = 0;
   g_forward_points_load_reason = "";
}

// Parses a forward-points timestamp using common CSV conventions.
datetime FXRCParseForwardTimestamp(const string value)
{
   datetime parsed = StringToTime(value);
   if(parsed > 0)
      return parsed;

   long unix_time = (long)StringToInteger(value);
   if(unix_time > 0)
      return (datetime)unix_time;

   return 0;
}

// Appends one forward-points record to the runtime cache.
void FXRCAppendForwardPointsRecord(const string symbol,
                                   const datetime timestamp,
                                   const int tenor_days,
                                   const double forward_points,
                                   const double spot_reference,
                                   const double bid_forward_points,
                                   const double ask_forward_points)
{
   int new_size = ArraySize(g_forward_points_records) + 1;
   ArrayResize(g_forward_points_records, new_size);
   int idx = new_size - 1;
   g_forward_points_records[idx].symbol = NormalizedSymbolName(symbol);
   g_forward_points_records[idx].timestamp = timestamp;
   g_forward_points_records[idx].tenor_days = tenor_days;
   g_forward_points_records[idx].forward_points = forward_points;
   g_forward_points_records[idx].spot_reference = spot_reference;
   g_forward_points_records[idx].bid_forward_points = bid_forward_points;
   g_forward_points_records[idx].ask_forward_points = ask_forward_points;
}

// Loads forward-points records from the configured common-files CSV.
bool FXRCLoadForwardPointsCache(const bool force_log)
{
   FXRCClearForwardPointsCache();
   if(!InpUseForwardPointsCarry)
      return true;

   ResetLastError();
   int handle = FileOpen(InpForwardPointsFile, FILE_READ | FILE_CSV | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
   {
      g_forward_points_load_reason = StringFormat(
         "forward-points file unavailable: %s err=%d",
         InpForwardPointsFile,
         GetLastError()
      );
      if(force_log)
         Print(g_forward_points_load_reason);
      return false;
   }

   int ignored = 0;
   while(!FileIsEnding(handle))
   {
      string ts_text = FileReadString(handle);
      if(FileIsEnding(handle) && StringLen(ts_text) == 0)
         break;

      string symbol = FileReadString(handle);
      string tenor_text = FileReadString(handle);
      string points_text = FileReadString(handle);
      string spot_text = FileReadString(handle);
      string bid_text = FileReadString(handle);
      string ask_text = FileReadString(handle);

      if(ts_text == "timestamp")
         continue;

      datetime timestamp = FXRCParseForwardTimestamp(ts_text);
      int tenor_days = (int)StringToInteger(tenor_text);
      double forward_points = StringToDouble(points_text);
      double spot_reference = StringToDouble(spot_text);
      double bid_forward_points = StringToDouble(bid_text);
      double ask_forward_points = StringToDouble(ask_text);

      if(timestamp <= 0 || StringLen(symbol) == 0 || tenor_days <= 0)
      {
         ignored++;
         continue;
      }

      FXRCAppendForwardPointsRecord(
         symbol,
         timestamp,
         tenor_days,
         forward_points,
         spot_reference,
         bid_forward_points,
         ask_forward_points
      );
   }

   FileClose(handle);
   g_forward_points_loaded = true;
   g_forward_points_last_load_time = SafeNow();
   if(g_forward_points_last_load_time <= 0)
      g_forward_points_last_load_time = TimeCurrent();

   if(ArraySize(g_forward_points_records) <= 0)
   {
      g_forward_points_load_reason = "forward-points cache loaded no usable rows";
      if(force_log)
         Print(g_forward_points_load_reason);
      return false;
   }

   g_forward_points_load_reason = "";
   if(force_log)
   {
      PrintFormat(
         "FXRC forward-points carry loaded %d row(s) from %s; ignored=%d. "
         + "Sign convention: forward = spot + forward_points * point; "
         + "long base carry uses (spot-forward)/spot annualized.",
         ArraySize(g_forward_points_records),
         InpForwardPointsFile,
         ignored
      );
   }

   return true;
}

// Ensures forward-points data are loaded if that carry source is enabled.
bool FXRCEnsureForwardPointsCache(const bool force_log)
{
   if(!InpUseForwardPointsCarry)
      return true;
   if(g_forward_points_loaded)
      return (ArraySize(g_forward_points_records) > 0);

   return FXRCLoadForwardPointsCache(force_log);
}

// Finds the freshest usable forward-points row for a symbol.
bool FXRCFindForwardPointsRecord(const string symbol,
                                 const datetime asof_time,
                                 FXRCForwardPointsRecord &record,
                                 string &reason)
{
   reason = "";
   string normalized = NormalizedSymbolName(symbol);
   int best_idx = -1;
   datetime best_time = 0;

   for(int i=0; i<ArraySize(g_forward_points_records); ++i)
   {
      if(g_forward_points_records[i].symbol != normalized)
         continue;
      if(g_forward_points_records[i].timestamp > asof_time)
         continue;
      if(g_forward_points_records[i].timestamp > best_time)
      {
         best_idx = i;
         best_time = g_forward_points_records[i].timestamp;
      }
   }

   if(best_idx < 0)
   {
      reason = "no forward-points row at or before signal time";
      return false;
   }

   int max_age_seconds = MathMax(0, InpForwardPointsMaxStaleDays) * 24 * 60 * 60;
   if(max_age_seconds > 0 && asof_time - best_time > max_age_seconds)
   {
      reason = "forward-points row is stale";
      return false;
   }

   record = g_forward_points_records[best_idx];
   return true;
}

// Computes carry from forward points using the documented sign convention.
bool ComputeForwardPointsCarrySignal(const string symbol,
                                     const double mid_px,
                                     const datetime asof_time,
                                     double &signal,
                                     double &annual_spread_frac,
                                     datetime &macro_date,
                                     string &reason)
{
   signal = 0.0;
   annual_spread_frac = 0.0;
   macro_date = 0;
   reason = "";

   if(!InpUseForwardPointsCarry)
   {
      reason = "forward-points carry is disabled";
      return false;
   }
   if(!FXRCEnsureForwardPointsCache(false))
   {
      reason = g_forward_points_load_reason;
      return false;
   }

   FXRCForwardPointsRecord record;
   if(!FXRCFindForwardPointsRecord(symbol, asof_time, record, reason))
      return false;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
   {
      reason = "symbol point unavailable for forward-points carry";
      return false;
   }

   double spot = (record.spot_reference > 0.0 ? record.spot_reference : mid_px);
   if(spot <= EPS())
   {
      reason = "spot reference unavailable for forward-points carry";
      return false;
   }

   double points = record.forward_points;
   if(record.bid_forward_points != 0.0 || record.ask_forward_points != 0.0)
      points = 0.5 * (record.bid_forward_points + record.ask_forward_points);

   double forward = spot + points * point;
   annual_spread_frac = ((spot - forward) / spot) * 365.0 / (double)record.tenor_days;
   signal = MathTanh(annual_spread_frac / InpCarrySignalScale);
   macro_date = record.timestamp;
   return true;
}
