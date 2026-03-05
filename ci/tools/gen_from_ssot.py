#!/usr/bin/env python3
# ci/tools/gen_from_ssot.py
#
# Phase-1 generator: "lock validator + deterministic regeneration hooks"
# - Reads spec/ssot.lock.md and (optionally) spec/ssot.yaml
# - Ensures sealed constants exist (guardrail)
# - (Later) can be extended to fully regenerate tests/vectors + tests/golden from spec/ssot.yaml
#
# Policy: generator must be deterministic and not depend on environment.

from __future__ import annotations
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LOCK = REPO / "spec" / "ssot.lock.md"
SSOT = REPO / "spec" / "ssot.yaml"


def die(msg: str, code: int = 1) -> None:
    sys.stdout.write(msg + "\n")
    raise SystemExit(code)


def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def main() -> int:
    if not LOCK.is_file():
        die(f"Missing lock file: {LOCK}", 1)

    lock = read_text(LOCK)

    # Guardrail checks: these strings must exist in the lock.
    required_markers = [
        "AllowedJung set (sealed)",
        "{ 0, 4, 8, 11, 13, 18, 19, 20 }",
        "Jung → state (3-bit) mapping (sealed)",
        "E1b — Streaming accumulation & emission",
        "EOF flush (sealed)",
        "LUT — `acc` (0..7) → `u32` word",
        "0x00000013",
        "0x00100513",
        "0x00200513",
        "0x00300513",
        "0x00400513",
        "0x00500513",
        "0x00600513",
        "0x00000073",
        "Atomic write — Option 3 (no contamination)",
        "Base temp name: `.<basename>.belowc.tmp`",
        "try: `.<basename>.belowc.tmp.<n>` for `n = 1..8`",
    ]

    missing = [m for m in required_markers if m not in lock]
    if missing:
        die("ssot.lock.md missing required markers:\n- " + "\n- ".join(missing), 1)

    # Optional presence check for ssot.yaml (we don't parse yet in phase-1).
    if not SSOT.is_file():
        # Not fatal if your project intentionally doesn't ship ssot.yaml,
        # but recommended to exist.
        sys.stdout.write(f"NOTE: ssot.yaml not found at {SSOT} (not fatal in phase-1)\n")

    # Phase-1 does not modify files. It only validates the sealed lock content.
    sys.stdout.write("gen_from_ssot: OK (phase-1 lock validation only)\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
