#!/usr/bin/env python3
"""
gen_dst.py — HamClock-style dst.txt from Kyoto DST realtime monthly file (CSI-like behavior)

Outputs 24 UTC hourly points:
YYYY-MM-DDTHH:00:00 <value>

Behavior implemented:
- Parse Kyoto DST monthly realtime file using fixed-width columns
- Ignore trailing extra column
- Stop row parsing at filler/garbage
- Special-case packed filler like "0999"/"2999": treat as value X for that hour, then stop
- Anchor to previous completed UTC hour (floor(now_utc) - 1h), clamped to source support
- CSI edge-hour policy for partial current-day row
- CSI-compatible append-only updates:
    * do NOT rewrite older timestamps if source later changes them
    * append only new timestamp/value
    * keep last 24 lines
- Month-boundary-safe rebuild/seed:
    * if current month alone cannot build a full 24h window, auto-fetch previous month
- Packed-edge guard:
    * if latest parsed hour came from X999 packed filler, do NOT synthesize +1 extra hour
- Append candidate consistency:
    * append mode computes candidate from build_csi_like_last24() (same path as rebuild)
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import pandas as pd
import requests


KYOTO_URL_TMPL = "https://wdc.kugi.kyoto-u.ac.jp/dst_realtime/presentmonth/dst{yy}{mm}.for.request"
KYOTO_ARCHIVE_URL_TMPL = "https://wdc.kugi.kyoto-u.ac.jp/dst_realtime/{yyyy}{mm}/dst{yy}{mm}.for.request"


@dataclass
class ParsedDstRow:
    year: int
    month: int
    day: int
    pre_field: Optional[int]   # field before hour00 (often 0)
    hours: Dict[int, int]      # hour -> value for valid parsed hours only
    stopped_early: bool        # True if row terminated due to filler/garbage before hour23
    last_hour_was_packed_filler: bool  # True if final parsed hour came from X999 packed filler


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def prev_month(dt: datetime) -> datetime:
    first = dt.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    return first - timedelta(days=1)


def build_presentmonth_url(dt_utc: Optional[datetime] = None) -> str:
    dt_utc = dt_utc or utc_now()
    return KYOTO_URL_TMPL.format(yy=dt_utc.strftime("%y"), mm=dt_utc.strftime("%m"))


def build_archive_url(dt_utc: datetime) -> str:
    return KYOTO_ARCHIVE_URL_TMPL.format(
        yyyy=dt_utc.strftime("%Y"),
        yy=dt_utc.strftime("%y"),
        mm=dt_utc.strftime("%m"),
    )


def download_text(url: str, timeout: int = 20) -> str:
    r = requests.get(url, timeout=timeout)
    r.raise_for_status()
    return r.text


def _parse_int_token(tok: str) -> Optional[int]:
    tok = tok.strip()
    if not tok:
        return None
    if not re.fullmatch(r"[+-]?\d+", tok):
        return None
    return int(tok)


def parse_dst_line_fixed(line: str) -> Optional[ParsedDstRow]:
    """
    Kyoto fixed-width parsing.

    Observed layout (1-based columns):
      1..3     "DST"
      4..5     YY
      6..7     MM
      8        '*'
      9..10    DD
      ...
      17..20   pre-field (often 0)
      21..24   hour00
      25..28   hour01
      ...
      113..116 hour23
      117..120 trailing extra column (ignored)
    """
    if not line.startswith("DST"):
        return None
    if len(line) < 24:
        return None

    yy = line[3:5]
    mm = line[5:7]
    dd = line[8:10]
    if not (yy.isdigit() and mm.isdigit() and dd.isdigit()):
        return None

    year = 2000 + int(yy)
    month = int(mm)
    day = int(dd)

    pre_raw = line[16:20]  # 1-based cols 17..20
    pre_field = _parse_int_token(pre_raw)

    hours: Dict[int, int] = {}
    stopped_early = False
    last_hour_was_packed_filler = False

    for hour in range(24):
        start = 20 + (hour * 4)  # 1-based col 21 => 0-based 20
        end = start + 4
        tok = line[start:end].strip()

        if tok == "":
            stopped_early = True
            break

        stop_after_this = False

        # Pure filler -> stop before using this field
        if tok == "9999":
            stopped_early = True
            break

        # Packed filler handling:
        #   "0999" -> value 0, then stop
        #   "2999" -> value 2, then stop
        #   "-999" -> value -9, then stop (defensive)
        m_packed = re.fullmatch(r"([+-]?\d)999", tok)
        if m_packed:
            val = int(m_packed.group(1))
            stop_after_this = True
            last_hour_was_packed_filler = True
        else:
            val = _parse_int_token(tok)
            if val is None:
                stopped_early = True
                break
            last_hour_was_packed_filler = False

        hours[hour] = val

        if stop_after_this:
            stopped_early = True
            break

    return ParsedDstRow(
        year=year,
        month=month,
        day=day,
        pre_field=pre_field,
        hours=hours,
        stopped_early=stopped_early,
        last_hour_was_packed_filler=last_hour_was_packed_filler,
    )


def parse_all_rows(text: str) -> List[ParsedDstRow]:
    rows: List[ParsedDstRow] = []
    for line in text.splitlines():
        if line.startswith("DST"):
            row = parse_dst_line_fixed(line)
            if row is not None:
                rows.append(row)
    rows.sort(key=lambda r: (r.year, r.month, r.day))
    return rows


def merge_rows(*row_lists: List[ParsedDstRow]) -> List[ParsedDstRow]:
    # Deduplicate by (year, month, day); later lists win
    merged: Dict[Tuple[int, int, int], ParsedDstRow] = {}
    for rows in row_lists:
        for r in rows:
            merged[(r.year, r.month, r.day)] = r
    out = list(merged.values())
    out.sort(key=lambda r: (r.year, r.month, r.day))
    return out


def rows_to_points(rows: List[ParsedDstRow]) -> pd.DataFrame:
    pts: List[Tuple[datetime, int]] = []
    for r in rows:
        for h, v in sorted(r.hours.items()):
            pts.append((datetime(r.year, r.month, r.day, h, 0, 0, tzinfo=timezone.utc), v))

    if not pts:
        return pd.DataFrame(columns=["ts", "value"])

    df = pd.DataFrame(pts, columns=["ts", "value"])
    df = df.drop_duplicates(subset=["ts"], keep="last").sort_values("ts").reset_index(drop=True)
    return df


def _build_maps(rows: List[ParsedDstRow]) -> Tuple[Dict[datetime, int], Dict[Tuple[int, int, int], ParsedDstRow]]:
    parsed_df = rows_to_points(rows)
    parsed_map: Dict[datetime, int] = {
        row.ts.to_pydatetime().astimezone(timezone.utc): int(row.value)
        for row in parsed_df.itertuples(index=False)
    }
    row_by_date: Dict[Tuple[int, int, int], ParsedDstRow] = {
        (r.year, r.month, r.day): r for r in rows
    }
    return parsed_map, row_by_date


def compute_csi_end_hour(rows: List[ParsedDstRow], now_utc: Optional[datetime] = None) -> datetime:
    """
    CSI-like anchor:
    - desired end = previous completed UTC hour (floor(now)-1h)
    - clamp to source-supported end
    - only allow +1 synthetic hour from pre_field if latest parsed hour was NOT a packed X999 edge
    """
    if not rows:
        raise ValueError("no rows")

    now_utc = (now_utc or utc_now()).astimezone(timezone.utc)
    now_floor = now_utc.replace(minute=0, second=0, microsecond=0)
    desired_end = now_floor - timedelta(hours=1)

    parsed_map, row_by_date = _build_maps(rows)
    if not parsed_map:
        raise ValueError("no parsed points")

    latest_parsed_ts = max(parsed_map.keys())
    latest_row = row_by_date.get((latest_parsed_ts.year, latest_parsed_ts.month, latest_parsed_ts.day))

    max_supported_end = latest_parsed_ts
    if (
        latest_row is not None
        and latest_row.pre_field is not None
        and not latest_row.last_hour_was_packed_filler
    ):
        max_supported_end = latest_parsed_ts + timedelta(hours=1)

    return min(desired_end, max_supported_end)


def _is_csi_partial_row_edge_override(ts: datetime, end_hour: datetime, row: ParsedDstRow) -> bool:
    """
    Empirically match CSI partial-row edge behavior.

    For a partial current-day row:
    - Usually force the final emitted hour (end_hour) to pre_field.
    - But if the source row already contains a parsed hour beyond end_hour on that day
      (i.e., Kyoto advanced further than our current output anchor), then keep end_hour
      as parsed and force the previous hour instead.
    """
    if row.pre_field is None:
        return False
    if not row.stopped_early:
        return False
    if (ts.year, ts.month, ts.day) != (end_hour.year, end_hour.month, end_hour.day):
        return False

    row_max_hour = max(row.hours.keys()) if row.hours else None
    if row_max_hour is None:
        return False

    if row_max_hour > end_hour.hour:
        return ts == (end_hour - timedelta(hours=1))
    else:
        return ts == end_hour


def value_for_timestamp(rows: List[ParsedDstRow], ts: datetime, end_hour: Optional[datetime] = None) -> int:
    ts = ts.astimezone(timezone.utc).replace(minute=0, second=0, microsecond=0)
    parsed_map, row_by_date = _build_maps(rows)

    if end_hour is None:
        end_hour = ts

    row = row_by_date.get((ts.year, ts.month, ts.day))

    # CSI partial-row edge override takes precedence
    if row is not None and _is_csi_partial_row_edge_override(ts, end_hour, row):
        return row.pre_field  # type: ignore[return-value]

    # CSI tail-lag rule:
    # If Kyoto row has already advanced beyond our emitted end_hour, pin end_hour to previous parsed hour.
    if (
        row is not None
        and row.stopped_early
        and (ts.year, ts.month, ts.day) == (end_hour.year, end_hour.month, end_hour.day)
    ):
        row_max_hour = max(row.hours.keys()) if row.hours else None
        if row_max_hour is not None and row_max_hour > end_hour.hour and ts == end_hour:
            prev_h = end_hour.hour - 1
            if prev_h in row.hours:
                return row.hours[prev_h]

    val = parsed_map.get(ts)
    if val is not None:
        return val

    # Boundary synthesis from pre_field
    if row is not None and row.pre_field is not None:
        return row.pre_field

    raise ValueError(f"No DST value available for {ts.isoformat()}")


def build_csi_like_last24(rows: List[ParsedDstRow], now_utc: Optional[datetime] = None) -> pd.DataFrame:
    end_hour = compute_csi_end_hour(rows, now_utc=now_utc)
    target_times = [end_hour - timedelta(hours=i) for i in range(23, -1, -1)]

    out_rows: List[Tuple[datetime, int]] = []
    for ts in target_times:
        out_rows.append((ts, value_for_timestamp(rows, ts, end_hour=end_hour)))

    return pd.DataFrame(out_rows, columns=["ts", "value"])


def format_line(ts: datetime, value: int) -> str:
    ts = ts.astimezone(timezone.utc).replace(tzinfo=None)
    return f"{ts:%Y-%m-%dT%H:%M:%S} {int(value)}"


def parse_output_line(line: str) -> Tuple[datetime, int]:
    m = re.fullmatch(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\s+([+-]?\d+)", line.strip())
    if not m:
        raise ValueError(f"Bad dst.txt line: {line!r}")
    ts = datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
    val = int(m.group(2))
    return ts, val


def write_dst_file(df: pd.DataFrame, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    lines: List[str] = []
    for _, row in df.iterrows():
        ts = row["ts"]
        if isinstance(ts, pd.Timestamp):
            ts = ts.to_pydatetime()
        lines.append(format_line(ts, int(row["value"])))
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def append_only_update(output_path: Path, new_ts: datetime, new_val: int) -> None:
    """
    CSI-compatible behavior:
    - normalize existing lines enough to avoid duplicate-tail corruption
    - if new timestamp > last timestamp: append and trim to 24
    - if == last timestamp: do nothing (do not rewrite)
    - if < last timestamp: do nothing
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)

    if not output_path.exists():
        raise FileNotFoundError(str(output_path))

    raw_lines = [ln for ln in output_path.read_text(encoding="utf-8").splitlines() if ln.strip()]
    if not raw_lines:
        raise ValueError("dst.txt exists but is empty")

    # Parse + de-dup by timestamp (keep first to preserve older CSI-like provisional values)
    parsed: List[Tuple[datetime, int]] = []
    for ln in raw_lines:
        parsed.append(parse_output_line(ln))

    dedup: Dict[datetime, int] = {}
    for ts, val in parsed:
        if ts not in dedup:
            dedup[ts] = val

    items = sorted(dedup.items(), key=lambda x: x[0])
    last_ts, _ = items[-1]

    # Guard against duplicate timestamp append
    if new_ts == last_ts:
        # still rewrite normalized file if duplicates were removed
        normalized_lines = [format_line(ts, val) for ts, val in items][-24:]
        if normalized_lines != raw_lines[-24:]:
            output_path.write_text("\n".join(normalized_lines) + "\n", encoding="utf-8")
        return

    if new_ts > last_ts:
        items.append((new_ts, new_val))
        items = items[-24:]
        output_path.write_text("\n".join(format_line(ts, val) for ts, val in items) + "\n", encoding="utf-8")
        return

    # new_ts < last_ts: do not rewrite prior/provisional values; just normalize if needed
    normalized_lines = [format_line(ts, val) for ts, val in items][-24:]
    if normalized_lines != raw_lines[-24:]:
        output_path.write_text("\n".join(normalized_lines) + "\n", encoding="utf-8")
    return


def fetch_rows_for_rebuild(now_utc: datetime, timeout: int, debug: bool = False) -> List[ParsedDstRow]:
    """
    For rebuild/seed:
    - Try current month (presentmonth endpoint)
    - If not enough to build full 24h window, also fetch previous month archive and merge
    """
    current_url = build_presentmonth_url(now_utc)
    current_text = download_text(current_url, timeout=timeout)
    current_rows = parse_all_rows(current_text)

    # Fast path: current month alone works
    try:
        df = build_csi_like_last24(current_rows, now_utc=now_utc)
        if len(df) == 24:
            if debug:
                print(f"[debug] rebuild source: current month only ({current_url})", file=sys.stderr)
            return current_rows
    except Exception:
        pass

    # Fallback: merge previous month archive + current month
    prev_dt = prev_month(now_utc)
    prev_url = build_archive_url(prev_dt)

    prev_rows: List[ParsedDstRow] = []
    prev_err: Optional[Exception] = None
    try:
        prev_text = download_text(prev_url, timeout=timeout)
        prev_rows = parse_all_rows(prev_text)
    except Exception as e:
        prev_err = e

    merged_rows = merge_rows(prev_rows, current_rows)

    # Validate merged rows can build 24h
    _ = build_csi_like_last24(merged_rows, now_utc=now_utc)

    if debug:
        if prev_err is None:
            print(f"[debug] rebuild source: merged previous+current months ({prev_url}) + ({current_url})", file=sys.stderr)
        else:
            print(f"[debug] previous month fetch failed ({prev_url}): {prev_err}", file=sys.stderr)

    return merged_rows


def fetch_rows_for_update(now_utc: datetime, timeout: int) -> List[ParsedDstRow]:
    """
    For normal append-only hourly updates, current month file is typically sufficient.
    """
    current_url = build_presentmonth_url(now_utc)
    current_text = download_text(current_url, timeout=timeout)
    return parse_all_rows(current_text)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", default="/opt/hamclock-backend/htdocs/ham/HamClock/dst/dst.txt")
    ap.add_argument("--url", default=None, help="Override current-month source URL (disables auto month-boundary fallback)")
    ap.add_argument("--timeout", type=int, default=20)
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("--rebuild", action="store_true", help="Force full rebuild of dst.txt instead of append-only update")
    args = ap.parse_args()

    now = utc_now()
    output_path = Path(args.output)

    try:
        if args.url:
            text = download_text(args.url, timeout=args.timeout)
            rows = parse_all_rows(text)
        else:
            if args.rebuild or not output_path.exists():
                rows = fetch_rows_for_rebuild(now, timeout=args.timeout, debug=args.debug)
            else:
                rows = fetch_rows_for_update(now, timeout=args.timeout)
    except requests.RequestException as e:
        print(f"{int(now.timestamp())} Error: download failed: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"{int(now.timestamp())} Error: source preparation failed: {e}", file=sys.stderr)
        return 1

    if not rows:
        print(f"{int(now.timestamp())} Error: no DST rows parsed", file=sys.stderr)
        return 1

    try:
        # Single source of truth for append candidate and rebuild output:
        window_df = build_csi_like_last24(rows, now_utc=now)

        if len(window_df) != 24:
            raise ValueError(f"expected 24 rows, got {len(window_df)}")
        if window_df["ts"].duplicated().any():
            raise ValueError("duplicate timestamps in computed window")
        if not window_df["ts"].is_monotonic_increasing:
            raise ValueError("computed timestamps not increasing")
        diffs = window_df["ts"].diff().dropna()
        if not (diffs == pd.Timedelta(hours=1)).all():
            raise ValueError("computed window has non-hourly cadence")

        last_row = window_df.iloc[-1]
        end_hour = last_row["ts"]
        if isinstance(end_hour, pd.Timestamp):
            end_hour = end_hour.to_pydatetime()
        end_val = int(last_row["value"])
    except Exception as e:
        print(f"{int(now.timestamp())} Error: failed to compute DST window: {e}", file=sys.stderr)
        return 1

    try:
        if args.rebuild or not output_path.exists():
            write_dst_file(window_df, output_path)
        else:
            append_only_update(output_path, end_hour, end_val)
    except Exception as e:
        print(f"{int(now.timestamp())} Error: dst update failed: {e}", file=sys.stderr)
        return 1

    if args.debug:
        try:
            print(window_df.to_string(index=False))
            print(f"\nlatest_end_hour={end_hour.isoformat()} latest_end_val={end_val}")
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
