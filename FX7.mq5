//+------------------------------------------------------------------+
//|                                                          FX7.mq5 |
//| Regime-Conditioned Time-Series Momentum with Novelty Overlay     |
//| Multi-file multi-symbol EA for MetaTrader 5                      |
//+------------------------------------------------------------------+
#property strict
#property version   "7.00"

#include "FX7/Inputs/Inputs.mqh"
#include "FX7/TypesAndGlobals/TypesAndGlobals.mqh"
#include "FX7/MetaAllocation/MetaAllocation.mqh"
#include "FX7/CurrencyExposure/CurrencyExposure.mqh"
#include "FX7/ExecutionQuality/ExecutionQuality.mqh"
#include "FX7/CrossSectionalMomentum/CrossSectionalMomentum.mqh"
#include "FX7/MediumTermTrend/MediumTermTrend.mqh"
#include "FX7/ResearchExport/ResearchExport.mqh"
#include "FX7/ProbabilityModel/ProbabilityModel.mqh"
#include "FX7/ForwardCarry/ForwardCarry.mqh"
#include "FX7/RegimeState/RegimeState.mqh"
#include "FX7/Events/Events.mqh"
#include "FX7/TradeExecution/TradeExecution.mqh"
#include "FX7/Signals/Signals.mqh"
#include "FX7/FeaturePipeline/FeaturePipeline.mqh"
#include "FX7/MacroData/MacroData.mqh"
#include "FX7/Core/Core.mqh"

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
