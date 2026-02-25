#!/usr/bin/env python3
"""
hc_zlib.py

Shared helpers for HamClock-style .z files (zlib-compressed payloads).
"""

from __future__ import annotations
import zlib


def zread(path: str) -> bytes:
    data = open(path, "rb").read()
    return zlib.decompress(data) if path.endswith(".z") else data


def zwrite(path: str, blob: bytes, level: int = 9):
    with open(path, "wb") as f:
        f.write(zlib.compress(blob, level))


def zcompress_file(in_path: str, out_path: str, level: int = 9):
    data = open(in_path, "rb").read()
    zwrite(out_path, data, level=level)
