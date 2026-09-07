# ds changelog

Tracks changes to the personal Claude Code dispatch configuration in this directory, keyed by the Claude Code version they were verified against. The three companion posts are updated alongside each entry:

- https://docs.dsdev.cn/blog/fable-5-workflow/
- https://docs.dsdev.cn/blog/claude-code-agent-workflow-prompts/
- https://docs.dsdev.cn/blog/personal-ai-agent-prompt-tips/

Entry format: Claude Code version, date, what changed here, and which official facts drove the change.

## 2.1.263 (2026-09-07)

Re-verified every factual claim in the three posts against current docs using five Sonnet readers (100 claims: 61 confirmed, 1 contradicted, 10 imprecise, the rest confirmed on secondary pages).

- `settings.snippet.json`: add `subagentPromptCacheTtl: "1h"`; workflow and subagent cache defaults to 5 minutes.
- `hooks/enforce-agent-dispatch.ps1`: Workflow script check splits case-sensitively on real `agent(` calls and skips empty-argument mentions, fixing a false deny on prompt text containing `Agent(type)`.
- `skills/dispatch-policy/SKILL.md`: name Fable 5.1 medium as the evaluation midpoint; note that the API's refusal fallback to Opus is not exposed by Claude Code.
- `skills/workflow-authoring/SKILL.md`: baseline stays the 2.1.260 bundled text; 2.1.263 has not produced a new bundled extraction to diff.
- Posts: general-purpose does not preload skills; the over-prescriptive-prompt claim is attributed to the bundled claude-api skill; Stop-hook block cap and `/goal` circuit breaker separated; teammate model resolution and `availableModels` substitution; PreToolUse deny guarantee quoted; `fable[1m]` marked undocumented; Large workflow warning, Agent Team 7x cost, CLAUDE.md 200-line guidance, `/skill-doctor`, 2.1.261 teammate cache fix added.

Relevant 2.1.261 changelog entries: `/skill-doctor`, `bashOutputMaxChars`, `taskOutputMaxChars`, `--append-subagent-system-prompt-file`, in-process teammate cache fix.

## 2.1.260 (2026-09-04, second pass)

Aligned routing with Anthropic guidance after checking the costs and model-config docs, the model-and-effort blog post, the Fable 5.1 prompting guide, and community practice.

- Hook enforces a per-role allowed model set instead of a single pin: Explore haiku or sonnet; planner, qa, reviewer sonnet or opus; implementer opus or sonnet; critical roles fable.
- New `agents/reviewer-fable.md`: read-only review on Fable at low effort, an ordinary start from L1, based on the official note that Fable 5.1 at low is competitive on cost per task.
- Critical Fable slot allowed from L2.
- `skills/dispatch-policy/SKILL.md`: escalation order (effort before model), adversarial review prompts.
- `agents/reviewer.md` and `agents/critical-reviewer.md`: adversarial framing.
- `CLAUDE.md`: verify fast-moving names by searching before answering.

## 2.1.260 (2026-09-04, first pass)

Initial extraction of the configuration from `~/.claude` after a deep review of the machine and the three posts.

- `CLAUDE.md` reduced to the cross-project engineering contract; budgets and routing moved to `skills/dispatch-policy/SKILL.md`.
- `skills/workflow-authoring/SKILL.md` overrides the bundled skill so every `agent()` names its model.
- Hook: fail closed on empty or malformed input; deny missing model, fork, out-of-set Fable; deny SendMessage to Fable roles; inspect Workflow scripts for per-call models.
- Critical roles moved from xhigh to high; refusal rerun rule; Codex delegation counted as a start.
- `profiles/coordinator.json`: `permissions.defaultMode: default` so worker `permissionMode` takes effect.
- Verified live: PreToolUse deny works under bypass mode; `ask` is auto-approved under bypass.
