# Contributing

This playbook comes from running Claude Code agents on a few real projects. It gets better when
people who use it report where it was wrong, unclear or expensive. You can report as a human, or
your agents can.

## Report a problem (the main way to contribute)

Open an issue with the **Playbook feedback** template. Search first:
`gh issue list -R TotallyNotAHackerTrustMeIAmADolphin/agent-playbook -S "<keyword>"`.

- One problem per issue.
- Name the section (Core, 0-13, A1-A12, P1-P17) and the playbook commit you use (or the date of
  your copy).
- Give evidence: what the text said, what happened, and the exact output. "Agents ignored X in
  4 of 10 tickets" helps more than "X does not work".
- Suggest a replacement or a deletion, not an extra rule. The file's one rule is that every rule
  stands once, so a fix edits or removes text.
- No secrets, customer data, private repository names or internal URLs. Paste only what you would
  put on a public website.

A report that is specific to one project gets a short answer explaining why, and is closed: its
rule belongs in that project's `CLAUDE.md` (playbook A10).

## Pull requests

Welcome for typos, broken links and fixes to scripts or hooks. For changes to rules, open an issue
first so the evidence is discussed before the wording. In a PR:

- Keep it to one topic.
- Do not rename or renumber sections or anchors: projects cite them.
- Keep the Core extraction working: the awk command on line 10 of the playbook must still print
  the Core section.
- Text is licensed CC BY 4.0 and code MIT (README, License); by opening a PR you agree to license
  your change the same way.

## Maintainers

How the maintainer sessions handle feedback issues is in `CLAUDE.md`.
