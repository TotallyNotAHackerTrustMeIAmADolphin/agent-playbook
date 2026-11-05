#!/usr/bin/env bash
# WorktreeCreate hook (playbook section 8, item 8). Replaces Claude Code's default worktree
# creation for `isolation: worktree` and every other worktree the session creates.
# Creates $PLAYBOOK_SCRATCH/work/<name> on a new branch <name> from a fresh origin/main, locked,
# and prints its absolute path as the last stdout line. Everything else goes to stderr.
# Fails closed: no absolute PLAYBOOK_SCRATCH, no origin/main or a git error means no worktree.
set -euo pipefail
in=$(cat)
field() { printf '%s' "$in" | sed -n "s/.*\"$1\" *: *\"\\([^\"]*\\)\".*/\\1/p" | sed 's/\\\\/\\/g'; }
name=$(field name)
cwd=$(field cwd)
[ -n "$name" ] || { echo "worktree-create: no name in hook input" >&2; exit 1; }
case "$name" in -*|.*|*[!A-Za-z0-9._-]*) echo "worktree-create: refusing name '$name'" >&2; exit 1;; esac
scratch=${PLAYBOOK_SCRATCH:-}
case "$scratch" in
  /*|[A-Za-z]:[/\\]*) ;;
  *) echo "worktree-create: env.PLAYBOOK_SCRATCH must be an absolute path in .claude/settings.local.json (playbook P6); got '$scratch'" >&2; exit 1;;
esac
repo=$(git -C "${cwd:-.}" rev-parse --show-toplevel)
dir="$scratch/work/$name"
[ ! -e "$dir" ] || { echo "worktree-create: $dir exists" >&2; exit 1; }
# A private ref per hook: parallel builders would otherwise race on refs/remotes/origin/main.
base="refs/playbook/base/$name"
trap 'git -C "$repo" update-ref -d "$base" 2>/dev/null || true' EXIT
git -C "$repo" fetch -q --no-write-fetch-head --refmap= origin "+refs/heads/main:$base" >&2
git -C "$repo" worktree add -q --lock --reason "agent $name" "$dir" -b "$name" "$base" >&2
cd "$dir" || exit 1
pwd -W 2>/dev/null || pwd
