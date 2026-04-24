//------------------------- Execution Quality Governor -------------------------//

// Resets an execution-quality decision to neutral behavior.
void FXRCResetExecutionQualityDecision(FXRCExecutionQualityDecision &decision)
{
   decision.allow_entry = true;
   decision.risk_multiplier = 1.0;
   decision.reason = "";
}

// Initializes bounded per-symbol execution-quality buffers.
void FXRCInitExecutionQualityState()
{
   int lookback = MathMax(1, InpExecQualitySpreadLookbackSamples);
   int contexts = MathMax(1, g_num_symbols * 6);
   ArrayResize(g_exec_quality_spread_samples, contexts * lookback);
   ArrayResize(g_exec_quality_sample_count, contexts);
   ArrayResize(g_exec_quality_next_slot, contexts);
   ArrayResize(g_exec_quality_last_bid, g_num_symbols);
   ArrayResize(g_exec_quality_last_ask, g_num_symbols);
   ArrayResize(g_exec_quality_last_spread_points, g_num_symbols);
   ArrayResize(g_exec_quality_last_quote_time, g_num_symbols);
   ArrayResize(g_exec_quality_stable_since, g_num_symbols);

   ArrayInitialize(g_exec_quality_spread_samples, 0.0);
   ArrayInitialize(g_exec_quality_sample_count, 0);
   ArrayInitialize(g_exec_quality_next_slot, 0);
   ArrayInitialize(g_exec_quality_last_bid, 0.0);
   ArrayInitialize(g_exec_quality_last_ask, 0.0);
   ArrayInitialize(g_exec_quality_last_spread_points, 0.0);
   ArrayInitialize(g_exec_quality_last_quote_time, 0);
   ArrayInitialize(g_exec_quality_stable_since, 0);
}

// Returns the execution-quality session index from server time.
int FXRCExecQualitySessionIndex(const datetime when)
{
   MqlDateTime tm;
   TimeToStruct(when, tm);

   if(tm.hour >= 22 || tm.hour < 1)
      return 0;
   if(tm.hour < 7)
      return 1;
   if(tm.hour < 13)
      return 2;
   if(tm.hour < 17)
      return 3;
   if(tm.hour < 22)
      return 4;

   return 5;
}

// Returns the state row for a symbol/session spread history.
int FXRCExecQualityStateIndex(const int symbol_idx, const int session_idx)
{
   return symbol_idx * 6 + session_idx;
}

// Returns the flat index into the spread sample ring buffer.
int FXRCExecQualitySampleIndex(const int state_idx, const int slot)
{
   int lookback = MathMax(1, InpExecQualitySpreadLookbackSamples);
   return state_idx * lookback + slot;
}

// Returns whether the current server time is inside the rollover skip window.
bool FXRCIsRolloverWindow(const datetime now)
{
   int skip_minutes = MathMax(0, InpExecQualityRolloverSkipMinutes);
   if(skip_minutes <= 0)
      return false;

   MqlDateTime tm;
   TimeToStruct(now, tm);
   int seconds = tm.hour * 3600 + tm.min * 60 + tm.sec;
   int window = skip_minutes * 60;
   return (seconds <= window || seconds >= 86400 - window);
}

// Samples current spread and quote stability for one symbol.
bool FXRCUpdateExecutionQualitySampleForSymbol(const int symbol_idx,
                                               string &reason)
{
   reason = "";
   if(symbol_idx < 0 || symbol_idx >= g_num_symbols)
      return false;

   MqlTick tick;
   ResetLastError();
   if(!SymbolInfoTick(g_symbols[symbol_idx], tick))
   {
      reason = StringFormat("quote unavailable for %s err=%d",
                            g_symbols[symbol_idx],
                            GetLastError());
      g_exec_quality_stable_since[symbol_idx] = 0;
      return false;
   }

   double point = SymbolInfoDouble(g_symbols[symbol_idx], SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;

   if(tick.bid <= 0.0 || tick.ask <= 0.0 || tick.ask <= tick.bid || point <= 0.0)
   {
      reason = StringFormat("invalid or crossed quote for %s", g_symbols[symbol_idx]);
      g_exec_quality_stable_since[symbol_idx] = 0;
      return false;
   }

   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();

   double spread_points = (tick.ask - tick.bid) / point;
   double previous_spread = g_exec_quality_last_spread_points[symbol_idx];
   bool abnormal_jump = (
      previous_spread > EPS()
      && spread_points > previous_spread * MathMax(1.0, InpExecQualityAbnormalSpreadMultiple)
   );

   if(g_exec_quality_stable_since[symbol_idx] <= 0 || abnormal_jump)
      g_exec_quality_stable_since[symbol_idx] = now;

   g_exec_quality_last_bid[symbol_idx] = tick.bid;
   g_exec_quality_last_ask[symbol_idx] = tick.ask;
   g_exec_quality_last_spread_points[symbol_idx] = spread_points;
   g_exec_quality_last_quote_time[symbol_idx] = (tick.time > 0 ? tick.time : now);

   int session_idx = FXRCExecQualitySessionIndex(now);
   int state_idx = FXRCExecQualityStateIndex(symbol_idx, session_idx);
   int lookback = MathMax(1, InpExecQualitySpreadLookbackSamples);
   int slot = g_exec_quality_next_slot[state_idx];
   g_exec_quality_spread_samples[FXRCExecQualitySampleIndex(state_idx, slot)] = spread_points;
   g_exec_quality_next_slot[state_idx] = (slot + 1) % lookback;
   g_exec_quality_sample_count[state_idx] = MathMin(
      lookback,
      g_exec_quality_sample_count[state_idx] + 1
   );

   return true;
}

// Updates execution-quality samples for all tracked symbols.
void FXRCUpdateExecutionQualitySamples()
{
   if(!InpUseExecutionQualityGovernor)
      return;

   for(int i=0; i<g_num_symbols; ++i)
   {
      string reason;
      FXRCUpdateExecutionQualitySampleForSymbol(i, reason);
   }
}

// Sorts a local double array in ascending order.
void FXRCSortDoubles(double &values[])
{
   int n = ArraySize(values);
   for(int i=0; i<n-1; ++i)
   {
      int best = i;
      for(int j=i+1; j<n; ++j)
      {
         if(values[j] < values[best])
            best = j;
      }

      if(best != i)
      {
         double tmp = values[i];
         values[i] = values[best];
         values[best] = tmp;
      }
   }
}

// Builds sorted spread samples for the current symbol/session context.
int FXRCCollectExecutionQualitySpreadSamples(const int symbol_idx, double &samples[])
{
   ArrayResize(samples, 0);
   if(symbol_idx < 0 || symbol_idx >= g_num_symbols)
      return 0;

   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();

   int session_idx = FXRCExecQualitySessionIndex(now);
   int state_idx = FXRCExecQualityStateIndex(symbol_idx, session_idx);
   int count = g_exec_quality_sample_count[state_idx];
   if(count <= 0)
      return 0;

   ArrayResize(samples, count);
   for(int i=0; i<count; ++i)
      samples[i] = g_exec_quality_spread_samples[FXRCExecQualitySampleIndex(state_idx, i)];

   FXRCSortDoubles(samples);
   return count;
}

// Returns a percentile from sorted spread samples.
double FXRCSpreadPercentile(const double &samples[], const double percentile)
{
   int count = ArraySize(samples);
   if(count <= 0)
      return 0.0;

   double clipped = Clip(percentile, 0.0, 1.0);
   int idx = (int)MathFloor(clipped * (double)(count - 1));
   idx = (int)Clip((double)idx, 0.0, (double)(count - 1));
   return samples[idx];
}

// Checks whether high-impact calendar events should block the pair.
bool FXRCExecutionCalendarBlackoutActiveForCurrency(const string currency,
                                                    const datetime now,
                                                    string &reason)
{
   reason = "";
   if(!InpExecQualityUseCalendarBlackout || MQLInfoInteger(MQL_TESTER))
      return false;

   MqlCalendarEvent events[];
   ResetLastError();
   int event_count = CalendarEventByCurrency(currency, events);
   if(event_count <= 0)
      return false;

   datetime from_time = now - MathMax(0, InpExecQualityNewsMinutesBefore) * 60;
   datetime to_time = now + MathMax(0, InpExecQualityNewsMinutesAfter) * 60;
   int checked = 0;
   for(int i=0; i<event_count && checked < 80; ++i)
   {
      if(events[i].importance != CALENDAR_IMPORTANCE_HIGH)
         continue;

      checked++;
      MqlCalendarValue values[];
      ResetLastError();
      int value_count = CalendarValueHistoryByEvent(events[i].id, values, from_time, to_time);
      if(value_count <= 0)
         continue;

      for(int v=0; v<value_count; ++v)
      {
         datetime event_time = CalendarValueRecordTime(values[v]);
         if(event_time >= from_time && event_time <= to_time)
         {
            reason = StringFormat(
               "news blackout for %s high-impact event %s",
               currency,
               events[i].event_code
            );
            return true;
         }
      }
   }

   return false;
}

// Checks whether a high-impact news blackout applies to the symbol.
bool FXRCExecutionCalendarBlackoutActive(const string symbol,
                                         const datetime now,
                                         string &reason)
{
   reason = "";
   if(!InpExecQualityUseCalendarBlackout)
      return false;

   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   if(FXRCExecutionCalendarBlackoutActiveForCurrency(base, now, reason))
      return true;
   if(FXRCExecutionCalendarBlackoutActiveForCurrency(quote, now, reason))
      return true;

   return false;
}

// Evaluates current execution conditions for a proposed entry.
bool FXRCEvaluateExecutionQuality(const int symbol_idx,
                                  const int dir,
                                  FXRCExecutionQualityDecision &decision)
{
   FXRCResetExecutionQualityDecision(decision);
   if(!InpUseExecutionQualityGovernor)
      return true;

   if(symbol_idx < 0 || symbol_idx >= g_num_symbols)
   {
      decision.allow_entry = false;
      decision.reason = "invalid execution-quality symbol index";
      return true;
   }

   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();

   if(FXRCIsRolloverWindow(now))
   {
      decision.allow_entry = false;
      decision.risk_multiplier = 0.0;
      decision.reason = "rollover window";
      return true;
   }

   string sample_reason = "";
   if(!FXRCUpdateExecutionQualitySampleForSymbol(symbol_idx, sample_reason))
   {
      decision.allow_entry = false;
      decision.risk_multiplier = 0.0;
      decision.reason = sample_reason;
      return true;
   }

   datetime quote_time = g_exec_quality_last_quote_time[symbol_idx];
   int stable_seconds = MathMax(0, InpExecQualityStableQuoteSeconds);
   int stale_limit = MathMax(5, stable_seconds * 3 + 5);
   if(quote_time > 0 && now - quote_time > stale_limit)
   {
      decision.allow_entry = false;
      decision.risk_multiplier = 0.0;
      decision.reason = "stale quote";
      return true;
   }

   datetime stable_since = g_exec_quality_stable_since[symbol_idx];
   if(stable_seconds > 0 && (stable_since <= 0 || now - stable_since < stable_seconds))
   {
      decision.allow_entry = false;
      decision.risk_multiplier = 0.0;
      decision.reason = "quote stability window not satisfied";
      return true;
   }

   string blackout_reason = "";
   if(FXRCExecutionCalendarBlackoutActive(g_symbols[symbol_idx], now, blackout_reason))
   {
      decision.allow_entry = false;
      decision.risk_multiplier = 0.0;
      decision.reason = blackout_reason;
      return true;
   }

   double samples[];
   int count = FXRCCollectExecutionQualitySpreadSamples(symbol_idx, samples);
   if(count < 20)
      return true;

   double current_spread = g_exec_quality_last_spread_points[symbol_idx];
   double median = FXRCSpreadPercentile(samples, 0.50);
   double high_percentile = FXRCSpreadPercentile(samples, InpExecQualityMaxSpreadPercentile);
   double elevated_percentile = FXRCSpreadPercentile(samples, 0.75);

   bool abnormal_by_percentile = current_spread > high_percentile + EPS();
   bool abnormal_by_multiple = (
      median > EPS()
      && current_spread > median * InpExecQualityAbnormalSpreadMultiple
   );

   if(abnormal_by_percentile || abnormal_by_multiple)
   {
      decision.allow_entry = false;
      decision.risk_multiplier = 0.0;
      decision.reason = StringFormat(
         "abnormal spread %.1f points exceeds context threshold %.1f",
         current_spread,
         MathMax(high_percentile, median * InpExecQualityAbnormalSpreadMultiple)
      );
      return true;
   }

   bool elevated = (
      current_spread > elevated_percentile + EPS()
      || (median > EPS() && current_spread > median * 1.50)
   );
   if(elevated)
   {
      decision.risk_multiplier = Clip(
         InpExecQualityElevatedCostRiskMultiplier,
         0.0,
         1.0
      );
      decision.reason = StringFormat(
         "elevated spread %.1f points versus median %.1f",
         current_spread,
         median
      );
   }

   return true;
}

// Performs a pre-trade execution-quality gate and logs blocking reasons.
bool FXRCExecutionQualityPreCheck(const int symbol_idx, const int dir)
{
   if(!InpUseExecutionQualityGovernor)
      return true;

   FXRCExecutionQualityDecision decision;
   FXRCEvaluateExecutionQuality(symbol_idx, dir, decision);
   if(!decision.allow_entry)
   {
      PrintFormat(
         "Skipping %s %s because execution quality is unacceptable: %s.",
         g_symbols[symbol_idx],
         (dir > 0 ? "long" : "short"),
         decision.reason
      );
      return false;
   }

   return true;
}

// Returns a bounded execution-quality risk multiplier for trade planning.
double FXRCExecutionQualityRiskMultiplier(const int symbol_idx,
                                          const int dir,
                                          string &reason)
{
   reason = "";
   if(!InpUseExecutionQualityGovernor)
      return 1.0;

   FXRCExecutionQualityDecision decision;
   FXRCEvaluateExecutionQuality(symbol_idx, dir, decision);
   reason = decision.reason;
   if(!decision.allow_entry)
      return 0.0;

   return Clip(decision.risk_multiplier, 0.0, 1.0);
}
