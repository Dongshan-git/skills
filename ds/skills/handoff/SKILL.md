---
name: handoff
description: Write the session handoff file before a planned break or a session switch, so a new session continues from the file instead of re-reading this conversation. Use when the user runs /handoff, says handoff or 交接, or announces a break longer than the prompt-cache lifetime.
---

# Handoff

Write one file that a fresh session can act on without this conversation. Facts, not narrative; the exact command, not a description of it.

## Where

Write `HANDOFF.md` in a `handoff` directory beside the auto-memory directory named in the system prompt (for example `C:\Users\DS\.claude\projects\E--ds-docs\handoff\HANDOFF.md`). Overwrite it: the previous handoff is superseded by definition. If the system prompt names no memory directory, write `.claude/HANDOFF.md` in the repository and tell the user it is untracked by intent.

## Contents, in this order

1. Header: task title; written at (local date and time); repository and branch; main-session model and effort; Claude Code version.
2. Goal and acceptance: the user's request in their words, the acceptance criteria, the actions the user authorized (stage, commit, push, publish, destructive), and the ones explicitly not authorized.
3. Done: each completed step with its evidence, as the command and its result or the file and what changed in it.
4. In progress: the exact state of unfinished work, including files mid-edit and what remains in each.
5. Decisions: choices made and why, including options rejected, so the next session does not reopen them.
6. Next steps: ordered, smallest first, each naming the command or file it starts from.
7. Blocked or needs the user: open questions, missing authorizations, external evidence that was not available.
8. Working tree: the output of `git status --short`, the files changed since the task began, and any user-owned dirty files that must not be reverted.
9. Dispatch ledger: task level, starts used with the model of each, remaining budget, and the run id of any active workflow.
10. Verification: the exact commands that prove the current state (tests, lint, typecheck, build) and their last result.

Keep it under 200 lines. Refer to files by path; do not paste file contents. Leave out tool output that a listed command reproduces.

## After writing

Reply with the file path and a two-line summary. Do not compact, clear, or end the session; the user decides that. The new session starts with: `Read <path> and continue from its Next steps. Treat its Decisions as settled and do not re-derive what it records.`
