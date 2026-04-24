//------------------------- Inputs -----------------------------------//
input group "=== Universe / Schedule ==="
input string             InpSymbols                   =
   "EURUSD,GBPUSD,USDJPY,AUDUSD,USDCAD,USDCHF,EURJPY,GBPJPY,EURGBP,AUDNZD";
input string             InpTradableSymbols           = "";
input ENUM_TIMEFRAMES    InpSignalTF                  = PERIOD_M15;
input bool               InpDebugStartupSequence      = false;
input bool               InpProcessCurrentClosedBarOnAttach = false;
input bool               InpRequireSynchronizedSignalBars = true;
input bool               InpAllowLong                 = true;
input bool               InpAllowShort                = true;
input int                InpMaxAcceptedSignals        = 5;
input int                InpMaxAccountOrders          = 5;

input group "=== FX Premia Composite ==="
input double             InpWeightMomentum            = 0.50;
input double             InpWeightCarry               = 0.25;
input double             InpWeightValue               = 0.25;
input bool               InpUseDynamicAllocator       = true;
enum ENUM_FXRC_CARRY_MODEL
{
   FXRC_CARRY_MODEL_BROKER_SWAP = 0,
   FXRC_CARRY_MODEL_RATE_DIFF = 1
};
enum ENUM_FXRC_VALUE_MODEL
{
   FXRC_VALUE_MODEL_PROXY = 0,
   FXRC_VALUE_MODEL_PPP = 1,
   FXRC_VALUE_MODEL_HYBRID = 2
};
input ENUM_FXRC_CARRY_MODEL InpCarryModel             = FXRC_CARRY_MODEL_RATE_DIFF;
input bool               InpCarryAllowBrokerFallback  = false;
input int                InpCarryMaxDataAgeDays       = 35;
input int                InpCarryReloadHours          = 12;
input ENUM_FXRC_VALUE_MODEL InpValueModel             = FXRC_VALUE_MODEL_PPP;
input ENUM_TIMEFRAMES    InpValueTF                   = PERIOD_D1;
input int                InpValueLookbackBars         = 252;
input int                InpValueHalfLifeBars         = 63;
input double             InpValueSignalScale          = 1.50;
input bool               InpPPPAllowProxyFallback     = false;
input int                InpPPPMaxDataAgeDays         = 92;
input int                InpPPPReloadHours            = 12;
input double             InpPPPGapScale               = 0.15;
input double             InpPPPBlendWeight            = 0.65;
input double             InpProxyBlendWeight          = 0.35;
input double             InpCarrySignalScale          = 0.04;
input double             InpAllocatorMomentumBoost    = 0.35;
input double             InpAllocatorValueBoost       = 0.25;
input double             InpAllocatorCarryVolPenalty  = 1.00;
input double             InpCarryVolCutoff            = 1.25;

input group "=== Trend Core ==="
input int                InpH1                        = 8;
input int                InpH2                        = 24;
input int                InpH3                        = 72;
input double             InpW1                        = 0.45;
input double             InpW2                        = 0.35;
input double             InpW3                        = 0.20;
input double             InpTanhScale                 = 2.0;
input int                InpERWindow                  = 12;
input int                InpBreakoutWindow            = 12;
input int                InpShortReversalWindow       = 4;

input group "=== Volatility / Regime ==="
input int                InpVolShortHalfLife          = 8;
input int                InpVolLongHalfLife           = 32;
input int                InpATRWindow                 = 14;
input double             InpGammaA                    = 0.8;
input double             InpGammaER                   = 0.8;
input double             InpGammaV                    = 0.6;
input double             InpGammaD                    = 0.4;
input double             InpV0                        = 1.50;
input double             InpGammaB                    = 0.5;
input double             InpGammaP                    = 0.4;
input double             InpVPanic                    = 1.80;

input group "=== Cost / Thresholds ==="
input double             InpBaseEntryThreshold        = 0.02;
input double             InpBaseExitThreshold         = 0.01;
input double             InpReversalThreshold         = 0.04;
input double             InpTheta0                    = 0.05;
input double             InpConfSlope                 = 6.0;
input double             InpAlphaSmooth               = 0.55;
input double             InpEtaCost                   = 0.05;
input double             InpEtaVol                    = 0.02;
input double             InpEtaBreakout               = 0.02;
input double             InpGammaCost                 = 0.50;
input double             InpAssumedRoundTripFeePct    = 0.00000;
input double             InpCommissionRoundTripPerLotEUR = 0.00;
input double             InpExpectedHoldingDays       = 5.0;

enum ENUM_FXRC_TRADE_MODEL
{
   FXRC_TRADE_MODEL_CLASSIC = 0,
   FXRC_TRADE_MODEL_MODERN = 1
};

input group "=== Trade Model / Sizing ==="
input ENUM_FXRC_TRADE_MODEL Trade_Model    = FXRC_TRADE_MODEL_CLASSIC;
input double             InpModernBaseTargetRiskPct = 0.20;
input double             InpModernMinTargetRiskPct  = 0.05;
input double             InpModernTargetATRPct      = 0.0060;
input double             InpModernVolAdjustMin      = 0.60;
input double             InpModernVolAdjustMax      = 1.60;
input double             InpModernCovariancePenaltyFloor = 0.50;
input double             InpModernForecastRiskATRScale   = 1.00;

input group "=== Meta Allocation Overlay ==="
input bool               InpUseMetaAllocator        = false;
input bool               InpMetaPersistStats        = true;
input int                InpMetaMinSamplesForThrottle = 25;
input int                InpMetaMinSamplesForBoost  = 50;
input int                InpMetaUpdateHalfLifeTrades = 250;
input double             InpMetaPriorWeight         = 30.0;
input double             InpMetaMinRiskMultiplier   = 0.0;
input double             InpMetaMaxRiskMultiplier   = 1.50;
input double             InpMetaNeutralRiskMultiplier = 1.0;
input double             InpMetaBadContextMultiplier = 0.50;
input double             InpMetaBlockBelowR         = -0.15;
input double             InpMetaBoostAboveR         = 0.10;
input double             InpMetaGain                = 0.75;
input double             InpMetaConservativeZ       = 0.75;
input int                InpMetaStatsFlushMinutes   = 10;

input group "=== Risk / Execution ==="
input long               InpMagicNumber              = 420004;
input double             InpClassicReferenceEURUSDLots       = 0.01;
input double             InpRiskPerTradePct           = 0.35;
input double             InpMaxPortfolioRiskPct       = 1.75;
input double             InpMaxPortfolioExposurePct   = 100.0;
input double             InpMaxMarginUsagePct         = 35.0;
input double             InpCatastrophicStopATR       = 3.0;
input double             InpClassicSinglePositionTakeProfitUSD = 5.0;
input double             InpClassicSessionResetProfitUSD     = 10.0;
input int                InpClassicUseTrailingStop              = 1;
input int                InpClassicTrailStartPct                = 50;
input int                InpClassicTrailSpacingPct              = 20;
input int                EAStopMinEqui                = 0;
input double             EAStopMaxDD                  = 0.0;
input double             InpMinConfidence             = 0.30;
input double             InpMinRegimeGate             = 0.02;
input double             InpHardMinRegimeGate         = 0.01;
input double             InpMinExecGate               = 0.02;
input int                InpPersistenceBars           = 1;
input int                InpSlippagePoints            = 20;
input int                InpTradeRetryCount           = 2;
input int                InpTradeVerifyAttempts       = 3;

input group "=== Currency Factor Exposure Control ==="
input bool               InpUseCurrencyFactorExposureControl = false;
input double             InpMaxNetSingleCurrencyExposurePct = 75.0;
input double             InpMaxGrossSingleCurrencyExposurePct = 125.0;
input double             InpMaxCurrencyBlocNetExposurePct = 150.0;
input double             InpMaxCurrencyFactorConcentrationPct = 65.0;
input bool               InpCurrencyExposureIncludeForeignPositions = false;

input group "=== Execution Quality Governor ==="
input bool               InpUseExecutionQualityGovernor = false;
input int                InpExecQualitySpreadLookbackSamples = 256;
input double             InpExecQualityMaxSpreadPercentile = 0.90;
input double             InpExecQualityAbnormalSpreadMultiple = 2.50;
input int                InpExecQualityStableQuoteSeconds = 3;
input int                InpExecQualityRolloverSkipMinutes = 10;
input double             InpExecQualityElevatedCostRiskMultiplier = 0.50;
input bool               InpExecQualityUseCalendarBlackout = false;
input int                InpExecQualityNewsMinutesBefore = 15;
input int                InpExecQualityNewsMinutesAfter = 15;

input group "=== Dependency Failure Policy ==="
input bool               InpFreezeEntriesOnDependencyFailure = true;
input bool               InpFlattenOnPersistentDependencyFailure = true;
input int                InpDependencyFailureGraceMinutes = 60;
input bool               InpDisableEAAfterEmergencyFlatten = true;

input group "=== Symbol Data Failure Handling ==="
input int                InpSymbolDataFailureGraceBars = 2;

input group "=== Correlation / Novelty Overlay ==="
input int                InpCorrLookback              = 40;
input double             InpShrinkageLambda           = 0.25;
input double             InpNoveltyFloorWeight        = 0.50;
input double             InpNoveltyCap                = 2.00;
input int                InpMinCandidatesForOrtho     = 2;
input double             InpUniquenessMin             = 0.15;
input double             InpCrowdingMax               = 0.90;
input double             InpFXOverlapFloor            = 0.35;
input double             InpClassOverlapFloor         = 0.20;
