# FX7

`FX7` is a multi-symbol MetaTrader 5 Expert Advisor for FX portfolio trading on closed-bar signals. It combines trend, carry, and value inputs with portfolio-level diversification, execution gating, and fail-safe runtime controls.

## Benefits

- Multi-factor alpha instead of single-indicator trading. FX7 blends time-series trend, carry, and a reliability-scaled value sleeve.
- Better portfolio construction. Dynamic allocation, correlation shrinkage, novelty orthogonalization, crowding limits, and persistence filters reduce redundant trades.
- Stronger risk controls. Regime gating, panic gating, cost gating, catastrophic stops, account/order caps, and margin/risk limits are enforced before entries are sent.
- Safer live operation. Event-assisted trade-state verification, dependency failure policies, stale-data isolation, synchronized bar processing, and a no-trade-on-attach option make live deployment less fragile.
- Cleaner execution quality. Retry logic refreshes both quote and protective stop, not just the entry price, so risk geometry stays closer to plan during fast moves.
- Better behavior under degraded data. Carry/PPP dependencies are rebuilt in memory at EA startup and can freeze entries, flatten exposure, or continue with stale inputs based on explicit policy settings.

## Strategy Summary

- Signal timeframe: `InpSignalTF` default `M15`
- Alpha sleeves: momentum, carry, value
- Macro sleeve role: carry and PPP/value are slower contextual inputs than the default intraday signal horizon, so momentum drives most short-horizon timing while macro sleeves bias ranking and conviction
- Portfolio overlay: panic gate, correlation shrinkage, novelty ranking, uniqueness and crowding filters
- Execution model: one managed position per symbol, closed-bar signal generation, immediate protective-stop enforcement, and accepted-target execution in rank priority order
- Trade styles: `Classic` and `Modern`

## Repository Contents

- [FX7.mq5](https://github.com/Pummelchen/FX7/blob/main/FX7.mq5): thin entry wrapper that includes the modular source tree
- `FX7/Inputs/Inputs.mqh`: all `input` parameters and public EA enums
- `FX7/TypesAndGlobals/TypesAndGlobals.mqh`: shared structs, cache state, globals, and runtime layout notes
- `FX7/MetaAllocation/MetaAllocation.mqh`: optional realized-R context learner and candidate/risk scaler
- `FX7/CurrencyExposure/CurrencyExposure.mqh`: optional currency-factor exposure vector and concentration limiter
- `FX7/ExecutionQuality/ExecutionQuality.mqh`: optional spread, rollover, quote-stability, and news blackout governor
- `FX7/AdaptiveStartupTuning/AdaptiveStartupTuning.mqh`: startup profile learner that calibrates trade-frequency thresholds, confidence floor, turnover, and sleeve weights from closed-bar history
- `FX7/CrossSectionalMomentum/CrossSectionalMomentum.mqh`: optional latent currency-strength momentum sleeve
- `FX7/MediumTermTrend/MediumTermTrend.mqh`: optional H4/D1 closed-bar trend sleeve for 1-day and 1-week context
- `FX7/ResearchExport/ResearchExport.mqh`: optional ex-ante feature snapshot export for offline validation
- `FX7/ProbabilityModel/ProbabilityModel.mqh`: optional calibrated logistic probability-model consumer
- `FX7/ForwardCarry/ForwardCarry.mqh`: optional forward-points carry support with stale-data controls
- `FX7/RegimeState/RegimeState.mqh`: optional filtered trend/chop/stress regime-state layer
- `FX7/Events/Events.mqh`: `OnInit`, `OnTick`, `OnTimer`, `OnTradeTransaction`, and runtime orchestration
- `FX7/TradeExecution/TradeExecution.mqh`: trade planning, request construction, send/retry, and verification logic
- `FX7/Signals/Signals.mqh`: portfolio ranking, novelty, crowding, and candidate selection
- `FX7/FeaturePipeline/FeaturePipeline.mqh`: symbol-level feature computation, value/carry integration, and sleeve blending
- `FX7/MacroData/MacroData.mqh`: startup-built carry/PPP cache creation, dependency health, and macro lookup helpers
- `FX7/Core/Core.mqh`: validation, reset helpers, conversions, and shared utility functions
- `research/`: offline feature labeling, walk-forward validation, and logistic probability-model training tools

## Data Requirements

FX7 can run with different dependency profiles:

- Pure momentum mode: no macro dependency required
- Carry mode: when the carry sleeve has a positive weight and uses rate differentials, the EA builds an in-memory rate-differential cache during startup
- PPP or hybrid value mode: when the value sleeve has a positive weight and the selected value model uses PPP, the EA builds an in-memory CPI/PPP cache during startup
- Optional forward-points carry: when `InpUseForwardPointsCarry=true`, FX7 can read `InpForwardPointsFile` from common terminal files and rejects stale rows via `InpForwardPointsMaxStaleDays`
- Optional probability filtering: when `InpUseProbabilityModel=true`, FX7 reads an offline-trained coefficient CSV from `InpProbabilityModelFile`

The baseline EA no longer requires external CSV files for carry/PPP macro dependencies. At startup the EA:

- pulls economic-calendar history for the currencies used by `InpSymbols`
- preserves calendar release timestamps so macro values are only available after publication
- reshapes carry into a forward-filled series and PPP into a CPI-style index path
- falls back to built-in major-currency profiles if calendar data is missing
- keeps the existing dependency health checks, freeze/flatten policy, and freshness controls

The optional forward-points, research-export, and probability-model files are explicit research/operator inputs. They are disabled by default and do not affect baseline behavior unless enabled.

If you enable carry or PPP modes for currencies that are neither covered by the terminal economic calendar nor the built-in fallback profiles, FX7 will treat that as a dependency failure and apply the configured runtime policy.

Built-in carry/PPP fallback profiles are a safety net, not a substitute for calendar-backed macro history. For live use, prefer calendar coverage and treat fallback-backed macro sleeves as degraded-quality inputs that deserve explicit review.

`InpMaxAccountOrders` is enforced against all currently open account positions plus pending orders, not just FX7-owned trades.

## Strategy Profile And Startup Learning

FX7 now starts in `FXRC_PROFILE_ACTIVE` with `InpUseStartupAutoCalibration=true`. At initialization the EA scans recent closed bars across the tradable universe and calibrates a bounded operating profile:

- entry-threshold multiplier
- exit-threshold multiplier
- reversal-threshold multiplier
- minimum confidence floor
- effective momentum/carry/value sleeve weights

The startup learner is intentionally unsupervised. It calibrates opportunity supply and trade-frequency pressure from historical score distributions; it does not train on future returns or claim profitability. The default active profile tilts the live model toward faster momentum-driven trading and sets carry/value weights to zero, which also avoids slow macro dependencies unless the user selects a slower profile or disables auto-calibration.

Useful controls:

```text
InpStrategyProfile=FXRC_PROFILE_ACTIVE
InpUseStartupAutoCalibration=true
InpTargetTradesPerDay=6.0
InpCalibrationLookbackDays=90
```

The default accepted-signal and account-order caps are `10`, so active mode is
not immediately capped by a five-order ceiling before risk, margin, exposure,
execution, and broker constraints are evaluated.

Profiles:

- `FXRC_PROFILE_CONSERVATIVE`: closest to static multi-premia behavior.
- `FXRC_PROFILE_BALANCED`: moderate threshold relaxation and lighter macro sleeve use.
- `FXRC_PROFILE_ACTIVE`: higher trade-frequency target, lower confidence floor, faster exits, momentum-only sleeve mix.
- `FXRC_PROFILE_RESEARCH`: broad opportunity capture for research and diagnostics.

The learner cannot bypass hard safety controls. If `InpMaxAccountOrders`, `InpMaxAcceptedSignals`, portfolio risk, margin, exposure, broker minimum volume, dependency shutdown, or execution checks block entries, those blocks still dominate. For materially higher realized trade counts, `InpMaxAccountOrders` and risk/exposure budgets must be consistent with the requested target trade rate.

Set `InpUseStartupAutoCalibration=false` to return to static input behavior.

## Optional Adaptive Overlays

FX7 includes three disabled-by-default overlays that can scale, suppress, throttle, or conservatively reweight already-qualified candidates. They do not create signals and they do not bypass hard stops, dependency policy, account caps, margin/risk limits, protective stops, or trade verification.

- Meta allocator: `InpUseMetaAllocator` learns realized R-multiple by coarse context bucket and scales or blocks already-qualified candidates when recent realized edge is weak. Keep learning conservative; over-reactive settings can overfit recent noise.
- Currency-factor exposure control: `InpUseCurrencyFactorExposureControl` converts pair trades into signed base/quote currency vectors and limits hidden EUR-equivalent concentration by single currency, bloc, and net-factor concentration.
- Execution-quality governor: `InpUseExecutionQualityGovernor` blocks or scales down entries during rollover windows, abnormal spreads, unstable quotes, elevated execution-cost states, and optional high-impact calendar-event blackout windows.

Recommended first live use is observation-heavy and conservative: enable one overlay at a time, monitor logs, and avoid aggressive meta-learning boosts until enough closed FX7-owned trades have accumulated.

## Optional Research Extensions

FX7 also includes disabled-by-default research components for transparent directional forecasting:

- Cross-sectional currency momentum: `InpUseCrossSectionalMomentum` estimates latent currency strength from the full FX universe and blends a bounded `xmom_score` only when `InpXMomCompositeWeight` is non-zero.
- Medium-term trend: `InpUseMediumTermTrend` adds a bounded H4/D1 trend score intended for 1-day and 1-week context, not current-bar prediction.
- Feature export: `InpUseResearchFeatureExport` writes closed-bar ex-ante feature rows without future labels.
- Probability model: `InpUseProbabilityModel` consumes offline-trained logistic coefficients and can block or scale already-qualified candidates using calibrated `P(UP)`.
- Regime state: `InpUseRegimeStateFilter` computes transparent trend/chop/stress probabilities and can remain feature-only or conservatively gate sleeves.

The live EA remains closed-bar and auditable. It does not train supervised prediction models, compute labels, or use future returns in the signal path.

Offline Python research tooling is in `research/` and requires:

```bash
python -m pip install -r research/requirements.txt
```

## Installation

Copy the full `FX7` folder into `MQL5/Experts/FX7/` so MetaEditor can resolve `FX7.mq5` plus the `FX7/<Module>/<Module>.mqh` includes, then compile `FX7.mq5`.

## Recommended Live Defaults

- Keep `InpProcessCurrentClosedBarOnAttach = false`
- Keep `InpRequireSynchronizedSignalBars = true`
- Keep `InpFreezeEntriesOnDependencyFailure = true`
- Keep `InpFlattenOnPersistentDependencyFailure = true` unless you explicitly want degraded-mode holding behavior
- Start with a narrow symbol list and conservative `InpRiskPerTradePct`

## Documentation

- [Wiki Home](https://github.com/Pummelchen/FX7/wiki)
- [Live Trader Guide](https://github.com/Pummelchen/FX7/wiki/Live-Trader)
- [Backtester Guide](https://github.com/Pummelchen/FX7/wiki/Backtester)
- [Research Extensions](docs/FX7_RESEARCH_EXTENSIONS.md)
- [Adaptive Startup Tuning](docs/FX7_ADAPTIVE_STARTUP_TUNING.md)
- [Probability Model](docs/FX7_PROBABILITY_MODEL.md)
- [Cross-Sectional Momentum](docs/FX7_CROSS_SECTIONAL_MOMENTUM.md)
- [Validation Protocol](docs/FX7_VALIDATION_PROTOCOL.md)
- [Research Tooling](research/README.md)

## Validation

This refactor was compiled successfully in MetaEditor with `0 errors, 0 warnings`.
