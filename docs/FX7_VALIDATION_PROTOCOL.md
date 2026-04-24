# FX7 Validation Protocol

FX7 research should be evaluated as a small-edge probabilistic forecasting problem. Avoid random train/test splits, full-sample normalization, and any use of future labels in the EA.

## Feature Export

Enable:

```text
InpUseResearchFeatureExport=true
InpResearchExportFile=FX7_feature_export.csv
InpResearchExportIncludeNonCandidates=true
```

The export contains closed-bar features only. It deliberately excludes future returns and labels.

## Labeling

Use `research/fx7_label_features.py` with a historical OHLC file. Labels are:

```text
y_1d = 1{log(Close[t+1] / Close[t]) > 0}
y_5d = 1{log(Close[t+5] / Close[t]) > 0}
```

Optional neutral labels can remove tiny moves inside a volatility-scaled dead zone.

## Walk-Forward Testing

Use `research/fx7_walkforward_validation.py`. Recommended defaults for 5-day labels:

```bash
python research/fx7_walkforward_validation.py \
  --input labeled_features.csv \
  --output-dir research_out \
  --horizon-days 5 \
  --train-min-days 365 \
  --test-window-days 30 \
  --step-days 30 \
  --purge-days 5 \
  --embargo-days 1
```

Required checks:

- Expanding or rolling chronological windows only.
- Purge overlapping labels.
- Embargo after each test window.
- Fit standardization inside the training window only.
- Report baselines and calibration metrics before live use.

The script writes `predictions_oos.csv`, `metrics_summary.csv`, `fold_metrics.csv`, `calibration_table.csv`, `validation_report.md`, and an EA-compatible `FX7_probability_model.csv`.

## Metrics

Track directional accuracy, balanced accuracy, precision/recall, ROC-AUC, PR-AUC, Brier score, log loss, calibration reliability, information coefficient, confidence-threshold hit rate, turnover proxy, and cost-adjusted return proxy when cost columns exist.

## Live Promotion

Only promote a model to `InpProbabilityModelFile` after stable out-of-sample behavior across symbols, regimes, and currency blocs. `P(UP)` is not a promise of profitability; transaction costs can overwhelm small directional edges.
