#!/usr/bin/env python3
"""Label FX7 feature-export rows with future 1-day and 5-day directions.

The EA exports only ex-ante features. This offline tool joins those rows to a
historical OHLC CSV and creates future-return labels for model research.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable

try:
    import numpy as np
    import pandas as pd
except ModuleNotFoundError:  # pragma: no cover - exercised only without research deps.
    np = None
    pd = None


def _require_dependencies() -> None:
    if np is None or pd is None:
        raise SystemExit(
            "Missing research dependencies. Install them with: "
            "python -m pip install -r research/requirements.txt"
        )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--features", required=True, type=Path, help="FX7 feature export CSV.")
    parser.add_argument(
        "--ohlc",
        required=True,
        type=Path,
        help="Long-format OHLC CSV with timestamp, symbol, and close columns.",
    )
    parser.add_argument("--output", required=True, type=Path, help="Output labeled CSV.")
    parser.add_argument("--timestamp-col", default="timestamp", help="OHLC timestamp column.")
    parser.add_argument("--symbol-col", default="symbol", help="OHLC symbol column.")
    parser.add_argument("--close-col", default="close", help="OHLC close column.")
    parser.add_argument(
        "--neutral-theta",
        type=float,
        default=0.0,
        help="If >0, marks labels neutral when abs(future_return) <= theta * realized_vol.",
    )
    return parser.parse_args()


def _require_columns(frame: pd.DataFrame, columns: Iterable[str], name: str) -> None:
    missing = [col for col in columns if col not in frame.columns]
    if missing:
        raise ValueError(f"{name} is missing required column(s): {', '.join(missing)}")


def _normalize_symbol(series: pd.Series) -> pd.Series:
    return series.astype(str).str.strip().str.upper()


def _read_features(path: Path) -> pd.DataFrame:
    features = pd.read_csv(path)
    _require_columns(features, ["timestamp_bar", "symbol"], "features")
    features["timestamp_bar"] = pd.to_datetime(features["timestamp_bar"], errors="coerce")
    features["symbol_norm"] = _normalize_symbol(features["symbol"])
    features = features.dropna(subset=["timestamp_bar", "symbol_norm"])
    return features.sort_values(["symbol_norm", "timestamp_bar"]).reset_index(drop=True)


def _read_ohlc(path: Path, timestamp_col: str, symbol_col: str, close_col: str) -> pd.DataFrame:
    ohlc = pd.read_csv(path)
    _require_columns(ohlc, [timestamp_col, symbol_col, close_col], "ohlc")
    ohlc = ohlc.rename(
        columns={timestamp_col: "ohlc_timestamp", symbol_col: "symbol", close_col: "ohlc_close"}
    )
    ohlc["ohlc_timestamp"] = pd.to_datetime(ohlc["ohlc_timestamp"], errors="coerce")
    ohlc["symbol_norm"] = _normalize_symbol(ohlc["symbol"])
    ohlc["ohlc_close"] = pd.to_numeric(ohlc["ohlc_close"], errors="coerce")
    ohlc = ohlc.dropna(subset=["ohlc_timestamp", "symbol_norm", "ohlc_close"])
    return ohlc.sort_values(["symbol_norm", "ohlc_timestamp"]).reset_index(drop=True)


def _add_forward_returns(ohlc: pd.DataFrame) -> pd.DataFrame:
    out = ohlc.copy()
    for horizon in (1, 5):
        future = out.groupby("symbol_norm")["ohlc_close"].shift(-horizon)
        out[f"future_return_{horizon}d"] = np.log(future / out["ohlc_close"])
    return out


def label_features(
    features: pd.DataFrame,
    ohlc: pd.DataFrame,
    neutral_theta: float,
) -> pd.DataFrame:
    """Attach close-aligned future-return labels without using future features."""

    labeled_prices = _add_forward_returns(ohlc)
    joined_parts: list[pd.DataFrame] = []
    for symbol, feature_group in features.groupby("symbol_norm", sort=False):
        price_group = labeled_prices[labeled_prices["symbol_norm"] == symbol]
        if price_group.empty:
            continue

        joined_parts.append(
            pd.merge_asof(
                feature_group.sort_values("timestamp_bar"),
                price_group.sort_values("ohlc_timestamp"),
                left_on="timestamp_bar",
                right_on="ohlc_timestamp",
                direction="backward",
                allow_exact_matches=True,
            )
        )

    if not joined_parts:
        raise ValueError("No feature rows matched the supplied OHLC symbols.")

    joined = pd.concat(joined_parts, ignore_index=True)

    for horizon in (1, 5):
        ret_col = f"future_return_{horizon}d"
        label_col = f"label_up_{horizon}d"
        neutral_col = f"label_neutral_{horizon}d"
        has_label = joined[ret_col].notna()
        joined[label_col] = np.where(has_label, np.where(joined[ret_col] > 0.0, 1, 0), np.nan)
        joined[neutral_col] = 0
        if neutral_theta > 0.0 and "realized_vol" in joined.columns:
            vol = pd.to_numeric(joined["realized_vol"], errors="coerce").fillna(0.0)
            neutral = has_label & (joined[ret_col].abs() <= neutral_theta * vol)
            joined.loc[neutral, neutral_col] = 1
            joined.loc[neutral, label_col] = -1

    return (
        joined.drop(columns=["symbol_y", "symbol_norm_y"], errors="ignore")
        .rename(columns={"symbol_x": "symbol", "symbol_norm_x": "symbol_norm"})
        .sort_values(["symbol_norm", "timestamp_bar"])
        .reset_index(drop=True)
    )


def main() -> None:
    args = _parse_args()
    _require_dependencies()
    features = _read_features(args.features)
    ohlc = _read_ohlc(args.ohlc, args.timestamp_col, args.symbol_col, args.close_col)
    labeled = label_features(features, ohlc, args.neutral_theta)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    labeled.to_csv(args.output, index=False)
    print(f"Wrote {len(labeled):,} labeled rows to {args.output}")


if __name__ == "__main__":
    main()
