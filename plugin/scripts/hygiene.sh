#!/usr/bin/env bash
# hygiene.sh   (playbook section 8, item 8; weekly, from A8 with nothing in flight)
# Run by the coordinator from the main checkout, GitHub only. Removes a ticket-* branch (tree,
# local and remote branch, builder scratch) when it has no open PR and its tips are heads of its
# merged or closed PRs (new commits since mean a re-dispatch: kept), and rev-* trees whose PR is
# merged or closed. Lists agent-* and land-* trees and every tree outside $PLAYBOOK_SCRATCH/work;
# then git worktree prune, a read-only fsck and git maintenance. Never --force, never
# `git branch --merged` (squash-merged commits are not ancestors of main).
set -uo pipefail
die() { echo "hygiene.sh: $*" >&2; exit 1; }
for c in gh git; do command -v $c >/dev/null || die "needs '$c'"; done
case "${PLAYBOOK_SCRATCH:-}" in /*|[A-Za-z]:[/\\]*) ;; *) die "PLAYBOOK_SCRATCH must be an absolute path";; esac
work=$(cd "$PLAYBOOK_SCRATCH/work" 2>/dev/null && { pwd -W 2>/dev/null || pwd; })
[ -n "$work" ] || die "$PLAYBOOK_SCRATCH/work does not exist"
. "$(dirname "$0")/remove-branch.sh"
git fetch -q --prune origin || die "git fetch failed"
fail=0

for b in $(git for-each-ref --format='%(refname:short)' 'refs/heads/ticket-*' 'refs/remotes/origin/ticket-*' |
           sed 's#^origin/##' | sort -u); do
  prs=$(gh pr list --head "$b" --state all --json state,headRefOid --jq '.[]|.state+" "+.headRefOid') ||
    { echo "skip $b: gh failed"; fail=1; continue; }
  case "$prs" in '') echo "keep $b (no PR)"; continue;; *OPEN*) echo "keep $b (open PR)"; continue;; esac
  new=""
  for r in "refs/heads/$b" "refs/remotes/origin/$b"; do
    tip=$(git rev-parse -q --verify "$r") || continue
    case "$prs" in *" $tip"*) ;; *) new=1;; esac
  done
  [ -z "$new" ] || { echo "keep $b (commits after its last PR: a re-dispatch?)"; continue; }
  if remove_branch "$b"; then echo "removed $b"; else echo "REFUSED $b: inspect it"; fail=1; fi
done

while IFS= read -r t; do
  case "$t" in "$work"/*) ;; *) echo "outside work/: $t"; continue;; esac
  name=${t##*/}
  case "$name" in
    rev-[0-9]*) p=${name#rev-}; p=${p%%-*}
       s=$(gh pr view "$p" --json state --jq .state) || { echo "skip $t: gh failed"; fail=1; continue; }
       case "$s" in MERGED|CLOSED)
         if git worktree remove "$t"; then echo "removed $t (PR #$p $s)"; else echo "REFUSED $t"; fail=1; fi;;
       esac;;
    agent-*) echo "look: $t (a builder that died before renaming, or a tree another agent made)";;
    land-*) echo "look: $t (left by a land.sh run)";;
  esac
done < <(git worktree list --porcelain | sed -n 's/^worktree //p' | tail -n +2)

git worktree prune
git fsck --no-progress --no-dangling --connectivity-only || { echo "git fsck reported problems"; fail=1; }
git maintenance run || fail=1
exit $fail
