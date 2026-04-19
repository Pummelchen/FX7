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
