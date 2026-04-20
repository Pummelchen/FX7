// Evaluates required dependency health.
bool EvaluateRequiredDependencyHealth(const datetime asof_time, string &scope, string &reason)
{
   scope = "";
   reason = "";

   string carry_reason;
   bool carry_ok = EvaluateCarryDependencyHealth(asof_time, carry_reason);
   if(CarrySignalRequiresExternalData())
      scope = "carry";

   string value_reason;
   bool value_ok = EvaluatePPPDependencyHealth(asof_time, value_reason);
   if(ValueSignalRequiresPPPData())
      scope = (StringLen(scope) > 0 ? scope + "+PPP" : "PPP");

   if(carry_ok && value_ok)
      return true;

   if(!carry_ok && !value_ok)
   {
      scope = "carry+PPP";
      reason = "carry: " + carry_reason + "; PPP: " + value_reason;
      return false;
   }

   if(!carry_ok)
   {
      scope = "carry";
      reason = carry_reason;
      return false;
   }

   scope = "PPP";
   reason = value_reason;
   return false;
}

// Returns whether the runtime requires carry or PPP dependencies.
bool DependenciesRequiredAtRuntime()
{
   return (CarrySignalRequiresExternalData() || ValueSignalRequiresPPPData());
}

// Evaluates PPP dependency health.
bool EvaluatePPPDependencyHealth(const datetime asof_time, string &reason)
{
   reason = "";
   if(!ValueSignalRequiresPPPData())
      return true;

   string coverage_reason;
   if(!ValidateRequiredPPPCoverage(coverage_reason))
   {
      reason = coverage_reason;
      return false;
   }

   for(int i=0; i<g_num_symbols; ++i)
   {
      double base_cpi = 0.0, quote_cpi = 0.0;
      datetime base_date = 0, quote_date = 0;
      if(!GetPPPRecordAtOrBefore(g_base_ccy[i], asof_time, base_cpi, base_date)
         || !GetPPPRecordAtOrBefore(g_quote_ccy[i], asof_time, quote_cpi, quote_date))
      {
         reason = StringFormat("PPP data missing at runtime for %s", g_symbols[i]);
         return false;
      }

      datetime macro_date = (datetime)MathMin((long)base_date, (long)quote_date);
      if(macro_date <= 0)
      {
         reason = StringFormat("PPP macro date is invalid for %s", g_symbols[i]);
         return false;
      }

      if((asof_time - macro_date) > (datetime)(InpPPPMaxDataAgeDays * 24 * 60 * 60))
      {
         reason = StringFormat("PPP data is stale for %s", g_symbols[i]);
         return false;
      }

      if(!GetPPPRecordAtOrBefore(g_base_ccy[i], macro_date, base_cpi, base_date)
         || !GetPPPRecordAtOrBefore(g_quote_ccy[i], macro_date, quote_cpi, quote_date))
      {
         reason = StringFormat("PPP date alignment failed for %s", g_symbols[i]);
         return false;
      }
   }

   return true;
}

// Evaluates carry dependency health.
bool EvaluateCarryDependencyHealth(const datetime asof_time, string &reason)
{
   reason = "";
   if(!CarrySignalRequiresExternalData())
      return true;

   string coverage_reason;
   if(!ValidateRequiredCarryCoverage(coverage_reason))
   {
      reason = coverage_reason;
      return false;
   }

   for(int i=0; i<g_num_symbols; ++i)
   {
      double base_rate = 0.0, quote_rate = 0.0;
      datetime base_date = 0, quote_date = 0;
      if(!GetCarryRecordAtOrBefore(g_base_ccy[i], asof_time, base_rate, base_date)
         || !GetCarryRecordAtOrBefore(g_quote_ccy[i], asof_time, quote_rate, quote_date))
      {
         reason = StringFormat("carry data missing at runtime for %s", g_symbols[i]);
         return false;
      }

      datetime macro_date = (datetime)MathMin((long)base_date, (long)quote_date);
      if(macro_date <= 0)
      {
         reason = StringFormat("carry macro date is invalid for %s", g_symbols[i]);
         return false;
      }

      if((asof_time - macro_date) > (datetime)(InpCarryMaxDataAgeDays * 24 * 60 * 60))
      {
         reason = StringFormat("carry data is stale for %s", g_symbols[i]);
         return false;
      }

      if(!GetCarryRecordAtOrBefore(g_base_ccy[i], macro_date, base_rate, base_date)
         || !GetCarryRecordAtOrBefore(g_quote_ccy[i], macro_date, quote_rate, quote_date))
      {
         reason = StringFormat("carry date alignment failed for %s", g_symbols[i]);
         return false;
      }
   }

   return true;
}

// Validates required PPP coverage.
bool ValidateRequiredPPPCoverage(string &reason)
{
   reason = "";
   if(!ValueSignalRequiresPPPData())
      return true;
   if(!EnsurePPPDataCache(false) || !g_ppp_cache.available)
   {
      reason = "required PPP data is unavailable";
      return false;
   }

   for(int i=0; i<g_num_symbols; ++i)
   {
      if(FindPPPCurrencyIndex(g_base_ccy[i]) < 0)
      {
         reason = StringFormat("missing PPP data for base currency %s", g_base_ccy[i]);
         return false;
      }
      if(FindPPPCurrencyIndex(g_quote_ccy[i]) < 0)
      {
         reason = StringFormat("missing PPP data for quote currency %s", g_quote_ccy[i]);
         return false;
      }
   }

   return true;
}

// Validates required carry coverage.
bool ValidateRequiredCarryCoverage(string &reason)
{
   reason = "";
   if(!CarrySignalRequiresExternalData())
      return true;
   if(!EnsureCarryDataCache(false) || !g_carry_cache.available)
   {
      reason = "required startup-built carry data is unavailable";
      return false;
   }

   for(int i=0; i<g_num_symbols; ++i)
   {
      if(FindCarryCurrencyIndex(g_base_ccy[i]) < 0)
      {
         reason = StringFormat("missing carry data for base currency %s", g_base_ccy[i]);
         return false;
      }
      if(FindCarryCurrencyIndex(g_quote_ccy[i]) < 0)
      {
         reason = StringFormat("missing carry data for quote currency %s", g_quote_ccy[i]);
         return false;
      }
   }

   return true;
}

// Ensures PPP data cache.
bool EnsurePPPDataCache(const bool force_log)
{
   if(!ValueModelUsesPPP())
      return true;

   datetime now = SafeNow();
   if(!g_ppp_cache.loaded)
      return LoadPPPDataCache(force_log);

   if(MQLInfoInteger(MQL_TESTER))
      return g_ppp_cache.available;

   int reload_seconds = MathMax(1, InpPPPReloadHours) * 3600;
   if(now > 0 && g_ppp_cache.last_load_time > 0 && (now - g_ppp_cache.last_load_time) < reload_seconds)
      return g_ppp_cache.available;

   return LoadPPPDataCache(force_log);
}

// Loads PPP data cache.
bool LoadPPPDataCache(const bool force_log)
{
   FXRCPPPCacheState previous = g_ppp_cache;
   g_ppp_cache.loaded = true;
   g_ppp_cache.last_load_time = SafeNow();
   g_ppp_cache.source_file = "startup:auto";

   string temp_ccy[];
   datetime temp_dates[];
   double temp_cpi[];
   ArrayResize(temp_ccy, 0);
   ArrayResize(temp_dates, 0);
   ArrayResize(temp_cpi, 0);

   bool used_fallback = false;
   string build_reason;
   if(!BuildPPPRecordsAtStartup(temp_ccy, temp_dates, temp_cpi, used_fallback, build_reason))
   {
      g_ppp_cache.reason = build_reason;
      if(previous.available)
      {
         g_ppp_cache.available = true;
         g_ppp_cache.last_success_time = previous.last_success_time;
         g_ppp_cache.record_count = previous.record_count;
         g_ppp_cache.currency_count = previous.currency_count;
         g_ppp_cache.source_file = previous.source_file;
      }
      if(force_log)
         Print(g_ppp_cache.reason);
      return g_ppp_cache.available;
   }

   SortPPPRecords(temp_ccy, temp_dates, temp_cpi);

   ArrayCopy(g_ppp_record_ccy, temp_ccy);
   ArrayCopy(g_ppp_record_date, temp_dates);
   ArrayCopy(g_ppp_record_cpi, temp_cpi);
   BuildPPPIndexFromRecords(g_ppp_record_ccy);

   g_ppp_cache.available = (ArraySize(g_ppp_record_ccy) > 0 && ArraySize(g_ppp_index_ccy) > 0);
   g_ppp_cache.last_success_time = g_ppp_cache.last_load_time;
   g_ppp_cache.record_count = ArraySize(g_ppp_record_ccy);
   g_ppp_cache.currency_count = ArraySize(g_ppp_index_ccy);
   g_ppp_cache.reason = "";
   g_ppp_cache.source_file = (used_fallback ? "startup:calendar+builtin" : "startup:calendar");

   if(force_log)
   {
      PrintFormat("FXRC PPP cache built during startup from %s with %d rows across %d currencies.",
                  g_ppp_cache.source_file, g_ppp_cache.record_count, g_ppp_cache.currency_count);
   }

   return g_ppp_cache.available;
}

// Ensures carry data cache.
bool EnsureCarryDataCache(const bool force_log)
{
   if(!CarryModelUsesExternal())
      return true;

   datetime now = SafeNow();
   if(!g_carry_cache.loaded)
      return LoadCarryDataCache(force_log);

   if(MQLInfoInteger(MQL_TESTER))
      return g_carry_cache.available;

   int reload_seconds = MathMax(1, InpCarryReloadHours) * 3600;
   if(now > 0 && g_carry_cache.last_load_time > 0 && (now - g_carry_cache.last_load_time) < reload_seconds)
      return g_carry_cache.available;

   return LoadCarryDataCache(force_log);
}

// Loads carry data cache.
bool LoadCarryDataCache(const bool force_log)
{
   FXRCCarryCacheState previous = g_carry_cache;
   g_carry_cache.loaded = true;
   g_carry_cache.last_load_time = SafeNow();
   g_carry_cache.source_file = "startup:auto";

   string temp_ccy[];
   datetime temp_dates[];
   double temp_rates[];
   ArrayResize(temp_ccy, 0);
   ArrayResize(temp_dates, 0);
   ArrayResize(temp_rates, 0);

   bool used_fallback = false;
   string build_reason;
   if(!BuildCarryRecordsAtStartup(temp_ccy, temp_dates, temp_rates, used_fallback, build_reason))
   {
      g_carry_cache.reason = build_reason;
      if(previous.available)
      {
         g_carry_cache.available = true;
         g_carry_cache.last_success_time = previous.last_success_time;
         g_carry_cache.record_count = previous.record_count;
         g_carry_cache.currency_count = previous.currency_count;
         g_carry_cache.source_file = previous.source_file;
      }
      if(force_log)
         Print(g_carry_cache.reason);
      return g_carry_cache.available;
   }

   SortPPPRecords(temp_ccy, temp_dates, temp_rates);

   ArrayCopy(g_carry_record_ccy, temp_ccy);
   ArrayCopy(g_carry_record_date, temp_dates);
   ArrayCopy(g_carry_record_rate, temp_rates);
   BuildCarryIndexFromRecords(g_carry_record_ccy);

   g_carry_cache.available = (ArraySize(g_carry_record_ccy) > 0 && ArraySize(g_carry_index_ccy) > 0);
   g_carry_cache.last_success_time = g_carry_cache.last_load_time;
   g_carry_cache.record_count = ArraySize(g_carry_record_ccy);
   g_carry_cache.currency_count = ArraySize(g_carry_index_ccy);
   g_carry_cache.reason = "";
   g_carry_cache.source_file = (used_fallback ? "startup:calendar+builtin" : "startup:calendar");

   if(force_log)
   {
      PrintFormat("FXRC carry cache built during startup from %s with %d rows across %d currencies.",
                  g_carry_cache.source_file, g_carry_cache.record_count, g_carry_cache.currency_count);
   }

   return g_carry_cache.available;
}

// Builds PPP records at startup.
bool BuildPPPRecordsAtStartup(string &temp_ccy[],
                              datetime &temp_dates[],
                              double &temp_cpi[],
                              bool &used_fallback,
                              string &reason)
{
   used_fallback = false;
   reason = "";

   string currencies[];
   if(CollectRequiredMacroCurrencies(currencies) <= 0)
   {
      reason = "no currencies are available to build PPP startup data";
      return false;
   }

   string failures = "";
   for(int i=0; i<ArraySize(currencies); ++i)
   {
      string currency = currencies[i];
      string currency_reason;
      if(BuildPPPCurrencySeriesFromCalendar(currency, temp_ccy, temp_dates, temp_cpi, currency_reason))
         continue;

      if(AppendFallbackPPPSeries(currency, temp_ccy, temp_dates, temp_cpi, currency_reason))
      {
         used_fallback = true;
         continue;
      }

      if(StringLen(failures) > 0)
         failures += "; ";
      failures += currency + ": " + currency_reason;
   }

   if(ArraySize(temp_ccy) <= 0)
   {
      reason = (StringLen(failures) > 0 ? failures : "PPP startup data build produced no rows");
      return false;
   }

   if(StringLen(failures) > 0)
   {
      reason = failures;
      return false;
   }

   return true;
}

// Builds carry records at startup.
bool BuildCarryRecordsAtStartup(string &temp_ccy[],
                                datetime &temp_dates[],
                                double &temp_rates[],
                                bool &used_fallback,
                                string &reason)
{
   used_fallback = false;
   reason = "";

   string currencies[];
   if(CollectRequiredMacroCurrencies(currencies) <= 0)
   {
      reason = "no currencies are available to build carry startup data";
      return false;
   }

   string failures = "";
   for(int i=0; i<ArraySize(currencies); ++i)
   {
      string currency = currencies[i];
      string currency_reason;
      if(BuildCarryCurrencySeriesFromCalendar(currency, temp_ccy, temp_dates, temp_rates, currency_reason))
         continue;

      if(AppendFallbackCarrySeries(currency, temp_ccy, temp_dates, temp_rates, currency_reason))
      {
         used_fallback = true;
         continue;
      }

      if(StringLen(failures) > 0)
         failures += "; ";
      failures += currency + ": " + currency_reason;
   }

   if(ArraySize(temp_ccy) <= 0)
   {
      reason = (StringLen(failures) > 0 ? failures : "carry startup data build produced no rows");
      return false;
   }

   if(StringLen(failures) > 0)
   {
      reason = failures;
      return false;
   }

   return true;
}

// Collects required macro currencies.
int CollectRequiredMacroCurrencies(string &currencies[])
{
   ArrayResize(currencies, 0);
   for(int i=0; i<g_num_symbols; ++i)
   {
      AppendCurrencyIfMissing(currencies, g_base_ccy[i]);
      AppendCurrencyIfMissing(currencies, g_quote_ccy[i]);
   }
   return ArraySize(currencies);
}

// Appends currency if missing.
void AppendCurrencyIfMissing(string &currencies[], const string currency)
{
   string normalized = NormalizeCurrencyCode(currency);
   if(StringLen(normalized) != 3)
      return;

   for(int i=0; i<ArraySize(currencies); ++i)
   {
      if(currencies[i] == normalized)
         return;
   }

   int new_size = ArraySize(currencies) + 1;
   ArrayResize(currencies, new_size);
   currencies[new_size - 1] = normalized;
}

// Builds carry currency series from calendar.
bool BuildCarryCurrencySeriesFromCalendar(const string currency,
                                          string &temp_ccy[],
                                          datetime &temp_dates[],
                                          double &temp_rates[],
                                          string &reason)
{
   reason = "";
   MqlCalendarEvent event;
   if(!SelectCalendarCarryEvent(currency, event, reason))
      return false;

   MqlCalendarValue values[];
   ResetLastError();
   int count = CalendarValueHistoryByEvent(event.id, values, BuildMacroHistoryStartTime(120), 0);
   if(count <= 0)
   {
      reason = StringFormat("calendar carry history unavailable for %s via %s err=%d", currency, event.event_code, GetLastError());
      return false;
   }

   datetime obs_months[];
   double monthly_rates[];
   ArrayResize(obs_months, 0);
   ArrayResize(monthly_rates, 0);

   for(int i=0; i<count; ++i)
   {
      double actual = 0.0;
      if(!ExtractCalendarActualValue(values[i], actual))
         continue;

      double normalized_rate = 0.0;
      if(!NormalizeCarryRateValue(actual, normalized_rate))
         continue;

      datetime record_time = CalendarValueRecordTime(values[i]);
      if(record_time <= 0)
         continue;

      UpsertMonthlyObservation(obs_months, monthly_rates, MacroMonthStart(record_time), normalized_rate);
   }

   if(ArraySize(obs_months) <= 0)
   {
      reason = StringFormat("calendar carry history has no usable actual values for %s via %s", currency, event.event_code);
      return false;
   }

   SortMonthlyObservations(obs_months, monthly_rates);
   if(!AppendCarrySeriesFromRateObservations(currency, obs_months, monthly_rates, temp_ccy, temp_dates, temp_rates, reason))
      return false;

   return true;
}

// Builds PPP currency series from calendar.
bool BuildPPPCurrencySeriesFromCalendar(const string currency,
                                        string &temp_ccy[],
                                        datetime &temp_dates[],
                                        double &temp_cpi[],
                                        string &reason)
{
   reason = "";
   MqlCalendarEvent event;
   if(!SelectCalendarPPPEvent(currency, event, reason))
      return false;

   MqlCalendarValue values[];
   ResetLastError();
   int count = CalendarValueHistoryByEvent(event.id, values, BuildMacroHistoryStartTime(120), 0);
   if(count <= 0)
   {
      reason = StringFormat("calendar PPP history unavailable for %s via %s err=%d", currency, event.event_code, GetLastError());
      return false;
   }

   datetime obs_months[];
   double annual_rates[];
   ArrayResize(obs_months, 0);
   ArrayResize(annual_rates, 0);

   for(int i=0; i<count; ++i)
   {
      double actual = 0.0;
      if(!ExtractCalendarActualValue(values[i], actual))
         continue;
      if(actual < -99.0 || actual > 1000.0)
         continue;

      datetime record_time = CalendarValueRecordTime(values[i]);
      if(record_time <= 0)
         continue;

      UpsertMonthlyObservation(obs_months, annual_rates, MacroMonthStart(record_time), actual);
   }

   if(ArraySize(obs_months) < 2)
   {
      reason = StringFormat("calendar PPP history is insufficient for %s via %s", currency, event.event_code);
      return false;
   }

   SortMonthlyObservations(obs_months, annual_rates);
   if(!AppendPPPSeriesFromInflationRates(currency, obs_months, annual_rates, temp_ccy, temp_dates, temp_cpi, reason))
      return false;

   return true;
}

// Selects calendar carry event.
bool SelectCalendarCarryEvent(const string currency, MqlCalendarEvent &selected, string &reason)
{
   reason = "";
   MqlCalendarEvent events[];
   ResetLastError();
   int count = CalendarEventByCurrency(currency, events);
   if(count <= 0)
   {
      reason = StringFormat("calendar returned no carry events for %s err=%d", currency, GetLastError());
      return false;
   }

   int best_idx = -1;
   int best_score = -1;
   for(int i=0; i<count; ++i)
   {
      int score = ScoreCarryCalendarEvent(currency, events[i]);
      if(score > best_score)
      {
         best_score = score;
         best_idx = i;
      }
   }

   if(best_idx < 0)
   {
      reason = StringFormat("no suitable carry calendar event was found for %s", currency);
      return false;
   }

   selected = events[best_idx];
   return true;
}

// Selects calendar PPP event.
bool SelectCalendarPPPEvent(const string currency, MqlCalendarEvent &selected, string &reason)
{
   reason = "";
   MqlCalendarEvent events[];
   ResetLastError();
   int count = CalendarEventByCurrency(currency, events);
   if(count <= 0)
   {
      reason = StringFormat("calendar returned no PPP events for %s err=%d", currency, GetLastError());
      return false;
   }

   int best_idx = -1;
   int best_score = -1;
   for(int i=0; i<count; ++i)
   {
      int score = ScorePPPCalendarEvent(currency, events[i]);
      if(score > best_score)
      {
         best_score = score;
         best_idx = i;
      }
   }

   if(best_idx < 0)
   {
      reason = StringFormat("no suitable PPP calendar event was found for %s", currency);
      return false;
   }

   selected = events[best_idx];
   return true;
}

// Scores a carry calendar event for the requested currency.
int ScoreCarryCalendarEvent(const string currency, const MqlCalendarEvent &event)
{
   if(event.type != CALENDAR_TYPE_INDICATOR)
      return -1;
   if(event.sector != CALENDAR_SECTOR_MONEY)
      return -1;
   if(event.unit != CALENDAR_UNIT_PERCENT)
      return -1;

   string code = NormalizeCalendarToken(event.event_code);
   int score = 0;
   if(IsPreferredCarryEventCode(currency, code))
      score += 100;
   else if(StringFind(code, "interest-rate-decision") >= 0)
      score += 80;
   else if(StringFind(code, "rate-decision") >= 0)
      score += 70;
   else if(StringFind(code, "official-cash-rate") >= 0)
      score += 70;
   else if(StringFind(code, "policy-rate") >= 0)
      score += 60;
   else if(StringFind(code, "target-rate") >= 0)
      score += 55;
   else if(StringFind(code, "interest-rate") >= 0)
      score += 50;
   else if(StringFind(code, "deposit-rate") >= 0 && currency == "EUR")
      score += 40;
   else
      return -1;

   if(event.importance == CALENDAR_IMPORTANCE_HIGH)
      score += 25;
   else if(event.importance == CALENDAR_IMPORTANCE_MODERATE)
      score += 10;

   return score;
}

// Scores a PPP calendar event for the requested currency.
int ScorePPPCalendarEvent(const string currency, const MqlCalendarEvent &event)
{
   if(event.type != CALENDAR_TYPE_INDICATOR)
      return -1;
   if(event.sector != CALENDAR_SECTOR_PRICES)
      return -1;
   if(event.unit != CALENDAR_UNIT_PERCENT)
      return -1;

   string code = NormalizeCalendarToken(event.event_code);
   if(StringFind(code, "ppi") >= 0)
      return -1;

   int score = 0;
   if(IsPreferredPPPEventCode(currency, code))
      score += 100;
   else if(StringFind(code, "cpi-yy") >= 0 && StringFind(code, "core") < 0)
      score += 85;
   else if(currency == "USD" && StringFind(code, "pce-price-index-yy") >= 0 && StringFind(code, "core") < 0)
      score += 80;
   else if(StringFind(code, "hicp-yy") >= 0 && StringFind(code, "core") < 0)
      score += 78;
   else if(StringFind(code, "inflation-rate-yy") >= 0)
      score += 72;
   else if(StringFind(code, "cpi") >= 0 && StringFind(code, "yy") >= 0 && StringFind(code, "core") < 0)
      score += 68;
   else if(StringFind(code, "core-cpi") >= 0 || StringFind(code, "core-hicp") >= 0 || StringFind(code, "core-pce-price-index-yy") >= 0)
      score += 55;
   else
      return -1;

   if(event.frequency == CALENDAR_FREQUENCY_MONTH)
      score += 10;
   else if(event.frequency == CALENDAR_FREQUENCY_QUARTER)
      score += 5;

   if(event.importance == CALENDAR_IMPORTANCE_HIGH)
      score += 15;
   else if(event.importance == CALENDAR_IMPORTANCE_MODERATE)
      score += 8;

   return score;
}

// Returns whether the calendar event code is preferred for carry data.
bool IsPreferredCarryEventCode(const string currency, const string code)
{
   string ccy = NormalizeCurrencyCode(currency);
   if(ccy == "EUR")
      return (code == "ecb-interest-rate-decision" || code == "ecb-deposit-rate-decision");
   if(ccy == "USD")
      return (code == "fed-interest-rate-decision" || code == "federal-funds-rate");
   if(ccy == "GBP")
      return (code == "boe-interest-rate-decision");
   if(ccy == "JPY")
      return (code == "boj-interest-rate-decision");
   if(ccy == "AUD")
      return (code == "rba-interest-rate-decision");
   if(ccy == "CAD")
      return (code == "boc-interest-rate-decision");
   if(ccy == "CHF")
      return (code == "snb-interest-rate-decision");
   if(ccy == "NZD")
      return (code == "rbnz-interest-rate-decision" || code == "official-cash-rate");
   if(ccy == "NOK")
      return (code == "norges-bank-interest-rate-decision");
   if(ccy == "SEK")
      return (code == "riksbank-interest-rate-decision");
   return false;
}

// Returns whether the calendar event code is preferred for PPP data.
bool IsPreferredPPPEventCode(const string currency, const string code)
{
   string ccy = NormalizeCurrencyCode(currency);
   if(ccy == "USD")
      return (code == "cpi-yy");
   if(ccy == "EUR")
      return (code == "cpi-yy" || code == "hicp-yy");
   if(ccy == "GBP")
      return (code == "cpi-yy");
   if(ccy == "JPY")
      return (code == "national-cpi-yy" || code == "cpi-yy");
   if(ccy == "AUD" || ccy == "CAD" || ccy == "CHF" || ccy == "NZD" || ccy == "SEK" || ccy == "NOK")
      return (code == "cpi-yy");
   return false;
}

// Extracts the best available actual calendar value.
bool ExtractCalendarActualValue(const MqlCalendarValue &value, double &actual)
{
   actual = 0.0;
   if(value.HasActualValue())
      actual = value.GetActualValue();
   else if(value.HasRevisedValue())
      actual = value.GetRevisedValue();
   else if(value.HasPreviousValue())
      actual = value.GetPreviousValue();
   else
      return false;

   return (actual == actual);
}

// Returns the effective record time for a calendar value.
datetime CalendarValueRecordTime(const MqlCalendarValue &value)
{
   datetime epoch_guard = D'1971.01.01';
   // Calendar history queries and freshness checks operate on trade-server event times.
   // Use the release timestamp as the availability key to avoid leaking inflation or
   // rate observations into the series before the calendar actually published them.
   if(value.time > epoch_guard)
      return value.time;
   return value.period;
}

// Builds the start time for macro-history requests.
datetime BuildMacroHistoryStartTime(const int months_back)
{
   datetime now = SafeNow();
   if(now <= 0)
      now = TimeCurrent();
   if(now <= 0)
      now = TimeLocal();
   return AddMonthsToDate(MacroMonthStart(now), -MathMax(months_back, 24));
}

// Returns the month-start timestamp for the supplied datetime.
datetime MacroMonthStart(const datetime when)
{
   MqlDateTime tm;
   TimeToStruct(when, tm);
   tm.day = 1;
   tm.hour = 0;
   tm.min = 0;
   tm.sec = 0;
   return StructToTime(tm);
}

// Adds a month offset to a month-aligned timestamp.
datetime AddMonthsToDate(const datetime when, const int offset)
{
   MqlDateTime tm;
   TimeToStruct(MacroMonthStart(when), tm);

   int months = tm.mon + offset;
   while(months > 12)
   {
      months -= 12;
      tm.year++;
   }
   while(months < 1)
   {
      months += 12;
      tm.year--;
   }

   tm.mon = months;
   tm.day = 1;
   tm.hour = 0;
   tm.min = 0;
   tm.sec = 0;
   return StructToTime(tm);
}

// Appends macro record.
void AppendMacroRecord(string &ccy[],
                       datetime &dates[],
                       double &values[],
                       const string currency,
                       const datetime record_date,
                       const double record_value)
{
   int new_size = ArraySize(ccy) + 1;
   ArrayResize(ccy, new_size);
   ArrayResize(dates, new_size);
   ArrayResize(values, new_size);
   ccy[new_size - 1] = NormalizeCurrencyCode(currency);
   dates[new_size - 1] = record_date;
   values[new_size - 1] = record_value;
}

// Upserts monthly observation.
void UpsertMonthlyObservation(datetime &months[], double &values[], const datetime month_start, const double value)
{
   for(int i=0; i<ArraySize(months); ++i)
   {
      if(months[i] == month_start)
      {
         values[i] = value;
         return;
      }
   }

   int new_size = ArraySize(months) + 1;
   ArrayResize(months, new_size);
   ArrayResize(values, new_size);
   months[new_size - 1] = month_start;
   values[new_size - 1] = value;
}

// Sorts monthly observations.
void SortMonthlyObservations(datetime &months[], double &values[])
{
   int n = ArraySize(months);
   for(int i=0; i<n-1; ++i)
   {
      int best = i;
      for(int j=i+1; j<n; ++j)
      {
         if(months[j] < months[best])
            best = j;
      }

      if(best != i)
      {
         datetime month_tmp = months[i];
         months[i] = months[best];
         months[best] = month_tmp;

         double value_tmp = values[i];
         values[i] = values[best];
         values[best] = value_tmp;
      }
   }
}

// Appends carry series from rate observations.
bool AppendCarrySeriesFromRateObservations(const string currency,
                                           const datetime &months[],
                                           const double &monthly_rates[],
                                           string &temp_ccy[],
                                           datetime &temp_dates[],
                                           double &temp_rates[],
                                           string &reason)
{
   reason = "";
   int total = ArraySize(months);
   if(total <= 0)
   {
      reason = StringFormat("no carry observations are available for %s", currency);
      return false;
   }

   datetime stop = MacroMonthStart(SafeNow());
   if(stop <= 0)
      stop = MacroMonthStart(TimeCurrent());
   if(stop <= 0)
      stop = months[total - 1];

   datetime cursor = months[0];
   double active_rate = monthly_rates[0];
   AppendMacroRecord(temp_ccy, temp_dates, temp_rates, currency, cursor, active_rate);

   for(int i=1; i<total; ++i)
   {
      datetime target = months[i];
      datetime next_month = AddMonthsToDate(cursor, 1);
      while(next_month < target)
      {
         cursor = next_month;
         AppendMacroRecord(temp_ccy, temp_dates, temp_rates, currency, cursor, active_rate);
         next_month = AddMonthsToDate(cursor, 1);
      }

      cursor = target;
      active_rate = monthly_rates[i];
      AppendMacroRecord(temp_ccy, temp_dates, temp_rates, currency, cursor, active_rate);
   }

   datetime next_month = AddMonthsToDate(cursor, 1);
   while(next_month <= stop)
   {
      cursor = next_month;
      AppendMacroRecord(temp_ccy, temp_dates, temp_rates, currency, cursor, active_rate);
      next_month = AddMonthsToDate(cursor, 1);
   }

   return true;
}

// Appends PPP series from inflation rates.
bool AppendPPPSeriesFromInflationRates(const string currency,
                                       const datetime &months[],
                                       const double &annual_rates[],
                                       string &temp_ccy[],
                                       datetime &temp_dates[],
                                       double &temp_cpi[],
                                       string &reason)
{
   reason = "";
   int total = ArraySize(months);
   if(total <= 0)
   {
      reason = StringFormat("no PPP inflation observations are available for %s", currency);
      return false;
   }

   double index_value = 100.0;
   datetime cursor = months[0];
   AppendMacroRecord(temp_ccy, temp_dates, temp_cpi, currency, cursor, index_value);

   double active_annual_rate = annual_rates[0];
   for(int i=1; i<total; ++i)
   {
      datetime target = months[i];
      while(cursor < target)
      {
         cursor = AddMonthsToDate(cursor, 1);
         // Apply the newly observed month's inflation rate to that month instead of
         // lagging the update by one full step, which would shift the rebuilt CPI
         // path away from the explicit level history the old CSVs represented.
         double step_annual_rate = active_annual_rate;
         if(cursor >= target)
            step_annual_rate = annual_rates[i];

         index_value *= AnnualRateToMonthlyFactor(step_annual_rate);
         AppendMacroRecord(temp_ccy, temp_dates, temp_cpi, currency, cursor, index_value);
      }
      active_annual_rate = annual_rates[i];
   }

   return true;
}

// Converts an annual rate into a monthly compounding factor.
double AnnualRateToMonthlyFactor(const double annual_rate_pct)
{
   double annual_factor = 1.0 + annual_rate_pct / 100.0;
   annual_factor = MathMax(annual_factor, 0.01);
   return MathPow(annual_factor, 1.0 / 12.0);
}

// Appends fallback carry series.
bool AppendFallbackCarrySeries(const string currency,
                               string &temp_ccy[],
                               datetime &temp_dates[],
                               double &temp_rates[],
                               string &reason)
{
   reason = "";
   string ccy = NormalizeCurrencyCode(currency);
   if(!HasFallbackCurrencyProfile(ccy))
   {
      reason = "built-in carry fallback does not support this currency";
      return false;
   }

   datetime start = BuildMacroHistoryStartTime(72);
   datetime stop = MacroMonthStart(SafeNow());
   if(stop <= 0)
      stop = MacroMonthStart(TimeCurrent());
   if(stop <= 0)
      stop = start;

   for(datetime cursor = start; cursor <= stop; cursor = AddMonthsToDate(cursor, 1))
   {
      double normalized_rate = 0.0;
      if(!NormalizeCarryRateValue(FallbackCarryRatePct(ccy, cursor), normalized_rate))
         continue;
      AppendMacroRecord(temp_ccy, temp_dates, temp_rates, ccy, cursor, normalized_rate);
   }

   reason = "built-in carry fallback was used";
   return true;
}

// Appends fallback PPP series.
bool AppendFallbackPPPSeries(const string currency,
                             string &temp_ccy[],
                             datetime &temp_dates[],
                             double &temp_cpi[],
                             string &reason)
{
   reason = "";
   string ccy = NormalizeCurrencyCode(currency);
   if(!HasFallbackCurrencyProfile(ccy))
   {
      reason = "built-in PPP fallback does not support this currency";
      return false;
   }

   datetime start = BuildMacroHistoryStartTime(72);
   datetime stop = MacroMonthStart(SafeNow());
   if(stop <= 0)
      stop = MacroMonthStart(TimeCurrent());
   if(stop <= 0)
      stop = start;

   double index_value = 100.0;
   AppendMacroRecord(temp_ccy, temp_dates, temp_cpi, ccy, start, index_value);
   for(datetime cursor = AddMonthsToDate(start, 1); cursor <= stop; cursor = AddMonthsToDate(cursor, 1))
   {
      index_value *= AnnualRateToMonthlyFactor(FallbackPPPAnnualRatePct(ccy, cursor));
      AppendMacroRecord(temp_ccy, temp_dates, temp_cpi, ccy, cursor, index_value);
   }

   reason = "built-in PPP fallback was used";
   return true;
}

// Returns whether a built-in macro fallback profile exists for the currency.
bool HasFallbackCurrencyProfile(const string currency)
{
   return (currency == "USD" || currency == "EUR" || currency == "GBP" || currency == "JPY"
        || currency == "AUD" || currency == "CAD" || currency == "CHF" || currency == "NZD"
        || currency == "SEK" || currency == "NOK");
}

// Returns the built-in fallback carry rate for the requested date.
double FallbackCarryRatePct(const string currency, const datetime when)
{
   MqlDateTime tm;
   TimeToStruct(when, tm);
   int year = tm.year;

   if(currency == "USD")
   {
      if(year <= 2022) return 4.25;
      if(year == 2023) return 5.25;
      if(year == 2024) return 5.00;
      if(year == 2025) return 4.75;
      return 4.50;
   }
   if(currency == "EUR")
   {
      if(year <= 2022) return 2.50;
      if(year == 2023) return 4.00;
      if(year == 2024) return 3.00;
      if(year == 2025) return 2.50;
      return 2.25;
   }
   if(currency == "GBP")
   {
      if(year <= 2022) return 3.50;
      if(year == 2023) return 5.25;
      if(year == 2024) return 4.75;
      if(year == 2025) return 4.25;
      return 3.75;
   }
   if(currency == "JPY")
   {
      if(year <= 2022) return -0.10;
      if(year == 2023) return 0.10;
      if(year == 2024) return 0.25;
      if(year == 2025) return 0.40;
      return 0.50;
   }
   if(currency == "AUD")
   {
      if(year <= 2022) return 2.60;
      if(year == 2023) return 4.35;
      if(year == 2024) return 4.35;
      if(year == 2025) return 4.10;
      return 4.10;
   }
   if(currency == "CAD")
   {
      if(year <= 2022) return 4.25;
      if(year == 2023) return 5.00;
      if(year == 2024) return 4.00;
      if(year == 2025) return 3.25;
      return 2.75;
   }
   if(currency == "CHF")
   {
      if(year <= 2022) return 1.00;
      if(year == 2023) return 1.75;
      if(year == 2024) return 1.00;
      if(year == 2025) return 0.50;
      return 0.25;
   }
   if(currency == "NZD")
   {
      if(year <= 2022) return 4.25;
      if(year == 2023) return 5.50;
      if(year == 2024) return 5.50;
      if(year == 2025) return 4.50;
      return 3.50;
   }
   if(currency == "SEK")
   {
      if(year <= 2022) return 2.50;
      if(year == 2023) return 4.00;
      if(year == 2024) return 3.50;
      if(year == 2025) return 2.75;
      return 2.25;
   }
   if(currency == "NOK")
   {
      if(year <= 2022) return 2.75;
      if(year == 2023) return 4.50;
      if(year == 2024) return 4.50;
      if(year == 2025) return 4.50;
      return 4.25;
   }

   return 0.0;
}

// Returns the built-in fallback annual PPP inflation rate for the requested date.
double FallbackPPPAnnualRatePct(const string currency, const datetime when)
{
   MqlDateTime tm;
   TimeToStruct(when, tm);
   int year = tm.year;

   if(currency == "USD")
   {
      if(year <= 2022) return 6.5;
      if(year == 2023) return 4.1;
      if(year == 2024) return 3.1;
      if(year == 2025) return 2.8;
      return 2.6;
   }
   if(currency == "EUR")
   {
      if(year <= 2022) return 8.5;
      if(year == 2023) return 5.4;
      if(year == 2024) return 2.7;
      if(year == 2025) return 2.3;
      return 2.1;
   }
   if(currency == "GBP")
   {
      if(year <= 2022) return 9.1;
      if(year == 2023) return 7.4;
      if(year == 2024) return 3.6;
      if(year == 2025) return 2.8;
      return 2.5;
   }
   if(currency == "JPY")
   {
      if(year <= 2022) return 2.3;
      if(year == 2023) return 3.2;
      if(year == 2024) return 2.7;
      if(year == 2025) return 2.1;
      return 1.9;
   }
   if(currency == "AUD")
   {
      if(year <= 2022) return 6.8;
      if(year == 2023) return 5.2;
      if(year == 2024) return 3.4;
      if(year == 2025) return 2.9;
      return 2.7;
   }
   if(currency == "CAD")
   {
      if(year <= 2022) return 6.9;
      if(year == 2023) return 3.9;
      if(year == 2024) return 2.8;
      if(year == 2025) return 2.5;
      return 2.3;
   }
   if(currency == "CHF")
   {
      if(year <= 2022) return 3.0;
      if(year == 2023) return 2.1;
      if(year == 2024) return 1.6;
      if(year == 2025) return 1.3;
      return 1.1;
   }
   if(currency == "NZD")
   {
      if(year <= 2022) return 7.2;
      if(year == 2023) return 5.9;
      if(year == 2024) return 4.1;
      if(year == 2025) return 3.2;
      return 2.8;
   }
   if(currency == "SEK")
   {
      if(year <= 2022) return 8.1;
      if(year == 2023) return 6.4;
      if(year == 2024) return 3.9;
      if(year == 2025) return 2.7;
      return 2.3;
   }
   if(currency == "NOK")
   {
      if(year <= 2022) return 5.8;
      if(year == 2023) return 5.5;
      if(year == 2024) return 4.0;
      if(year == 2025) return 3.0;
      return 2.5;
   }

   return 2.5;
}

// Normalizes calendar token.
string NormalizeCalendarToken(const string value)
{
   string out = value;
   StringTrimLeft(out);
   StringTrimRight(out);
   StringToLower(out);
   return out;
}

// Normalizes carry rate value.
bool NormalizeCarryRateValue(const double raw_value, double &normalized_rate)
{
   normalized_rate = 0.0;
   double abs_value = MathAbs(raw_value);
   if(abs_value <= EPS())
      return true;

   if(abs_value <= 100.0)
   {
      // Calendar carry events are filtered to percent units, so convert the
      // published percentage-point value into the annual fraction used by the
      // strategy. This keeps low-rate currencies such as JPY or CHF in the
      // correct scale instead of treating 0.25 as 25%.
      normalized_rate = raw_value / 100.0;
      return true;
   }

   return false;
}


// Gets the series close at or before the requested time.
bool GetSeriesCloseAtOrBefore(const string symbol,
                              const ENUM_TIMEFRAMES timeframe,
                              const datetime when,
                              double &close_price,
                              datetime &bar_time)
{
   close_price = 0.0;
   bar_time = 0;

   int shift = iBarShift(symbol, timeframe, when, false);
   if(shift < 0)
      return false;

   bar_time = iTime(symbol, timeframe, shift);
   if(bar_time <= 0)
      return false;

   close_price = iClose(symbol, timeframe, shift);
   return (close_price > 0.0);
}

// Gets the rolling value-anchor time for the symbol.
bool GetRollingValueAnchorTime(const string symbol, const datetime asof_time, datetime &anchor_time)
{
   anchor_time = 0;

   // Rebase PPP to the active value window instead of the oldest shared macro date.
   int bars_needed = InpValueLookbackBars + 5;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   ResetLastError();
   int copied = CopyRates(symbol, InpValueTF, asof_time, bars_needed, rates);
   if(copied < InpValueLookbackBars + 2)
      return false;

   int oldest_shift = MathMin(InpValueLookbackBars + 1, copied - 1);
   anchor_time = rates[oldest_shift].time;
   return (anchor_time > 0);
}

// Gets the first PPP record date for the currency.
bool GetPPPFirstRecordDate(const string currency, datetime &record_date)
{
   record_date = 0;
   int idx = FindPPPCurrencyIndex(currency);
   if(idx < 0)
      return false;

   int start = g_ppp_index_start[idx];
   if(start < 0 || start >= ArraySize(g_ppp_record_date))
      return false;

   record_date = g_ppp_record_date[start];
   return (record_date > 0);
}

// Gets the carry record at or before the requested time.
bool GetCarryRecordAtOrBefore(const string currency, const datetime asof_time, double &rate_value, datetime &record_date)
{
   rate_value = 0.0;
   record_date = 0;

   int idx = FindCarryCurrencyIndex(currency);
   if(idx < 0)
      return false;

   int start = g_carry_index_start[idx];
   int count = g_carry_index_count[idx];
   for(int i=start + count - 1; i>=start; --i)
   {
      if(g_carry_record_date[i] <= asof_time)
      {
         rate_value = g_carry_record_rate[i];
         record_date = g_carry_record_date[i];
         return true;
      }
   }

   return false;
}

// Gets the PPP record at or before the requested time.
bool GetPPPRecordAtOrBefore(const string currency, const datetime asof_time, double &cpi_value, datetime &record_date)
{
   cpi_value = 0.0;
   record_date = 0;

   int idx = FindPPPCurrencyIndex(currency);
   if(idx < 0)
      return false;

   int start = g_ppp_index_start[idx];
   int count = g_ppp_index_count[idx];
   for(int i=start + count - 1; i>=start; --i)
   {
      if(g_ppp_record_date[i] <= asof_time)
      {
         cpi_value = g_ppp_record_cpi[i];
         record_date = g_ppp_record_date[i];
         return (cpi_value > 0.0);
      }
   }

   return false;
}

// Finds carry currency index.
int FindCarryCurrencyIndex(const string currency)
{
   string needle = NormalizeCurrencyCode(currency);
   for(int i=0; i<ArraySize(g_carry_index_ccy); ++i)
   {
      if(g_carry_index_ccy[i] == needle)
         return i;
   }
   return -1;
}

// Finds PPP currency index.
int FindPPPCurrencyIndex(const string currency)
{
   string needle = NormalizeCurrencyCode(currency);
   for(int i=0; i<ArraySize(g_ppp_index_ccy); ++i)
   {
      if(g_ppp_index_ccy[i] == needle)
         return i;
   }
   return -1;
}

// Builds carry index from records.
void BuildCarryIndexFromRecords(const string &ccy[])
{
   ArrayResize(g_carry_index_ccy, 0);
   ArrayResize(g_carry_index_start, 0);
   ArrayResize(g_carry_index_count, 0);

   int total = ArraySize(ccy);
   if(total <= 0)
      return;

   int start = 0;
   while(start < total)
   {
      string currency = ccy[start];
      int count = 1;
      while(start + count < total && ccy[start + count] == currency)
         count++;

      int new_size = ArraySize(g_carry_index_ccy) + 1;
      ArrayResize(g_carry_index_ccy, new_size);
      ArrayResize(g_carry_index_start, new_size);
      ArrayResize(g_carry_index_count, new_size);
      g_carry_index_ccy[new_size - 1] = currency;
      g_carry_index_start[new_size - 1] = start;
      g_carry_index_count[new_size - 1] = count;

      start += count;
   }
}

// Builds PPP index from records.
void BuildPPPIndexFromRecords(const string &ccy[])
{
   ArrayResize(g_ppp_index_ccy, 0);
   ArrayResize(g_ppp_index_start, 0);
   ArrayResize(g_ppp_index_count, 0);

   int total = ArraySize(ccy);
   if(total <= 0)
      return;

   int start = 0;
   while(start < total)
   {
      string currency = ccy[start];
      int count = 1;
      while(start + count < total && ccy[start + count] == currency)
         count++;

      int new_size = ArraySize(g_ppp_index_ccy) + 1;
      ArrayResize(g_ppp_index_ccy, new_size);
      ArrayResize(g_ppp_index_start, new_size);
      ArrayResize(g_ppp_index_count, new_size);
      g_ppp_index_ccy[new_size - 1] = currency;
      g_ppp_index_start[new_size - 1] = start;
      g_ppp_index_count[new_size - 1] = count;

      start += count;
   }
}

// Sorts PPP records.
void SortPPPRecords(string &ccy[], datetime &dates[], double &values[])
{
   int n = ArraySize(ccy);
   for(int i=0; i<n-1; ++i)
   {
      int best = i;
      for(int j=i+1; j<n; ++j)
      {
         if(PPPRecordLess(ccy[j], dates[j], ccy[best], dates[best]))
            best = j;
      }

      if(best != i)
      {
         string ccy_tmp = ccy[i];
         ccy[i] = ccy[best];
         ccy[best] = ccy_tmp;

         datetime date_tmp = dates[i];
         dates[i] = dates[best];
         dates[best] = date_tmp;

         double value_tmp = values[i];
         values[i] = values[best];
         values[best] = value_tmp;
      }
   }
}

// Returns whether one PPP record sorts before another.
bool PPPRecordLess(const string ccy_a, const datetime date_a, const string ccy_b, const datetime date_b)
{
   if(ccy_a < ccy_b)
      return true;
   if(ccy_a > ccy_b)
      return false;
   return (date_a < date_b);
}

// Normalizes currency code.
string NormalizeCurrencyCode(const string value)
{
   string out = value;
   StringTrimLeft(out);
   StringTrimRight(out);
   StringToUpper(out);
   return out;
}

// Normalizes premia weights.
void NormalizePremiaWeights(double &w_m, double &w_c, double &w_v)
{
   double wsum = MathMax(w_m + w_c + w_v, EPS());
   w_m /= wsum;
   w_c /= wsum;
   w_v /= wsum;
}
