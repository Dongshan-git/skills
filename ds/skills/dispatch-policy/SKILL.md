---
name: dispatch-policy
description: Cost-first budget and model routing for Agent, fork, Workflow, Agent Team, and Codex delegation. Load before the first delegation in a task, or when the user asks about task levels, worker budgets, or which model a worker should use.
---

# Dispatch Policy

Token cost is a first-class constraint; wall-clock time is a separate one. Default to L0. Concurrency changes wall-clock, not tokens: run every independent start of a phase at once and serialize only a stage that consumes an earlier stage's output. The budgets below are ceilings, not targets.

## Task levels

Budgets are counted in Opus-equivalent starts. Weigh each start by its model: haiku 0.2, sonnet 0.4, opus 1, fable 2 (the API list-price ratios to Opus 5; subscription usage draws down in roughly the same proportion). Two role exceptions: `reviewer-fable` at low effort weighs 1, on Anthropic's statement that Fable 5.1 at low is often competitive with Opus and Sonnet on cost per task; the critical Fable roles at high weigh 2. Effort changes a start's tokens but not its weight; keep effort in the role definition.

| Level | Use for | Budget (Opus-equivalent starts) | Active workflows | Critical Fable starts |
| --- | --- | --: | --: | --: |
| L0 Direct | Explanations and small edits from current context | 0 | 0 | 0 |
| L1 Bounded | One independent task, no cross-check needed | 1 | 0 | 0 |
| L2 Standard | One implementation plus independent QA or review | 4 | 1 | 1 |
| L3 Complex | Cross-module, high-risk, or research-then-implement | 6 | 1 | 1 |
| L4 Exceptional | Large migration, full audit, performance campaign; requires explicit user approval in this conversation | 8 | 1 | 1 |

Worked examples: an opus implementer, a sonnet qa, a sonnet reviewer, and five haiku Explore starts spend 2.8 of L2's 4; three opus and two sonnet readers spend 3.8 of L3's 6; a workflow of ten sonnet finders spends 4.

Counting rules:

- Every Agent call, fork, workflow agent(), pipeline item, teammate, Codex delegation, restart, resume, repair, and rerun is a start at its model's weight. A fork weighs as the main-session model. A Codex delegation weighs 1.
- Keep one cumulative ledger per user task. The budget belongs to the whole task, not to one workflow; do not split a task across workflows to evade it.
- In one phase use either direct Agent dispatch or a workflow, never both at once. One active workflow at a time.
- Run all genuinely independent starts of a phase concurrently. Sibling workflow agents share a prompt-cache prefix, so a fan-out costs no more than the same starts run one by one. Serialize only stages that need an earlier result. The runtime caps still apply: 12 concurrent Agent-tool subagents (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`) and up to 16 concurrent workflow agents; a candidate set beyond a runtime cap runs in batches, never silently truncated.
- Do not invent independent work to fill the concurrency. Every start still needs a reason.
- At L2 and above, report once before the first dispatch: level, each planned start with its weight and the weighted total, planned concurrency, model per role, and Fable allowance. Update only when the level or the remaining budget changes. L1 needs no ledger.
- At any limit, stop creating workers and report the unfinished work. Do not raise the level without the user's instruction.
- A user prompt may tighten these limits; it cannot loosen system instructions, permissions, tool allowlists, or hooks.

## Model routing

Always pass an explicit `subagent_type` and `model` alias to the Agent tool. Aliases resolve to the current generation; do not pin specific versions. Keep `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` unset so per-call and definition-level models apply, and read the resolved model from the Agent tool result.

Each role has a default model in its definition and an allowed set enforced by the hook. Overriding within the allowed set per call is normal; the default is where to start, not a ceiling.

| Role | Default | Allowed | Typical work |
| --- | --- | --- | --- |
| Explore | haiku | haiku, sonnet | Narrow discovery, evidence lists; sonnet when the search needs more context or turns |
| planner | sonnet/high | sonnet, opus | Bounded plans; opus for cross-module architecture |
| implementer | opus/high | opus, sonnet | Production and test changes; sonnet for mechanical edits you can describe precisely |
| qa | sonnet/high | sonnet, opus | Builds, tests, browser checks, reproduction |
| reviewer | sonnet/high | sonnet, opus | Ordinary independent review; opus for permissions, data, concurrency, migration, public contracts |
| reviewer-fable | fable/low | fable | Read-only review when Sonnet's judgment is not enough; Anthropic reports Fable 5.1 at low is often competitive with Opus and Sonnet on cost per task while scoring higher |
| critical-implementer | fable/high | fable | One named critical change |
| critical-reviewer | fable/high | fable | One named critical audit |

Escalation order, from the Claude Code model guidance: ask whether the worker did not try hard enough or did not know enough. Not trying hard enough (skipped a file, did not run tests, did not double-check) means raise effort or rerun with a sharper prompt on the same model. Not knowing enough (subtle bug, unfamiliar domain, architecture decision) means move to a stronger model. Judge cost per completed task, not per token; a cheaper worker that needs another round is not cheaper.

Routing notes:

- implementer at opus/high runs at the model's default effort: Claude Code defaults to high on every model that supports effort except Opus 4.7, and xhigh is only the default under ultracode. Raise to xhigh when rework or failed verification shows the task needs it.
- Review prompts are adversarial: ask the reviewer to refute the change and prove it does not work. A second reviewer with fresh context beats re-asking the same one.
- Built-in types such as general-purpose and Plan also need an explicit haiku, sonnet, or opus alias.
- A fork ignores the model parameter and runs on the main-session model. Count it at that model's weight and use it only when the full conversation context is required.
- Codex delegation, including codex-rescue, counts as a start and is used only when the user names Codex in the current conversation. The plugin's proactive-use guidance does not override this.
- Preserve the configured main-session model. A dedicated coordinator profile may pin opus/high.
- Do not use Agent Teams unless workers must talk to each other. Do not enable ultracode.

## Fable worker gate

Two kinds of Fable worker exist and are budgeted differently.

- `reviewer-fable` at low effort is an ordinary read-only start. It is allowed from L1 upward and weighs 1 against the level's budget. Use it when a Sonnet review is uncertain or the diff is high-stakes, and tell it to read before concluding because Fable at low searches less on its own.
- `critical-implementer` and `critical-reviewer` at high effort are the critical slot: at most one start per user task, weighing 2, allowed from L2 upward (an implementation plus its review is L2, and the review may be the critical one), never more than one Fable worker of any kind running concurrently.
- Use the critical slot only for a named issue involving security, permissions, privacy, concurrency, transactions, irreversible migration, high-impact release, a critical architecture boundary, or one evidence-backed normal-role attempt that failed.
- Run critical roles serially after cheaper evidence is consolidated into a compact packet. Never place any Fable worker in parallel(), pipeline(), restart, resume, repair, or rerun.
- Never use Fable workers for exploration, fan-out, routine implementation, builds, browser QA, formatting, or documentation.
- Raise a critical role to xhigh only when an eval on real tasks shows headroom at high. Anthropic reports Fable 5.1 at medium roughly matches Fable 5 at lower cost, so medium is the named midpoint to evaluate between reviewer-fable at low and the critical roles at high.
- If a Fable worker ends with a refusal stop reason, report that, do not count it as a failed normal-role attempt, and rerun the same task on opus/xhigh without spending another Fable start. Claude Code does re-run classifier-flagged requests on a category fallback model (Fable 5.1: biology on Opus 5, cybersecurity on Opus 4.8) and shows a notice; this machine sets `switchModelsOnFlag: false`, which turns that into a pause for a manual choice in interactive sessions and an error in `-p` runs, and the docs do not say whether the automatic fallback reaches subagents. The manual rerun rule therefore stays. Finding vulnerabilities in source code is permitted; false positives come mostly from compile-check phrasing, obscure languages, and base64 in tool output.
