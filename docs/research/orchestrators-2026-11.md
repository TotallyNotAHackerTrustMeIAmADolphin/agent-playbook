# How others build coding-agent orchestrators (November 2026)

Research for issue #25. Question: how do other systems run one coordinator with many short-lived
coding workers, from ticket to merged PR, behind a review gate, and what should the playbook adopt,
drop or replace?

**Method.** Primary sources only: vendor documentation, the authors' engineering posts, repositories
and papers. Every claim carries a source tag `[Sn]`; the source list at the end gives the URL and the
access date. A claim tagged **unverified (memory)** comes from prior knowledge and was not checked
against a source in this run. Nothing here changes the playbook; each proposal is meant to become its
own ticket.

**Scope.** Ten systems, picked for how close they are to our setup (one long-running coordinator,
short-lived coding sub-agents, tickets to PRs, a separate review gate, git worktrees, a usage budget).
Depth goes to the first five. Not covered in this run: LangGraph, CrewAI, AutoGen, MetaGPT, Factory,
the OpenAI Agents SDK and the Claude Agent SDK as a library (see "Gaps").

## Systems covered

1. **Claude Code sub-agents**: workers spawned by one session, defined in `.claude/agents/` [S1].
2. **Claude Code agent teams**: one lead session plus teammate sessions with a shared task list, experimental [S2].
3. **Claude Code platform pieces we already lean on**: worktrees [S3], hooks and the CLAUDE.md guidance [S4][S5], cost tracking [S6], the hosted Code Review product [S7].
4. **Anthropic's multi-agent research system** (engineering post) [S8].
5. **Anthropic's long-running agent harness** (engineering post) [S9], plus "Building effective agents" [S10].
6. **OpenAI Codex** (cloud tasks, AGENTS.md, code review) [S11][S12][S13].
7. **GitHub Copilot coding agent** [S14][S15].
8. **Cursor cloud (background) agents** [S16].
9. **OpenHands** [S17] and **SWE-agent** [S18] (open source / research).
10. **Aider** architect mode [S19]; **herd** (herd-os/herd) [S20] as an open-source issues-to-PR orchestrator.

### "Herder"

The owner mentioned "Herder". No project of exactly that name could be verified. Searches turned up
three similarly named tools, none of which is clearly the one meant:

- **herdr** (herdrdev/herdr, Apache-2.0): "the runtime your coding agents live on", a terminal
  runtime that keeps agent panes alive, marks each as working, blocked or idle, and lets agents spawn
  panes and message each other through a CLI and socket API. Its README does not mention tickets,
  PRs, review or worktrees [S21]. It is a terminal multiplexer, not a workflow orchestrator.
- **herd** (herd-os/herd, Apache-2.0): decomposes a feature into tasks tied to issues, runs headless
  workers (Claude Code, OpenCode or Codex) in dependency tiers on self-hosted runners, an integrator
  consolidates each tier, a monitor retries failed workers, an agent review with fix cycles runs on
  one batch PR, and a human merges [S20]. This is the closest in shape to our workflow.
- **codeherd**: a CLI that manages worktrees and tmux sessions for parallel agents; seen only in a
  search result, its repository was not read. **Unverified.**

Which one the owner meant stays open; the owner should name it.

## Comparison table

Columns are the questions from the issue's point 2. "n/s" means the source read does not say.

| System | Roles; may the coordinator edit? | Worker isolation | Ticket to merge | Review: separate agent? Gate? | Keeping instructions short | What they measure |
|---|---|---|---|---|---|---|
| **Our playbook** | Owner, coordinator, builder, reviewer, ops agents; coordinator never edits (section 1) | Hand-made git worktree per ticket, detached review tree (section 8, item 8) | Tracker ticket, builder PR, review, `land.sh` squash with pinned head, batch CI, `ship.sh` | Yes, separate `reviewer` dispatch with mutation tests; blocks the merge by risk class (section 5) | One home: `CLAUDE.md` (A10); "keep it short"; no number | Tokens per ticket, review rounds, escape rate, lead time, change failure, idle time (section 9) |
| **Claude Code sub-agents** | Main session delegates; nothing stops it from editing. Sub-agents may nest up to three layers by default [S1] | Optional `isolation: worktree`: temporary worktree from the default branch, removed if unchanged [S1][S3] | Not prescribed; `/batch` has sub-agents publish PRs [S3] | Docs suggest a read-only reviewer sub-agent (`tools: Read, Grep, Glob`), told to "skip style" [S5] | `CLAUDE.md` loaded by every non-Explore/Plan sub-agent unless `omitClaudeMd` [S1] | `maxTurns` per agent; `/usage` attributes usage to sub-agents [S1][S6] |
| **Claude Code agent teams** (experimental) | Lead plus teammates; lead "sometimes starts implementing tasks itself", docs tell you to make it wait [S2] | Own context window each; no file isolation stated, "Two teammates editing the same file leads to overwrites" [S2] | Shared task list with dependencies and file-locked claiming [S2] | Example: three reviewer teammates with distinct lenses; `TaskCompleted` / `TeammateIdle` hooks can block with exit 2 [S2] | Teammates load `CLAUDE.md`, MCP, skills; keep spawn prompts focused [S2][S6] | "approximately 7x more tokens than standard sessions when teammates run in plan mode" [S6] |
| **Anthropic research system** | Lead agent plans, spawns sub-agents, synthesizes; whether the lead searches itself is n/s [S8] | Separate context windows [S8] | n/a (research, not code) | LLM-as-judge evaluation, not a per-task gate [S8] | Effort scaled in the prompt: 1 agent for simple, 2-4 for comparisons, more than 10 for complex [S8] | Token use "explains 80% of the variance"; multi-agent uses about 15x chat tokens; eval started with about 20 queries [S8] |
| **Anthropic long-running harness** | Initializer agent, then a coding agent per session [S9] | n/s | Feature list in JSON, all failing at first; agent may flip only `passes`; one feature at a time; git commits for recovery [S9] | None; says a QA/testing agent "could" help, untested [S9] | Progress file plus git log as the hand-off [S9] | Failure modes listed qualitatively [S9] |
| **OpenAI Codex** | Task per workspace; human reviews and opens the PR [S11] | "Each task has its own workspace"; network destinations can be limited [S11] | Task, diff and checks, follow-ups, then commit or PR by the user [S11] | Code review on GitHub PRs (auto or `@codex review`); a chat review "doesn't post comments, approve it, or merge it" [S13] | `AGENTS.md` layered root to leaf, one per directory, capped by `project_doc_max_bytes` = 32 KiB [S12] | n/s in sources read |
| **GitHub Copilot coding agent** | Agent works on assigned issues; humans review [S15] | GitHub Actions or cloud sandbox; "environment is destroyed after the session ends"; firewall on by default [S14][S15] | Issue, one branch, one PR per task; 59-minute cap per session [S14][S15] | Human review; agent-triggered Actions workflows "require approval from a user with write access" [S15] | Custom instructions (repo, org) [S14]; file names n/s | n/s in sources read |
| **Cursor cloud agents** | n/s | "isolated VMs in the cloud"; network domains can be limited [S16] | Clone, separate branch, push, optional PR [S16] | n/s | Repo hooks in `.cursor/hooks.json` run in the VM [S16]; rule files n/s | n/s |
| **OpenHands / SWE-agent** | Single agent per task | Docker sandbox recommended; process or remote also possible [S17] | Benchmark tasks (SWE-bench) | n/a | SWE-agent: the tool interface ("ACI") design itself raised the solve rate, 12.5% pass@1 on SWE-bench at the time [S18] | Benchmark solve rate [S18] |
| **Aider / herd** | Aider: architect model proposes, editor model edits, sequential [S19]. herd: workers, integrator, monitor, human merges [S20] | herd: self-hosted runners [S20] | herd: feature, issues, tiers, one batch PR [S20] | herd: agent review with fix cycles before a human merge [S20] | n/s | n/s |

## Where we are custom for no reason

1. **Worktree creation and cleanup by hand (section 4, section 8 item 8).** Section 4 says the
   built-in isolation "chooses its own base and cleans up on its own schedule". The current docs say:
   the default base `"fresh"` is the remote default branch, fetched when older than 24 hours (5-second
   cap), falling back to local `HEAD` only without a remote [S3]; a worktree with changes or unpushed
   commits is never swept, and the sweep only touches agent worktrees older than `cleanupPeriodDays`
   [S3]; Claude Code holds a `git worktree lock` while the agent runs [S3]; and a `WorktreeCreate`
   hook can replace creation entirely, including the path [S3]. What the built-in path still does not
   give us: a branch name `ticket-<n>`, a base fetched in the same turn, and a lock that outlives the
   agent until `MERGED`. A `WorktreeCreate` hook that runs our exact `git worktree add --lock` command
   would keep those and drop the hand step from every dispatch. Evidence is the docs only; a trial is
   needed.
2. **The merged-tree check in `land.sh` (section 8, item 5).** A GitHub merge queue builds a
   temporary branch from the latest base plus the queued PRs and merges only after required checks
   pass, with squash supported [S22]. The playbook already says private repos get it only on
   Enterprise Cloud. Which public repos qualify could not be confirmed from the page read; from memory,
   public repositories **owned by an organization** qualify and personal-account repos do not
   (**unverified (memory)**). If the repo qualifies, the merge queue replaces the merge-tree step and
   the "second and later merges" rule.
3. **Usage bookkeeping by hand (A7 `agent-usage:` comments, section 9 "Tokens per ticket").**
   `/usage` already attributes recent usage to sub-agents, skills and MCP servers and recommends
   changes [S6]; OpenTelemetry export streams per-session token and cost metrics [S6]. A script over
   either could fill the metric instead of a comment typed per hand-back. Note `/usage` is per machine
   and approximate [S6].
4. **Instruction-only completion checks (section 4 "Tests in the foreground", A1).** Claude Code docs
   say a rule with no exceptions belongs in a hook, not in `CLAUDE.md`: "If something has to happen
   every time, make it a hook, a deny rule, or a managed setting" [S5]. A `Stop`-type hook exits 2 to
   send the agent back to work until a check passes [S5]; agent definitions accept their own `hooks`
   [S1]. The playbook's own rule ("a rule that fails once in prose moves into tooling", section 6)
   points the same way, and the background-tests nudge "recurs" (section 4). Whether a sub-agent's stop
   hook fires on the sub-agent's hand-back was not verified in this run.

## Where others have evidence and we only have a guess

| Our value | Where | What the sources say | Verdict |
|---|---|---|---|
| Builder ceiling of about 5 | Section 2, P5 | Agent teams: "Start with 3-5 teammates for most workflows"; "Three focused teammates often outperform five scattered ones"; "5-6 tasks per teammate" [S2]. Research system: "most coding tasks involve fewer truly parallelizable tasks than research" [S8]. Token use scales about linearly with active agents [S2][S6]. | Our 5 sits at the top of the vendor range. The evidence is vendor guidance, not a measured study, but it argues for a default of 3 with 5 as the ceiling. |
| `CLAUDE.md` size: "keep it short" | Section 4, A10 | "target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence" [S4]; "Aim to keep CLAUDE.md under 200 lines" [S6]; test for each line: what Claude could not work out from the code [S5]; Codex caps combined `AGENTS.md` at 32 KiB [S12]; auto memory loads the first 200 lines or 25 KB [S4]. Imports do not reduce cost [S4]. | Evidence for a concrete number: 200 lines. Our memory-index budget (about 50 lines, under 6 KB, section 9) is within the vendor limit. |
| Review rounds (2-3 on critical) and the blocker line | Section 5 | "A reviewer that's asked to find problems will always find *something*. If you fix every finding, you end up with extra abstraction layers" [S5]. Code Review defaults to correctness, not style or coverage, and filters findings with a verification step [S7]. | Supports our blocker / low-note line. No source gives a round count. |
| 30-line re-review threshold | Section 5 | No source found. Code Review can be set to run once, after every push, or on request [S7]. | Still a guess. Keep it, label it as one, and measure escapes on skipped re-reviews. |
| Cost of a review agent | Section 5 config-values class | Code Review prices by review level (Quick, Standard, Deep) [S7]; figures are on a costs page not read in this run. Multi-agent runs cost about 15x a chat turn [S8]; teams about 7x a session in plan mode [S6]. | Direction confirmed (review is not cheap), no per-review number verified. |
| Escape rate as the quality metric | Section 9 | Anthropic evaluates with LLM-as-judge on a small fixed set, about 20 real queries to start [S8]. Code Review states a no-finding review does not mean the code is error-free [S7]. | Others measure on a fixed eval set; we measure only in production. See "What we lack". |
| One ticket per builder | Core, section 8 | Harness: "work on only one feature at a time" was "critical" [S9]; Copilot: one branch, one PR per task [S14]. | Confirmed. |
| Coordinator never edits | Section 1 | Agent teams docs treat a lead that implements as a failure to correct: "Wait for your teammates to complete their tasks before proceeding" [S2]. Research system: the lead plans and synthesizes [S8]. | Consistent with vendor practice; no cost study found. |

## What we lack

1. **A fixed evaluation set for playbook changes.** Anthropic started with about 20 real queries and
   an LLM judge, and found token use explains 80% of performance variance [S8]. Our PDCA (section 9)
   waits about 10 live tickets per change. A replay set of past tickets with known outcomes would let a
   rule change be tested before it ships.
2. **Ephemeral sandboxes with a default egress limit.** Copilot destroys the environment after each
   session and has a firewall on by default [S15]; Codex and Cursor let the environment limit network
   destinations [S11][S16]; OpenHands recommends a Docker sandbox [S17]. Our section 6 lists a sandbox
   and an egress allowlist as options among many.
3. **A verification pass inside review.** Code Review runs several finders in parallel, then a
   verification step that drops false positives before anything is posted [S7]. Our reviewer is one
   agent; the class disagreement rule (section 5) is our only filter.
4. **Human approval before agent-triggered CI runs.** Copilot requires a write-access user to approve
   workflows on agent PRs [S15]. Our batch CI runs after merge; hosted CI on agent PRs is not discussed.
5. **A hard wall-clock cap per worker.** Copilot caps a session at 59 minutes [S14]. We cap turns
   (`maxTurns`) only; `--max-budget-usd` exists for headless runs [S5].
6. **The reviewer cannot nest agents.** Sub-agents may spawn sub-agents up to three layers by default
   [S1]. A1 sets `disallowedTools: Agent` for the builder; A2 (reviewer) and A11 (researcher) do not.

## Proposals

Each line: playbook section, action, evidence. Each should become its own ticket linking to #25.

1. **Section 4 "Worktrees are created by hand" and section 8 item 8: replace** the hand-made
   worktree step with a `WorktreeCreate` hook (or `isolation: worktree` after a trial) that runs our
   exact create command, and correct the stated reason, which no longer matches the docs. Evidence:
   [S3] fresh base from the remote default branch, kept when it holds work, lock while running,
   creation replaceable by hook.
2. **Section 9 and A10: adopt** a size budget of 200 lines for `CLAUDE.md`, with the vendor test
   "what Claude could not work out from the code", and path-scoped `.claude/rules/` for module-only
   rules. Evidence: [S4][S5][S6]; Codex's 32 KiB cap [S12].
3. **Section 2 and P5: replace** "1 to about 5 builders" with a default of 3 and a ceiling of 5,
   citing the vendor guidance instead of our own guess. Evidence: [S2][S8].
4. **Section 4 "Tests in the foreground" and A1: replace** the instruction with a hook in the
   builder definition that refuses hand-back until the targeted tests pass (exit 2). Evidence: [S1]
   agent-level `hooks`; [S5] Stop-hook pattern and "make it a hook". Verify first that the hook fires
   on a sub-agent's hand-back.
5. **Section 8 item 5 (merged-tree check) and item 10 (`land.sh`): replace** with a GitHub merge
   queue once the public repo is confirmed eligible; keep the script steps the queue does not cover
   (pinned head, closed-issue check, cleanup). Evidence: [S22]; eligibility unverified.
6. **Section 9 metric "Tokens per ticket" and A7 `agent-usage:` line: replace** the hand-posted
   comment with a script over OpenTelemetry export or `/usage` attribution. Evidence: [S6].
7. **Section 9 PDCA: adopt** a replay set of about 20 closed tickets to test a rule change before it
   ships. Evidence: [S8].
8. **Section 5 "Re-review only when it pays": keep, mark as a guess.** Label the 30-line threshold as
   an uncalibrated starting value and add "escapes after a skipped re-review" to the metrics. Evidence:
   none found for any threshold; [S7] offers per-push or on-request triggers only.
9. **Section 5 reviewer: adopt** a verification pass: each blocker the reviewer reports must come with
   a reproducing command or failing test before the coordinator classes it. Evidence: [S7] finders plus
   verification step; [S5] reviewers always find something.
10. **Section 6 security model: adopt** a sandbox with an egress allowlist as the default for builders
    and reviewers, not one option among many. Evidence: [S15][S11][S16][S17].
11. **A2 reviewer and A11 researcher: adopt** `disallowedTools: Agent`, as A1 already does. Evidence:
    [S1] default nesting depth of three.
12. **Agent teams: drop as a candidate for builders, for now.** Teams are experimental, cannot be
    resumed with in-process teammates, give no file isolation, and start teammates in the lead's
    permission mode [S2]. Revisit for parallel review lenses only (security, performance, tests), which
    is the docs' own example [S2].

## Gaps and open questions

- Not covered: LangGraph, CrewAI, AutoGen, MetaGPT, Factory, the OpenAI Agents SDK, the Claude Agent
  SDK as a library. Devin's docs page read gave too little to fill a row [S23].
- Not verified: merge queue eligibility for public personal-account repos; Code Review per-review
  cost; whether a sub-agent `Stop`/`SubagentStop` hook can block a sub-agent's hand-back; Copilot's
  instruction file names; Codex isolation details beyond "own workspace" (the original launch post
  returned 403).
- "Herder": not identified; three candidates listed above.
- Terms: no code or text from any source is reused here beyond short quotes, so no terms of use were
  checked. Adopting herd or herdr code would need its Apache-2.0 terms read first.

## Sources

All accessed 2026-11-05.

- [S1] Claude Code docs, "Create custom subagents": https://code.claude.com/docs/en/sub-agents
- [S2] Claude Code docs, "Orchestrate teams of Claude Code sessions": https://code.claude.com/docs/en/agent-teams
- [S3] Claude Code docs, "Run parallel sessions with worktrees": https://code.claude.com/docs/en/worktrees
- [S4] Claude Code docs, "How Claude remembers your project": https://code.claude.com/docs/en/memory
- [S5] Claude Code docs, "Best practices for Claude Code": https://code.claude.com/docs/en/best-practices
- [S6] Claude Code docs, "Manage costs effectively": https://code.claude.com/docs/en/costs
- [S7] Claude Code docs, "Code Review": https://code.claude.com/docs/en/code-review
- [S8] Anthropic Engineering, "How we built our multi-agent research system" (2025-06-13): https://www.anthropic.com/engineering/multi-agent-research-system
- [S9] Anthropic Engineering, "Effective harnesses for long-running agents" (2025-11-26): https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
- [S10] Anthropic Engineering, "Building effective agents" (2024-12-19): https://www.anthropic.com/engineering/building-effective-agents
- [S11] OpenAI Codex docs, "Cloud": https://learn.chatgpt.com/docs/cloud (redirected from https://developers.openai.com/codex/cloud)
- [S12] OpenAI Codex docs, "AGENTS.md": https://learn.chatgpt.com/docs/agent-configuration/agents-md (redirected from https://developers.openai.com/codex/guides/agents-md)
- [S13] OpenAI Codex docs, "Code review": https://learn.chatgpt.com/docs/code-review
- [S14] GitHub Docs, "About Copilot coding agent": https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-coding-agent
- [S15] GitHub Docs, "Responsible use of Copilot coding agent": https://docs.github.com/en/copilot/responsible-use/copilot-coding-agent
- [S16] Cursor docs, "Background agents": https://cursor.com/docs/background-agent
- [S17] OpenHands docs, "Runtimes overview": https://docs.openhands.dev/usage/runtimes/overview
- [S18] Yang et al., "SWE-agent: Agent-Computer Interfaces Enable Automated Software Engineering", arXiv:2405.15793: https://arxiv.org/abs/2405.15793
- [S19] Aider docs, "Chat modes": https://aider.chat/docs/usage/modes.html
- [S20] herd-os/herd repository README: https://github.com/herd-os/herd
- [S21] herdrdev/herdr repository README: https://github.com/herdrdev/herdr
- [S22] GitHub Docs, "Managing a merge queue": https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue
- [S23] Devin docs, "Introducing Devin": https://docs.devin.ai/get-started/devin-intro

[S10] backs the general stance that complexity should be added only when needed ("finding the
simplest solution possible, and only increasing complexity when needed") and the orchestrator-workers
and evaluator-optimizer patterns our coordinator/builder/reviewer split maps onto.
