# FX7 Research Extensions

FX7 now includes disabled-by-default research extensions for small probabilistic FX edges. They are transparent overlays around the existing alpha engine. They do not create trades, bypass protective stops, or override portfolio/risk/margin/account caps.

## Modules

- `FX7/CrossSectionalMomentum/CrossSectionalMomentum.mqh`: estimates latent currency-strength momentum from the active pair universe and maps it back to pair scores.
- `FX7/MediumTermTrend/MediumTermTrend.mqh`: computes H4/D1 closed-bar trend scores for 1-day and 1-week directional context.
- `FX7/ResearchExport/ResearchExport.mqh`: writes ex-ante feature snapshots for offline modeling.
- `FX7/ProbabilityModel/ProbabilityModel.mqh`: consumes an offline-trained logistic coefficient CSV and computes calibrated `P(UP)`.
- `FX7/ForwardCarry/ForwardCarry.mqh`: adds optional forward-points carry input support with stale-data checks and fallbacks.
- `FX7/RegimeState/RegimeState.mqh`: computes simple current-information regime probabilities for trend-friendly, choppy, and stress states.

## Default Behavior

All trading-impacting extensions are off by default or have zero composite weight by default:

```text
InpUseCrossSectionalMomentum=false
InpXMomCompositeWeight=0.0
InpUseMediumTermTrend=false
InpMediumTrendCompositeWeight=0.0
InpUseProbabilityModel=false
InpUseForwardPointsCarry=false
InpUseRegimeStateFilter=false
```

Feature export is also disabled by default and is logging-only when enabled.

## Example Modes

Conservative OHLC-only mode:

```text
InpUseMediumTermTrend=true
InpMediumTrendCompositeWeight=0.10
InpUseCrossSectionalMomentum=true
InpXMomCompositeWeight=0.10
InpUseProbabilityModel=false
```

Research-export mode:

```text
InpUseResearchFeatureExport=true
InpResearchExportCandidatesOnly=false
InpResearchExportIncludeNonCandidates=true
InpUseProbabilityModel=false
```

Probability-filter mode:

```text
InpUseProbabilityModel=true
InpProbabilityUseAsFilter=true
InpProbabilityUseAsRiskScaler=false
InpProbabilityMinEdge=0.03
InpProbabilityBlockContradiction=true
```

Carry-enhanced mode:

```text
InpUseForwardPointsCarry=true
InpCarryModel=FXRC_CARRY_MODEL_HYBRID_BEST_AVAILABLE
InpCarryFallbackToRateDifferential=true
InpCarryFallbackToBrokerSwap=true
```

## Safety Notes

Use closed bars only. Do not train on full-sample normalized features. Do not evaluate overlapping 5-day labels without purge and embargo. Treat `P(UP)` as a calibrated directional estimate, not a profit forecast. Small directional edges can disappear after spread, slippage, swaps, and turnover.
