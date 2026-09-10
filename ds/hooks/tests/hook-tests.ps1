$ErrorActionPreference = 'Continue'
$hook = if ($env:HOOK_UNDER_TEST) { $env:HOOK_UNDER_TEST } else { 'C:\Users\DS\.claude\hooks\enforce-agent-dispatch.ps1' }
$sessionId = 'f2fc05d6-e4ab-4142-a95b-4b645975a631'
$transcript = "C:\Users\DS\.claude\projects\E--ds-docs\$sessionId.jsonl"
$researchScript = 'C:\Users\DS\.claude\projects\E--ds-docs\f2fc05d6-e4ab-4142-a95b-4b645975a631\workflows\scripts\claude-code-deep-research-2-1-267-wf_902195b8-125.js'

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

Invoke-Hook 'a Agent reviewer+sonnet' (Ag @{ subagent_type = 'reviewer'; model = 'sonnet'; prompt = 'x' }) 'passthrough'
Invoke-Hook 'b Agent reviewer+fable' (Ag @{ subagent_type = 'reviewer'; model = 'fable'; prompt = 'x' }) 'deny'
Invoke-Hook 'c Agent fork' (Ag @{ subagent_type = 'fork'; model = 'sonnet'; prompt = 'x' }) 'deny'
Invoke-Hook 'd Agent no model' (Ag @{ subagent_type = 'reviewer'; prompt = 'x' }) 'deny'
Invoke-Hook 'q Agent codex:codex-rescue+sonnet' (Ag @{ subagent_type = 'codex:codex-rescue'; model = 'sonnet'; prompt = 'x' }) 'passthrough'
Invoke-Hook 'r Agent general-purpose+sonnet' (Ag @{ subagent_type = 'general-purpose'; model = 'sonnet'; prompt = 'x' }) 'ask'
Invoke-Hook 'r2 Agent general-purpose+fable' (Ag @{ subagent_type = 'general-purpose'; model = 'fable'; prompt = 'x' }) 'deny'
Invoke-Hook 'e Wf one call omits model' (Wf "const a = await agent('p1', { agentType: 'planner', model: 'sonnet' });`nconst b = await agent('p2');") 'deny'
Invoke-Hook 'f Wf double quotes' (Wf "await agent(`"p1`", { model: `"sonnet`" }); await agent(`"p2`", { model: `"haiku`" });") 'ask'
Invoke-Hook 'g Wf multi-line opts' (Wf "await agent(`n  'p1',`n  {`n    model: 'sonnet',`n    label: 'x'`n  }`n);") 'ask'
Invoke-Hook 'h Wf later unrelated model text' (Wf "const a = await agent({ prompt: 'p1' });`nconst cfg = { model: 'sonnet' };") 'deny'
Invoke-Hook 'i Wf prompt mentions agent( before opts' (Wf "const a = await agent('p1', { model: 'sonnet' });`nconst b = await agent('p2', { model: 'sonnet' });`nconst c = await agent(``Do not call agent(anything) yourself. Report findings only.``, { model: 'sonnet', agentType: 'reviewer' });") 'ask'
Invoke-Hook 'i2 Wf prompt string with model: text inside' (Wf "const a = await agent('the prompt says model: sonnet is fine', {});") 'deny'
Invoke-Hook 'i3 Wf template with `${} interpolation' (Wf "const P = 'x';`nconst a = await agent(``Prefix `${P} and agent(mention) `${JSON.stringify({model:'fable'})}``, { model: 'haiku' });") 'ask'
Invoke-Hook 'i4 Wf comment mentions agent(' (Wf "// agent( in a comment`n/* agent( block */`nconst a = await agent('p', { model: 'opus' });") 'ask'
Invoke-Hook 'j Wf agentType reviewer-fable' (Wf "await agent('p', { agentType: 'reviewer-fable' });") 'deny'
Invoke-Hook 'j2 Wf agentType reviewer + model fable' (Wf "await agent('p', { agentType: 'reviewer', model: 'fable' });") 'deny'
Invoke-Hook 'o Wf only call model fable' (Wf "await agent('p', { model: 'fable' });") 'deny'
Invoke-Hook 'o2 Wf model sonnet[1m]' (Wf "await agent('p', { model: 'sonnet[1m]' });") 'ask'
Invoke-Hook 'o3 Wf model non-literal' (Wf "const m = 'sonnet'; await agent('p', { model: m });") 'deny'
Invoke-Hook 'o4 Wf agentType defined role without model' (Wf "await agent('p', { agentType: 'qa' });") 'ask'
Invoke-Hook 'o5 Wf nested workflow()' (Wf "await agent('p', { model: 'sonnet' }); await workflow('deep-research');") 'deny'
Invoke-Hook 'o6 Wf empty agent() mention only' (Wf "const x = agent(); await agent('p', { model: 'sonnet' });") 'ask'
Invoke-Hook 'o7 Wf pipeline arrow with model' (Wf "const r = await pipeline(ITEMS, it => agent(``Do `${it}``, { model: 'haiku', schema: S }), (prev, it) => agent(``Verify `${prev.x}``, { model: 'sonnet' }));") 'ask'
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
Invoke-Hook 't Wf real research script via scriptPath' (@{ tool_name = 'Workflow'; tool_input = @{ scriptPath = $researchScript }; cwd = 'E:\ds-docs' } | ConvertTo-Json -Compress) 'ask'
Invoke-Hook 'u Bash passthrough' (@{ tool_name = 'Bash'; tool_input = @{ command = 'ls' } } | ConvertTo-Json -Compress) 'passthrough'
