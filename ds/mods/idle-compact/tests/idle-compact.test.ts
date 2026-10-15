import { expect, mock, test } from 'claude-code/testing'

const MINUTE = 60_000

function usage(tokens?: number) {
  return { value: { startedAt: 0, context: { tokens, window: 1_000_000 }, rateLimits: [] } }
}

// Registers the stubs every test needs and returns what the mod did
function setup(on: any, tokens: number | undefined, veto?: string) {
  const clock = mock.clock(on)
  const calls = { compact: 0, logs: [] as string[] }
  on('turn.start', ($: any, e: any) => ({ turnId: e.turnId }))
  on('turn.complete', () => ({ text: '' }))
  on('session.end', () => ({ sessionId: 's' }))
  on('session.usage', () => usage(tokens))
  on('session.compact', () => {
    calls.compact += 1
    return veto ? { skip: veto } : { messages: [{ role: 'user', text: 'summary', toolUses: [] }] }
  })
  on('ui.log', ($: any, e: any) => {
    calls.logs.push(e.text)
    return { value: undefined }
  })
  return { clock, calls }
}

function complete($: any, turnId: string, agentId?: string) {
  return $.turn.complete({ turnId, answer: '', durationMs: 1, isAborted: false, usage: null, ...(agentId ? { agentId } : {}) })
}

test('a large conversation idle for 54 minutes is compacted once', async ($, on) => {
  const { clock, calls } = setup(on, 250_000)
  await complete($, 't1')
  await clock.advance(53 * MINUTE)
  expect(calls.compact).toBe(0)
  await clock.advance(1 * MINUTE)
  expect(calls.compact).toBe(1)
  expect(calls.logs[0]).toMatch(/compacted 250K tokens after 54 idle minutes/)
  await clock.advance(120 * MINUTE)
  expect(calls.compact).toBe(1)
})

test('a conversation under 200K tokens is left alone', async ($, on) => {
  const { clock, calls } = setup(on, 199_999)
  await complete($, 't1')
  await clock.advance(60 * MINUTE)
  expect(calls.compact).toBe(0)
})

test('a session with no token count yet is left alone', async ($, on) => {
  const { clock, calls } = setup(on, undefined)
  await complete($, 't1')
  await clock.advance(60 * MINUTE)
  expect(calls.compact).toBe(0)
})

test('a compaction another hook vetoes is not reported as done', async ($, on) => {
  const { clock, calls } = setup(on, 300_000, 'PreCompact hook blocked it')
  await complete($, 't1')
  await clock.advance(54 * MINUTE)
  expect(calls.compact).toBe(1)
  expect(calls.logs).toEqual([])
})

test('a new main-loop turn cancels the pending compaction and the next idle period re-arms it', async ($, on) => {
  const { clock, calls } = setup(on, 300_000)
  await complete($, 't1')
  await clock.advance(30 * MINUTE)
  await $.turn.start({ turnId: 't2' })
  await clock.advance(40 * MINUTE)
  expect(calls.compact).toBe(0)
  await complete($, 't2')
  await clock.advance(54 * MINUTE)
  expect(calls.compact).toBe(1)
})

test('subagent turns neither arm nor cancel the main-loop timer', async ($, on) => {
  const { clock, calls } = setup(on, 300_000)
  await complete($, 's1', 'agent-1')
  await clock.advance(60 * MINUTE)
  expect(calls.compact).toBe(0)
  await complete($, 't1')
  await clock.advance(20 * MINUTE)
  await $.turn.start({ turnId: 's2', agentId: 'agent-1' })
  await clock.advance(34 * MINUTE)
  expect(calls.compact).toBe(1)
})

test('ending the session cancels the pending compaction', async ($, on) => {
  const { clock, calls } = setup(on, 300_000)
  await complete($, 't1')
  await $.session.end({ reason: 'clear' })
  await clock.advance(60 * MINUTE)
  expect(calls.compact).toBe(0)
})
