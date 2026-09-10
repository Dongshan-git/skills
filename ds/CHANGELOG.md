# ds changelog

Tracks changes to the personal Claude Code dispatch configuration in this directory, keyed by the Claude Code version they were verified against. The three companion posts are updated alongside each entry:

- https://docs.dsdev.cn/blog/fable-5-workflow/
- https://docs.dsdev.cn/blog/claude-code-agent-workflow-prompts/
- https://docs.dsdev.cn/blog/personal-ai-agent-prompt-tips/

Entry format: Claude Code version, date, what changed here, and which official facts drove the change.

## 2.1.267 (2026-09-10)

Re-verified the three posts and this configuration against the official docs (downloaded as markdown) and the 2.1.265-2.1.267 changelog: three Sonnet post readers, one Opus config review with 25 hook cases, one Sonnet changelog analysis, one Opus adversarial pass. All 15 version citations in the posts hold; 2.1.265-2.1.267 contradict nothing, but the docs and the machine state exposed real defects.

- `hooks/enforce-agent-dispatch.ps1`: Workflow scripts are now lexed before inspection. The old split on every `agent(` occurrence denied compliant scripts whose prompt text mentioned `agent(` (reproduced live twice on 2.1.267) and passed a model-less call whenever later text contained `model: 'sonnet'`. The new scanner strips comments, strings, and template literals (keeping `${}` expressions as code), finds each real agent call, and checks only the direct `model` / `agentType` properties of its last top-level options object; a non-literal model, a nested `workflow()` call, unbalanced parentheses, an unreadable script, or any Fable model or role is denied. Two Opus adversarial passes on that first lexer found sixteen more bypasses or false denies and two fail-open crashes, all fixed: regex literals (a backtick or quote inside one blinded the scanner) now have their own lexer state, with `++`/`--` before a slash read as division; `agent`/`workflow` reached through an alias, `.call`, `.apply`, `?.()`, an invoked member access, or a `\u` escape in an identifier denies, while a property key or field named `agent` is allowed; arguments are split at depth-0 commas and exactly two are required, the second being the options object literal (a lone object would be the prompt and inherit the session model); duplicate keys, spreads, non-literal or concatenated values, and quoted keys are handled; the alias pattern is anchored with `\A`/`\z` so a template literal with a trailing newline cannot pass; option strings are scanned once, removing a quadratic path that stalled 20 KB scripts for 74 s; a non-empty script with no parsable agent call denies; `Test-Path`/`Get-Content`/`Get-ChildItem` failures exit 2 instead of exit 1 (which Claude Code treats as non-blocking); the Agent branch accepts `sonnet[1m]`/`opus[1m]` like the Workflow branch. Saved workflows are resolved from the hook's `cwd` upward, then `~/.claude/workflows`; the plugin-cache search was dropped (plugin workflows are namespaced with a colon and never pass the name validator); bundled workflows stay denied. `ask` decisions now carry `additionalContext`, because hooks.md says an ask reason is shown to the user but never to Claude. SendMessage to a bare agent ID reads the session's `agent-<id>.meta.json` and denies Fable targets or unresolvable IDs (sub-agents.md: `to` accepts an ID); `session_id` must be alphanumeric. Stdin is read explicitly as UTF-8: Windows PowerShell decoded it with the GBK console code page, and an ellipsis before a closing quote in Claude Code's `tool_input.content` preview corrupted the JSON and blocked a legitimate SendMessage with exit 2. A third pass left only three deliberate evasions (ternary alias, `globalThis['agent']`, capturing `globalThis.agent` into a variable), closed by denying global-object access (`globalThis`, `window`, `self`, `global`, `this.agent`), computed member access with a string key, and dynamic code (`eval`, `Function`, `import()`). 108 test cases pass; the harnesses are checked in under `hooks/tests/` (they reference one live session's transcript path and agent ID for the SendMessage lookup cases, adjust before reuse).
- `skills/dispatch-policy/SKILL.md`: opus/high is the model's default effort (model-config.md: `high` on every model that supports effort except Opus 4.7), not a step below a default of xhigh. Claude Code does re-run classifier-flagged requests on a category fallback model (Fable 5.1: biology on Opus 5, cybersecurity on Opus 4.8); `switchModelsOnFlag: false` on this machine turns that into a manual choice, and the docs are silent on subagents, so the manual opus/xhigh rerun rule stays with a corrected rationale.
- `skills/workflow-authoring/SKILL.md`: rebased on the 2.1.267 bundled text extracted from `claude.exe` (no Temp copy exists for this skill). Restored the bundled paragraph on CLAUDE.md injection into subagents. Recorded that the bundled "default to omitting model" clause renders only while `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is unset, and that `/effort ultracode` injects the bundled text rather than this override, so the hook is the enforcing layer in ultracode sessions.
- Settings (machine only, not part of the snippet): `includeCoAuthoredBy` replaced by `attribution`; the unused `impeccable` marketplace entry removed. Evaluated and rejected: `permissions.ask` rules for `git add`, `git commit`, `git push`. `Bash(git:*)` resolves in step 1 of auto mode's decision order, so commits never reach the classifier, and ask rules would prompt in every mode including bypass; the owner chose to keep git authorization as a CLAUDE.md rule rather than a prompt.
- `agents/coordinator.md`: `Agent(...)` allowlist now includes `codex:codex-rescue`, matching the hook's `codex:*` pass-through and the dispatch-policy Codex rule.
- `agents/critical-reviewer.md`: removed a duplicated sentence.
- Decided, not changed: `permissionMode: plan` on the read-only roles stays as an intent declaration. It is ignored under the machine's `defaultMode: auto` (sub-agents.md:549) and holds only under the coordinator profile's `default` mode; the owner accepts tool lists plus prompt text as the read-only guarantee in auto sessions.

Relevant 2.1.265-2.1.267 changelog entries: `maxEffortLevel`; `effort:` frontmatter fix on pinned-effort models (Opus 4.7, Opus 4.8, Fable 5; not the aliases used here); Workflow `agent()` large-schema refusal fix in auto mode; prompt-cache fixes for resumed subagents, SubagentStart context and preloaded skills, and `/model` switches; sub-agents docs add a 2.1.267 rule that a subagent declaring `bypassPermissions` keeps the main conversation's mode.

## 2.1.263 (2026-09-07, agents resync)

- `agents/*.md`: drop the `maxTurns` field from every role and the coordinator sentence that referenced it; the machine removed turn caps earlier and the repo copy had drifted. Turn limits stay out of the definitions; the dispatch-policy start budget is the ceiling.

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
