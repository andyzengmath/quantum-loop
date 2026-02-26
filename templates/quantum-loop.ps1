<#
.SYNOPSIS
    Quantum-Loop autonomous development loop for Windows (native PowerShell).

.DESCRIPTION
    Sequential execution of stories from quantum.json via Claude Code CLI.
    Each iteration spawns a fresh Claude Code instance with CLAUDE.md instructions.
    No bash, no WSL, no Git Bash required.

.PARAMETER MaxIterations
    Maximum iterations before stopping (default: 20)

.PARAMETER MaxRetries
    Max retry attempts per story (default: 3)

.PARAMETER SkipPermissions
    Add --dangerously-skip-permissions to Claude CLI calls

.PARAMETER Model
    Override the Claude model

.EXAMPLE
    .\quantum-loop.ps1 -MaxIterations 20 -SkipPermissions
    .\quantum-loop.ps1 -MaxIterations 50 -SkipPermissions -Model "claude-sonnet-4-5-20250514"
#>

param(
    [int]$MaxIterations = 20,
    [int]$MaxRetries = 3,
    [switch]$SkipPermissions,
    [string]$Model = ""
)

$ErrorActionPreference = "Stop"

# ─── Dependency Check ───
if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
    Write-Error "claude CLI not found. Install Claude Code first."
    exit 1
}

if (-not (Get-Command "jq" -ErrorAction SilentlyContinue)) {
    Write-Error "jq not found. Install it: https://jqlang.github.io/jq/download/"
    exit 1
}

if (-not (Test-Path "quantum.json")) {
    Write-Error "quantum.json not found. Run /quantum-loop:plan first."
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PromptFile = Join-Path $ScriptDir "CLAUDE.md"
if (-not (Test-Path $PromptFile)) {
    # Fallback: look in current directory
    if (Test-Path "CLAUDE.md") { $PromptFile = "CLAUDE.md" }
    else { Write-Error "CLAUDE.md not found."; exit 1 }
}

# ─── Update max retries ───
$jqExpr = ".stories |= map(.retries.maxAttempts = $MaxRetries)"
$tmp = jq $jqExpr quantum.json
$tmp | Set-Content -Path quantum.json -Encoding UTF8 -NoNewline

# ─── Header ───
$Branch = jq -r '.branchName' quantum.json
Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "  Quantum-Loop Autonomous Development" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "  Branch:      $Branch"
Write-Host "  Mode:        Sequential (PowerShell native)"
Write-Host "  Max Iter:    $MaxIterations"
Write-Host "  Max Retries: $MaxRetries"
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# ─── Summary Table ───
function Show-Summary {
    Write-Host ""
    Write-Host "Summary" -ForegroundColor Yellow

    $stories = jq -r '.stories[] | "\(.id)|\(.title)|\(.status)|\(.retries.attempts)/\(.retries.maxAttempts)"' quantum.json
    Write-Host ("{0,-10} {1,-40} {2,-8} {3,-8}" -f "Story", "Title", "Status", "Retries")
    Write-Host ("{0,-10} {1,-40} {2,-8} {3,-8}" -f "----------", "----------------------------------------", "--------", "--------")

    foreach ($line in $stories) {
        $parts = $line -split '\|'
        if ($parts.Count -ge 4) {
            $title = if ($parts[1].Length -gt 40) { $parts[1].Substring(0, 40) } else { $parts[1] }
            Write-Host ("{0,-10} {1,-40} {2,-8} {3,-8}" -f $parts[0], $title, $parts[2], $parts[3])
        }
    }

    $total = (jq '.stories | length' quantum.json)
    $passed = (jq '[.stories[] | select(.status == "passed")] | length' quantum.json)
    Write-Host ""
    Write-Host "Result: $passed/$total stories passed"
}

# ─── Main Loop ───
for ($iteration = 1; $iteration -le $MaxIterations; $iteration++) {
    Write-Host "`n=== Iteration $iteration / $MaxIterations ===" -ForegroundColor Green
    Write-Host ""

    # Select next executable story from DAG
    $storyId = jq -r '
        .stories as $all |
        [.stories[] |
          select(
            (.status == "pending" or (.status == "failed" and .retries.attempts < .retries.maxAttempts)) and
            (if (.dependsOn | length) == 0 then true
             else [.dependsOn[] | . as $dep | $all | map(select(.id == $dep)) | .[0].status] | all(. == "passed")
             end)
          )
        ] |
        sort_by(.priority) |
        .[0].id // empty
    ' quantum.json

    if ([string]::IsNullOrWhiteSpace($storyId) -or $storyId -eq "null") {
        $allPassed = jq '[.stories[].status] | all(. == "passed")' quantum.json
        if ($allPassed -eq "true") {
            Write-Host ""
            Write-Host "===========================================" -ForegroundColor Green
            Write-Host "  COMPLETE - All stories passed!" -ForegroundColor Green
            Write-Host "===========================================" -ForegroundColor Green
            Show-Summary
            exit 0
        } else {
            Write-Host ""
            Write-Host "===========================================" -ForegroundColor Red
            Write-Host "  BLOCKED - No executable stories remain." -ForegroundColor Red
            Write-Host "===========================================" -ForegroundColor Red
            Show-Summary
            exit 1
        }
    }

    $storyTitle = jq -r --arg id $storyId '.stories[] | select(.id == $id) | .title' quantum.json
    $storyAttempt = jq -r --arg id $storyId '.stories[] | select(.id == $id) | .retries.attempts' quantum.json

    Write-Host "Story:   $storyId - $storyTitle"
    Write-Host "Attempt: $([int]$storyAttempt + 1)"
    Write-Host ""

    # Mark story as in_progress
    $tmp = jq --arg id $storyId '
        .stories |= map(if .id == $id then .status = "in_progress" else . end) |
        .updatedAt = (now | todate)
    ' quantum.json
    $tmp | Set-Content -Path quantum.json -Encoding UTF8 -NoNewline

    # Build claude command
    $promptContent = Get-Content -Path $PromptFile -Raw
    $claudeArgs = @("--print")
    if ($SkipPermissions) { $claudeArgs = @("--dangerously-skip-permissions", "--print") }
    if ($Model) { $claudeArgs += @("--model", $Model) }
    $claudeArgs += @("-p", $promptContent, "--", "Implement story $storyId from quantum.json. This is iteration $iteration.")

    Write-Host "Spawning claude for story $storyId..."

    # Run claude and capture output
    $output = ""
    try {
        $output = & claude @claudeArgs 2>&1 | Out-String
    } catch {
        Write-Host "Claude process error: $_" -ForegroundColor Red
    }

    # Process output signals
    if ($output -match "<quantum>COMPLETE</quantum>") {
        Write-Host ""
        Write-Host "===========================================" -ForegroundColor Green
        Write-Host "  COMPLETE - All stories passed!" -ForegroundColor Green
        Write-Host "===========================================" -ForegroundColor Green
        Show-Summary
        exit 0
    }
    elseif ($output -match "<quantum>STORY_PASSED</quantum>") {
        Write-Host "Story $storyId PASSED. Continuing..." -ForegroundColor Green
    }
    elseif ($output -match "<quantum>STORY_FAILED</quantum>") {
        Write-Host "Story $storyId FAILED (attempt $([int]$storyAttempt + 1)). Will retry if attempts remain." -ForegroundColor Yellow
    }
    elseif ($output -match "<quantum>BLOCKED</quantum>") {
        Write-Host ""
        Write-Host "===========================================" -ForegroundColor Red
        Write-Host "  BLOCKED - Agent reports no executable stories." -ForegroundColor Red
        Write-Host "===========================================" -ForegroundColor Red
        Show-Summary
        exit 1
    }
    else {
        Write-Host "WARNING: No recognized signal. Story may not have completed cleanly." -ForegroundColor Yellow
        $lastLines = ($output -split "`n") | Select-Object -Last 10
        Write-Host "Last 10 lines:"
        $lastLines | ForEach-Object { Write-Host "  $_" }
    }

    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Yellow
Write-Host "  MAX_ITERATIONS reached ($MaxIterations)." -ForegroundColor Yellow
Write-Host "===========================================" -ForegroundColor Yellow
Show-Summary
exit 2
