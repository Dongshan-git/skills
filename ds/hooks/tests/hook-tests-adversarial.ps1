# Adversarial cases from the 2026-09-10 review. Dot-source the base harness functions by running it with
# $env:HOOK_ONLY_FUNCTIONS = '1' is not supported, so the helper is duplicated here.
$ErrorActionPreference = 'Continue'
$hook = if ($env:HOOK_UNDER_TEST) { $env:HOOK_UNDER_TEST } else { 'C:\Users\DS\.claude\hooks\enforce-agent-dispatch.ps1' }
$sessionId = 'f2fc05d6-e4ab-4142-a95b-4b645975a631'
$transcript = "C:\Users\DS\.claude\projects\E--ds-docs\$sessionId.jsonl"

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
  elseif ($p.ExitCode -ne 0) { $decision = "exit$($p.ExitCode)"; $reason = $err }
  elseif ($out) { $j = $out | ConvertFrom-Json; $decision = $j.hookSpecificOutput.permissionDecision; $reason = $j.hookSpecificOutput.permissionDecisionReason }
  $ok = if ($decision -eq $Expect) { 'PASS' } else { 'FAIL' }
  "[{0}] {1}: got {2} (expected {3}) :: {4}" -f $ok, $Name, $decision, $Expect, ($reason.Substring(0, [Math]::Min(140, $reason.Length)))
}
function Wf { param([string]$Script) return (@{ tool_name = 'Workflow'; tool_input = @{ script = $Script }; cwd = 'E:\ds-docs'; session_id = $sessionId; transcript_path = $transcript } | ConvertTo-Json -Compress -Depth 5) }
function Sm { param([string]$To, [string]$Sid = $sessionId) return (@{ tool_name = 'SendMessage'; tool_input = @{ to = $To; message = 'hi' }; cwd = 'E:\ds-docs'; session_id = $Sid; transcript_path = $transcript } | ConvertTo-Json -Compress -Depth 5) }
function Ag { param([hashtable]$Fields) return (@{ tool_name = 'Agent'; tool_input = $Fields; cwd = 'E:\ds-docs' } | ConvertTo-Json -Compress -Depth 5) }

Invoke-Hook 'D1 backtick in regex hides calls' (Wf "const fence = /``/g;`nconst notes = await agent('Summarise', { model: 'fable' });") 'deny'
Invoke-Hook 'D1b backtick regex + compliant calls' (Wf "const fence = /``/g;`nconst notes = await agent('Summarise', { model: 'sonnet' });`nconst c = await agent('Check', { model: 'opus' });") 'ask'
Invoke-Hook 'D2 quote in regex same line' (Wf "const re = /don't/; await agent('p', { model: 'fable' });") 'deny'
Invoke-Hook 'D2b quote in regex + compliant' (Wf "const re = /say`"/; await agent('p', { model: 'haiku' });") 'ask'
Invoke-Hook 'D2c division not regex' (Wf "const n = 10 / 2; const m = a / b / c; await agent('p', { model: 'sonnet' });") 'ask'
Invoke-Hook 'D2d regex with class containing slash' (Wf "const re = /[/]x/; await agent('p', { model: 'sonnet' });") 'ask'
Invoke-Hook 'D3 duplicate model key' (Wf "await agent('p', { model: 'sonnet', model: 'fable' });") 'deny'
Invoke-Hook 'D3b duplicate agentType key' (Wf "await agent('p', { agentType: 'qa', agentType: 'critical-reviewer' });") 'deny'
Invoke-Hook 'D4 opts second arg fable, third sonnet' (Wf "await agent('p', { model: 'fable' }, { model: 'sonnet' });") 'deny'
Invoke-Hook 'D4b three args compliant still deny' (Wf "await agent('p', { model: 'sonnet' }, { x: 1 });") 'deny'
Invoke-Hook 'D5a alias const a = agent' (Wf "const a = agent;`nawait a('p', { model: 'fable' });") 'deny'
Invoke-Hook 'D5b agent.call' (Wf "await agent.call(null, 'p', { model: 'fable' });") 'deny'
Invoke-Hook 'D5c agent.apply' (Wf "await agent.apply(null, ['p', { model: 'fable' }]);") 'deny'
Invoke-Hook 'D5d globalThis.agent' (Wf "await globalThis.agent('p', { model: 'fable' });") 'deny'
Invoke-Hook 'D5e optional call agent?.(' (Wf "await agent?.('p', { model: 'fable' });") 'deny'
Invoke-Hook 'D5f unicode escape identifier' (Wf "await \u0061gent('p', { model: 'fable' });") 'deny'
Invoke-Hook 'D5g workflow alias' (Wf "const w = workflow; await w('deep-research'); await agent('p', { model: 'sonnet' });") 'deny'
Invoke-Hook 'D6 spread after model' (Wf "await agent('p', { model: 'sonnet', ...override });") 'deny'
Invoke-Hook 'D6b spread before model' (Wf "await agent('p', { ...base, model: 'sonnet' });") 'deny'
Invoke-Hook 'D7 model literal + suffix' (Wf "await agent('p', { model: 'sonnet' + suffix });") 'deny'
Invoke-Hook 'D8 quoted key single' (Wf "await agent('p', { 'model': 'sonnet' });") 'ask'
Invoke-Hook 'D8b quoted key double' (Wf "await agent('p', { `"model`": `"sonnet`" });") 'ask'
Invoke-Hook 'D8c quoted agentType key' (Wf "await agent('p', { 'agentType': 'qa' });") 'ask'
Invoke-Hook 'D8d prompt string containing model: text at depth 1' (Wf "await agent('p', { prompt: 'model: fable is bad', model: 'sonnet' });") 'ask'
Invoke-Hook 'D9a name with trailing newline' ('{"tool_name":"Workflow","tool_input":{"name":"foo\n"},"cwd":"E:\\ds-docs"}') 'deny'
Invoke-Hook 'D9b scriptPath access denied' ('{"tool_name":"Workflow","tool_input":{"scriptPath":"C:\\Windows\\System32\\config\\SAM"},"cwd":"E:\\ds-docs"}') 'exit2'
Invoke-Hook 'D10a unterminated template' (Wf "const s = ``abc;`nawait agent('p', { model: 'fable' });") 'deny'
Invoke-Hook 'D10b unterminated block comment' (Wf "/* start`nawait agent('p', { model: 'fable' });") 'deny'
Invoke-Hook 'D11a script is number' ('{"tool_name":"Workflow","tool_input":{"script":42},"cwd":"E:\\ds-docs"}') 'deny'
Invoke-Hook 'D11b script is array' ('{"tool_name":"Workflow","tool_input":{"script":["a","b"]},"cwd":"E:\\ds-docs"}') 'deny'
Invoke-Hook 'D12a Agent reviewer sonnet[1m]' (Ag @{ subagent_type = 'reviewer'; model = 'sonnet[1m]'; prompt = 'x' }) 'passthrough'
Invoke-Hook 'D12b Agent reviewer opus[1m]' (Ag @{ subagent_type = 'reviewer'; model = 'opus[1m]'; prompt = 'x' }) 'passthrough'
Invoke-Hook 'D12c Agent reviewer fable[1m]' (Ag @{ subagent_type = 'reviewer'; model = 'fable[1m]'; prompt = 'x' }) 'deny'
Invoke-Hook 'R1 zero calls non-empty script' (Wf "const x = 1;") 'deny'
Invoke-Hook 'R4 session_id traversal' (Sm 'a446350e4ace45639' '..\..') 'deny'
Invoke-Hook 'R5 escaped quote in model literal' (Wf "await agent('p', { model: 'son\'net' });") 'deny'
Invoke-Hook 'O nested object with model inside opts' (Wf "await agent('p', { schema: { properties: { model: { type: 'string' } } }, model: 'sonnet' });") 'ask'
Invoke-Hook 'O2 comment inside args' (Wf "await agent('p', /* opts */ { model: 'sonnet' /* fine */ });") 'ask'
Invoke-Hook 'O3 CRLF input' (Wf "const a = await agent('p1', { model: 'sonnet' });`r`nconst b = await agent('p2', { model: 'haiku' });`r`n") 'ask'
Invoke-Hook 'O4 template with regex-looking text' (Wf "await agent(``Use /grep/ and a/b ratio``, { model: 'sonnet' });") 'ask'
Invoke-Hook 'O5 model in template interpolation ignored' (Wf "const P='x'; await agent(``Prefix `${P} `${JSON.stringify({model:'fable'})}``, { model: 'haiku' });") 'ask'
Invoke-Hook 'O6 arrow in pipeline with regex in code' (Wf "const clean = s => s.replace(/``/g, '');`nconst r = await pipeline(ITEMS, it => agent(``Do `${clean(it)}``, { model: 'haiku' }), (p, it) => agent('verify', { model: 'sonnet' }));") 'ask'
Invoke-Hook 'O7 model then trailing comma' (Wf "await agent('p', { model: 'sonnet', });") 'ask'
Invoke-Hook 'E1 ellipsis before closing quote (live failure)' ('{"tool_name":"SendMessage","tool_input":{"to":"main","message":"long text","content":"Your findings were fixed\u2026"},"cwd":"E:\\ds-docs"}'.Replace('\u2026', [string][char]0x2026)) 'passthrough'
Invoke-Hook 'E2 Chinese text followed by quote in SendMessage' (Sm '审查者') 'ask'
Invoke-Hook 'E3 Chinese prompt in workflow script' (Wf "await agent('核对第十一节的检查清单', { model: 'sonnet' });") 'ask'
Invoke-Hook 'E4 emoji in workflow prompt' (Wf "await agent('Check 🚀 rollout', { model: 'haiku' });") 'ask'
Invoke-Hook 'N1 postfix ++ before slash hides fable call' (Wf "const pct = i++ / total; await agent('a', { model: 'fable' });`nawait agent('b', { model: 'sonnet' });") 'deny'
Invoke-Hook 'N1b postfix -- before slash count' (Wf "const r = x-- / n; await agent('a', { model: 'sonnet' });`nawait agent('b', { model: 'sonnet' });") 'ask'
Invoke-Hook 'N2 model template with trailing newline' (Wf "await agent('p', { model: ``sonnet`n`` });") 'deny'
Invoke-Hook 'N3 single object argument' (Wf "await agent({ model: 'sonnet' });") 'deny'
Invoke-Hook 'N3b prompt only' (Wf "await agent('p');") 'deny'
Invoke-Hook 'N4 20KB depth-1 option string performance' (Wf ("await agent('p', { model: 'sonnet', label: '" + ('x' * 20000) + "' });")) 'ask'
Invoke-Hook 'F1 property named agent' (Wf "const out = [];`nconst r = await agent('p', { model: 'sonnet' });`nout.push({ agent: 'p', result: r });") 'ask'
Invoke-Hook 'F2 reading field named agent' (Wf "const r = await agent('p', { model: 'sonnet' });`nconsole.log(r.agent);") 'ask'
Invoke-Hook 'F2b member invocation still denied' (Wf "await globalThis.agent('p', { model: 'sonnet' });") 'deny'
Invoke-Hook 'F2c member call via .call denied' (Wf "await x.agent.call(null, 'p', { model: 'sonnet' });") 'deny'
Invoke-Hook 'F3 regex after paren fails closed' (Wf "if (ok) /don't/.test(s); await agent('a', {model:'fable'}); await agent('b', {model:'sonnet'});") 'deny'
Invoke-Hook 'S1 ternary alias' (Wf "const f = ok ? agent : other; await f('p', { model: 'fable' });`nawait agent('b', { model: 'sonnet' });") 'deny'
Invoke-Hook 'S1b property key after comma still ask' (Wf "const r = await agent('p', { model: 'sonnet' });`nout.push({ id: 1, agent: 'p', result: r });") 'ask'
Invoke-Hook 'S2 computed member string key' (Wf "await globalThis['agent']('p', { model: 'fable' });`nawait agent('b', { model: 'sonnet' });") 'deny'
Invoke-Hook 'S2b computed member on other object' (Wf "const g = getG(); await g['agent']('p', { model: 'fable' });`nawait agent('b', { model: 'sonnet' });") 'deny'
Invoke-Hook 'S3 captured globalThis.agent' (Wf "const f = globalThis.agent;`nawait f('p', { model: 'fable' });`nawait agent('b', { model: 'sonnet' });") 'deny'
Invoke-Hook 'S3b destructuring from globalThis' (Wf "const { agent: f } = globalThis;`nawait f('p', { model: 'fable' });`nawait agent('b', { model: 'sonnet' });") 'deny'
Invoke-Hook 'S3c this.agent' (Wf "const f = this.agent; await f('p', { model: 'fable' }); await agent('b', { model: 'sonnet' });") 'deny'
Invoke-Hook 'S3d eval' (Wf "await eval('agent')('p', { model: 'fable' }); await agent('b', { model: 'sonnet' });") 'deny'
Invoke-Hook 'S3e new Function' (Wf "const f = new Function('return agent')(); await f('p', { model: 'fable' }); await agent('b', { model: 'sonnet' });") 'deny'
Invoke-Hook 'S3f dynamic import' (Wf "const m = await import('x'); await agent('b', { model: 'sonnet' });") 'deny'
Invoke-Hook 'S3g field read on result still ask' (Wf "const r = await agent('p', { model: 'sonnet' });`nconsole.log(r.agent, r.workflow);") 'ask'
Invoke-Hook 'S3h shorthand property denied' (Wf "const r = await agent('p', { model: 'sonnet' }); out.push({ agent });") 'deny'
Invoke-Hook 'O8 real research script' (@{ tool_name = 'Workflow'; tool_input = @{ scriptPath = 'C:\Users\DS\.claude\projects\E--ds-docs\f2fc05d6-e4ab-4142-a95b-4b645975a631\workflows\scripts\claude-code-deep-research-2-1-267-wf_902195b8-125.js' }; cwd = 'E:\ds-docs' } | ConvertTo-Json -Compress) 'ask'
