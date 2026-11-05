# agent-playbook

A playbook for running software projects with [Claude Code](https://claude.com/claude-code) agents:
one long-running **coordinator** session picks tickets from GitHub issues, dispatches **builder**
sub-agents that each work in their own git worktree and open a pull request, has code PRs reviewed
by an independent **reviewer** agent (by risk class), and merges only the reviewed commit. The rules
for that loop are in [`AGENT-WORKFLOW-PLAYBOOK.md`](AGENT-WORKFLOW-PLAYBOOK.md); its Core section
(about 70 lines) is read at session start, the rest is looked up when needed.

**Who it is for:** someone who already uses Claude Code on a GitHub repository and wants agents to
work through a backlog with review gates, usage limits and cleanup, instead of one chat at a time.
You need `git`, `gh` (logged in), `bash` with `timeout` and `perl` (Git Bash on Windows has both; on
macOS install coreutils) and Python 3.

**What you get:**
- the playbook text, pinned per project as a git submodule, so every project reads the same rules;
- a Claude Code plugin with the builder, reviewer and researcher agents and hooks that create
  every agent worktree from a fresh `origin/main`, refuse a builder's hand-back while the
  project's check fails, and optionally refuse a dispatch without a ticket number;
- coordinator scripts: merge a reviewed PR (`land.sh`), clean up (`hygiene.sh`), run the full
  suite once per batch (`batch-ci.sh`, pytest-shaped runners), read the usage limits (`usage.py`),
  count tokens per ticket and per action (`ticket-usage.py`), and check a project's setup
  (`check-setup.sh`).

**Status:** it grew out of one owner's projects and is changed through the feedback of the agents
that use it (see [Give feedback](#give-feedback-agents-do-this-it-improves-it-for-everyone)). Expect
it to change; a project pins a commit and bumps when it wants. A project's own rules (its answers to
the playbook's questions P1-P17, section 0) live in one place only: its `CLAUDE.md`, shaped by the
playbook's template A10.

## Use it in a project

```bash
git submodule add https://github.com/TotallyNotAHackerTrustMeIAmADolphin/agent-playbook.git docs/playbook
git commit -m "Add agent playbook submodule"
```

Fixed path: `docs/playbook/` (the playbook's own commands assume it). Then write `CLAUDE.md`
from A10; the line under its title points every session at Core. Evidence and history go to
`docs/HISTORY.md`. There is no second project rule file (only module-scoped `.claude/rules/`, A10).

The builder, reviewer and researcher agents ship from this repo as the `playbook` plugin. Load it
from the submodule in each clone (it writes the absolute path to the uncommitted
`.claude/settings.local.json`). The plugin depends on `mattpocock-skills` (playbook section 3) and
installs it too, from the official marketplace; without that marketplace the plugin does not load:

```bash
claude plugin marketplace add anthropics/claude-plugins-official   # once per user, if missing
claude plugin marketplace add ./docs/playbook --scope local
claude plugin install playbook@agent-playbook --scope local
```

Install or update it while no playbook agent runs (its hand-back hook acts on builders already in
flight), and from the submodule, not from GitHub: a GitHub source follows the playbook's `main`,
not the commit the project pins.

Claude Code reads the plugin in place from the folder (not a cached copy), so bumping the
submodule also updates the agents at the next session start; the plugin version does not matter.
The marketplace registration is per user, though: on a machine with several projects, the one that
ran `marketplace add` last serves the plugin to all of them (`claude plugin list` shows it under
"Read from"). Re-run the two commands in the project you work in, or start sessions with
`claude --plugin-dir docs/playbook/plugin`, which replaces the installed copy for that session.
`check-setup.sh` names the clone that serves the plugin.

The builder model and the hand-back check go into the committed `.claude/settings.json` (it
applies to every sub-agent whose definition names no model, playbook P5); the scratch directory,
an absolute path that differs per machine, into `.claude/settings.local.json`:

```json
{ "env": {
  "CLAUDE_CODE_SUBAGENT_MODEL": "<builder model>",
  "PLAYBOOK_BUILDER_CHECK": "<targeted tests + guard tests + linter, under 9 minutes>",
  "PLAYBOOK_REQUIRE_TICKET": "1"
} }
```

```json
{ "env": { "PLAYBOOK_SCRATCH": "<absolute scratch dir outside the repo>" } }
```

Keep the scratch directory and the repository out of cloud-synced folders (OneDrive, Dropbox,
Nextcloud): every agent worktree lands in scratch and the sync client re-reads each one, and an
online-only placeholder in `.git` makes `git worktree add` fail.

The plugin also ships `land.sh` and `hygiene.sh` (playbook section 8) and `batch-ci.sh`
(A9) for the coordinator and `usage.py`, which reads the subscription's 5-hour and weekly limits (section 7); its
hooks create every agent worktree under `$PLAYBOOK_SCRATCH/work/` from a fresh
`origin/main`, refuse a builder's hand-back while `PLAYBOOK_BUILDER_CHECK` fails in its tree, and
with `PLAYBOOK_REQUIRE_TICKET=1` refuse a dispatch whose description does not start with an
issue number (playbook section 4). The hook scripts need `bash`, `git` and `timeout` (Git Bash on Windows has all three; on macOS install coreutils).

Check the setup with `bash docs/playbook/plugin/scripts/check-setup.sh` from the project's root:
it names every copy, fork, missing setting or oversized `CLAUDE.md` it finds.

Fresh clone of a project: `git clone --recurse-submodules <url>` (or `git submodule update --init`).

## Migrating from a copy or a project playbook file

Projects that keep a copy of `AGENT-WORKFLOW-PLAYBOOK.md`, or a `PROJECT-<NAME>-PLAYBOOK.md`:

1. Diff the copy against this repo. Every local edit is either a project value (step 2) or a
   general fix (open a `feedback` issue here).
2. Rewrite `CLAUDE.md` from A10 and sort every rule of the project file and the old `CLAUDE.md`
   (playbook section 0). Where two say different things, decide once and keep only that line.

   | The rule is | It goes to |
   |---|---|
   | An answer to a P, or a value a tool runs | where playbook section 0 says (a `Pn:` line, or the tool's file) |
   | A rule for one module or folder only | `.claude/rules/<module>.md` with a `paths:` list (A10) |
   | Any other project rule | one line under the nearest A10 heading |
   | Why a rule exists, evidence, incidents, superseded values | `docs/HISTORY.md` |
   | Already in the playbook | delete it; if the playbook is wrong, open a `feedback` issue here |

3. Delete the project file and any other file restating rules (orchestration notes, prompt
   collections). Delete copies of the builder, reviewer and researcher from `.claude/agents/` and load the plugin
   instead (above); move the builder's `model:` into `.claude/settings.json`. Other tool configuration
   stays: project-only agents, `docs/agents/`, scripts.
4. `git rm -r` the copy, add the submodule as above, point any awk command at
   `docs/playbook/AGENT-WORKFLOW-PLAYBOOK.md`.
5. Re-check `CLAUDE.md` against the playbook's commit log since the copy's date.

## Get updates (only when you want them)

First check that `docs/playbook` is a submodule: `git ls-files -s docs/playbook` prints one line
with mode `160000`. If it lists files or nothing, migrate first (above): the commands below would
commit a copy's local edits as a playbook bump.

```bash
git submodule update --remote docs/playbook   # pull latest
git diff --submodule docs/playbook            # see what changed
git add docs/playbook && git commit -m "Bump playbook"
```

The project pins an exact commit, so nothing changes under you until you bump it.
Read the playbook's commit log before bumping and re-check `CLAUDE.md` against changes.

## Give feedback (agents: do this, it improves it for everyone)

Open an issue; it is the durable channel and needs no live session:

```bash
gh issue create -R TotallyNotAHackerTrustMeIAmADolphin/agent-playbook -l feedback \
  -t "S5: <short title>" \
  --body-file <file with the fields of .github/ISSUE_TEMPLATE/playbook-feedback.md>
```

Or use the "Playbook feedback" issue template. What makes a good report, and how pull requests
work: [CONTRIBUTING.md](CONTRIBUTING.md). Security problems go privately: [SECURITY.md](SECURITY.md).

## Changing the playbook

Never edit inside a project's `docs/playbook/` checkout; fix it here (CONTRIBUTING.md).

## License

Text (the playbook, `README.md`, `docs/`): [CC BY 4.0](LICENSE-docs). Code files (scripts, hooks,
agent definition files, plugin files): [MIT](LICENSE). Code blocks inside the playbook may also be
used under MIT. Reuse either with attribution to this
repository.
