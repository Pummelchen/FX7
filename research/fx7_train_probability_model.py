#!/usr/bin/env python3
"""Train a transparent logistic probability model for FX7.

The output CSV is intentionally simple so the EA can consume it directly:
model_version,horizon_days,feature_name,coefficient,intercept_flag,
optional_symbol,optional_base_currency,optional_quote_currency.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

try:
    import numpy as np
    import pandas as pd
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import brier_score_loss, log_loss, roc_auc_score
    from sklearn.preprocessing import StandardScaler
except ModuleNotFoundError:  # pragma: no cover - exercised only without research deps.
    np = None
    pd = None
    LogisticRegression = None
    StandardScaler = None
    brier_score_loss = None
    log_loss = None
    roc_auc_score = None


DEFAULT_FEATURES = [
    "momentum_score",
    "carry_score",
    "value_score",
    "xmom_score",
    "medium_trend_score",
    "realized_vol",
    "vol_ratio",
    "breakout_score_or_participation",
    "efficiency_ratio",
    "reversal_penalty",
    "panic_gate_value",
    "cost_long",
    "cost_short",
    "composite_raw",
]


def _require_dependencies() -> None:
    if np is None or pd is None or LogisticRegression is None or StandardScaler is None:
        raise SystemExit(
            "Missing research dependencies. Install them with: "
            "python -m pip install -r research/requirements.txt"
        )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Labeled feature CSV.")
    parser.add_argument("--output-model", required=True, type=Path, help="EA coefficient CSV.")
    parser.add_argument(
        "--output-coefficients",
        type=Path,
        default=None,
        help="Optional human-readable coefficient CSV.",
    )
    parser.add_argument("--horizon-days", type=int, choices=(1, 5), default=5)
    parser.add_argument("--features", nargs="*", default=DEFAULT_FEATURES)
    parser.add_argument("--min-rows", type=int, default=500)
    parser.add_argument("--c", type=float, default=0.25, help="Inverse regularization strength.")
    parser.add_argument("--l1-ratio", type=float, default=0.25, help="Elastic-net L1 ratio.")
    parser.add_argument(
        "--calibration",
        choices=("none", "platt"),
        default="none",
        help="Platt calibration is folded back into linear coefficients.",
    )
    parser.add_argument("--calibration-fraction", type=float, default=0.20)
    parser.add_argument("--seed", type=int, default=42)
    return parser.parse_args()


def _available_features(frame: pd.DataFrame, requested: Sequence[str]) -> list[str]:
    features = [name for name in requested if name in frame.columns]
    if not features:
        raise ValueError("None of the requested feature columns are present.")
    return features


def _prepare_xy(frame: pd.DataFrame, features: Sequence[str], horizon_days: int) -> tuple[pd.DataFrame, pd.Series]:
    label_col = f"label_up_{horizon_days}d"
    if label_col not in frame.columns:
        raise ValueError(f"Missing label column {label_col}; run fx7_label_features.py first.")

    data = frame.copy()
    data[label_col] = pd.to_numeric(data[label_col], errors="coerce")
    data = data[data[label_col].isin([0, 1])]
    x = data.loc[:, features].apply(pd.to_numeric, errors="coerce")
    x = x.replace([np.inf, -np.inf], np.nan).fillna(0.0)
    y = data[label_col].astype(int)
    return x, y


def _fit_logistic(x: pd.DataFrame, y: pd.Series, args: argparse.Namespace) -> tuple[np.ndarray, float]:
    if len(x) < args.min_rows:
        raise ValueError(f"Need at least {args.min_rows} rows, found {len(x)}.")
    if y.nunique() < 2:
        raise ValueError("Training labels contain only one class.")

    split = len(x)
    use_platt = args.calibration == "platt" and 0.05 <= args.calibration_fraction <= 0.40
    if use_platt:
        split = int(round(len(x) * (1.0 - args.calibration_fraction)))
        split = max(100, min(split, len(x) - 100))

    scaler = StandardScaler()
    x_train = x.iloc[:split]
    y_train = y.iloc[:split]
    x_train_scaled = scaler.fit_transform(x_train)

    model = LogisticRegression(
        penalty="elasticnet",
        solver="saga",
        l1_ratio=args.l1_ratio,
        C=args.c,
        max_iter=5000,
        random_state=args.seed,
        n_jobs=1,
    )
    model.fit(x_train_scaled, y_train)

    coef_scaled = model.coef_[0].astype(float)
    intercept = float(model.intercept_[0])
    coef_raw = coef_scaled / np.maximum(scaler.scale_, 1e-12)
    intercept_raw = intercept - float(np.sum(coef_scaled * scaler.mean_ / np.maximum(scaler.scale_, 1e-12)))

    if use_platt:
        x_cal = x.iloc[split:]
        y_cal = y.iloc[split:]
        scores = x_cal.to_numpy(dtype=float) @ coef_raw + intercept_raw
        platt = LogisticRegression(penalty=None, solver="lbfgs", max_iter=1000)
        platt.fit(scores.reshape(-1, 1), y_cal)
        slope = float(platt.coef_[0][0])
        offset = float(platt.intercept_[0])
        coef_raw = coef_raw * slope
        intercept_raw = intercept_raw * slope + offset

    return coef_raw, intercept_raw


def _write_model(path: Path, features: Sequence[str], coef: np.ndarray, intercept: float, horizon_days: int) -> None:
    rows = [
        {
            "model_version": 1,
            "horizon_days": horizon_days,
            "feature_name": "intercept",
            "coefficient": intercept,
            "intercept_flag": 1,
            "optional_symbol": "",
            "optional_base_currency": "",
            "optional_quote_currency": "",
        }
    ]
    for feature, value in zip(features, coef):
        rows.append(
            {
                "model_version": 1,
                "horizon_days": horizon_days,
                "feature_name": feature,
                "coefficient": float(value),
                "intercept_flag": 0,
                "optional_symbol": "",
                "optional_base_currency": "",
                "optional_quote_currency": "",
            }
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(rows).to_csv(path, index=False)


def _print_in_sample_diagnostics(x: pd.DataFrame, y: pd.Series, coef: np.ndarray, intercept: float) -> None:
    logit = x.to_numpy(dtype=float) @ coef + intercept
    p_up = 1.0 / (1.0 + np.exp(-np.clip(logit, -30.0, 30.0)))
    metrics = {
        "rows": len(y),
        "brier": brier_score_loss(y, p_up),
        "log_loss": log_loss(y, p_up, labels=[0, 1]),
    }
    if y.nunique() == 2:
        metrics["roc_auc"] = roc_auc_score(y, p_up)
    print(pd.Series(metrics).to_string())


def main() -> None:
    args = _parse_args()
    _require_dependencies()
    frame = pd.read_csv(args.input)
    features = _available_features(frame, args.features)
    x, y = _prepare_xy(frame, features, args.horizon_days)
    coef, intercept = _fit_logistic(x, y, args)
    _write_model(args.output_model, features, coef, intercept, args.horizon_days)
    if args.output_coefficients:
        args.output_coefficients.parent.mkdir(parents=True, exist_ok=True)
        pd.DataFrame({"feature": features, "coefficient": coef}).to_csv(
            args.output_coefficients,
            index=False,
        )
    _print_in_sample_diagnostics(x, y, coef, intercept)
    print(f"Wrote EA probability model to {args.output_model}")


if __name__ == "__main__":
    main()
