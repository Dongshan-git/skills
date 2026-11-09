// Backstop for Claude Code's built-in idle compaction. Written for 2.1.300, when the built-in
// feature needed fetched feature flags; since 2.1.314 it also runs with DISABLE_TELEMETRY set,
// usually fires first (0.9 of the cache window after the last request), and then this mod finds
// a small context and does nothing. The mod only acts where the built-in pass did not compact,
// and unlike it does not hold back when the usage limit is near.
// After a main-loop turn ends, wait 0.9 of the one-hour prompt cache lifetime; if no turn has
// started since and the context is large, compact while the cache is still warm, so the next
// message sends a summary instead of rebuilding the whole conversation cache.

// 54 minutes, the point the built-in feature fires at (0.9 of the one-hour TTL)
const FIRE_AFTER_MS = 54 * 60_000;
// A timer that runs later than this (the computer slept) finds the cache already gone
const LATE_MS = 60_000;
// The built-in feature's default threshold
const MIN_TOKENS = 200_000;

let timer = null;
let armedAt = 0;

export function register(on) {
  // Subagent and teammate turns carry e.agentId; only the main loop's cache matters here
  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) disarm();
    return next(e);
  });

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) await arm($);
    return next(e);
  });

  on('session.end', async ($, e, next) => {
    disarm();
    return next(e);
  });
}

function disarm() {
  if (timer !== null) timer.cancel();
  timer = null;
}

async function arm($) {
  disarm();
  armedAt = await $.clock.now();
  timer = $.clock.after(FIRE_AFTER_MS, () => fire($));
}

async function fire($) {
  timer = null;
  const idleMs = (await $.clock.now()) - armedAt;
  if (idleMs > FIRE_AFTER_MS + LATE_MS) return;
  // tokens is absent until the session's first response
  const tokens = (await $.session.usage()).context.tokens ?? 0;
  if (tokens < MIN_TOKENS) return;
  // Rejects while a turn runs and in headless (-p / SDK) sessions; the rejection goes to the debug log
  const result = await $.session.compact();
  if ('skip' in result) return;
  $.ui.log(
    `compacted ${Math.round(tokens / 1000)}K tokens after ${Math.round(idleMs / 60_000)} idle minutes, before the prompt cache expired`
  );
}
