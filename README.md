# FX7

`FX7.mq5` is a multi-symbol MetaTrader 5 Expert Advisor for FX portfolio trading on closed-bar signals. It combines trend, carry, and value inputs with portfolio-level diversification, execution gating, and fail-safe runtime controls.

## Benefits

- Multi-factor alpha instead of single-indicator trading. FX7 blends time-series trend, carry, and a reliability-scaled value sleeve.
- Better portfolio construction. Dynamic allocation, correlation shrinkage, novelty orthogonalization, crowding limits, and persistence filters reduce redundant trades.
- Stronger risk controls. Regime gating, panic gating, cost gating, catastrophic stops, account/order caps, and margin/risk limits are enforced before entries are sent.
- Safer live operation. Event-assisted trade-state verification, dependency failure policies, stale-data isolation, synchronized bar processing, and a no-trade-on-attach option make live deployment less fragile.
- Cleaner execution quality. Retry logic refreshes both quote and protective stop, not just the entry price, so risk geometry stays closer to plan during fast moves.
- Better behavior under degraded data. External carry/PPP dependencies can freeze entries, flatten exposure, or continue with stale inputs based on explicit policy settings.

## Strategy Summary

- Signal timeframe: `InpSignalTF` default `M15`
- Alpha sleeves: momentum, carry, value
- Portfolio overlay: panic gate, correlation shrinkage, novelty ranking, uniqueness and crowding filters
- Execution model: one managed position per symbol, closed-bar signal generation, immediate protective-stop enforcement
- Trade styles: `Classic` and `Modern`

## Repository Contents

- [FX7.mq5](https://github.com/Pummelchen/FX7/blob/main/FX7.mq5): main EA source

## Data Requirements

FX7 can run with different dependency profiles:

- Pure momentum mode: no external macro files required
- External carry mode: provide `FXRC_CarryRates.csv`
- PPP or hybrid value mode: provide `FXRC_PPP_CPI.csv`

File location is controlled by:

- `InpCarryUseCommonFile`
- `InpPPPUseCommonFile`

When these are `false`, place files in the terminal `MQL5/Files` folder. When `true`, place them in the terminal common files folder.

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

## Validation

This packaged release was compiled successfully in MetaEditor with `0 errors, 0 warnings`.
