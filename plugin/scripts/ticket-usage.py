#!/usr/bin/env python3
"""Tokens per ticket from Claude Code's sub-agent transcripts (playbook section 9).

Every sub-agent dispatch has a description that starts with its issue number, `#<n> ...`
(playbook section 4); a PR number later in the description is ignored. Claude Code stores each
sub-agent's transcript and that description under
<config>/projects/<project slug>/<session>/subagents/. This script sums the tokens of every
assistant message per ticket and flags tickets above 3 x the median.

Tokens per message = input + cache creation + cache read + output: what the model processed,
so it grows with turns times context. A relative gauge, not cost: cache reads dominate and
models differ. Each message id counts once.

Limits: only this machine, only transcripts Claude Code has not cleaned up yet
(`cleanupPeriodDays`), only dispatches whose description starts with `#<n>` (the rest are
counted and reported). In single-writer mode the session's own work is not a sub-agent and is
not counted.

Usage: python3 ticket-usage.py [--project <repo dir>] [--ticket <n>] [--factor 3]
"""
import argparse
import glob
import json
import os
import re
import statistics
import sys

TICKET = re.compile(r"\s*#(\d+)\b")


def project_dir(repo):
    config = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    slug = re.sub(r"[^A-Za-z0-9]", "-", os.path.abspath(repo))
    return os.path.join(config, "projects", slug)


def agent_tokens(path):
    seen, total = set(), 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") != "assistant":
                continue
            m = d.get("message") or {}
            u = m.get("usage") or {}
            key = m.get("id") or d.get("uuid")
            if not u or key in seen:
                continue
            seen.add(key)
            total += sum(int(u.get(k) or 0) for k in (
                "input_tokens", "cache_creation_input_tokens",
                "cache_read_input_tokens", "output_tokens"))
    return total


def collect(pdir):
    rows = []  # (ticket or None, role, tokens)
    pattern = os.path.join(glob.escape(pdir), "*", "subagents", "*.meta.json")
    for meta_path in glob.glob(pattern):
        try:
            with open(meta_path, encoding="utf-8") as f:
                meta = json.load(f)
        except (OSError, ValueError):
            continue
        transcript = meta_path[: -len(".meta.json")] + ".jsonl"
        if not os.path.exists(transcript):
            continue
        hit = TICKET.match(meta.get("description") or "")
        ticket = int(hit.group(1)) if hit else None
        rows.append((ticket, meta.get("agentType") or "?", agent_tokens(transcript)))
    return rows


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--project", default=".", help="repo dir the coordinator runs in (default: .)")
    ap.add_argument("--ticket", type=int, help="print only this ticket")
    ap.add_argument("--factor", type=float, default=3.0, help="flag above factor x median")
    a = ap.parse_args(argv)

    pdir = project_dir(a.project)
    if not os.path.isdir(pdir):
        print(f"no transcripts at {pdir}", file=sys.stderr)
        return 1
    per_ticket, skipped, skipped_tokens = {}, 0, 0
    for ticket, role, tokens in collect(pdir):
        if ticket is None:
            skipped, skipped_tokens = skipped + 1, skipped_tokens + tokens
            continue
        t = per_ticket.setdefault(ticket, {})
        t[role] = t.get(role, 0) + tokens
    if skipped:
        print(f"not attributed: {skipped} dispatches, {skipped_tokens} tokens"
              " (description does not start with #<n>)", file=sys.stderr)
    if not per_ticket:
        print("no dispatch description starts with #<n>", file=sys.stderr)
        return 1
    totals = {n: sum(r.values()) for n, r in per_ticket.items()}
    median = statistics.median(totals.values())
    shown = [n for n in sorted(totals) if a.ticket is None or n == a.ticket]
    if not shown:
        print(f"no dispatch for #{a.ticket}", file=sys.stderr)
        return 1
    print(f"ticket\ttokens\tflag\troles (median {median:.0f})")
    for n in shown:
        flag = "HIGH" if totals[n] > a.factor * median else ""
        roles = ", ".join(f"{r} {v}" for r, v in sorted(per_ticket[n].items()))
        print(f"#{n}\t{totals[n]}\t{flag}\t{roles}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
