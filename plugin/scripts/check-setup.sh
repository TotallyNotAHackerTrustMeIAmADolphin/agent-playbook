#!/usr/bin/env bash
# check-setup.sh   (playbook section 12; run from the project's root, and weekly from A8)
# Checks a project's playbook setup against section 0, A10 and the README: one rule file (no
# playbook copies or forks, a clean submodule from the canonical repo), CLAUDE.md within A10's
# budget, the setup skill's docs/agents/, module rules scoped by paths:, no copied agent
# definitions, the plugin and its settings.
# Changes nothing except one `git fetch` of the canonical main into the submodule's FETCH_HEAD.
# Prints one line per check; exits 1 if any check FAILs. INFO lines never fail.
set -uo pipefail
URL=https://github.com/TotallyNotAHackerTrustMeIAmADolphin/agent-playbook   # as in README
fails=0
ok()   { echo "OK    $*"; }
fail() { echo "FAIL  $*"; fails=$((fails+1)); }
info() { echo "INFO  $*"; }
indent() { sed 's/^/        /'; }
norm() { printf '%s' "$1" | tr 'A-Z' 'a-z' |
  sed -e 's#^git@github\.com:#https://github.com/#' -e 's#^ssh://git@github\.com/#https://github.com/#' \
      -e 's#/*$##' -e 's#\.git$##' -e 's#/*$##'; }
TO=$(command -v timeout || command -v gtimeout)   # gtimeout: Homebrew coreutils on macOS
PB=docs/playbook
[ -e .git ] || { echo "check-setup.sh: run it from the project's root" >&2; exit 2; }

# The playbook: a registered submodule at docs/playbook from the canonical repo, unedited
gitlink=$(git ls-files -s -- "$PB" | awk 'NR==1 {print $1}')
registered=$(git config -f .gitmodules --get "submodule.$PB.path" 2>/dev/null)
if [ "$gitlink" != 160000 ] || [ "$registered" != "$PB" ]; then
  fail "$PB is not a submodule registered in .gitmodules (README, Use it in a project)"
elif [ ! -e "$PB/.git" ]; then
  fail "$PB is registered but not checked out: git submodule update --init (README)"
else
  ok "$PB is a submodule"
  u=$(git config -f .gitmodules --get "submodule.$PB.url")
  [ "$(norm "$u")" = "$(norm "$URL")" ] && ok "$PB comes from $URL" ||
    fail "$PB comes from '$u', not $URL (a fork: fix it in the playbook repo)"
  d=$(git -C "$PB" status --porcelain)
  [ -z "$d" ] && ok "$PB checkout is clean" ||
    fail "$PB checkout has local edits or files (fix them in the playbook repo, README):
$(printf '%s\n' "$d" | indent)"
  [ "$(git -C "$PB" rev-parse HEAD)" = "$(git rev-parse ":$PB" 2>/dev/null)" ] ||
    fail "$PB is checked out at another commit than the project records (git submodule update, or commit the bump)"
  if GIT_TERMINAL_PROMPT=0 ${TO:+"$TO" 60} git -C "$PB" fetch -q "$URL" main 2>/dev/null; then
    git -C "$PB" merge-base --is-ancestor HEAD FETCH_HEAD &&
      ok "$PB is at a commit on the canonical main" ||
      fail "$PB is at a commit that is not on $URL main (a local fork; fix it in the playbook repo)"
    n=$(git -C "$PB" rev-list --count HEAD..FETCH_HEAD)
    [ "${n:-0}" = 0 ] || info "$PB is $n commit(s) behind the canonical main (bump when you want: README)"
  else
    info "could not fetch $URL; fork and freshness not checked"
  fi
fi
copies=$(git ls-files -- ':(icase,glob)**/*playbook*.md')   # a submodule's files are not listed
[ -z "$copies" ] && ok "no playbook copies or project playbook files" ||
  fail "playbook copies or project files: project rules belong in CLAUDE.md (README, Migrating):
$(printf '%s\n' "$copies" | indent)"

# CLAUDE.md: present, under 200 lines, pointing at Core (A10)
if [ -f CLAUDE.md ]; then
  n=$(wc -l < CLAUDE.md)
  [ "$n" -lt 200 ] && ok "CLAUDE.md has $n lines" || fail "CLAUDE.md has $n lines; A10 says under 200 (move module rules to .claude/rules/, history to docs/HISTORY.md: README, Migrating)"
  grep -q "$PB/AGENT-WORKFLOW-PLAYBOOK.md" CLAUDE.md && ok "CLAUDE.md points at the playbook" ||
    fail "CLAUDE.md does not name $PB/AGENT-WORKFLOW-PLAYBOOK.md (add A10's line under the title)"
else
  fail "no CLAUDE.md (write it from the A10 skeleton)"
fi

# The owner's one-time setup skill (section 12): docs/agents/ and the CLAUDE.md block it writes
miss=""
for f in docs/agents/issue-tracker.md docs/agents/domain.md; do [ -f "$f" ] || miss="$miss $f"; done
grep -q '^## Agent skills' CLAUDE.md 2>/dev/null || miss="$miss CLAUDE.md:'## Agent skills'"
[ -z "$miss" ] && ok "setup-matt-pocock-skills has run (docs/agents/)" ||
  fail "missing:$miss; the owner runs /mattpocock-skills:setup-matt-pocock-skills once (section 12; human-only)"

# Module rules: every .claude/rules file has a non-empty paths: list in its frontmatter (A10)
if [ -d .claude/rules ]; then
  while IFS= read -r f; do
    LC_ALL=C awk '
      { sub(/\r$/, "") }
      NR==1 { sub(/^\357\273\277/, ""); if ($0 != "---") exit 1; next }
      $0 == "---" { closed=1; exit }
      /^paths:/ { p=1; v=$0; sub(/^paths:[ \t]*/, "", v)
                  if (v ~ /^\[[ \t]*[^] \t]/ || (v != "" && v !~ /^[[#]/)) items=1; next }
      p && /^[ \t]*-[ \t]*[^ \t]/ { items=1; next }
      /^[^ \t]/ { p=0 }
      END { exit !(closed && items) }' "$f" &&
      ok "$f has paths:" || fail "$f has no paths: list in a closed frontmatter; its rule goes into CLAUDE.md (A10)"
  done < <(find .claude/rules -name '*.md' -type f)
fi

# Agents come from the plugin, not from copies
for a in builder reviewer researcher; do
  c=$( { find .claude/agents -maxdepth 1 -iname "$a.md"
         grep -ilE "^name:[[:space:]]*\"?$a\"?[[:space:]]*$" .claude/agents/*.md; } 2>/dev/null | sort -u)
  [ -z "$c" ] || fail "agent copies (the plugin ships playbook:$a, README): $(echo $c)"
done

# Plugin and settings (README): settings.json and settings.local.json
enabled() {   # the value in settings.local.json wins over settings.json
  local f v r=""
  for f in .claude/settings.json .claude/settings.local.json; do
    [ -f "$f" ] || continue
    v=$(grep -oE '"playbook@agent-playbook" *: *(true|false)' "$f" | tail -n 1 | grep -oE '(true|false)$')
    [ -z "$v" ] || r=$v
  done
  [ "$r" = true ]
}
enabled && ok "plugin playbook@agent-playbook enabled" ||
  fail "plugin not enabled for this clone (README: claude plugin install playbook@agent-playbook --scope local)"
# The marketplace registration is per user: another project's clone may serve the plugin (README).
# INFO only: the remedy repoints the other project, and a --plugin-dir session is invisible here.
lc() { tr '\\' / | tr 'A-Z' 'a-z'; }
if command -v claude >/dev/null; then
  # parses the "Read from:" line of the human-readable list (the --json field is readFromFolder)
  rf=$(${TO:+"$TO" 60} claude plugin list 2>/dev/null | awk '{ sub(/\r$/, "") }
         /playbook@agent-playbook/ {f=1; next} f && /^[ \t]*$/ {exit}
         f && /Read from:/ {sub(/.*Read from:[ \t]*/, ""); print; exit}' | lc)
  here=$( { pwd -W 2>/dev/null || pwd -P; } | lc)/$PB/plugin
  if [ -z "$rf" ]; then info "claude plugin list names no folder for playbook@agent-playbook"
  elif [ "${rf%/}" = "$here" ]; then ok "the plugin is read from this clone's $PB"
  else info "the installed plugin is read from $rf, another clone; sessions here get its agents
        unless started with --plugin-dir $PB/plugin (README, Use it in a project)"
  fi
else
  info "claude not on PATH; which clone serves the plugin is not checked"
fi
for k in CLAUDE_CODE_SUBAGENT_MODEL PLAYBOOK_BUILDER_CHECK; do
  grep -q "\"$k\" *: *\"[^\"]" .claude/settings.json 2>/dev/null && ok "$k in .claude/settings.json" ||
    fail "$k missing or empty in .claude/settings.json (README; P5, P6)"
done
s=$(sed -n 's/.*"PLAYBOOK_SCRATCH" *: *"\([^"]*\)".*/\1/p' .claude/settings.local.json 2>/dev/null | sed 's/\\\\/\\/g')
case "$s" in
  '') fail "PLAYBOOK_SCRATCH missing from .claude/settings.local.json (README; P6)";;
  /*|[A-Za-z]:[/\\]*) [ -d "$s" ] && ok "PLAYBOOK_SCRATCH exists" || fail "PLAYBOOK_SCRATCH '$s' does not exist (create it, outside cloud-synced folders)";;
  *) fail "PLAYBOOK_SCRATCH '$s' is not an absolute path";;
esac
git ls-files --error-unmatch .claude/settings.local.json >/dev/null 2>&1 &&
  fail ".claude/settings.local.json is committed; it holds per-machine paths (untrack it, add it to .gitignore)"

[ $fails -eq 0 ] && echo "check-setup: all checks passed" || echo "check-setup: $fails check(s) failed"
[ $fails -eq 0 ]
