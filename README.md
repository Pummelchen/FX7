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
- Portfolio overlay: panic gate, correlation shrinkage, novelty ranking, uniqueness and crowding filters
- Execution model: one managed position per symbol, closed-bar signal generation, immediate protective-stop enforcement
- Trade styles: `Classic` and `Modern`

## Repository Contents

- [FX7.mq5](https://github.com/Pummelchen/FX7/blob/main/FX7.mq5): thin entry wrapper that includes the modular source tree
- `FX7/Inputs/Inputs.mqh`: all `input` parameters and public EA enums
- `FX7/TypesAndGlobals/TypesAndGlobals.mqh`: shared structs, cache state, globals, and runtime layout notes
- `FX7/Events/Events.mqh`: `OnInit`, `OnTick`, `OnTimer`, `OnTradeTransaction`, and runtime orchestration
- `FX7/TradeExecution/TradeExecution.mqh`: trade planning, request construction, send/retry, and verification logic
- `FX7/Signals/Signals.mqh`: portfolio ranking, novelty, crowding, and candidate selection
- `FX7/FeaturePipeline/FeaturePipeline.mqh`: symbol-level feature computation, value/carry integration, and sleeve blending
- `FX7/MacroData/MacroData.mqh`: startup-built carry/PPP cache creation, dependency health, and macro lookup helpers
- `FX7/Core/Core.mqh`: validation, reset helpers, conversions, and shared utility functions

## Data Requirements

FX7 can run with different dependency profiles:

- Pure momentum mode: no macro dependency required
- Carry mode: when the carry sleeve has a positive weight and uses rate differentials, the EA builds an in-memory rate-differential cache during startup
- PPP or hybrid value mode: when the value sleeve has a positive weight and the selected value model uses PPP, the EA builds an in-memory CPI/PPP cache during startup

No external CSV files are used anymore. At startup the EA:

- pulls economic-calendar history for the currencies used by `InpSymbols`
- reshapes carry into a monthly forward-filled series and PPP into a monthly CPI-style index path
- falls back to built-in major-currency profiles if calendar data is missing
- keeps the existing dependency health checks, freeze/flatten policy, and freshness controls

If you enable carry or PPP modes for currencies that are neither covered by the terminal economic calendar nor the built-in fallback profiles, FX7 will treat that as a dependency failure and apply the configured runtime policy.

`InpMaxAccountOrders` is enforced against all currently open account positions plus pending orders, not just FX7-owned trades.

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

## Validation

This refactor was compiled successfully in MetaEditor with `0 errors, 0 warnings`.
