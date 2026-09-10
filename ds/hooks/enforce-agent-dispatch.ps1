$ErrorActionPreference = 'Stop'

$DefinedRoles = @('Explore', 'planner', 'implementer', 'qa', 'reviewer')
$FableRoles = @('reviewer-fable', 'critical-implementer', 'critical-reviewer')
$ModelAliasPattern = '\A(haiku|sonnet|opus)(\[1m\])?\z'
$RegexKeywords = @('return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void', 'throw', 'case', 'do', 'else', 'yield', 'await')

function Write-Decision {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('deny', 'ask')]
    [string]$Decision,
    [Parameter(Mandatory = $true)]
    [string]$Reason,
    [string]$Context
  )

  $output = @{
    hookEventName = 'PreToolUse'
    permissionDecision = $Decision
    permissionDecisionReason = $Reason
  }
  if (-not [string]::IsNullOrWhiteSpace($Context)) {
    # An ask reason is shown to the user only; additionalContext reaches Claude with the tool result.
    $output.additionalContext = $Context
  }
  @{ hookSpecificOutput = $output } | ConvertTo-Json -Compress -Depth 4
  exit 0
}

function Fail-Closed {
  param([Parameter(Mandatory = $true)][string]$Message)
  [Console]::Error.WriteLine($Message)
  exit 2
}

function Test-IdentifierChar {
  param([char]$Char)
  return ([char]::IsLetterOrDigit($Char) -or $Char -eq '_' -or $Char -eq '$')
}

# Marks every character of a JavaScript source as code ('c'), string/template/regex content ('s'),
# or comment ('m'), so later scans only see real code. Template `${...}` expressions count as code.
function Get-CodeMask {
  param([Parameter(Mandatory = $true)][string]$Source)

  $mask = New-Object char[] $Source.Length
  $state = 'code'
  $templateDepthStack = New-Object System.Collections.Generic.Stack[int]
  $braceDepth = 0
  $inRegexClass = $false
  $i = 0
  while ($i -lt $Source.Length) {
    $ch = $Source[$i]
    $next = if ($i + 1 -lt $Source.Length) { $Source[$i + 1] } else { [char]0 }
    if ($state -eq 'code') {
      if ($ch -eq '/' -and $next -eq '/') { $state = 'line'; $mask[$i] = 'm'; $mask[$i + 1] = 'm'; $i += 2; continue }
      if ($ch -eq '/' -and $next -eq '*') { $state = 'block'; $mask[$i] = 'm'; $mask[$i + 1] = 'm'; $i += 2; continue }
      if ($ch -eq '/') {
        # Regex literal or division: decide by the previous significant code character.
        $j = $i - 1
        while ($j -ge 0 -and ($mask[$j] -eq 'm' -or [char]::IsWhiteSpace($Source[$j]))) { $j-- }
        $isRegex = $false
        if ($j -lt 0) { $isRegex = $true }
        elseif ($mask[$j] -eq 's') { $isRegex = $false }
        else {
          $prev = $Source[$j]
          $prev2 = if ($j -ge 1) { $Source[$j - 1] } else { [char]0 }
          if (($prev -eq '+' -and $prev2 -eq '+') -or ($prev -eq '-' -and $prev2 -eq '-')) { $isRegex = $false }
          elseif ('(,=:[!&|?{};+-*%<>~^'.IndexOf($prev) -ge 0) { $isRegex = $true }
          elseif (Test-IdentifierChar $prev) {
            $k = $j
            while ($k -ge 0 -and $mask[$k] -eq 'c' -and (Test-IdentifierChar $Source[$k])) { $k-- }
            $word = $Source.Substring($k + 1, $j - $k)
            if ($word -in $RegexKeywords) { $isRegex = $true }
          }
        }
        if ($isRegex) { $state = 'regex'; $inRegexClass = $false; $mask[$i] = 's'; $i++; continue }
        $mask[$i] = 'c'; $i++; continue
      }
      if ($ch -eq "'") { $state = 'single'; $mask[$i] = 's'; $i++; continue }
      if ($ch -eq '"') { $state = 'double'; $mask[$i] = 's'; $i++; continue }
      if ($ch -eq '`') { $state = 'template'; $mask[$i] = 's'; $i++; continue }
      if ($templateDepthStack.Count -gt 0) {
        if ($ch -eq '{') { $braceDepth++ }
        elseif ($ch -eq '}') {
          if ($braceDepth -eq 0) { $templateDepthStack.Pop() | Out-Null; $state = 'template'; $mask[$i] = 's'; $i++; continue }
          $braceDepth--
        }
      }
      $mask[$i] = 'c'; $i++; continue
    }
    if ($state -eq 'single' -or $state -eq 'double') {
      $quote = if ($state -eq 'single') { "'" } else { '"' }
      $mask[$i] = 's'
      if ($ch -eq '\') { if ($i + 1 -lt $Source.Length) { $mask[$i + 1] = 's' }; $i += 2; continue }
      if ($ch -eq $quote -or $ch -eq "`n") { $state = 'code' }
      $i++; continue
    }
    if ($state -eq 'template') {
      $mask[$i] = 's'
      if ($ch -eq '\') { if ($i + 1 -lt $Source.Length) { $mask[$i + 1] = 's' }; $i += 2; continue }
      if ($ch -eq '$' -and $next -eq '{') { $mask[$i + 1] = 's'; $templateDepthStack.Push(1); $braceDepth = 0; $state = 'code'; $i += 2; continue }
      if ($ch -eq '`') { $state = 'code' }
      $i++; continue
    }
    if ($state -eq 'regex') {
      $mask[$i] = 's'
      if ($ch -eq '\') { if ($i + 1 -lt $Source.Length) { $mask[$i + 1] = 's' }; $i += 2; continue }
      if ($ch -eq "`n") { $state = 'code'; $i++; continue }
      if ($inRegexClass) { if ($ch -eq ']') { $inRegexClass = $false }; $i++; continue }
      if ($ch -eq '[') { $inRegexClass = $true; $i++; continue }
      if ($ch -eq '/') { $state = 'code' }
      $i++; continue
    }
    if ($state -eq 'line') {
      $mask[$i] = 'm'
      if ($ch -eq "`n") { $state = 'code' }
      $i++; continue
    }
    # block comment
    $mask[$i] = 'm'
    if ($ch -eq '*' -and $next -eq '/') { $mask[$i + 1] = 'm'; $state = 'code'; $i += 2; continue }
    $i++; continue
  }
  if ($state -ne 'code' -and $state -ne 'line') {
    return $null
  }
  return $mask
}

# Reads a quoted literal that starts at $Index in the original source and returns @{ Value; End }
# (End is the index just past the closing quote), or $null when the value is not a plain literal.
function Read-LiteralValue {
  param([string]$Source, [int]$Index)
  while ($Index -lt $Source.Length -and [char]::IsWhiteSpace($Source[$Index])) { $Index++ }
  if ($Index -ge $Source.Length) { return $null }
  $quote = $Source[$Index]
  if ($quote -ne "'" -and $quote -ne '"' -and $quote -ne '`') { return $null }
  $end = $Source.IndexOf($quote, $Index + 1)
  if ($end -lt 0) { return $null }
  $value = $Source.Substring($Index + 1, $end - $Index - 1)
  if ($value.IndexOf('\') -ge 0 -or $value.IndexOf('$') -ge 0) { return $null }
  return @{ Value = $value; End = $end + 1 }
}

# Returns the literal value of a direct property of the options object, or denies.
function Get-OptionLiteral {
  param([string]$Script, [string]$KeyView, [string]$CodeView, [int]$Offset, [string]$Key, [int]$CallNumber)
  $keyMatches = [regex]::Matches($KeyView, "(?<![A-Za-z0-9_`$])(?:'$Key'|`"$Key`"|$Key)\s*:")
  if ($keyMatches.Count -eq 0) { return $null }
  if ($keyMatches.Count -gt 1) {
    Write-Decision -Decision 'deny' -Reason "Workflow agent call #$CallNumber sets $Key more than once; JavaScript keeps the last value, so the call cannot be verified."
  }
  $m = $keyMatches[0]
  $literal = Read-LiteralValue -Source $Script -Index ($Offset + $m.Index + $m.Length)
  if ($null -eq $literal) {
    Write-Decision -Decision 'deny' -Reason "Workflow agent call #$CallNumber sets $Key to something other than a plain quoted literal. Use a literal alias such as 'sonnet'."
  }
  $k = $literal.End - $Offset
  while ($k -lt $CodeView.Length -and [char]::IsWhiteSpace($CodeView[$k])) { $k++ }
  if ($k -lt $CodeView.Length -and $CodeView[$k] -ne ',' -and $CodeView[$k] -ne '}') {
    Write-Decision -Decision 'deny' -Reason "Workflow agent call #$CallNumber combines the $Key literal with an expression. Use a plain literal."
  }
  return $literal.Value
}

function Find-WorkflowScriptByName {
  param([string]$Name, [string]$StartDirectory)

  if ($Name -notmatch '\A[A-Za-z0-9_.-]+\z' -or $Name -match '\.\.') { return $null }
  $candidates = New-Object System.Collections.Generic.List[string]
  $dir = $StartDirectory
  while (-not [string]::IsNullOrWhiteSpace($dir)) {
    $candidates.Add((Join-Path $dir ".claude\workflows\$Name.js"))
    $parent = Split-Path -Path $dir -Parent
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $dir) { break }
    $dir = $parent
  }
  $candidates.Add((Join-Path $env:USERPROFILE ".claude\workflows\$Name.js"))
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  return $null
}

function Test-WorkflowScript {
  param([Parameter(Mandatory = $true)][string]$Script)

  $mask = Get-CodeMask -Source $Script
  if ($null -eq $mask) {
    Write-Decision -Decision 'deny' -Reason 'Workflow script could not be lexed to the end: an unterminated string, template literal, regex literal, or block comment, or a regex literal written directly after a closing parenthesis, which the policy cannot tell from division. Rewrite the script with plain literals.'
  }
  $codeChars = New-Object char[] $Script.Length
  $noCommentChars = New-Object char[] $Script.Length
  for ($i = 0; $i -lt $Script.Length; $i++) {
    $codeChars[$i] = if ($mask[$i] -eq 'c') { $Script[$i] } else { ' ' }
    $noCommentChars[$i] = if ($mask[$i] -eq 'm') { ' ' } else { $Script[$i] }
  }
  $code = -join $codeChars
  $noComment = -join $noCommentChars

  if ([regex]::IsMatch($code, '\\u[0-9A-Fa-f]{4}|\\u\{|\\x[0-9A-Fa-f]{2}')) {
    Write-Decision -Decision 'deny' -Reason 'Workflow script uses escape sequences outside string literals, which can hide an identifier from inspection.'
  }
  # A bare agent/workflow identifier must be a direct call. The only exemption is an object-literal
  # property key (`{ agent: ... }` or `, agent: ...`); a ternary such as `ok ? agent : other` is not one.
  foreach ($ref in [regex]::Matches($code, '(?<![A-Za-z0-9_$.])(agent|workflow)(?![A-Za-z0-9_$])(?!\s*\()')) {
    $isKey = [regex]::IsMatch($code.Substring(0, $ref.Index), '[{,]\s*\z') -and [regex]::IsMatch($code.Substring($ref.Index + $ref.Length), '\A\s*:')
    if (-not $isKey) {
      Write-Decision -Decision 'deny' -Reason 'Workflow script references agent or workflow without calling it directly (alias, ternary, .call, .apply, or optional call). Write every dispatch as a direct agent(prompt, { model }) call.'
    }
  }
  # Reading a field named agent off a result is fine; invoking through a member, reaching the global
  # object, computed access with a string key, or dynamic code can all alias the real function.
  if ([regex]::IsMatch($code, '\.\s*(agent|workflow)\s*(\(|\?\.|\.\s*(call|apply|bind)\b)')) {
    Write-Decision -Decision 'deny' -Reason 'Workflow script invokes agent or workflow through a member (for example globalThis.agent). Write every dispatch as a direct agent(prompt, { model }) call.'
  }
  if ([regex]::IsMatch($code, '(?<![A-Za-z0-9_$.])(globalThis|window|self|global)(?![A-Za-z0-9_$])|(?<![A-Za-z0-9_$.])this\s*\.\s*(agent|workflow)(?![A-Za-z0-9_$])')) {
    Write-Decision -Decision 'deny' -Reason 'Workflow script accesses the global object (globalThis, window, self, global, or this.agent), which can alias agent or workflow. Call agent(prompt, { model }) directly.'
  }
  if ([regex]::IsMatch($noComment, '\[\s*([''"`])(agent|workflow)\1\s*\]')) {
    Write-Decision -Decision 'deny' -Reason 'Workflow script accesses agent or workflow through a computed member with a string key. Call agent(prompt, { model }) directly.'
  }
  if ([regex]::IsMatch($code, '(?<![A-Za-z0-9_$.])(eval|Function)\s*\(|(?<![A-Za-z0-9_$.])new\s+Function(?![A-Za-z0-9_$])|(?<![A-Za-z0-9_$.])import\s*\(')) {
    Write-Decision -Decision 'deny' -Reason 'Workflow script uses dynamic code (eval, Function, or import()), which the dispatch policy cannot inspect.'
  }
  if ([regex]::IsMatch($code, '(?<![A-Za-z0-9_$.])workflow\s*\(')) {
    Write-Decision -Decision 'deny' -Reason 'Workflow scripts may not call workflow() for a nested workflow: the child script cannot be inspected for per-agent models. Inline the child stages instead.'
  }

  $callNumber = 0
  foreach ($match in [regex]::Matches($code, '(?<![A-Za-z0-9_$.])agent\s*\(')) {
    $open = $match.Index + $match.Length - 1
    $depth = 0
    $close = -1
    for ($j = $open; $j -lt $code.Length; $j++) {
      $c = $code[$j]
      if ($c -eq '(' -or $c -eq '[' -or $c -eq '{') { $depth++ }
      elseif ($c -eq ')' -or $c -eq ']' -or $c -eq '}') { $depth--; if ($depth -eq 0) { $close = $j; break } }
    }
    if ($close -lt 0) {
      Write-Decision -Decision 'deny' -Reason 'Workflow script has an agent call whose parentheses do not balance, so its model cannot be verified.'
    }
    if ([string]::IsNullOrWhiteSpace($noComment.Substring($open + 1, $close - $open - 1))) { continue }
    $callNumber++

    # Split the arguments at depth-zero commas; the API is agent(prompt, options).
    $argsCode = $code.Substring($open + 1, $close - $open - 1)
    $argStarts = New-Object System.Collections.Generic.List[int]
    $argEnds = New-Object System.Collections.Generic.List[int]
    $depth = 0
    $argStart = 0
    for ($j = 0; $j -lt $argsCode.Length; $j++) {
      $c = $argsCode[$j]
      if ($c -eq '(' -or $c -eq '[' -or $c -eq '{') { $depth++ }
      elseif ($c -eq ')' -or $c -eq ']' -or $c -eq '}') { $depth-- }
      elseif ($c -eq ',' -and $depth -eq 0) { $argStarts.Add($argStart); $argEnds.Add($j); $argStart = $j + 1 }
    }
    if (-not [string]::IsNullOrWhiteSpace($noComment.Substring($open + 1 + $argStart, $argsCode.Length - $argStart))) {
      $argStarts.Add($argStart); $argEnds.Add($argsCode.Length)
    }
    if ($argStarts.Count -gt 2) {
      Write-Decision -Decision 'deny' -Reason "Workflow agent call #$callNumber passes more than two arguments; the API is agent(prompt, options)."
    }
    if ($argStarts.Count -lt 2) {
      # agent(prompt) alone, or a lone object literal, passes no options and inherits the main-session model.
      Write-Decision -Decision 'deny' -Reason "Workflow agent call #$callNumber passes no options argument; the API is agent(prompt, options) and every call must set options.model to haiku, sonnet, or opus. A missing model inherits the main-session model."
    }
    $optsIndex = 1
    $segment = $argsCode.Substring($argStarts[$optsIndex], $argEnds[$optsIndex] - $argStarts[$optsIndex])
    $optsStart = -1
    for ($j = 0; $j -lt $segment.Length; $j++) { if (-not [char]::IsWhiteSpace($segment[$j])) { $optsStart = $j; break } }
    $optsEnd = -1
    for ($j = $segment.Length - 1; $j -ge 0; $j--) { if (-not [char]::IsWhiteSpace($segment[$j])) { $optsEnd = $j; break } }
    if ($optsStart -lt 0 -or $segment[$optsStart] -ne '{' -or $segment[$optsEnd] -ne '}') {
      Write-Decision -Decision 'deny' -Reason "Workflow agent call #$callNumber does not pass its options as an object literal, so its model cannot be verified."
    }
    $optsOffset = $open + 1 + $argStarts[$optsIndex] + $optsStart
    $optsLength = $optsEnd - $optsStart + 1

    # Views of the options object limited to its direct (depth-1) content: one keeps only code,
    # the other also keeps quoted property keys so 'model': and "model": are recognised.
    $codeView = New-Object char[] $optsLength
    $keyView = New-Object char[] $optsLength
    for ($j = 0; $j -lt $optsLength; $j++) { $codeView[$j] = ' '; $keyView[$j] = ' ' }
    $depth = 0
    $j = 0
    while ($j -lt $optsLength) {
      $abs = $optsOffset + $j
      $c = $Script[$abs]
      $isCode = $mask[$abs] -eq 'c'
      if ($isCode -and ($c -eq '(' -or $c -eq '[' -or $c -eq '{')) { $depth++; $j++; continue }
      if ($isCode -and ($c -eq ')' -or $c -eq ']' -or $c -eq '}')) { $depth--; $j++; continue }
      if ($depth -eq 1 -and $isCode) { $codeView[$j] = $c; $keyView[$j] = $c; $j++; continue }
      if ($depth -eq 1 -and $mask[$abs] -eq 's') {
        # Scan the whole string run once; keep it in the key view only when it is a property key.
        $k = $abs
        while ($k -lt $Script.Length -and $mask[$k] -eq 's') { $k++ }
        $runEnd = $k
        while ($k -lt $Script.Length -and [char]::IsWhiteSpace($Script[$k])) { $k++ }
        $isKey = ($k -lt $Script.Length -and $Script[$k] -eq ':' -and $mask[$k] -eq 'c')
        if ($isKey) {
          for ($r = $abs; $r -lt $runEnd -and ($r - $optsOffset) -lt $optsLength; $r++) { $keyView[$r - $optsOffset] = $Script[$r] }
        }
        $j = [Math]::Min($runEnd - $optsOffset, $optsLength)
        continue
      }
      $j++
    }
    $codeViewText = -join $codeView
    $keyViewText = -join $keyView
    if ($codeViewText.Contains('...')) {
      Write-Decision -Decision 'deny' -Reason "Workflow agent call #$callNumber spreads another object into its options, which can override model. Write the options inline."
    }

    $model = Get-OptionLiteral -Script $Script -KeyView $keyViewText -CodeView $codeViewText -Offset $optsOffset -Key 'model' -CallNumber $callNumber
    $agentType = Get-OptionLiteral -Script $Script -KeyView $keyViewText -CodeView $codeViewText -Offset $optsOffset -Key 'agentType' -CallNumber $callNumber

    if (($null -ne $model -and $model -match 'fable') -or ($null -ne $agentType -and $agentType -in $FableRoles)) {
      Write-Decision -Decision 'deny' -Reason "Workflow agent call #$callNumber uses Fable. Workflow scripts may not use fable or a Fable role; run a Fable critical role serially through the Agent tool after the workflow has consolidated evidence."
    }
    if ($null -ne $model -and $model -match $ModelAliasPattern) { continue }
    if ($null -ne $agentType -and $agentType -in $DefinedRoles) { continue }
    $modelText = if ($null -ne $model) { "'$model'" } else { 'nothing' }
    Write-Decision -Decision 'deny' -Reason "Workflow agent call #$callNumber names $modelText as model and no defined agentType (Explore, planner, implementer, qa, reviewer). Every agent call must set model to haiku, sonnet, or opus. A missing model inherits the main-session model."
  }
  if ($callNumber -eq 0) {
    Write-Decision -Decision 'deny' -Reason 'Workflow script contains no agent call the dispatch policy could parse. A workflow without direct agent(prompt, { model }) calls has nothing verifiable to run.'
  }
  return $callNumber
}

function Resolve-AgentMeta {
  param([string]$AgentId, [string]$TranscriptPath, [string]$SessionId)
  if ([string]::IsNullOrWhiteSpace($TranscriptPath) -or $SessionId -notmatch '\A[0-9A-Za-z-]+\z') { return $null }
  $sessionDir = Join-Path (Split-Path -Path $TranscriptPath -Parent) $SessionId
  if (-not (Test-Path -LiteralPath $sessionDir -PathType Container)) { return $null }
  $meta = Get-ChildItem -LiteralPath $sessionDir -Recurse -Filter "agent-$AgentId.meta.json" -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $meta) { return $null }
  return (Get-Content -LiteralPath $meta.FullName -Raw | ConvertFrom-Json)
}

# Claude Code writes the hook input as UTF-8. Windows PowerShell decodes [Console]::In with the console
# code page (GBK on this machine), where a multibyte sequence can swallow the following quote and
# corrupt the JSON, so read the raw bytes as UTF-8 explicitly and emit UTF-8 as well.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.UTF8Encoding]::new($false))
$raw = $reader.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) {
  Fail-Closed 'Agent dispatch policy received empty hook input.'
}

try {
  $call = $raw | ConvertFrom-Json
} catch {
  $dump = Join-Path $env:TEMP 'claude-dispatch-hook-parse-error.txt'
  try { [System.IO.File]::WriteAllText($dump, $raw) } catch { $dump = '(dump failed)' }
  Fail-Closed "Agent dispatch policy could not parse the hook input ($($_.Exception.Message)). Raw input saved to $dump."
}

if ($null -eq $call -or [string]::IsNullOrWhiteSpace([string]$call.tool_name)) {
  Fail-Closed 'Agent dispatch policy received hook input without tool_name.'
}

$workingDirectory = [string]$call.cwd
if ([string]::IsNullOrWhiteSpace($workingDirectory)) { $workingDirectory = (Get-Location).Path }

if ($call.tool_name -eq 'Workflow') {
  $script = $null
  if ($call.tool_input.script -is [string]) { $script = [string]$call.tool_input.script }
  if ([string]::IsNullOrWhiteSpace($script)) {
    $path = [string]$call.tool_input.scriptPath
    $name = [string]$call.tool_input.name
    try {
      if ([string]::IsNullOrWhiteSpace($path) -and -not [string]::IsNullOrWhiteSpace($name)) {
        $path = Find-WorkflowScriptByName -Name $name -StartDirectory $workingDirectory
        if ([string]::IsNullOrWhiteSpace($path)) {
          Write-Decision -Decision 'deny' -Reason "Saved workflow '$name' was not found under any .claude\workflows directory from the working directory up or under ~\.claude\workflows, so it is a bundled or plugin workflow whose agent models cannot be inspected. Pass an inline script with explicit models instead."
        }
      }
      if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
        $script = Get-Content -LiteralPath $path -Raw
      }
    } catch {
      Fail-Closed "Agent dispatch policy could not read the workflow script: $($_.Exception.Message)"
    }
  }
  if ([string]::IsNullOrWhiteSpace($script)) {
    Write-Decision -Decision 'deny' -Reason 'Workflow script could not be read by the dispatch policy hook, so its agent models cannot be verified. Pass the script inline or a readable scriptPath.'
  }
  $calls = Test-WorkflowScript -Script $script
  Write-Decision -Decision 'ask' -Reason "Workflow with $calls agent call(s); every call names an approved model. Confirm the task level, total starts, peak concurrency, and rerun policy." -Context "Dispatch policy: this workflow declares $calls agent call(s), each with an explicit model. Before relying on its results, record the task level, cumulative starts, peak concurrency, and rerun policy in the ledger; a relaunch or resume counts every rerun agent as a new start."
}

if ($call.tool_name -eq 'SendMessage') {
  $target = [string]$call.tool_input.to
  if ($target -eq 'main') {
    exit 0
  }
  if ($target -match 'critical-|fable') {
    Write-Decision -Decision 'deny' -Reason "SendMessage to '$target' would resume a Fable role. Fable workers are never resumed; start a new explicitly approved task instead."
  }
  if ($target -match '^[0-9a-f]{12,}$') {
    try {
      $meta = Resolve-AgentMeta -AgentId $target -TranscriptPath ([string]$call.transcript_path) -SessionId ([string]$call.session_id)
    } catch {
      Fail-Closed "Agent dispatch policy could not read agent metadata: $($_.Exception.Message)"
    }
    if ($null -eq $meta) {
      Write-Decision -Decision 'deny' -Reason "SendMessage to agent ID '$target' cannot be resolved to a model from this session's agent metadata, so it may resume a Fable worker. Address the agent by its role name instead."
    }
    $metaModel = [string]$meta.model
    $metaType = [string]$meta.agentType
    if ($metaModel -match 'fable' -or $metaType -in $FableRoles -or $metaType -match 'critical-|fable') {
      Write-Decision -Decision 'deny' -Reason "SendMessage to agent ID '$target' would resume a Fable worker ($metaType, model $metaModel). Fable workers are never resumed."
    }
    Write-Decision -Decision 'ask' -Reason "SendMessage resumes agent '$target' ($metaType, model $metaModel) and counts as a new worker start." -Context "Dispatch policy: resuming agent '$target' ($metaType on $metaModel) is a new worker start. Count it in the task ledger and stop if the level's total is reached."
  }
  Write-Decision -Decision 'ask' -Reason "SendMessage to '$target' resumes that agent and counts as a new worker start." -Context "Dispatch policy: resuming '$target' is a new worker start. Count it in the task ledger and stop if the level's total is reached."
}

if ($call.tool_name -ne 'Agent') {
  exit 0
}

$agentType = [string]$call.tool_input.subagent_type
$model = [string]$call.tool_input.model
$modelBase = $model -replace '\[1m\]$', ''

if ([string]::IsNullOrWhiteSpace($agentType)) {
  Write-Decision -Decision 'deny' -Reason 'Every Agent dispatch must specify subagent_type.'
}

if ($agentType -eq 'fork') {
  Write-Decision -Decision 'deny' -Reason 'A fork ignores the model parameter and runs on the main-session model. Dispatch an explicit worker role with a model alias instead; if the full conversation context is truly required, the user must run the fork after removing this rule for the session.'
}

if ([string]::IsNullOrWhiteSpace($model)) {
  Write-Decision -Decision 'deny' -Reason "Agent '$agentType' must specify an explicit model. Model inheritance is prohibited."
}

$policies = @{
  'Explore' = @{ model = @('haiku', 'sonnet') }
  'planner' = @{ model = @('sonnet', 'opus') }
  'implementer' = @{ model = @('opus', 'sonnet') }
  'qa' = @{ model = @('sonnet', 'opus') }
  'reviewer' = @{ model = @('sonnet', 'opus') }
  'reviewer-fable' = @{ model = @('fable') }
  'critical-implementer' = @{ model = @('fable') }
  'critical-reviewer' = @{ model = @('fable') }
}

if ($policies.ContainsKey($agentType)) {
  $policy = $policies[$agentType]
  if ($modelBase -notin @($policy.model)) {
    Write-Decision -Decision 'deny' -Reason "Agent '$agentType' must use model '$($policy.model -join ' or ')', not '$model'."
  }
  exit 0
}

if ($modelBase -eq 'fable') {
  Write-Decision -Decision 'deny' -Reason "Fable is restricted to reviewer-fable, critical-implementer, and critical-reviewer; agent type '$agentType' is not approved."
}

if ($modelBase -notin @('haiku', 'sonnet', 'opus')) {
  Write-Decision -Decision 'deny' -Reason "Unknown agent type '$agentType' must use an explicit haiku, sonnet, or opus model alias."
}

if ($agentType -like 'codex:*') {
  exit 0
}

Write-Decision -Decision 'ask' -Reason "Agent type '$agentType' has no role definition and inherits the main-session effort level." -Context "Dispatch policy: agent type '$agentType' has no role definition, so it inherits the main-session effort level. Prefer a defined role (Explore, planner, implementer, qa, reviewer, reviewer-fable) that pins its own effort, and count this dispatch as a worker start."
