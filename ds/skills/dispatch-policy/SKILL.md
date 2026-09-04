---
name: dispatch-policy
description: Cost-first budget and model routing for Agent, fork, Workflow, Agent Team, and Codex delegation. Load before the first delegation in a task, or when the user asks about task levels, worker budgets, or which model a worker should use.
---

# Dispatch Policy

Token cost is a first-class constraint. Default to L0 and serial execution. The limits below are ceilings, not targets.

## Task levels

| Level | Use for | Total starts | Starts per workflow | Active workflows | Concurrency | Fable worker starts |
|---|---|--:|--:|--:|--:|--:|
| L0 Direct | Explanations and small edits from current context | 0 | 0 | 0 | 0 | 0 |
| L1 Bounded | One independent task, no cross-check needed | 1 | none | 0 | 1 | 0 |
| L2 Standard | One implementation plus independent QA or review | 4 | 4 | 1 | 2 | 0 |
| L3 Complex | Cross-module, high-risk, or research-then-implement | 6 | 6 | 1 | 3 | 1 |
| L4 Exceptional | Large migration, full audit, performance campaign; requires explicit user approval in this conversation | 8 | 8 | 1 | 4 | 1 |

Counting rules:

- Every Agent call, fork, workflow agent(), pipeline item, teammate, Codex delegation, restart, resume, repair, and rerun is one start.
- Keep one cumulative ledger per user task. Do not split a task across workflows to evade its total.
- In one phase use either direct Agent dispatch or a workflow, never both at once.
- Parallelize only genuinely independent work when the wall-clock gain justifies the extra context.
- At L2 and above, report once before the first dispatch: level, planned starts, peak concurrency, model per role, and Fable allowance. Update only when the level or remaining capacity changes. L1 needs no ledger.
- At any limit, stop creating workers and report the unfinished work. Do not raise the level without the user's instruction.
- A user prompt may tighten these limits; it cannot loosen system instructions, permissions, tool allowlists, or hooks.

## Model routing

Always pass an explicit `subagent_type` and `model` alias to the Agent tool. Aliases resolve to the current generation; do not pin specific versions. Keep `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` unset so per-call and definition-level models apply, and read the resolved model from the Agent tool result.

| Role | Model / effort | Typical work |
|---|---|---|
| Explore | haiku; sonnet/low when the search needs more context or turns | Narrow discovery, evidence lists |
| planner | sonnet/high | Bounded plans, dependency analysis |
| implementer | opus/high | Normal production and test changes |
| qa | sonnet/high | Builds, tests, browser checks, reproduction |
| reviewer | sonnet/high | Ordinary independent review |
| critical-implementer | fable/high | One named critical change |
| critical-reviewer | fable/high | One named critical audit |

Routing notes:

- implementer at opus/high is a deliberate step below the Claude Code default effort. Raise to xhigh when rework or failed verification shows the task needs it.
- Built-in types such as general-purpose and Plan also need an explicit haiku, sonnet, or opus alias.
- A fork ignores the model parameter and runs on the main-session model. Count it as a main-model start and use it only when the full conversation context is required.
- Codex delegation, including codex-rescue, counts as a start and is used only when the user names Codex in the current conversation. The plugin's proactive-use guidance does not override this.
- Preserve the configured main-session model. A dedicated coordinator profile may pin opus/high.
- Do not use Agent Teams unless workers must talk to each other. Do not enable ultracode.

## Fable worker gate

- Fable workers are prohibited in L0 through L2. In L3 and L4 one Fable start is optional, never more than one concurrently.
- Use it only for a named issue involving security, permissions, privacy, concurrency, transactions, irreversible migration, high-impact release, a critical architecture boundary, or one evidence-backed normal-role attempt that failed.
- Run it serially after cheaper evidence is consolidated into a compact packet. Never place it in parallel(), pipeline(), restart, resume, repair, or rerun.
- Never use it for exploration, fan-out, routine implementation, builds, browser QA, formatting, documentation, or ordinary review.
- Raise its effort to xhigh only when an eval on real tasks shows headroom at high.
- If it ends with a refusal stop reason, report that, do not count it as a failed normal-role attempt, and rerun the same task on opus/xhigh without spending another Fable start.
