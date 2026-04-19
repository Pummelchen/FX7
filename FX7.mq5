//+------------------------------------------------------------------+
//|                                                          FX7.mq5 |
//| Regime-Conditioned Time-Series Momentum with Novelty Overlay     |
//| Multi-file multi-symbol EA for MetaTrader 5                      |
//+------------------------------------------------------------------+
#property strict
#property version   "7.00"

#include "src/FX7Inputs.mqh"
#include "src/FX7TypesAndGlobals.mqh"
#include "src/FX7Events.mqh"
#include "src/FX7TradeExecution.mqh"
#include "src/FX7Signals.mqh"
#include "src/FX7FeaturePipeline.mqh"
#include "src/FX7MacroData.mqh"
#include "src/FX7Core.mqh"

// Routes terminal initialization into the modular runtime implementation.
int OnInit()
{
   return FX7HandleInit();
}

// Routes tick processing into the modular runtime implementation.
void OnTick()
{
   FX7HandleTick();
}

// Routes deinitialization into the modular runtime implementation.
void OnDeinit(const int reason)
{
   FX7HandleDeinit(reason);
}

// Routes timer callbacks into the modular runtime implementation.
void OnTimer()
{
   FX7HandleTimer();
}

// Routes trade-transaction callbacks into the modular runtime implementation.
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   FX7HandleTradeTransaction(trans, request, result);
}
