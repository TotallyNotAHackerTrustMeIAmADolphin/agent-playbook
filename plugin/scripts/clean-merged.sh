#!/usr/bin/env bash
# clean-merged.sh <ticket-branch> <merge commit>   (playbook section 8, item 8)
# For a project WITHOUT PRs, run by the coordinator from the main checkout after it squash-merged
# (or merged) the ticket locally. Removes the branch's tree, local and remote branch and builder
# scratch (remove-branch.sh, never --force) once the merge state shows the branch is in: <merge
# commit> is on main, and each branch tip is an ancestor of main or has the same patch as the
# merge commit. Anything else (commits after the merge: a re-dispatch) is kept.
set -uo pipefail
die() { echo "clean-merged.sh: $*" >&2; exit 1; }
[ $# -eq 2 ] || die "usage: clean-merged.sh <ticket-branch> <merge commit>"
b=$1; m=$(git rev-parse -q --verify "$2^{commit}") || die "no commit '$2'"
git fetch -q origin || die "git fetch failed"
git merge-base --is-ancestor "$m" origin/main || die "$m is not on origin/main (push the merge first)"
pid() { git diff "$1" "$2" | git patch-id --stable | cut -d' ' -f1; }
want=$(pid "$m^" "$m")
for r in "refs/heads/$b" "refs/remotes/origin/$b"; do
  tip=$(git rev-parse -q --verify "$r") || continue
  git merge-base --is-ancestor "$tip" origin/main && continue
  [ -n "$want" ] && [ "$(pid "$(git merge-base "$tip" "$m^")" "$tip")" = "$want" ] ||
    die "keep $b: $r is neither in main nor the content of $m (a re-dispatch? inspect it)"
done
. "$(dirname "$0")/remove-branch.sh"
remove_branch "$b"; rc=$?
[ $rc -eq 0 ] && echo "removed $b" || die "$b not fully removed (rc $rc): inspect it (section 11)"
