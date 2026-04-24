#!/usr/bin/env python3
"""Run purged walk-forward validation for FX7 probability research."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Sequence

try:
    import numpy as np
    import pandas as pd
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import (
        accuracy_score,
        balanced_accuracy_score,
        brier_score_loss,
        log_loss,
        precision_recall_fscore_support,
        average_precision_score,
        roc_auc_score,
    )
    from sklearn.preprocessing import StandardScaler
except ModuleNotFoundError:  # pragma: no cover - exercised only without research deps.
    np = None
    pd = None
    LogisticRegression = None
    StandardScaler = None
    accuracy_score = None
    balanced_accuracy_score = None
    brier_score_loss = None
    log_loss = None
    precision_recall_fscore_support = None
    average_precision_score = None
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
    parser.add_argument("--output-dir", required=True, type=Path, help="Directory for validation outputs.")
    parser.add_argument("--horizon-days", type=int, choices=(1, 5), default=5)
    parser.add_argument("--features", nargs="*", default=DEFAULT_FEATURES)
    parser.add_argument("--train-min-days", type=int, default=365)
    parser.add_argument("--train-window-days", type=int, default=0, help="0 means expanding window.")
    parser.add_argument("--test-window-days", type=int, default=30)
    parser.add_argument("--step-days", type=int, default=30)
    parser.add_argument("--purge-days", type=int, default=5)
    parser.add_argument("--embargo-days", type=int, default=1)
    parser.add_argument("--edge-threshold", type=float, default=0.03)
    parser.add_argument("--seed", type=int, default=42)
    return parser.parse_args()


def _load_frame(path: Path, horizon_days: int, requested_features: Sequence[str]) -> tuple[pd.DataFrame, list[str]]:
    frame = pd.read_csv(path)
    if "timestamp_bar" not in frame.columns:
        raise ValueError("Input must contain timestamp_bar.")
    label_col = f"label_up_{horizon_days}d"
    if label_col not in frame.columns:
        raise ValueError(f"Input must contain {label_col}.")

    frame["timestamp_bar"] = pd.to_datetime(frame["timestamp_bar"], errors="coerce")
    frame[label_col] = pd.to_numeric(frame[label_col], errors="coerce")
    frame = frame.dropna(subset=["timestamp_bar", label_col])
    frame = frame[frame[label_col].isin([0, 1])].copy()
    frame[label_col] = frame[label_col].astype(int)
    features = [name for name in requested_features if name in frame.columns]
    if not features:
        raise ValueError("None of the requested features are present.")
    for feature in features:
        frame[feature] = pd.to_numeric(frame[feature], errors="coerce")
    frame[features] = frame[features].replace([np.inf, -np.inf], np.nan).fillna(0.0)
    return frame.sort_values("timestamp_bar").reset_index(drop=True), features


def _fit_predict(
    train: pd.DataFrame,
    test: pd.DataFrame,
    features: Sequence[str],
    label_col: str,
    seed: int,
) -> tuple[np.ndarray, np.ndarray, float]:
    scaler = StandardScaler()
    x_train = scaler.fit_transform(train.loc[:, features])
    y_train = train[label_col].to_numpy(dtype=int)
    x_test = scaler.transform(test.loc[:, features])

    if len(np.unique(y_train)) < 2:
        p = np.full(len(test), float(np.mean(y_train)))
        return p, np.zeros(len(features)), float(np.log(p[0] / max(1.0 - p[0], 1e-12)))

    model = LogisticRegression(
        penalty="elasticnet",
        solver="saga",
        l1_ratio=0.25,
        C=0.25,
        max_iter=5000,
        random_state=seed,
        n_jobs=1,
    )
    model.fit(x_train, y_train)
    p_up = model.predict_proba(x_test)[:, 1]
    coef_scaled = model.coef_[0].astype(float)
    coef_raw = coef_scaled / np.maximum(scaler.scale_, 1e-12)
    intercept_raw = float(model.intercept_[0]) - float(
        np.sum(coef_scaled * scaler.mean_ / np.maximum(scaler.scale_, 1e-12))
    )
    return p_up, coef_raw, intercept_raw


def _walkforward_splits(frame: pd.DataFrame, args: argparse.Namespace):
    first = frame["timestamp_bar"].min().normalize()
    last = frame["timestamp_bar"].max().normalize()
    test_start = first + pd.Timedelta(days=args.train_min_days + args.purge_days)
    while test_start + pd.Timedelta(days=args.test_window_days) <= last:
        train_end = test_start - pd.Timedelta(days=args.purge_days)
        train_start = first
        if args.train_window_days > 0:
            train_start = train_end - pd.Timedelta(days=args.train_window_days)
        test_end = test_start + pd.Timedelta(days=args.test_window_days)
        embargo_end = test_end + pd.Timedelta(days=args.embargo_days)
        train = frame[(frame["timestamp_bar"] >= train_start) & (frame["timestamp_bar"] < train_end)]
        test = frame[(frame["timestamp_bar"] >= test_start) & (frame["timestamp_bar"] < test_end)]
        if len(train) > 100 and len(test) > 0:
            yield train, test, test_start, test_end, embargo_end
        test_start += pd.Timedelta(days=args.step_days)


def _metrics(y: np.ndarray, p: np.ndarray, edge_threshold: float) -> dict[str, float]:
    pred = (p >= 0.5).astype(int)
    precision, recall, _, _ = precision_recall_fscore_support(
        y,
        pred,
        labels=[0, 1],
        zero_division=0,
    )
    out = {
        "rows": float(len(y)),
        "directional_accuracy": accuracy_score(y, pred),
        "balanced_accuracy": balanced_accuracy_score(y, pred),
        "precision_down": precision[0],
        "precision_up": precision[1],
        "recall_down": recall[0],
        "recall_up": recall[1],
        "brier": brier_score_loss(y, p),
        "log_loss": log_loss(y, p, labels=[0, 1]),
        "hit_rate_edge": np.nan,
        "coverage_edge": float(np.mean(np.abs(p - 0.5) >= edge_threshold)),
    }
    if len(np.unique(y)) == 2:
        out["roc_auc"] = roc_auc_score(y, p)
        out["pr_auc"] = average_precision_score(y, p)
    mask = np.abs(p - 0.5) >= edge_threshold
    if np.any(mask):
        out["hit_rate_edge"] = accuracy_score(y[mask], pred[mask])
    return out


def _sigmoid(values: pd.Series | np.ndarray) -> np.ndarray:
    raw = np.asarray(values, dtype=float)
    return 1.0 / (1.0 + np.exp(-np.clip(raw, -30.0, 30.0)))


def _baseline_predictions(test: pd.DataFrame, train_up_rate: float) -> dict[str, np.ndarray]:
    rows = len(test)
    trend_source = "medium_trend_score" if "medium_trend_score" in test.columns else "momentum_score"
    if trend_source not in test.columns:
        trend_source = "composite_raw"

    trend = pd.to_numeric(test.get(trend_source, 0.0), errors="coerce").fillna(0.0)
    carry = pd.to_numeric(test.get("carry_score", 0.0), errors="coerce").fillna(0.0)
    breakout = pd.to_numeric(
        test.get("breakout_score_or_participation", 0.5),
        errors="coerce",
    ).fillna(0.5)
    vol_ratio = pd.to_numeric(test.get("vol_ratio", 1.0), errors="coerce").fillna(1.0)

    p_trend = _sigmoid(1.5 * trend)
    p_carry = _sigmoid(1.5 * carry)
    p_breakout = np.clip(0.5 + 0.50 * (breakout.to_numpy(dtype=float) - 0.5), 0.01, 0.99)
    p_vol_filter = np.where(vol_ratio.to_numpy(dtype=float) > 1.50, 0.5, p_trend)
    p_ensemble = np.clip((p_trend + p_carry + p_vol_filter) / 3.0, 0.01, 0.99)

    return {
        "coin_flip": np.full(rows, 0.5),
        "majority_class": np.full(rows, np.clip(train_up_rate, 0.01, 0.99)),
        "simple_trend": p_trend,
        "simple_breakout": p_breakout,
        "simple_carry": p_carry,
        "simple_volatility_filter": p_vol_filter,
        "naive_trend_carry_vol_ensemble": p_ensemble,
    }


def _bootstrap_ci(y: np.ndarray, p: np.ndarray, seed: int) -> dict[str, float]:
    rng = np.random.default_rng(seed)
    n = len(y)
    if n < 50:
        return {}
    acc = []
    brier = []
    block = max(5, int(round(np.sqrt(n))))
    starts = np.arange(0, n, block)
    for _ in range(300):
        sampled = rng.choice(starts, size=len(starts), replace=True)
        idx = np.concatenate([np.arange(s, min(s + block, n)) for s in sampled])
        yy = y[idx]
        pp = p[idx]
        acc.append(accuracy_score(yy, (pp >= 0.5).astype(int)))
        brier.append(brier_score_loss(yy, pp))
    return {
        "accuracy_ci_low": float(np.quantile(acc, 0.025)),
        "accuracy_ci_high": float(np.quantile(acc, 0.975)),
        "brier_ci_low": float(np.quantile(brier, 0.025)),
        "brier_ci_high": float(np.quantile(brier, 0.975)),
    }


def _calibration_table(y: np.ndarray, p: np.ndarray, bins: int = 10) -> pd.DataFrame:
    frame = pd.DataFrame({"y": y, "p": p})
    frame["bin"] = pd.cut(frame["p"], bins=np.linspace(0.0, 1.0, bins + 1), include_lowest=True)
    return (
        frame.groupby("bin", observed=False)
        .agg(count=("y", "size"), mean_p_up=("p", "mean"), observed_up_rate=("y", "mean"))
        .reset_index()
    )


def _add_cost_and_turnover_proxies(oos: pd.DataFrame, summary: dict[str, float], label_col: str) -> None:
    if "symbol" in oos.columns:
        ordered = oos.sort_values(["symbol", "timestamp_bar"]) if "timestamp_bar" in oos.columns else oos
        direction = np.where(ordered["p_up"].to_numpy(dtype=float) >= 0.5, 1, -1)
        changes = (
            pd.Series(direction, index=ordered.index)
            .groupby(ordered["symbol"].astype(str))
            .diff()
            .fillna(0.0)
        )
        summary["turnover_proxy"] = float(np.mean(np.abs(changes) > 0.0))

    ret_col = label_col.replace("label_up", "future_return")
    if ret_col in oos.columns:
        future_return = pd.to_numeric(oos[ret_col], errors="coerce").fillna(0.0).to_numpy(dtype=float)
        signed = np.where(oos["p_up"].to_numpy(dtype=float) >= 0.5, 1.0, -1.0)
        cost = np.zeros(len(oos))
        if "cost_long" in oos.columns and "cost_short" in oos.columns:
            long_cost = pd.to_numeric(oos["cost_long"], errors="coerce").fillna(0.0).to_numpy(dtype=float)
            short_cost = pd.to_numeric(oos["cost_short"], errors="coerce").fillna(0.0).to_numpy(dtype=float)
            cost = np.where(signed > 0.0, long_cost, short_cost)
        summary["cost_adjusted_return_proxy"] = float(np.mean(signed * future_return - cost))


def _write_final_model(
    frame: pd.DataFrame,
    features: Sequence[str],
    label_col: str,
    horizon_days: int,
    output_path: Path,
    seed: int,
) -> tuple[np.ndarray, float]:
    p, coef, intercept = _fit_predict(frame, frame, features, label_col, seed)
    del p
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
    pd.DataFrame(rows).to_csv(output_path, index=False)
    return coef, intercept


def main() -> None:
    args = _parse_args()
    _require_dependencies()
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    frame, features = _load_frame(args.input, args.horizon_days, args.features)
    label_col = f"label_up_{args.horizon_days}d"

    predictions = []
    fold_rows = []
    for fold, (train, test, test_start, test_end, embargo_end) in enumerate(
        _walkforward_splits(frame, args),
        start=1,
    ):
        p_up, _, _ = _fit_predict(train, test, features, label_col, args.seed + fold)
        baselines = _baseline_predictions(test, float(train[label_col].mean()))
        fold_pred = test.copy()
        fold_pred["fold"] = fold
        fold_pred["p_up"] = p_up
        fold_pred["pred_up"] = (p_up >= 0.5).astype(int)
        for name, values in baselines.items():
            fold_pred[f"p_{name}"] = values
        fold_pred["test_start"] = test_start
        fold_pred["test_end"] = test_end
        fold_pred["embargo_end"] = embargo_end
        predictions.append(fold_pred)
        metrics = _metrics(test[label_col].to_numpy(dtype=int), p_up, args.edge_threshold)
        metrics["fold"] = fold
        metrics["test_start"] = str(test_start.date())
        metrics["test_end"] = str(test_end.date())
        fold_rows.append(metrics)

    if not predictions:
        raise ValueError("No walk-forward folds were generated; reduce train-min-days or window settings.")

    oos = pd.concat(predictions, ignore_index=True)
    oos.to_csv(output_dir / "predictions_oos.csv", index=False)

    y = oos[label_col].to_numpy(dtype=int)
    p = oos["p_up"].to_numpy(dtype=float)
    summary = _metrics(y, p, args.edge_threshold)
    summary.update(_bootstrap_ci(y, p, args.seed))
    _add_cost_and_turnover_proxies(oos, summary, label_col)
    summary["model"] = "fx7_logistic"
    summary_rows = [summary]
    for col in [c for c in oos.columns if c.startswith("p_") and c != "p_up"]:
        row = _metrics(y, oos[col].to_numpy(dtype=float), args.edge_threshold)
        row["model"] = col.removeprefix("p_")
        summary_rows.append(row)
    pd.DataFrame(summary_rows).to_csv(output_dir / "metrics_summary.csv", index=False)
    pd.DataFrame(fold_rows).to_csv(output_dir / "fold_metrics.csv", index=False)
    _calibration_table(y, p).to_csv(output_dir / "calibration_table.csv", index=False)

    if f"future_return_{args.horizon_days}d" in oos.columns:
        ret = pd.to_numeric(oos[f"future_return_{args.horizon_days}d"], errors="coerce")
        summary["information_coefficient"] = float(pd.Series(p).corr(ret, method="spearman"))

    final_coef, final_intercept = _write_final_model(
        frame,
        features,
        label_col,
        args.horizon_days,
        output_dir / "FX7_probability_model.csv",
        args.seed,
    )
    pd.DataFrame(
        {
            "feature": ["intercept", *features],
            "coefficient": [final_intercept, *final_coef.tolist()],
        }
    ).to_csv(output_dir / "feature_importance_or_coefficients.csv", index=False)

    report = [
        "# FX7 Walk-Forward Validation Report",
        "",
        f"Horizon: {args.horizon_days} day(s)",
        f"Rows OOS: {int(summary['rows'])}",
        f"Directional accuracy: {summary['directional_accuracy']:.4f}",
        f"Balanced accuracy: {summary['balanced_accuracy']:.4f}",
        f"Brier score: {summary['brier']:.6f}",
        f"Log loss: {summary['log_loss']:.6f}",
        f"ROC-AUC: {summary.get('roc_auc', np.nan):.4f}",
        f"PR-AUC: {summary.get('pr_auc', np.nan):.4f}",
        f"Edge-threshold coverage: {summary['coverage_edge']:.4f}",
        "",
        "Interpretation: treat any improvement as a small probabilistic edge candidate, not as evidence of profitability. Re-check transaction costs, turnover, and stability by symbol and currency bloc before live filtering.",
    ]
    (output_dir / "validation_report.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print(f"Wrote walk-forward outputs to {output_dir}")


if __name__ == "__main__":
    main()
