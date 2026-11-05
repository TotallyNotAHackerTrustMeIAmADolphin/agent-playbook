#!/usr/bin/env bash
# PreToolUse hook on SubagentHandback for playbook:builder (playbook section 4).
# Refuses the builder's hand-back while its tree has uncommitted or untracked files, unpushed
# commits, or the project's check command fails there. The check is the project's env.PLAYBOOK_BUILDER_CHECK (P6), run with
# bash -c in the agent's working directory under a 540 s timeout (the hook itself gets 600 s).
# A report starting with "PARTIAL:" passes (turn budget); the coordinator treats it as
# unfinished. Exit 2 sends stderr back to the builder as the reason.
set -uo pipefail
in=$(cat)
field() { printf '%s' "$in" | sed -n "s/.*\"$1\" *: *\"\\([^\"]*\\)\".*/\\1/p" | sed 's/\\\\/\\/g'; }
refuse() { echo "Hand-back refused: $*" >&2; exit 2; }
[ "$(field agent_type)" = "playbook:builder" ] || exit 0
cwd=$(field cwd)
case "$(printf '%s' "$in" | sed -n 's/.*"message" *: *"\(.\{0,8\}\).*/\1/p')" in PARTIAL:) exit 0;; esac
[ -n "${PLAYBOOK_BUILDER_CHECK:-}" ] ||
  refuse "env.PLAYBOOK_BUILDER_CHECK is not set in .claude/settings.json (playbook P6). Send the report starting with PARTIAL: and name this."
command -v timeout >/dev/null ||
  refuse "the gate needs the 'timeout' command (coreutils). Send the report starting with PARTIAL: and name this."
cd "${cwd:-.}" || refuse "cannot enter $cwd"
dirty=$(git status --porcelain 2>&1) || refuse "not a git tree: $PWD"
[ -z "$dirty" ] || refuse "uncommitted or untracked files in $PWD (commit them, or ignore them via .gitignore):
$dirty"
ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null) ||
  refuse "the branch has no upstream; push it with git push -u origin HEAD"
[ "$ahead" = 0 ] || refuse "$ahead commit(s) not pushed; push first"
out=$(timeout 540 bash -c "$PLAYBOOK_BUILDER_CHECK" 2>&1)
rc=$?
[ $rc -eq 0 ] && exit 0
refuse "the check '$PLAYBOOK_BUILDER_CHECK' exited $rc in $PWD. Fix and run it again; last lines:
$(printf '%s\n' "$out" | tail -n 30)"
