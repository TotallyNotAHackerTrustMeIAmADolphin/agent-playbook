# Security

Most of this repository is text. The `playbook` plugin under `plugin/` is different: once a
project installs it, its hooks run shell scripts on that machine.

- `WorktreeCreate`: replaces Claude Code's creation of every worktree; it runs `git fetch origin`
  and `git worktree add` under the configured scratch directory.
- `PreToolUse` on `SubagentHandback`: before a builder hands back, runs the project's own check
  command (`PLAYBOOK_BUILDER_CHECK`) in the builder's tree. Running that configured command is
  by design, not a finding.
- `PreToolUse` on `Agent`: reads each dispatch's input and checks the description; runs nothing.

Its agent definitions also steer what agents do in your repository.

Read `plugin/` before installing, and pin the submodule to a commit you have read (README, Get
updates).

## Reporting a vulnerability

Do not open a public issue. Use GitHub's private reporting instead: **Security → Report a
vulnerability** on this repository. Include the affected file, the commit, and a minimal
reproduction. Expect a first answer within a week.

In scope:
- A hook script that can be made to write outside the configured scratch directory or to run
  input as a command.
- Agent or playbook text that tells agents to weaken a safeguard: leaking secrets, skipping a
  review, pushing to `main` or deleting data.

Out of scope: weaknesses in Claude Code itself (report those to Anthropic) and in projects that use
the playbook.
