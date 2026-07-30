#!/usr/bin/env python3
"""
apply_config.py - populate the SparkNotebooks from a single git-ignored .env file.

Why a script (and not runtime file reads): the Microsoft Sentinel notebook kernel runs on
a cloud Spark pool, so a cell cannot read a local .env at run time. Instead we stamp the
tenant-specific workspace name from .env into the notebooks locally, before you run them,
and restore the placeholder before you commit, so the real name is never checked in.

Usage:
    python3 apply_config.py apply     # .env value  -> notebooks (do this before running)
    python3 apply_config.py reset     # notebooks   -> placeholder (do this before commit)
    python3 apply_config.py check     # exit 1 if a real workspace name is present (pre-commit/CI)
    python3 apply_config.py status    # show current state of each notebook

Config key (in .env):  SENTINEL_WORKSPACE_NAME
Placeholder token in the notebooks:  your-workspace-name
"""
from __future__ import annotations
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(HERE, ".env")
NOTEBOOKS = sorted(glob.glob(os.path.join(HERE, "demos", "*.ipynb")))
PLACEHOLDER = "your-workspace-name"
KEY = "SENTINEL_WORKSPACE_NAME"


def read_env(path: str) -> dict[str, str]:
    values: dict[str, str] = {}
    if not os.path.exists(path):
        return values
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            values[k.strip()] = v.strip().strip('"').strip("'")
    return values


def workspace_from_env() -> str:
    env = read_env(ENV_PATH)
    val = env.get(KEY, "").strip()
    if not val:
        sys.exit(f"ERROR: {KEY} not set in {ENV_PATH}. Copy .env.example to .env and set it.")
    return val


def replace_in_notebooks(old: str, new: str) -> int:
    if old == new:
        return 0
    changed = 0
    for nb in NOTEBOOKS:
        with open(nb, encoding="utf-8") as fh:
            text = fh.read()
        if old in text:
            with open(nb, "w", encoding="utf-8") as fh:
                fh.write(text.replace(old, new))
            print(f"  updated {os.path.relpath(nb, HERE)} ({text.count(old)} occurrence(s))")
            changed += 1
    return changed


def cmd_apply() -> int:
    ws = workspace_from_env()
    if ws == PLACEHOLDER:
        print(f"{KEY} is still the placeholder; nothing to inject. Set a real value in .env.")
        return 0
    print(f"Injecting workspace '{ws}' into {len(NOTEBOOKS)} notebook(s)...")
    n = replace_in_notebooks(PLACEHOLDER, ws)
    print(f"Done. {n} notebook(s) updated. Remember: run 'reset' before you commit.")
    return 0


def cmd_reset() -> int:
    ws = workspace_from_env()
    if ws == PLACEHOLDER:
        print("Notebooks already use the placeholder; nothing to reset.")
        return 0
    print(f"Restoring placeholder in {len(NOTEBOOKS)} notebook(s)...")
    n = replace_in_notebooks(ws, PLACEHOLDER)
    print(f"Done. {n} notebook(s) reset to '{PLACEHOLDER}'.")
    return 0


def cmd_check() -> int:
    env = read_env(ENV_PATH)
    ws = env.get(KEY, "").strip()
    if not ws or ws == PLACEHOLDER:
        print("check: no real workspace name configured; nothing could leak. OK.")
        return 0
    offenders = []
    for nb in NOTEBOOKS:
        with open(nb, encoding="utf-8") as fh:
            if ws in fh.read():
                offenders.append(os.path.relpath(nb, HERE))
    if offenders:
        print("check: FAIL - real workspace name found in:")
        for o in offenders:
            print("  -", o)
        print("Run 'python3 apply_config.py reset' before committing.")
        return 1
    print("check: OK - no real workspace name present in notebooks.")
    return 0


def cmd_status() -> int:
    env = read_env(ENV_PATH)
    ws = env.get(KEY, "").strip() or "(unset)"
    print(f".env {KEY} = {ws}")
    for nb in NOTEBOOKS:
        with open(nb, encoding="utf-8") as fh:
            text = fh.read()
        state = "placeholder" if PLACEHOLDER in text else "populated"
        print(f"  {os.path.relpath(nb, HERE):45s} {state}")
    return 0


COMMANDS = {"apply": cmd_apply, "reset": cmd_reset, "check": cmd_check, "status": cmd_status}


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        return 2
    if not NOTEBOOKS:
        sys.exit(f"ERROR: no notebooks found under {os.path.join(HERE, 'demos')}")
    return COMMANDS[sys.argv[1]]()


if __name__ == "__main__":
    raise SystemExit(main())
