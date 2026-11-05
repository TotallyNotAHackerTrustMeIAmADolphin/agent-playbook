#!/usr/bin/env bash
# PreToolUse hook on Agent (Task in older Claude Code; playbook section 4). Opt-in via
# env.PLAYBOOK_REQUIRE_TICKET=1: refuses a dispatch from the main session whose description does
# not start with an issue number, `#<n> ...`; `#0` marks work for no ticket.
# Section 9's token metric (scripts/ticket-usage.py) reads that number from the transcripts.
# A dispatch from inside a sub-agent (the hook input names an agent_type) passes: an agent's own
# helpers belong to its ticket. A skill running in the main session must use `#<n>` or `#0` too.
set -uo pipefail
in=$(cat)
[ "${PLAYBOOK_REQUIRE_TICKET:-}" = 1 ] || exit 0
case "$in" in *'"agent_type"'*) exit 0;; esac
desc=$(printf '%s' "$in" | sed -n 's/.*"description" *: *"\([^"]*\)".*/\1/p')
case "$desc" in
  '#'[0-9]*) n=${desc#\#}; n=${n%%[!0-9]*}; rest=${desc#\#$n}
             case "$rest" in ''|' '*|-*|:*) exit 0;; esac;;
esac
echo "Dispatch refused: start the description with the issue number, e.g. '#123 build' or '#123 review PR 456' ('#0 ...' for work without a ticket; playbook section 4). Got: '$desc'" >&2
exit 2
