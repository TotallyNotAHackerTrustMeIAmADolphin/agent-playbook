# Claude Code usage analysis: what the playbook adopted (November 2026)

Source: https://github.com/inevolin/claude-code-usage-analysis (README.md, FINDINGS.md), read 2026-11-17,
plus the Reddit discussion of it (r/ClaudeAI). Third-party study; the playbook cites it, it does not vouch for it.

## Findings adopted (section 2, "A pause past the prompt cache costs a rebuild")

| Finding | Evidence strength | Where |
|---|---|---|
| Cache TTL 5 min (API key, credits) / 1 h (subscription); a miss rewrites the history, about 10 × a fresh small fix at 97k tokens | Best supported: 5 runs warm 1.49-1.52 ×, 5 runs stale 9.76-9.92 × (one session size, Opus 5.5). 1-hour figure calculated | section 2 |
| `/compact` before a pause 2.5 ×; after it 9.7 × (n=2-3) | Measured, small n | section 2 |
| `/clear` plus a 3-line note after a pause is about a fresh start | Measured | sections 2, 7 |
| Changing tool list 22 × (n=2); model switch same effect per vendor docs, not measured; effort, `CLAUDE.md` edit, new MCP server did not break the cache (n=3) | Measured, Claude Code 2.1.325 | section 2 |
| Long tool output +15% to +64% over 6 turns (n=2) | Preliminary | section 7 metrics |
| Scheduled `claude -p` fresh instead of `--resume` (about 3 ×) | Calculated, not tested live | section 7 |
| Raw tokens mislead: equal raw tokens, 6.5 × apart in cost | Measured | section 2 |

## Not adopted

- Compaction trigger tuning (`--autocompact 180000` "43% less"): the study's own simulator failed its back-test; live it tied the default (n=1).
- CLI vs Desktop vs T3 Code overhead (1.80 ×, 1.19 ×): n=1 per client.
- The study's own caveats (FINDINGS.md): ratios against a tiny baseline inflate; units are API list price, not subscription weights.

## Open question from the thread, not answered by the study

Is delegating a search to a sub-agent cheaper than doing it in the main session? Each sub-agent pays its own cache write, so it likely depends on how large the main history already is. Candidate: measure with `ticket-usage.py` cache-weighted before writing a rule. `ticket-usage.py` currently reports raw tokens ("a relative gauge, not cost").
