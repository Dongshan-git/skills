$ErrorActionPreference = 'Continue'
$hook = if ($env:HOOK_UNDER_TEST) { $env:HOOK_UNDER_TEST } else { 'C:\Users\DS\.claude\hooks\enforce-agent-dispatch.ps1' }
# A throwaway session directory stands in for a real one, so SendMessage and Fable-count cases do not
# depend on a session that the cleanup period may already have removed.
$sessionRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dispatch-hook-session-' + [guid]::NewGuid().ToString('N'))
$sessionId = 'f2fc05d6-e4ab-4142-a95b-4b645975a631'
$transcript = Join-Path $sessionRoot "$sessionId.jsonl"
$agentDir = Join-Path $sessionRoot "$sessionId\subagents\workflows\wf_fixture"
New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
Set-Content -LiteralPath $transcript -Value ''
Set-Content -LiteralPath (Join-Path $agentDir 'agent-a446350e4ace45639.meta.json') -Value '{"agentType":"workflow-subagent","description":"fixture","model":"opus"}'
$researchScript = Join-Path $PSScriptRoot 'fixtures\research-workflow.js'

function Invoke-Hook {
  param([string]$Name, [string]$Json, [string]$Expect)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'powershell.exe'
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$hook`""
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
  $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write($Json)
  $p.StandardInput.Close()
  $out = $p.StandardOutput.ReadToEnd().Trim()
  $err = $p.StandardError.ReadToEnd().Trim()
  $p.WaitForExit()
  $decision = 'passthrough'
  $reason = ''
  if ($p.ExitCode -eq 2) { $decision = 'exit2'; $reason = $err }
  elseif ($out) { $j = $out | ConvertFrom-Json; $decision = $j.hookSpecificOutput.permissionDecision; $reason = $j.hookSpecificOutput.permissionDecisionReason }
  $ok = if ($decision -eq $Expect) { 'PASS' } else { 'FAIL' }
  "[{0}] {1}: got {2} (expected {3}) :: {4}" -f $ok, $Name, $decision, $Expect, ($reason.Substring(0, [Math]::Min(150, $reason.Length)))
}

function Wf { param([string]$Script) return (@{ tool_name = 'Workflow'; tool_input = @{ script = $Script }; cwd = 'E:\ds-docs'; session_id = $sessionId; transcript_path = $transcript } | ConvertTo-Json -Compress -Depth 5) }
function Sm { param([string]$To) return (@{ tool_name = 'SendMessage'; tool_input = @{ to = $To; message = 'hi' }; cwd = 'E:\ds-docs'; session_id = $sessionId; transcript_path = $transcript } | ConvertTo-Json -Compress -Depth 5) }
function Ag { param([hashtable]$Fields) return (@{ tool_name = 'Agent'; tool_input = $Fields; cwd = 'E:\ds-docs' } | ConvertTo-Json -Compress -Depth 5) }
function AgS { param([hashtable]$Fields) return (@{ tool_name = 'Agent'; tool_input = $Fields; cwd = 'E:\ds-docs'; session_id = $sessionId; transcript_path = $transcript } | ConvertTo-Json -Compress -Depth 5) }

Invoke-Hook 'a Agent reviewer+sonnet' (Ag @{ subagent_type = 'reviewer'; model = 'sonnet'; prompt = 'x' }) 'passthrough'
Invoke-Hook 'b Agent reviewer+fable' (Ag @{ subagent_type = 'reviewer'; model = 'fable'; prompt = 'x' }) 'deny'
Invoke-Hook 'c Agent fork' (Ag @{ subagent_type = 'fork'; model = 'sonnet'; prompt = 'x' }) 'deny'
Invoke-Hook 'd Agent no model' (Ag @{ subagent_type = 'reviewer'; prompt = 'x' }) 'deny'
Invoke-Hook 'q Agent codex:codex-rescue+sonnet' (Ag @{ subagent_type = 'codex:codex-rescue'; model = 'sonnet'; prompt = 'x' }) 'passthrough'
Invoke-Hook 'r Agent general-purpose+sonnet' (Ag @{ subagent_type = 'general-purpose'; model = 'sonnet'; prompt = 'x' }) 'ask'
Invoke-Hook 'r2 Agent general-purpose+fable' (Ag @{ subagent_type = 'general-purpose'; model = 'fable'; prompt = 'x' }) 'deny'
Invoke-Hook 'e Wf one call omits model' (Wf "const a = await agent('p1', { agentType: 'planner', model: 'sonnet' });`nconst b = await agent('p2');") 'deny'
Invoke-Hook 'f Wf double quotes' (Wf "await agent(`"p1`", { model: `"sonnet`" }); await agent(`"p2`", { model: `"haiku`" });") 'allow'
Invoke-Hook 'g Wf multi-line opts' (Wf "await agent(`n  'p1',`n  {`n    model: 'sonnet',`n    label: 'x'`n  }`n);") 'allow'
Invoke-Hook 'h Wf later unrelated model text' (Wf "const a = await agent({ prompt: 'p1' });`nconst cfg = { model: 'sonnet' };") 'deny'
Invoke-Hook 'i Wf prompt mentions agent( before opts' (Wf "const a = await agent('p1', { model: 'sonnet' });`nconst b = await agent('p2', { model: 'sonnet' });`nconst c = await agent(``Do not call agent(anything) yourself. Report findings only.``, { model: 'sonnet', agentType: 'reviewer' });") 'allow'
Invoke-Hook 'i2 Wf prompt string with model: text inside' (Wf "const a = await agent('the prompt says model: sonnet is fine', {});") 'deny'
Invoke-Hook 'i3 Wf template with `${} interpolation' (Wf "const P = 'x';`nconst a = await agent(``Prefix `${P} and agent(mention) `${JSON.stringify({model:'fable'})}``, { model: 'haiku' });") 'allow'
Invoke-Hook 'i4 Wf comment mentions agent(' (Wf "// agent( in a comment`n/* agent( block */`nconst a = await agent('p', { model: 'opus' });") 'allow'
Invoke-Hook 'j Wf agentType reviewer-fable' (Wf "await agent('p', { agentType: 'reviewer-fable' });") 'deny'
Invoke-Hook 'j2 Wf agentType reviewer + model fable' (Wf "await agent('p', { agentType: 'reviewer', model: 'fable' });") 'deny'
Invoke-Hook 'o Wf only call model fable' (Wf "await agent('p', { model: 'fable' });") 'deny'
Invoke-Hook 'o2 Wf model sonnet[1m]' (Wf "await agent('p', { model: 'sonnet[1m]' });") 'allow'
Invoke-Hook 'o3 Wf model non-literal' (Wf "const m = 'sonnet'; await agent('p', { model: m });") 'deny'
Invoke-Hook 'o4 Wf agentType defined role without model' (Wf "await agent('p', { agentType: 'qa' });") 'allow'
Invoke-Hook 'o5 Wf nested workflow()' (Wf "await agent('p', { model: 'sonnet' }); await workflow('deep-research');") 'deny'
Invoke-Hook 'o6 Wf empty agent() mention only' (Wf "const x = agent(); await agent('p', { model: 'sonnet' });") 'allow'
Invoke-Hook 'o7 Wf pipeline arrow with model' (Wf "const r = await pipeline(ITEMS, it => agent(``Do `${it}``, { model: 'haiku', schema: S }), (prev, it) => agent(``Verify `${prev.x}``, { model: 'sonnet' }));") 'allow'
Invoke-Hook 'o8 Wf unbalanced parens' (Wf "await agent('p', { model: 'sonnet' }") 'deny'
Invoke-Hook 'k1 Sm main' (Sm 'main') 'passthrough'
Invoke-Hook 'k2 Sm reviewer-fable' (Sm 'reviewer-fable') 'deny'
Invoke-Hook 'k3 Sm qa' (Sm 'qa') 'ask'
Invoke-Hook 'k4 Sm unknown id' (Sm '7f3a2b19c0d4e5f6') 'deny'
Invoke-Hook 'k5 Sm real id (opus workflow agent)' (Sm 'a446350e4ace45639') 'ask'
Invoke-Hook 'l empty stdin' '' 'exit2'
Invoke-Hook 'm malformed json' '{ this is not json' 'exit2'
Invoke-Hook 'm2 no tool_name' '{"tool_input":{"to":"x"}}' 'exit2'
Invoke-Hook 'n Wf scriptPath nonexistent' (@{ tool_name = 'Workflow'; tool_input = @{ scriptPath = 'C:\does\not\exist\wf.js' }; cwd = 'E:\ds-docs' } | ConvertTo-Json -Compress) 'deny'
Invoke-Hook 's Wf by name deep-research (bundled)' (@{ tool_name = 'Workflow'; tool_input = @{ name = 'deep-research' }; cwd = 'E:\ds-docs' } | ConvertTo-Json -Compress) 'deny'
Invoke-Hook 't Wf real research script via scriptPath' (@{ tool_name = 'Workflow'; tool_input = @{ scriptPath = $researchScript }; cwd = 'E:\ds-docs' } | ConvertTo-Json -Compress) 'allow'
Invoke-Hook 'v1 Wf agentType Explore + model opus' (Wf "await agent('p', { agentType: 'Explore', model: 'opus' });") 'deny'
Invoke-Hook 'v2 Wf agentType implementer + model haiku' (Wf "await agent('p', { agentType: 'implementer', model: 'haiku' });") 'deny'
Invoke-Hook 'v3 Wf agentType Explore + model sonnet' (Wf "await agent('p', { agentType: 'Explore', model: 'sonnet' });") 'allow'
Invoke-Hook 'v4 Wf agentType implementer + model opus[1m]' (Wf "await agent('p', { agentType: 'implementer', model: 'opus[1m]' });") 'allow'
# Per-call effort and name on Fable roles (Agent tool effort since 2.1.292).
Invoke-Hook 'w1 Agent reviewer-fable fresh session' (AgS @{ subagent_type = 'reviewer-fable'; model = 'fable'; prompt = 'x' }) 'passthrough'
Invoke-Hook 'w2 Agent reviewer-fable with effort high' (AgS @{ subagent_type = 'reviewer-fable'; model = 'fable'; effort = 'high'; prompt = 'x' }) 'deny'
Invoke-Hook 'w3 Agent critical-reviewer with effort low' (AgS @{ subagent_type = 'critical-reviewer'; model = 'fable'; effort = 'low'; prompt = 'x' }) 'deny'
Invoke-Hook 'w4 Agent critical-implementer with name' (AgS @{ subagent_type = 'critical-implementer'; model = 'fable'; name = 'helper'; prompt = 'x' }) 'deny'
Invoke-Hook 'w5 Agent reviewer sonnet with effort xhigh' (Ag @{ subagent_type = 'reviewer'; model = 'sonnet'; effort = 'xhigh'; prompt = 'x' }) 'passthrough'
Invoke-Hook 'w6 Agent implementer opus with name' (Ag @{ subagent_type = 'implementer'; model = 'opus'; name = 'impl'; prompt = 'x' }) 'passthrough'
# More than one script source in one Workflow call.
Invoke-Hook 'y1 Wf script + scriptPath' (@{ tool_name = 'Workflow'; tool_input = @{ script = "await agent('p', { model: 'sonnet' });"; scriptPath = $researchScript }; cwd = 'E:\ds-docs' } | ConvertTo-Json -Compress) 'deny'
Invoke-Hook 'y2 Wf script + name' (@{ tool_name = 'Workflow'; tool_input = @{ script = "await agent('p', { model: 'sonnet' });"; name = 'inside' }; cwd = 'E:\ds-docs' } | ConvertTo-Json -Compress) 'deny'
Invoke-Hook 'y3 Wf scriptPath + name' (@{ tool_name = 'Workflow'; tool_input = @{ scriptPath = $researchScript; name = 'inside' }; cwd = 'E:\ds-docs' } | ConvertTo-Json -Compress) 'deny'
# Saved-workflow resolution: by meta.name, only between the working directory and the repository root, then the personal directory.
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('dispatch-hook-fixture-' + [guid]::NewGuid().ToString('N'))
foreach ($d in @('repo\sub', 'repo\.git', 'repo\.claude\workflows', '.claude\workflows', 'cfg\workflows')) { New-Item -ItemType Directory -Force -Path (Join-Path $fixture $d) | Out-Null }
function SavedWf { param([string]$MetaName, [string]$Model) return "export const meta = { name: '$MetaName', description: 'fixture' }`nawait agent('p', { model: '$Model' });" }
Set-Content -LiteralPath (Join-Path $fixture 'repo\.claude\workflows\inside.js') -Value (SavedWf 'inside' 'sonnet')
Set-Content -LiteralPath (Join-Path $fixture '.claude\workflows\above.js') -Value (SavedWf 'above' 'sonnet')
Set-Content -LiteralPath (Join-Path $fixture 'cfg\workflows\personal.js') -Value (SavedWf 'personal' 'sonnet')
Set-Content -LiteralPath (Join-Path $fixture 'repo\.claude\workflows\renamed-file.js') -Value (SavedWf 'by-meta' 'haiku')
Set-Content -LiteralPath (Join-Path $fixture 'repo\.claude\workflows\decoy.js') -Value (SavedWf 'decoy-meta' 'sonnet')
Set-Content -LiteralPath (Join-Path $fixture 'repo\.claude\workflows\real.js') -Value (SavedWf 'decoy' 'fable')
Set-Content -LiteralPath (Join-Path $fixture 'repo\.claude\workflows\dup-a.js') -Value (SavedWf 'dup' 'sonnet')
Set-Content -LiteralPath (Join-Path $fixture 'repo\.claude\workflows\dup-b.js') -Value (SavedWf 'dup' 'sonnet')
Set-Content -LiteralPath (Join-Path $fixture 'repo\.claude\workflows\no-meta.js') -Value "await agent('p', { model: 'sonnet' });"
Set-Content -LiteralPath (Join-Path $fixture 'repo\.claude\workflows\phases-first.js') -Value "export const meta = {`n  phases: [{ title: 'A', name: 'nested' }],`n  description: 'has name: wrong inside a string',`n  name: 'phases-first',`n}`nawait agent('p', { model: 'sonnet' });"
function WfName { param([string]$Name, [string]$Cwd) return (@{ tool_name = 'Workflow'; tool_input = @{ name = $Name }; cwd = $Cwd } | ConvertTo-Json -Compress) }
Invoke-Hook 'x1 Wf by name inside the repo' (WfName 'inside' (Join-Path $fixture 'repo\sub')) 'allow'
Invoke-Hook 'x2 Wf by name above the repo root' (WfName 'above' (Join-Path $fixture 'repo\sub')) 'deny'
$env:CLAUDE_CONFIG_DIR = Join-Path $fixture 'cfg'
Invoke-Hook 'x3 Wf by name personal via CLAUDE_CONFIG_DIR' (WfName 'personal' (Join-Path $fixture 'repo\sub')) 'allow'
Remove-Item -Path Env:CLAUDE_CONFIG_DIR
Invoke-Hook 'x4 Wf by name personal without CLAUDE_CONFIG_DIR' (WfName 'personal' (Join-Path $fixture 'repo\sub')) 'deny'
Invoke-Hook 'x5 Wf by meta.name whose file name differs' (WfName 'by-meta' (Join-Path $fixture 'repo\sub')) 'allow'
Invoke-Hook 'x6 Wf name matches a decoy file, meta.name owner uses fable' (WfName 'decoy' (Join-Path $fixture 'repo\sub')) 'deny'
Invoke-Hook 'x7 Wf two scripts declare the same meta.name' (WfName 'dup' (Join-Path $fixture 'repo\sub')) 'deny'
Invoke-Hook 'x8 Wf file name only, no meta block' (WfName 'no-meta' (Join-Path $fixture 'repo\sub')) 'deny'
Invoke-Hook 'x9 Wf meta.name after phases and strings mentioning name:' (WfName 'phases-first' (Join-Path $fixture 'repo\sub')) 'allow'
Remove-Item -LiteralPath $fixture -Recurse -Force
Invoke-Hook 'u Bash passthrough' (@{ tool_name = 'Bash'; tool_input = @{ command = 'ls' } } | ConvertTo-Json -Compress) 'passthrough'
Remove-Item -LiteralPath $sessionRoot -Recurse -Force
