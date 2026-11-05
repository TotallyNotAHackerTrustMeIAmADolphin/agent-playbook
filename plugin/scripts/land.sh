#!/usr/bin/env bash
# land.sh <pr> <reviewed full sha> <body file>   (playbook section 8, item 10)
# Run by the coordinator from the main checkout, GitHub only. Stops at the first failed step:
#   1. the PR targets main from this repo, its head is the reviewed sha, GitHub calls it mergeable;
#   2. if main moved past the branch's base: the merged tree passes PLAYBOOK_BUILDER_CHECK (item 5);
#   3. squash merge pinned to the sha, subject "<title> (#<pr>)", body from the file (items 4, 5);
#   4. state is MERGED;
#   5. removes a ticket-* branch's tree, local and remote branch and scratch subdir (item 8);
#   6. runs env.PLAYBOOK_AFTER_LAND, if set, with the merge commit as $1 (P4);
#   7. checks that every issue the PR closes is closed (item 2).
set -uo pipefail
die() { echo "land.sh: $*" >&2; exit 1; }
[ $# -eq 3 ] || die "usage: land.sh <pr> <reviewed full sha> <body file>"
pr=$1; sha=$2; body=$3
hex40() { [ ${#1} -eq 40 ] && case "$1" in *[!0-9a-f]*) return 1;; esac; }
case "$pr" in ''|*[!0-9]*) die "PR number expected, got '$pr'";; esac
hex40 "$sha" || die "full 40-hex sha expected, got '$sha'"
[ -s "$body" ] || die "body file '$body' is missing or empty"
for c in gh git timeout; do command -v $c >/dev/null || die "needs '$c'"; done
git fetch -q origin || die "git fetch failed"
q() { gh pr view "$pr" --json "$1" --jq "$2"; }

# 1. same repo, base main, reviewed head, mergeable (UNKNOWN: GitHub is still computing)
for i in 1 2 3 4 5 6 7 8 9 10; do
  mergeable=$(q mergeable .mergeable) || die "gh pr view $pr failed"
  [ "$mergeable" = UNKNOWN ] || break
  sleep 6
done
state=$(q state .state); head=$(q headRefOid .headRefOid); branch=$(q headRefName .headRefName)
base=$(q baseRefName .baseRefName); fork=$(q isCrossRepository .isCrossRepository); title=$(q title .title)
[ "$state" = OPEN ] || die "PR #$pr is $state"
[ "$fork" = false ] || die "PR #$pr comes from a fork; land it by hand"
[ "$base" = main ] || die "PR #$pr targets $base, not main (a stacked child: item 9)"
[ "$head" = "$sha" ] || die "head moved: PR #$pr is at $head, reviewed $sha (delta re-review first)"
[ "$mergeable" = MERGEABLE ] || die "PR #$pr is $mergeable (CONFLICTING goes to the fixer, A4)"

# 2. merged-tree check when main moved since the branch's base
git cat-file -e "$sha^{commit}" 2>/dev/null || git fetch -q origin "$sha" || die "cannot fetch $sha"
main=$(git rev-parse origin/main) || die "no origin/main"
if [ "$(git merge-base origin/main "$sha")" != "$main" ]; then
  [ -n "${PLAYBOOK_BUILDER_CHECK:-}" ] || die "main moved since the branch's base and PLAYBOOK_BUILDER_CHECK is not set"
  T=$(git merge-tree --write-tree origin/main "$sha"); rc=$?
  [ $rc -eq 1 ] && die "the merge with origin/main conflicts: send PR #$pr to the fixer (A4)"
  [ $rc -eq 0 ] || die "git merge-tree failed (exit $rc; needs Git 2.38+)"
  M=$(git commit-tree "$T" -p "$main" -p "$sha" -m "land.sh merged-tree check #$pr") || die "commit-tree failed"
  case "${PLAYBOOK_SCRATCH:-}" in /*|[A-Za-z]:[/\\]*) ;; *) die "PLAYBOOK_SCRATCH must be an absolute path";; esac
  wt="$PLAYBOOK_SCRATCH/work/land-$pr"
  git worktree add -q --detach "$wt" "$M" || die "cannot create $wt (a leftover from an earlier run? remove it)"
  out=$(cd "$wt" && timeout 540 bash -c "$PLAYBOOK_BUILDER_CHECK" 2>&1); rc=$?
  # land.sh created this tree a moment ago and nobody else uses it, so --force is safe here
  git worktree remove --force "$wt" || echo "land.sh: could not remove $wt; remove it before the next run" >&2
  [ $rc -eq 0 ] || die "the merged tree fails the check (exit $rc); not merged. Last lines:
$(printf '%s\n' "$out" | tail -n 30)"
fi

# 3. pinned squash merge with the explicit subject and body
gh pr merge "$pr" --squash --match-head-commit "$sha" --subject "$title (#$pr)" --body-file "$body" ||
  die "merge refused (a moved head needs a delta re-review; never merge without the pin)"

# 4. merged
state=$(q state .state); merged=$(q mergeCommit .mergeCommit.oid)
[ "$state" = MERGED ] && hex40 "$merged" || die "PR #$pr is '$state' (merge commit '$merged') after the merge call; nothing cleaned up"

# 5. clean up the builder's tree and branches (never --force on a builder tree)
. "$(dirname "$0")/remove-branch.sh"
remove_branch "$branch"; rc=$?
[ $rc -eq 1 ] && die "merged as $merged, but $branch was not fully removed: inspect it (section 11); then run PLAYBOOK_AFTER_LAND $merged by hand and check the closed issues (item 2)"
[ $rc -eq 2 ] && echo "land.sh: $branch is not a ticket-* branch; left in place"

# 6. project steps after a merge (e.g. fast-forward the deploy checkout)
if [ -n "${PLAYBOOK_AFTER_LAND:-}" ]; then
  bash -c "$PLAYBOOK_AFTER_LAND" land "$merged" || die "merged as $merged; PLAYBOOK_AFTER_LAND failed"
fi

# 7. the intended issues closed (GitHub closes them shortly after the merge)
for i in 1 2 3 4 5; do
  open=""
  for n in $(q closingIssuesReferences '.closingIssuesReferences[].number'); do
    [ "$(gh issue view "$n" --json state --jq .state)" = CLOSED ] || open="$open #$n"
  done
  [ -z "$open" ] && break
  sleep 5
done
[ -z "$open" ] || die "merged as $merged, but these issues are still open:$open (check the keywords, item 2)"
echo "land.sh: PR #$pr merged as $merged"
