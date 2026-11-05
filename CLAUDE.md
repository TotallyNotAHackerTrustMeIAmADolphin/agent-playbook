# agent-playbook: Maintainer Context

## What this repo is
The central, project-agnostic Agent Workflow Playbook (`AGENT-WORKFLOW-PLAYBOOK.md`).
Projects include it as a git submodule at `docs/playbook/` and keep their own rules in
their `CLAUDE.md` only (A10). Setup, updates and feedback: see `README.md`.

## Ground rules
- The playbook's own rule applies: every rule stands exactly once, where it is executed.
  A new rule replaces or removes one. Link instead of copying.
- Keep it project-agnostic. Project values, names and incident evidence belong in the project's `CLAUDE.md` or `docs/HISTORY.md`.
- Section numbers and anchors (Core, 0-13, A1-A12, P1-P17) are cited by projects. Do not
  renumber or rename them without a note in the commit message. Keep the `<!-- toc -->` list in sync.
- The awk command on line 10 assumes the path `docs/playbook/`. Do not change the path.
- No secrets, customer data or private project details in this repo or its issues.
- Change via branch + PR. Small, one topic per commit.

## Feedback issues (label `feedback`)
Agents from other projects report problems as GitHub issues here.
1. `gh issue list -l feedback` at session start when asked to maintain the playbook.
2. Check the claim against the playbook text; ask the reporter's project only if evidence is missing.
3. Fix by editing or removing a rule (not by adding a parallel one), reference the issue in the
   commit (`Fixes #n`), and comment what changed so projects know to bump the submodule.
4. Reject with a short reason if it is project-specific: it belongs in that project's `CLAUDE.md`.

## Not here
Do not edit a project's `docs/playbook/` checkout. Fix it in this repo, then bump the pointer there.
