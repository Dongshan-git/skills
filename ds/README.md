# ds: personal Claude Code dispatch configuration

Claude Code version: 2.1.260. Source of truth for the files installed under `~/.claude` on my machine. Everything model-facing is English; the rationale and the review that produced these files live on the blog:

- https://docs.dsdev.cn/blog/fable-5-workflow/
- https://docs.dsdev.cn/blog/claude-code-agent-workflow-prompts/

| Path | Installs to | Purpose |
| --- | --- | --- |
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | Global engineering contract, kept small because every session and worker loads it |
| `skills/dispatch-policy/SKILL.md` | `~/.claude/skills/dispatch-policy/` | L0-L4 budgets, role-to-model routing, Fable gate; loaded before the first delegation |
| `skills/workflow-authoring/SKILL.md` | `~/.claude/skills/workflow-authoring/` | Personal override of the bundled skill: every `agent()` must name its model. Derived from the 2.1.260 bundled text; re-diff after upgrades |
| `agents/*.md` | `~/.claude/agents/` | coordinator, Explore, planner, implementer, qa, reviewer, critical-implementer, critical-reviewer |
| `hooks/enforce-agent-dispatch.ps1` | `~/.claude/hooks/` | PreToolUse gate for Agent, Workflow, SendMessage: explicit model or deny |
| `profiles/coordinator.json` | `~/.claude/profiles/` | `claude --profile coordinator`: Opus/high lead with no write tools |
| `settings.snippet.json` | merge into `~/.claude/settings.json` | Hook registration, spawn depth 1, concurrency caps |

`skills/workflow-authoring/SKILL.md` mirrors Anthropic's bundled text and keeps its original punctuation. Not part of the upstream skill buckets; the repo-level `CLAUDE.md` rules for promoted skills do not apply here.
