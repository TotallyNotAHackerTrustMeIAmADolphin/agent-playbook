#!/usr/bin/env python3
"""Subscription usage limits as Claude Code sees them (playbook section 7, P10).

Runs `claude -p /usage` in a temp directory: no model call, no tokens, no project hooks. Prints one
line per limit (session = the 5-hour window, weekly_all, weekly_scoped per model) with its percent
and reset time in local time. With --max-session / --max-weekly it exits 3 when the session
window, 4 when the weekly limit (weekly_all) is at or above the threshold (weekly wins).
Exit 1: the limits could not be read (then say so; never guess them).

Every call queries a rate-limited endpoint: check before a dispatch, not in a loop.

Usage: python3 usage.py [--max-session 95] [--max-weekly 95]
"""
import argparse
import datetime
import json
import shutil
import subprocess
import sys
import tempfile


def read_limits():
    exe = shutil.which("claude")
    if not exe:
        sys.exit("usage.py: the claude command is not on PATH")
    # An argument list, no shell: Git Bash cannot rewrite "/usage" into a path here.
    out = subprocess.run([exe, "-p", "/usage", "--output-format", "stream-json", "--verbose"],
                         cwd=tempfile.gettempdir(), capture_output=True, text=True,
                         encoding="utf-8", errors="replace", timeout=120).stdout
    for line in out.splitlines():
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        report = msg.get("usage_report") if isinstance(msg, dict) else None
        if report and (report.get("rate_limits") or {}).get("limits"):
            return report["rate_limits"]["limits"]
    return None


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--max-session", type=float, help="exit 3 at or above this percent (P10)")
    ap.add_argument("--max-weekly", type=float, help="exit 4 at or above this percent (P10)")
    args = ap.parse_args(argv)
    try:
        limits = read_limits()
    except (OSError, subprocess.SubprocessError) as e:
        sys.exit(f"usage.py: claude -p /usage failed: {e}")
    if not limits:
        sys.exit("usage.py: no usage report (not logged in with a subscription, or an old Claude Code)")
    pct = {}
    for lim in limits:
        name = lim.get("kind", "?")
        model = ((lim.get("scope") or {}).get("model") or {}).get("display_name")
        if model:
            name += f" ({model})"
        reset = lim.get("resets_at")
        if reset:
            try:
                reset = datetime.datetime.fromisoformat(reset.replace("Z", "+00:00")).astimezone()
                reset = reset.strftime("%Y-%m-%d %H:%M UTC%z")
            except ValueError:
                pass  # print the raw value
        print(f"{name}: {lim.get('percent')}% used, resets {reset or '-'}")
        if isinstance(lim.get("percent"), (int, float)):
            pct.setdefault(lim.get("kind"), lim["percent"])
    for kind, limit in (("weekly_all", args.max_weekly), ("session", args.max_session)):
        if limit is not None and kind not in pct:
            print(f"usage.py: no {kind} percent in the report; cannot check the threshold", file=sys.stderr)
            return 1
    if args.max_weekly is not None and pct["weekly_all"] >= args.max_weekly:
        print(f"OVER weekly threshold {args.max_weekly:g}%: stop developing (section 7)")
        return 4
    if args.max_session is not None and pct["session"] >= args.max_session:
        print(f"OVER session threshold {args.max_session:g}%: no new dispatch (section 7)")
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
