//------------------------- Currency Factor Exposure Control -------------------------//

// Resets a currency-exposure check result.
void FXRCResetCurrencyExposureCheck(FXRCCurrencyExposureCheck &check)
{
   check.allowed = true;
   check.max_allowed_volume = 0.0;
   check.reason = "";
}

// Finds a currency exposure row.
int FXRCFindCurrencyExposureIndex(const string currency,
                                  const FXRCCurrencyExposure &exposures[])
{
   for(int i=0; i<ArraySize(exposures); ++i)
   {
      if(exposures[i].currency == currency)
         return i;
   }

   return -1;
}

// Adds a signed and gross EUR-equivalent amount to a currency exposure vector.
bool FXRCAddCurrencyExposure(FXRCCurrencyExposure &exposures[],
                             const string currency,
                             const double signed_amount,
                             string &reason)
{
   reason = "";
   string ccy = NormalizeCurrencyCode(currency);
   if(StringLen(ccy) != 3)
   {
      reason = "invalid currency code in exposure vector";
      return false;
   }

   double signed_eur = 0.0;
   if(!TryConvertCash(ccy, "EUR", signed_amount, signed_eur))
   {
      reason = StringFormat("currency exposure conversion unavailable from %s to EUR", ccy);
      return false;
   }

   int idx = FXRCFindCurrencyExposureIndex(ccy, exposures);
   if(idx < 0)
   {
      int new_size = ArraySize(exposures) + 1;
      ArrayResize(exposures, new_size);
      idx = new_size - 1;
      exposures[idx].currency = ccy;
      exposures[idx].net_eur = 0.0;
      exposures[idx].gross_eur = 0.0;
   }

   exposures[idx].net_eur += signed_eur;
   exposures[idx].gross_eur += MathAbs(signed_eur);
   return true;
}

// Adds the base/quote currency vector for an FX pair position.
bool FXRCAddPairCurrencyExposure(FXRCCurrencyExposure &exposures[],
                                 const string symbol,
                                 const int dir,
                                 const double volume,
                                 const double price,
                                 string &reason)
{
   reason = "";
   if(dir == 0 || volume <= EPS() || price <= EPS())
      return true;

   string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   double contract_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(StringLen(base) != 3 || StringLen(quote) != 3 || contract_size <= EPS())
   {
      reason = "currency exposure requires valid FX base/quote and contract size";
      return false;
   }

   double base_amount = (double)dir * volume * contract_size;
   double quote_amount = -(double)dir * volume * contract_size * price;
   if(!FXRCAddCurrencyExposure(exposures, base, base_amount, reason))
      return false;
   if(!FXRCAddCurrencyExposure(exposures, quote, quote_amount, reason))
      return false;

   return true;
}

// Adds a selected account position to the currency exposure vector.
bool FXRCAddSelectedPositionCurrencyExposure(FXRCCurrencyExposure &exposures[],
                                             string &reason)
{
   reason = "";
   string symbol = PositionGetString(POSITION_SYMBOL);
   if(!IsForexPositionSymbol(symbol))
      return true;

   if(!InpCurrencyExposureIncludeForeignPositions && !IsSelectedFXRCPosition())
      return true;

   int dir = PositionDirFromType(PositionGetInteger(POSITION_TYPE));
   double volume = PositionGetDouble(POSITION_VOLUME);
   double price = PositionGetDouble(POSITION_PRICE_CURRENT);
   if(price <= EPS())
   {
      MqlTick tick;
      double mid = 0.0;
      if(!GetMidPrice(symbol, tick, mid))
      {
         reason = StringFormat("currency exposure quote unavailable for %s", symbol);
         return false;
      }
      price = mid;
   }

   return FXRCAddPairCurrencyExposure(exposures, symbol, dir, volume, price, reason);
}

// Builds the current portfolio currency exposure vector.
bool FXRCBuildCurrentCurrencyExposure(FXRCCurrencyExposure &exposures[],
                                      string &reason)
{
   ArrayResize(exposures, 0);
   reason = "";

   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(!FXRCAddSelectedPositionCurrencyExposure(exposures, reason))
         return false;
   }

   return true;
}

// Returns whether a currency belongs to a simple editable bloc.
bool FXRCCurrencyInBloc(const string currency, const string bloc)
{
   if(bloc == "USD")
      return (currency == "USD");
   if(bloc == "EUROPE")
      return (currency == "EUR" || currency == "GBP" || currency == "CHF");
   if(bloc == "FUNDING_SAFE_HAVEN")
      return (currency == "JPY" || currency == "CHF");
   if(bloc == "COMMODITY")
      return (currency == "AUD" || currency == "NZD" || currency == "CAD");

   return false;
}

// Checks the exposure vector against configured currency-factor limits.
bool FXRCCurrencyExposureVectorAllowed(const FXRCCurrencyExposure &exposures[],
                                       string &reason)
{
   reason = "";
   string account_ccy = AccountInfoString(ACCOUNT_CURRENCY);
   double equity_eur = 0.0;
   if(!TryConvertCash(account_ccy, "EUR", AccountInfoDouble(ACCOUNT_EQUITY), equity_eur)
      || equity_eur <= EPS())
   {
      reason = "currency exposure equity conversion unavailable";
      return false;
   }

   double max_single_net = equity_eur * InpMaxNetSingleCurrencyExposurePct / 100.0;
   double max_single_gross = equity_eur * InpMaxGrossSingleCurrencyExposurePct / 100.0;
   double total_abs_net = 0.0;
   double max_abs_net = 0.0;

   for(int i=0; i<ArraySize(exposures); ++i)
   {
      double abs_net = MathAbs(exposures[i].net_eur);
      total_abs_net += abs_net;
      max_abs_net = MathMax(max_abs_net, abs_net);

      if(abs_net > max_single_net + EPS())
      {
         reason = StringFormat(
            "currency exposure cap reached: net %s %.2f EUR exceeds %.2f EUR",
            exposures[i].currency,
            abs_net,
            max_single_net
         );
         return false;
      }

      if(exposures[i].gross_eur > max_single_gross + EPS())
      {
         reason = StringFormat(
            "currency exposure cap reached: gross %s %.2f EUR exceeds %.2f EUR",
            exposures[i].currency,
            exposures[i].gross_eur,
            max_single_gross
         );
         return false;
      }
   }

   string blocs[4] = {"USD", "EUROPE", "FUNDING_SAFE_HAVEN", "COMMODITY"};
   double max_bloc_net = equity_eur * InpMaxCurrencyBlocNetExposurePct / 100.0;
   for(int b=0; b<ArraySize(blocs); ++b)
   {
      double bloc_net = 0.0;
      for(int i=0; i<ArraySize(exposures); ++i)
      {
         if(FXRCCurrencyInBloc(exposures[i].currency, blocs[b]))
            bloc_net += exposures[i].net_eur;
      }

      if(MathAbs(bloc_net) > max_bloc_net + EPS())
      {
         reason = StringFormat(
            "currency exposure cap reached: %s bloc net %.2f EUR exceeds %.2f EUR",
            blocs[b],
            MathAbs(bloc_net),
            max_bloc_net
         );
         return false;
      }
   }

   if(total_abs_net > EPS())
   {
      double concentration_pct = 100.0 * max_abs_net / total_abs_net;
      if(concentration_pct > InpMaxCurrencyFactorConcentrationPct + EPS())
      {
         reason = StringFormat(
            "currency factor concentration %.2f%% exceeds %.2f%%",
            concentration_pct,
            InpMaxCurrencyFactorConcentrationPct
         );
         return false;
      }
   }

   return true;
}

// Checks whether a proposed trade volume is allowed by currency exposure limits.
bool FXRCCurrencyExposureAllowsVolume(const int symbol_idx,
                                      const int dir,
                                      const double entry_price,
                                      const double volume,
                                      string &reason)
{
   reason = "";
   FXRCCurrencyExposure exposures[];
   if(!FXRCBuildCurrentCurrencyExposure(exposures, reason))
      return false;

   if(volume > EPS())
   {
      if(!FXRCAddPairCurrencyExposure(
         exposures,
         g_symbols[symbol_idx],
         dir,
         volume,
         entry_price,
         reason))
      {
         return false;
      }
   }

   return FXRCCurrencyExposureVectorAllowed(exposures, reason);
}

// Caps proposed volume by currency-factor exposure limits without ever increasing it.
bool FXRCLimitVolumeByCurrencyExposure(const int symbol_idx,
                                       const int dir,
                                       const double entry_price,
                                       double &cap_volume,
                                       string &reason)
{
   reason = "";
   if(!InpUseCurrencyFactorExposureControl)
      return true;
   if(symbol_idx < 0 || symbol_idx >= g_num_symbols || cap_volume <= EPS())
      return true;

   string full_reason = "";
   if(FXRCCurrencyExposureAllowsVolume(symbol_idx, dir, entry_price, cap_volume, full_reason))
      return true;

   string zero_reason = "";
   if(!FXRCCurrencyExposureAllowsVolume(symbol_idx, dir, entry_price, 0.0, zero_reason))
   {
      reason = (StringLen(zero_reason) > 0 ? zero_reason : full_reason);
      return false;
   }

   double lo = 0.0;
   double hi = cap_volume;
   for(int step=0; step<24; ++step)
   {
      double mid = 0.5 * (lo + hi);
      string mid_reason = "";
      if(FXRCCurrencyExposureAllowsVolume(symbol_idx, dir, entry_price, mid, mid_reason))
         lo = mid;
      else
         hi = mid;
   }

   if(lo <= EPS())
   {
      reason = (StringLen(full_reason) > 0 ? full_reason : "currency exposure cap reached");
      return false;
   }

   if(lo < cap_volume * 0.995)
   {
      PrintFormat(
         "Currency exposure reduced %s %s volume from %.2f to %.2f: %s.",
         g_symbols[symbol_idx],
         (dir > 0 ? "long" : "short"),
         cap_volume,
         lo,
         full_reason
      );
   }

   cap_volume = lo;
   return true;
}
