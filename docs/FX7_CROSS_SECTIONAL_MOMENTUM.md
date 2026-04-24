# FX7 Cross-Sectional Momentum

The cross-sectional momentum sleeve estimates latent currency strength across the active FX universe, then converts the currency scores back into pair scores. This helps avoid treating several USD-factor trades as independent pair signals.

## Method

For each lookback, FX7 uses closed bars only:

```text
r_pair = log(Close[1] / Close[1 + lookback])
r_A/B ~= strength_A - strength_B
```

It builds a small ridge-regularized least-squares system with `+1` for base currency and `-1` for quote currency. The resulting currency scores are centered to enforce an approximate zero-sum constraint. If the system is underdetermined or singular, FX7 falls back to a transparent contribution method:

```text
strength[base] += pair_return
strength[quote] -= pair_return
```

The pair score is the base currency score minus the quote currency score. Horizon scores are blended, optionally volatility-normalized, and squashed with `tanh`.

## Key Inputs

```text
InpUseCrossSectionalMomentum=false
InpXMomTF=PERIOD_D1
InpXMomLookback1=20
InpXMomLookback2=60
InpXMomLookback3=120
InpXMomCompositeWeight=0.0
InpXMomMinSymbols=8
InpXMomRequireSynchronizedBars=true
```

The sleeve has no trading impact unless enabled and `InpXMomCompositeWeight` is non-zero.

## Bias Controls

The module never uses `shift=0`. Missing or unsynchronized data mark the score invalid. If too few symbols are available, the module logs a warning and leaves scores neutral.
