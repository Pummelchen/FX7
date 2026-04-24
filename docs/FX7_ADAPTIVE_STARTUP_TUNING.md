# FX7 Adaptive Startup Tuning

FX7 includes a startup learner for practical trade-frequency control. It is designed to reduce manual model-parameter tuning without adding an opaque live ML model.

## What It Tunes

At EA initialization, `FX7/AdaptiveStartupTuning/AdaptiveStartupTuning.mqh` scans closed historical bars for the configured `InpSymbols` universe and estimates the recent distribution of closed-bar momentum opportunity scores. It then sets bounded runtime controls:

- entry-threshold multiplier
- exit-threshold multiplier
- reversal-threshold multiplier
- minimum confidence floor
- effective momentum/carry/value sleeve weights

The default profile is:

```text
InpStrategyProfile=FXRC_PROFILE_ACTIVE
InpUseStartupAutoCalibration=true
InpTargetTradesPerDay=6.0
InpCalibrationLookbackDays=90
```

## Why It Is Not Profit Training

The startup learner is unsupervised. It does not compute future returns, labels, PnL, Sharpe, drawdown, or win rate inside the EA. That is deliberate: short startup windows are too easy to overfit. Supervised probability research remains in the offline Python workflow and must be validated with walk-forward, purge, embargo, and costs.

## Profiles

- `FXRC_PROFILE_CONSERVATIVE`: closest to static multi-premia behavior.
- `FXRC_PROFILE_BALANCED`: moderate threshold relaxation and lighter macro sleeve use.
- `FXRC_PROFILE_ACTIVE`: higher opportunity supply, faster exits, lower confidence floor, and momentum-only effective sleeve mix.
- `FXRC_PROFILE_RESEARCH`: broad opportunity capture for feature export and diagnostics.

## Trade Count Limits

The learner can only make more already-qualified candidates available. It cannot bypass:

- `InpMaxAccountOrders`
- `InpMaxAcceptedSignals`
- portfolio risk and exposure caps
- margin caps
- broker minimum volume
- dependency failure policy
- execution quality and quote checks
- protective stop requirements

If the target is six trades per day but `InpMaxAccountOrders` is set below the
effective number of simultaneous positions implied by the holding period, the
account-order cap will dominate realized frequency. The default account and
accepted-signal caps are aligned with active mode at `10`, but they still need
to be raised deliberately for higher-throughput research profiles.

## Static Mode

To return to static input behavior:

```text
InpUseStartupAutoCalibration=false
```

Static mode uses the explicit weights, thresholds, and confidence floor from `Inputs.mqh`.
