# agent-playbook

Central, project-agnostic **Agent Workflow Playbook** (`AGENT-WORKFLOW-PLAYBOOK.md`).
Projects include it as a git submodule instead of keeping copies, and keep only their own
answers/values in a slim `PROJECT-<NAME>-PLAYBOOK.md`.

## Use it in a project

```bash
git submodule add https://github.com/<owner>/agent-playbook.git docs/playbook
git commit -m "Add agent playbook submodule"
```

Fixed path: `docs/playbook/` (the playbook's own commands assume it). The project file lives
**next to** the submodule, not inside it: `docs/PROJECT-<NAME>-PLAYBOOK.md`.
Add to the project's `CLAUDE.md`: read `docs/playbook/AGENT-WORKFLOW-PLAYBOOK.md` (Core) at session start.

Fresh clone of a project: `git clone --recurse-submodules <url>` (or `git submodule update --init`).

## Get updates (only when you want them)

```bash
git submodule update --remote docs/playbook   # pull latest
git diff --submodule docs/playbook            # see what changed
git add docs/playbook && git commit -m "Bump playbook"
```

The project pins an exact commit, so nothing changes under you until you bump it.
Read the playbook's commit log before bumping and re-check your project file against changes.

## Give feedback (agents: do this, it improves it for everyone)

Open an issue; it is the durable channel and needs no live session:

```bash
gh issue create -R <owner>/agent-playbook -l feedback \
  -t "S5: <short title>" \
  -b "Project/role: ...\nSection: ...\nWhat happened: ...\nEvidence: ...\nSuggestion: ..."
```

Or use the "Playbook feedback" issue template. Rules: one issue per problem, name the section,
give evidence, no secrets or customer data. Search first: `gh issue list -R <owner>/agent-playbook -S "<keyword>"`.

## Changing the playbook

Only change it via PR or by the maintainer. Keep the file's one rule: every rule stands once.
Never edit inside a project's `docs/playbook/` checkout; fix it here.
