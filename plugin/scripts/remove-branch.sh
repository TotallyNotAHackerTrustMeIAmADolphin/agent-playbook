# Sourced by land.sh and hygiene.sh (playbook section 8, item 8). Call only after the branch's
# PR is MERGED or CLOSED. remove_branch <branch>: for a ticket-<n>[-<k>] branch only, unlocks and
# removes its worktree (never --force), deletes the local and the remote branch and the builder's
# scratch subdir. Returns 2 for any other branch name (touches nothing), 1 if the tree will not go
# (it stays, locked again: inspect it, section 11) or the remote branch survives.
remove_branch() {
  local b=$1 tree reason
  case "$b" in ticket-[0-9]*) ;; *) return 2;; esac
  tree=$(git worktree list --porcelain | awk -v b="refs/heads/$b" '
    /^worktree /{w=substr($0,10)} $0=="branch " b {print w}')
  if [ -n "$tree" ]; then
    reason=$(git worktree list --porcelain | awk -v t="worktree $tree" '
      $0==t {f=1; next} /^worktree /{f=0} f && /^locked/ {sub(/^locked ?/,""); print}')
    git worktree unlock "$tree" 2>/dev/null
    git worktree remove "$tree" || { git worktree lock --reason "${reason:-locked}" "$tree"; return 1; }
  fi
  git branch -D "$b" >/dev/null 2>&1
  git ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1
  case $? in
    0) git push -q origin --delete "$b" || { echo "remote branch $b not deleted" >&2; return 1; };;
    2) ;;
    *) echo "cannot reach origin to delete $b" >&2; return 1;;
  esac
  case "${PLAYBOOK_SCRATCH:-}" in
    /*|[A-Za-z]:[/\\]*) rm -rf "$PLAYBOOK_SCRATCH/builder-${b#ticket-}";;
  esac
  return 0
}
