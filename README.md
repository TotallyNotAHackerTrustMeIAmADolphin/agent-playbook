# agent-playbook

Central, project-agnostic **Agent Workflow Playbook** (`AGENT-WORKFLOW-PLAYBOOK.md`).
Projects include it as a git submodule instead of keeping copies. A project's own rules (its
answers to P1-P17) live in one place only: its `CLAUDE.md`, shaped by the playbook's A10.

## Use it in a project

```bash
git submodule add https://github.com/TotallyNotAHackerTrustMeIAmADolphin/agent-playbook.git docs/playbook
git commit -m "Add agent playbook submodule"
```

Fixed path: `docs/playbook/` (the playbook's own commands assume it). Then write `CLAUDE.md`
from A10; the line under its title points every session at Core. Evidence and history go to
`docs/HISTORY.md`. There is no second project rule file (only module-scoped `.claude/rules/`, A10).

The builder, reviewer and researcher agents ship from this repo as the `playbook` plugin. Load it
from the submodule, once per clone (it writes the absolute path to the uncommitted
`.claude/settings.local.json`):

```bash
claude plugin marketplace add ./docs/playbook --scope local
claude plugin install playbook@agent-playbook --scope local
```

Claude Code reads the plugin from the submodule folder, so bumping the submodule also updates the
agents (new sessions). The builder model goes into the committed `.claude/settings.json` (it
applies to every sub-agent whose definition names no model, playbook P5); the scratch directory,
an absolute path that differs per machine, into `.claude/settings.local.json`:

```json
{ "env": { "CLAUDE_CODE_SUBAGENT_MODEL": "<builder model>" } }
```

```json
{ "env": { "PLAYBOOK_SCRATCH": "<absolute scratch dir outside the repo>" } }
```

Fresh clone of a project: `git clone --recurse-submodules <url>` (or `git submodule update --init`).

## Migrating from a copy or a project playbook file

Projects that keep a copy of `AGENT-WORKFLOW-PLAYBOOK.md`, or a `PROJECT-<NAME>-PLAYBOOK.md`:

1. Diff the copy against this repo. Every local edit is either a project value (step 2) or a
   general fix (open a `feedback` issue here).
2. Rewrite `CLAUDE.md` from A10: one line per P answer (P7 and P8 are tables), merged with what `CLAUDE.md` and the
   project file said. Where they disagree, decide once and keep only that line.
3. Move evidence, incidents and history from the project file into `docs/HISTORY.md`; delete the
   project file and any other file restating rules (orchestration notes, prompt collections). Delete
   copies of the builder, reviewer and researcher from `.claude/agents/` and load the plugin
   instead (above); move the builder's `model:` into `.claude/settings.json`. Other tool configuration
   stays: project-only agents, `docs/agents/`, scripts.
4. `git rm -r` the copy, add the submodule as above, point any awk command at
   `docs/playbook/AGENT-WORKFLOW-PLAYBOOK.md`.
5. Re-check `CLAUDE.md` against the playbook's commit log since the copy's date.

## Get updates (only when you want them)

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
  -b "Project/role: ...\nSection: ...\nWhat happened: ...\nEvidence: ...\nSuggestion: ..."
```

Or use the "Playbook feedback" issue template. Rules: one issue per problem, name the section,
give evidence, no secrets or customer data. Search first: `gh issue list -R TotallyNotAHackerTrustMeIAmADolphin/agent-playbook -S "<keyword>"`.

## Changing the playbook

Only change it via PR or by the maintainer. Keep the file's one rule: every rule stands once.
Never edit inside a project's `docs/playbook/` checkout; fix it here.

## License

Text (the playbook, `README.md`, `docs/`): [CC BY 4.0](LICENSE-docs). Code files (scripts, hooks,
agent definition files, plugin files): [MIT](LICENSE). Code blocks inside the playbook may also be
used under MIT. Reuse either with attribution to this
repository.
