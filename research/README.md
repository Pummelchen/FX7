# FX7 Research Tooling

This folder contains offline tooling for turning FX7 feature exports into transparent calibrated probability models. The EA never creates future labels and never trains a live black-box model.

## Workflow

1. Enable `InpUseResearchFeatureExport=true` in FX7 and collect `FX7_feature_export.csv`.
2. Prepare a long-format OHLC CSV with `timestamp`, `symbol`, and `close`.
3. Label features:

```bash
python research/fx7_label_features.py \
  --features FX7_feature_export.csv \
  --ohlc daily_ohlc.csv \
  --output labeled_features.csv
```

4. Run purged walk-forward validation:

```bash
python research/fx7_walkforward_validation.py \
  --input labeled_features.csv \
  --output-dir research_out \
  --horizon-days 5 \
  --purge-days 5 \
  --embargo-days 1
```

5. Train an EA-consumable coefficient file:

```bash
python research/fx7_train_probability_model.py \
  --input labeled_features.csv \
  --horizon-days 5 \
  --output-model FX7_probability_model.csv \
  --output-coefficients feature_importance_or_coefficients.csv
```

## Outputs

- `validation_report.md`: plain-language walk-forward summary.
- `metrics_summary.csv`: aggregate OOS metrics.
- `fold_metrics.csv`: fold-level metrics.
- `calibration_table.csv`: reliability data by probability bucket.
- `predictions_oos.csv`: out-of-sample probabilities and labels.
- `FX7_probability_model.csv`: coefficient CSV for `InpProbabilityModelFile`.
- `feature_importance_or_coefficients.csv`: human-readable coefficients.

## Bias Controls

- Labels use future returns only offline.
- Feature rows are joined to historical closes at or before the feature timestamp.
- Walk-forward splits are chronological, with purge and embargo support for overlapping 5-day labels.
- Standardization is fitted only inside each training window.
- Reported results are directional research diagnostics, not profitability claims.
