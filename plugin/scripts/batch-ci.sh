#!/usr/bin/env bash
# batch-ci.sh <full sha>   (playbook section 7 and A9; the coordinator runs it, backgrounded)
# The full suite once on main's sha in ONE recycled detached tree, <scratch>/ci/tree. Writes
# <scratch>/ci/<sha7>.log, ends with one line "BATCH CI <sha7>: GREEN|RED[...]" and posts it as
# the commit status "batch-ci". RED for: a new failure, a timed-out or crashed part, an exit-1
# part without failure ids, a missing part, a lint failure; a new failure that passes alone is a
# "flaky candidate", still RED until a ticket decides (section 7, known-red list).
# Settings (.claude/settings.json env, P11), for a pytest-shaped runner (-q -rfE output):
#   PLAYBOOK_CI_RUNNER    e.g. "python -m pytest"
#   PLAYBOOK_CI_PARTS     path groups separated by ';', each run as one part under the timeout
#   PLAYBOOK_CI_LINT      optional, e.g. "ruff check ."
#   PLAYBOOK_CI_KNOWN_RED optional known-red file, relative to the main checkout or absolute;
#                         default <scratch>/ci/known_red.txt. One test id per line, '#' comments.
#   PLAYBOOK_CI_TIMEOUT   optional seconds per part, default 590 (fits the tool's time limit)
# Needs git, timeout (macOS: coreutils), perl, gh. The runner is split on spaces, never globbed. Exit 0 on GREEN, 1 on RED, 2 on a usage or setup error.
set -uf      # -f: no globbing of $RUNNER, the parts or test ids
die() { echo "batch-ci.sh: $*" >&2; exit 2; }
[ $# -eq 1 ] || die "usage: batch-ci.sh <full sha>"
SHA=$1
[ ${#SHA} -eq 40 ] && case "$SHA" in *[!0-9a-f]*) false;; esac || die "full 40-hex sha expected, got '$SHA'"
case "${PLAYBOOK_SCRATCH:-}" in /*|[A-Za-z]:[/\\]*) ;; *) die "PLAYBOOK_SCRATCH must be an absolute path";; esac
RUNNER=${PLAYBOOK_CI_RUNNER:-}; PARTS=${PLAYBOOK_CI_PARTS:-}; LINT=${PLAYBOOK_CI_LINT:-}
[ -n "$RUNNER" ] && [ -n "$PARTS" ] || die "set PLAYBOOK_CI_RUNNER and PLAYBOOK_CI_PARTS (P11)"
TO=${PLAYBOOK_CI_TIMEOUT:-590}
for c in git timeout perl gh; do command -v $c >/dev/null || die "needs '$c'"; done
MAIN=$(git rev-parse --show-toplevel 2>/dev/null) || die "run it from the main checkout"
S7=${SHA:0:7}; ROOT="$PLAYBOOK_SCRATCH/ci"; TREE="$ROOT/tree"; LOG="$ROOT/$S7.log"
case "${PLAYBOOK_CI_KNOWN_RED:-}" in
  '') KR="$ROOT/known_red.txt";; /*|[A-Za-z]:[/\\]*) KR=$PLAYBOOK_CI_KNOWN_RED;; *) KR="$MAIN/$PLAYBOOK_CI_KNOWN_RED";;
esac
mkdir -p "$ROOT" || die "cannot create $ROOT"
mkdir "$ROOT/lock" 2>/dev/null || die "another batch CI runs (or a crashed one left $ROOT/lock: remove it)"
trap 'rmdir "$ROOT/lock" 2>/dev/null' EXIT
: > "$LOG"; set +f; rm -f "$ROOT/$S7".part-*; set -f

# a failed fetch or checkout must not fall through to a stale tree
( set -e
  git -C "$MAIN" fetch -q origin
  [ -d "$TREE" ] || git -C "$MAIN" worktree add -q --detach "$TREE" "$SHA"
  cd "$TREE" && git checkout -q --detach "$SHA" ) >>"$LOG" 2>&1 ||
  { echo "BATCH CI $S7: RED (checkout failed)" | tee -a "$LOG"; exit 1; }
cd "$TREE" || exit 1

# no pipe between runner and exit code (a pipe loses 124); -rfE prints one FAILED/ERROR <id> line each
N=0
run() { N=$((N+1)); timeout "$TO" $RUNNER -q -rfE "$@" >"$ROOT/$S7.part-$N.out" 2>&1 </dev/null
        echo $? >"$ROOT/$S7.part-$N.rc"; }
IFS=';' read -ra GROUPS_ <<< "$PARTS"
for g in "${GROUPS_[@]}"; do
  read -ra P <<< "$g"                       # paths split on whitespace
  [ ${#P[@]} -gt 0 ] || continue
  run "${P[@]}"
done
WANT=$N
[ "$WANT" -gt 0 ] || { echo "BATCH CI $S7: RED (PLAYBOOK_CI_PARTS names no paths)" | tee -a "$LOG"; exit 1; }
LINTRC=0; if [ -n "$LINT" ]; then bash -c "$LINT" >>"$LOG" 2>&1 </dev/null; LINTRC=$?; fi

# ids from the short-summary section only, well-formed lines only, " - msg" cut after the id
ids() { sed -n '/^=* short test summary info/,$p' "$1" | perl -ne \
  'print "$1\n" if /^(?:FAILED|ERROR) (\S+?\.py(?:::[^\s\[]+)*(?:\[.*?\])?)(?: - .*)?\s*$/'; }
: > "$ROOT/fails"; BAD=0; SEEN=0
N=0
while [ "$N" -lt "$WANT" ]; do N=$((N+1)); f="$ROOT/$S7.part-$N.rc"
  [ -e "$f" ] || continue; SEEN=$((SEEN+1)); n=${f##*.part-}; n=${n%.rc}; rc=$(cat "$f")
  out="$ROOT/$S7.part-$n.out"
  case $rc in
    0) echo "part $n: ok" >>"$LOG";;
    124) echo "part $n: TIMEOUT" >>"$LOG"; BAD=1;;
    *) ids "$out" >>"$ROOT/fails"; c=$(ids "$out" | wc -l | tr -d ' ')
       if [ "$rc" = 1 ] && [ "$c" -gt 0 ]; then echo "part $n: failed ($c ids)" >>"$LOG"
       else echo "part $n: ERROR rc=$rc" >>"$LOG"; BAD=1; fi;;   # crash, rc 2-5/137, or rc 1 without ids
  esac
done
[ "$SEEN" -eq "$WANT" ] || { echo "parts missing: $SEEN of $WANT" >>"$LOG"; BAD=1; }
{ [ -f "$KR" ] && grep -vE '^[[:space:]]*(#|$)' "$KR" | sed 's/[[:space:]]*$//'; } >"$ROOT/kr"
if [ -s "$ROOT/kr" ]; then   # an empty pattern file behaves differently across greps
  sort -u "$ROOT/fails" | grep -vxFf "$ROOT/kr" >"$ROOT/new"
  sort -u "$ROOT/fails" | grep -xFf "$ROOT/kr" >"$ROOT/known"
else sort -u "$ROOT/fails" >"$ROOT/new"; : >"$ROOT/known"; fi
{ echo "known-red:"; sed 's/^/  /' "$ROOT/known"; echo "new failures:"; sed 's/^/  /' "$ROOT/new"; } >>"$LOG"

# rerun each NEW failure once, alone: a pass makes it a flaky candidate, still not GREEN
FLAKY=""
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if timeout 300 $RUNNER -q "$id" </dev/null >/dev/null 2>&1; then
    FLAKY="$FLAKY $id"; echo "flaky candidate: $id" >>"$LOG"
  else BAD=1; fi
done <"$ROOT/new"
[ "$LINTRC" = 0 ] || { echo "lint: FAILED (rc $LINTRC)" >>"$LOG"; BAD=1; }
if [ "$BAD" = 1 ]; then V="RED"; elif [ -n "$FLAKY" ]; then V="RED (flaky candidates only:$FLAKY)"; else V=GREEN; fi
echo "BATCH CI $S7: $V" | tee -a "$LOG"
[ "$V" = GREEN ] && ST=success || ST=failure
gh api "repos/{owner}/{repo}/statuses/$SHA" -f state=$ST -f context=batch-ci \
  -f description="$(printf '%s' "BATCH CI $S7: $V" | cut -c1-140)" >/dev/null ||
  echo "batch-ci.sh: could not post the commit status; the verdict stands in $LOG" >&2
[ "$V" = GREEN ]
