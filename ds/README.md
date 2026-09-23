# ds: personal Claude Code dispatch configuration

Claude Code version: 2.1.280 (config re-verified 2026-09-23; the workflow-authoring override is derived from the 2.1.267 bundled text extracted from the binary and re-diffed against 2.1.280, which differs only in runtime placeholders). Source of truth for the files installed under `~/.claude` on my machine. Everything model-facing is English; the rationale and the review that produced these files live on the blog:

- https://docs.dsdev.cn/blog/fable-5-workflow/
- https://docs.dsdev.cn/blog/claude-code-agent-workflow-prompts/

| Path | Installs to | Purpose |
| --- | --- | --- |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | Global engineering contract, kept small because every session and worker loads it |
| `skills/dispatch-policy/SKILL.md` | `~/.claude/skills/dispatch-policy/` | L0-L4 budgets in Opus-equivalent starts (haiku 0.25, sonnet 0.5, opus 1, fable 2.5; list-price ratios to Opus 5.5, the `opus` alias since 2.1.280), role-to-model routing, Fable gate; independent starts run concurrently; loaded before the first delegation |
| `skills/workflow-authoring/SKILL.md` | `~/.claude/skills/workflow-authoring/` | Personal override of the bundled skill: every `agent()` must name its model. Derived from the 2.1.267 bundled text (a template literal inside `claude.exe`), unchanged through 2.1.280; re-diff after upgrades. Not injected by `/effort ultracode`, which loads the bundled text |
| `agents/*.md` | `~/.claude/agents/` | coordinator, Explore, planner, implementer, qa, reviewer, reviewer-fable, critical-implementer, critical-reviewer |
| `hooks/enforce-agent-dispatch.ps1` | `~/.claude/hooks/` | PreToolUse gate for Agent, Workflow, SendMessage: explicit model within each role's allowed set, or deny. Workflow scripts are lexed (comments, strings, and template literals stripped), each agent call's options object is checked for a literal model, and an `agentType`/`model` pair is checked against the same per-role sets as an Agent call; a saved workflow is resolved only between the working directory and the repository root, then under `CLAUDE_CONFIG_DIR` or `~/.claude` |
| `hooks/tests/*.ps1` | not installed | Test matrix for the hook (116 cases, run under PowerShell 7 with `powershell.exe` as the target); set `HOOK_UNDER_TEST` to test a copy |
| `profiles/coordinator.json` | `~/.claude/profiles/` | `claude --settings ~/.claude/profiles/coordinator.json`: Opus/high lead with no write tools. It is a plain settings file (`--profile` is not a Claude Code flag); `--settings` ranks above user settings, so its `permissions.defaultMode: default` overrides the global `auto` and worker `permissionMode` takes effect |
| `settings.snippet.json` | merge into `~/.claude/settings.json` | Hook registration, spawn depth 1, a 12-subagent concurrency guard, `medium` workflow size guideline, 1h subagent prompt-cache TTL. The machine also carries `skipWorkflowUsageWarning: true`, an undocumented flag the 2.1.280 binary marks `@internal`: Claude Code writes it when the auto-mode workflow usage prompt is accepted (it is unrelated to the advisory Large-workflow warning); it is not part of the snippet |

`skills/workflow-authoring/SKILL.md` mirrors Anthropic's bundled text, apart from the policy hunks its header lists, and keeps its original punctuation. Not part of the upstream skill buckets; the repo-level `CLAUDE.md` rules for promoted skills do not apply here.
