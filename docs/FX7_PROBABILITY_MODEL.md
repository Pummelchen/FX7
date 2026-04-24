# FX7 Probability Model

The probability model is an optional live consumer of coefficients trained offline. FX7 does not train a live model and does not create future labels in the EA.

## Coefficient File

`InpProbabilityModelFile` points to a common-files CSV with this schema:

```csv
model_version,horizon_days,feature_name,coefficient,intercept_flag,optional_symbol,optional_base_currency,optional_quote_currency
1,5,intercept,-0.01,1,,,
1,5,momentum_score,0.12,0,,,
```

Supported features include:

```text
momentum_score
carry_score
value_score
xmom_score
medium_trend_score
realized_vol
vol_ratio
breakout_score_or_participation
efficiency_ratio
reversal_penalty
panic_gate_value
cost_long
cost_short
composite_raw
```

## Live Use

For BUY candidates, the filter requires `p_up >= 0.5 + InpProbabilityMinEdge`. For SELL candidates, it requires `p_up <= 0.5 - InpProbabilityMinEdge`. If `InpProbabilityBlockContradiction=true`, BUYs below 0.5 and SELLs above 0.5 are blocked.

Risk scaling is optional. If enabled, it maps `abs(p_up - 0.5)` into a bounded multiplier between `InpProbabilityMinRiskScale` and `InpProbabilityMaxRiskScale`. It can only scale an already-qualified candidate and remains below existing risk caps.

## Failure Behavior

If the model file is missing, malformed, incompatible with `InpProbabilityHorizonDays`, or has no applicable coefficients, FX7 logs the issue and leaves probability filtering neutral for that cycle.

## Interpretation

`p_up` is a calibrated directional estimate for the configured horizon. It is not a profitability estimate. Spread, slippage, swaps, execution failures, and turnover can destroy a small directional edge.
