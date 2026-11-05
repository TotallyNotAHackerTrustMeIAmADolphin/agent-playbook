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
(`cleanupPeriodDays`), only dispatches whose description starts with `#<n>` (the rest, and
`#0` for work without a ticket, are counted and reported as unattributed). In single-writer mode the session's own work is not a sub-agent and is
not counted.

--by-action: where the tokens go. Every turn re-reads the whole context, so a tool result costs
its size again on every later API call of that agent until a compaction drops it. Per action
(tool name; shell tools by the command's first word; Agent by type) the script prints calls,
errors, result tokens and carried tokens (result tokens x the later API calls that re-read them),
then the single results that were carried most. It reads the sub-agents and the sessions' own
transcripts (with --ticket, only that ticket's sub-agents). Result tokens are estimated: text at
2 characters per token (calibrated on context growth in real transcripts: median 1.9, Bash and
Read about 2.1, WebFetch and Grep about 1.45), fixed values for images, PDFs and tool
references. Not counted: tool inputs (a long Write is re-read too) and the few results a
compaction keeps. A gauge for ranking actions, not a bill.

Usage: python3 ticket-usage.py [--project <repo dir>] [--ticket <n>] [--factor 3]
       python3 ticket-usage.py --by-action [--project <repo dir>] [--ticket <n>] [--top 15]
"""
import argparse
import glob
import json
import os
import re
import shlex
import statistics
import sys

TICKET = re.compile(r"\s*#(\d+)\b")
SHELL = ("Bash", "PowerShell")
ASSIGN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
SEGMENT = re.compile(r"&&|\|\||[;|\n]")
PREFIX = ("do", "then", "else", "time", "nice", "timeout")
SKIP = ("cd", "Set-Location", "pushd", "for", "while", "until", "if", "elif", "foreach", "done",
        "fi", "}", "function", "case", "esac", "")
CHARS_PER_TOKEN = 2
BLOCK_TOKENS = {"image": 1600, "document": 3000, "tool_reference": 550}  # measured medians, rounded


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


def subagents(pdir):
    """(ticket or None, role, transcript path) per sub-agent dispatch."""
    rows = []
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
        ticket = ticket or None  # '#0' marks work without a ticket: unattributed
        rows.append((ticket, meta.get("agentType") or "?", transcript))
    return rows


def collect(pdir):
    return [(t, role, agent_tokens(p)) for t, role, p in subagents(pdir)]


def shell_command(command):
    """First command word that is not a cd, a loop header, an export or a variable assignment."""
    for part in SEGMENT.split(command):
        try:
            words = shlex.split(part, comments=True, posix=False)
        except ValueError:
            words = part.split()
        words = [w.lstrip("({&") for w in words]
        words = [w for w in words if w]
        while words and (words[0] in PREFIX or re.fullmatch(r"-n|-?\d+[smh]?", words[0])):
            words = words[1:]  # timeout 300 x, nice -n 10 x: x is the command
        while words and (ASSIGN.match(words[0]) or words[0] in ("export", "env")):
            if "$(" in words[0]:  # x=$(git ...): the command substitution is the command
                words = [words[0].split("$(", 1)[1]] + words[1:]
                break
            words = words[1:]
        if words and words[0].startswith("$") and ("=" in words[0] or words[1:2] == ["="]):
            continue  # PowerShell: $x = ...
        if words and words[0].split("(")[0] not in SKIP and "()" not in words[0]:
            return os.path.basename(words[0].strip("\"')").replace("\\", "/")) or "?"
    return "?"


def action_label(name, inp):
    if name in SHELL:
        return f"{name}:{shell_command(str(inp.get('command') or ''))}"
    if name == "Agent":
        return f"Agent:{inp.get('subagent_type') or 'general-purpose'}"
    return name


def action_detail(name, inp):
    if name in SHELL:
        return " ".join(str(inp.get("command") or "").split())[:80]
    for key in ("file_path", "pattern", "url", "description", "query", "to"):
        if inp.get(key):
            return " ".join(str(inp[key]).split())[:80]
    return ""


def result_tokens(content):
    if isinstance(content, str):
        return len(content) // CHARS_PER_TOKEN
    n = 0
    for b in content if isinstance(content, list) else []:
        kind = b.get("type") if isinstance(b, dict) else None
        if kind == "text":
            n += len(b.get("text") or "") // CHARS_PER_TOKEN
        else:
            n += BLOCK_TOKENS.get(kind, 0)
    return n


def action_rows(path):
    """(action, detail, is_error, result tokens, carried tokens) per tool result."""
    calls, seen, done, live = {}, set(), [], []  # live: [action, detail, error, tokens, re-reads]
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            kind, m = d.get("type"), d.get("message") or {}
            if kind == "system" and d.get("subtype") == "compact_boundary":
                done, live = done + live, []  # the summary replaces them
            elif kind == "assistant":
                key = m.get("id") or d.get("uuid")
                if m.get("usage") and key not in seen:  # one API call, streamed over several lines
                    seen.add(key)
                    for r in live:
                        r[4] += 1
                for b in m.get("content") or []:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                        name = b.get("name") or "?"
                        calls[b.get("id")] = (action_label(name, inp), action_detail(name, inp))
            elif kind == "user" and isinstance(m.get("content"), list):
                for b in m["content"]:
                    if isinstance(b, dict) and b.get("type") == "tool_result":
                        action, det = calls.get(b.get("tool_use_id"), ("?", ""))
                        live.append([action, det, bool(b.get("is_error")),
                                     result_tokens(b.get("content")), 0])
    return [(a, det, e, t, t * n) for a, det, e, t, n in done + live], len(seen)


def by_action(pdir, ticket, top):
    if ticket is None:
        paths = glob.glob(os.path.join(glob.escape(pdir), "*.jsonl"))
        paths += [p for _, _, p in subagents(pdir)]
    else:
        paths = [p for t, _, p in subagents(pdir) if t == ticket]
    if not paths:
        print("no transcripts" + (f" for #{ticket}" if ticket else ""), file=sys.stderr)
        return 1
    agg, single, processed, api_calls = {}, [], 0, 0
    for path in paths:
        processed += agent_tokens(path)
        rows, n = action_rows(path)
        api_calls += n
        for action, det, err, tokens, carried in rows:
            a = agg.setdefault(action, [0, 0, 0, 0])
            a[0], a[1], a[2], a[3] = a[0] + 1, a[1] + err, a[2] + tokens, a[3] + carried
            single.append((carried, tokens, action, det))
    total = sum(a[3] for a in agg.values()) or 1
    print(f"{len(paths)} transcripts, {api_calls} API calls, {processed} tokens processed"
          f" ({processed // max(api_calls, 1)} per call); carried tool results, estimated:"
          f" about {total}")
    print("action\tcalls\terrors\tresult_tokens\tcarried_tokens\tshare")
    ranked = sorted(agg.items(), key=lambda kv: -kv[1][3])
    if len(ranked) > top:
        rest = [sum(a[i] for _, a in ranked[top:]) for i in range(4)]
        ranked = ranked[:top] + [(f"other ({len(ranked) - top} actions)", rest)]
    for action, a in ranked:
        print(f"{action}\t{a[0]}\t{a[1]}\t{a[2]}\t{a[3]}\t{100 * a[3] / total:.0f}%")
    print(f"\ncarried most (top {top}):\ncarried_tokens\tresult_tokens\taction\tdetail")
    for carried, tokens, action, det in sorted(single, reverse=True)[:top]:
        print(f"{carried}\t{tokens}\t{action}\t{det}")
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--project", default=".", help="repo dir the coordinator runs in (default: .)")
    ap.add_argument("--ticket", type=int, help="print only this ticket")
    ap.add_argument("--factor", type=float, default=3.0, help="flag above factor x median")
    ap.add_argument("--by-action", action="store_true", help="tokens per action, not per ticket")
    ap.add_argument("--top", type=int, default=15, help="--by-action: rows and results to list")
    a = ap.parse_args(argv)

    pdir = project_dir(a.project)
    if not os.path.isdir(pdir):
        print(f"no transcripts at {pdir}", file=sys.stderr)
        return 1
    if a.by_action:
        return by_action(pdir, a.ticket, a.top)
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
