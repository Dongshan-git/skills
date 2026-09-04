$ErrorActionPreference = 'Stop'

function Write-Decision {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('deny', 'ask')]
    [string]$Decision,
    [Parameter(Mandatory = $true)]
    [string]$Reason
  )

  @{
    hookSpecificOutput = @{
      hookEventName = 'PreToolUse'
      permissionDecision = $Decision
      permissionDecisionReason = $Reason
    }
  } | ConvertTo-Json -Compress
  exit 0
}

function Fail-Closed {
  param([Parameter(Mandatory = $true)][string]$Message)
  [Console]::Error.WriteLine($Message)
  exit 2
}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) {
  Fail-Closed 'Agent dispatch policy received empty hook input.'
}

try {
  $call = $raw | ConvertFrom-Json
} catch {
  Fail-Closed 'Agent dispatch policy could not parse the hook input.'
}

if ($null -eq $call -or [string]::IsNullOrWhiteSpace([string]$call.tool_name)) {
  Fail-Closed 'Agent dispatch policy received hook input without tool_name.'
}

if ($call.tool_name -eq 'Workflow') {
  $script = [string]$call.tool_input.script
  if ([string]::IsNullOrWhiteSpace($script)) {
    $path = [string]$call.tool_input.scriptPath
    if ([string]::IsNullOrWhiteSpace($path) -and -not [string]::IsNullOrWhiteSpace([string]$call.tool_input.name)) {
      $name = [string]$call.tool_input.name
      foreach ($candidate in @((Join-Path (Get-Location) ".claude\workflows\$name.js"), (Join-Path $env:USERPROFILE ".claude\workflows\$name.js"))) {
        if (Test-Path -LiteralPath $candidate) { $path = $candidate; break }
      }
    }
    if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
      $script = Get-Content -LiteralPath $path -Raw
    }
  }
  if ([string]::IsNullOrWhiteSpace($script)) {
    Write-Decision -Decision 'deny' -Reason 'Workflow script could not be read by the dispatch policy hook, so its agent models cannot be verified. Pass the script inline or a readable scriptPath.'
  }
  $segments = $script -split 'agent\s*\('
  for ($i = 1; $i -lt $segments.Count; $i++) {
    $seg = $segments[$i]
    $hasModel = $seg -match "model\s*:\s*['`"]?(haiku|sonnet|opus)['`"]?"
    $hasRole = $seg -match "agentType\s*:\s*['`"](Explore|planner|implementer|qa|reviewer)['`"]"
    if (-not ($hasModel -or $hasRole)) {
      Write-Decision -Decision 'deny' -Reason "Workflow agent() call #$i names neither model (haiku, sonnet, opus) nor a defined agentType (Explore, planner, implementer, qa, reviewer). A missing model inherits the main-session model."
    }
  }
  if ($script -match "model\s*:\s*['`"]?fable") {
    Write-Decision -Decision 'deny' -Reason 'Workflow scripts may not use fable. Run a Fable critical role serially through the Agent tool after the workflow has consolidated evidence.'
  }
  Write-Decision -Decision 'ask' -Reason 'Workflow execution can fan out. Every agent() names its model. Confirm the declared task level, total starts, peak concurrency, and rerun policy before launch.'
}

if ($call.tool_name -eq 'SendMessage') {
  $target = [string]$call.tool_input.to
  if ($target -eq 'main') {
    exit 0
  }
  if ($target -match 'critical-|fable') {
    Write-Decision -Decision 'deny' -Reason "SendMessage to '$target' would resume a Fable critical role. Fable workers are never resumed; start a new explicitly approved task instead."
  }
  Write-Decision -Decision 'ask' -Reason "SendMessage to '$target' resumes that agent and counts as a new worker start. Confirm the task budget still allows it."
}

if ($call.tool_name -ne 'Agent') {
  exit 0
}

$agentType = [string]$call.tool_input.subagent_type
$model = [string]$call.tool_input.model

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
  if ($model -notin @($policy.model)) {
    Write-Decision -Decision 'deny' -Reason "Agent '$agentType' must use model '$($policy.model -join ' or ')', not '$model'."
  }
  exit 0
}

if ($model -eq 'fable') {
  Write-Decision -Decision 'deny' -Reason "Fable is restricted to reviewer-fable, critical-implementer, and critical-reviewer; agent type '$agentType' is not approved."
}

if ($model -notin @('haiku', 'sonnet', 'opus')) {
  Write-Decision -Decision 'deny' -Reason "Unknown agent type '$agentType' must use an explicit haiku, sonnet, or opus model alias."
}

if ($agentType -like 'codex:*') {
  exit 0
}

Write-Decision -Decision 'ask' -Reason "Agent type '$agentType' has no role definition, so it inherits the main-session effort level. Confirm, or use a defined role (Explore, planner, implementer, qa, reviewer, reviewer-fable) that pins its own effort."

