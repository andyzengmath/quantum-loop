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
    [int]$StaleTimeout = 20,
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

# ─── Final Verification Sweep ───
function Final-VerificationSweep {
    Write-Host "`n[FINAL SWEEP] Running test suite before declaring COMPLETE..." -ForegroundColor Cyan
    $testCmd = $null
    if (Test-Path "package.json") { $testCmd = "npm test" }
    elseif (Test-Path "pyproject.toml") { $testCmd = "python -m pytest -x -q" }
    elseif (Test-Path "Cargo.toml") { $testCmd = "cargo test" }
    elseif (Test-Path "go.mod") { $testCmd = "go test ./..." }

    if ($testCmd) {
        try {
            Invoke-Expression $testCmd 2>&1 | Out-Null
            Write-Host "[FINAL SWEEP] Test suite passed." -ForegroundColor Green
        } catch {
            Write-Host "[FINAL SWEEP] FAILED: test suite. Cannot declare COMPLETE." -ForegroundColor Red
            Show-Summary
            exit 1
        }
    } else {
        Write-Host "[FINAL SWEEP] No test suite detected, skipping." -ForegroundColor Yellow
    }

    # Import smoke test (warning only)
    if (Test-Path "package.json") {
        $entry = jq -r '.main // empty' package.json 2>$null
        if ($entry) {
            try {
                node -e "require('./$entry')" 2>&1 | Out-Null
                Write-Host "[FINAL SWEEP] Import smoke test passed." -ForegroundColor Green
            } catch {
                Write-Host "[FINAL SWEEP] WARNING: Import smoke test failed (non-blocking)." -ForegroundColor Yellow
            }
        }
    }
}

# ─── Stale Story Detection ───
function Detect-StaleStories {
    $staleIds = jq -r --argjson threshold $StaleTimeout '
        .stories[] |
        select(.status == "in_progress" and .startedAt != null) |
        select(((now | floor) - (.startedAt | fromdateiso8601)) > ($threshold * 60)) |
        .id
    ' quantum.json 2>$null

    if ($staleIds) {
        foreach ($sid in $staleIds) {
            if ([string]::IsNullOrWhiteSpace($sid)) { continue }
            Write-Host "[STALE] $sid - resetting to failed (exceeded $StaleTimeout minute threshold)" -ForegroundColor Yellow
            $tmp = jq --arg id $sid --argjson threshold $StaleTimeout '
                .stories |= map(if .id == $id then
                    .status = (if .retries.attempts + 1 >= .retries.maxAttempts then "blocked" else "failed" end) |
                    .startedAt = null |
                    .retries.attempts += 1 |
                    .retries.failureLog += [{"phase": "stale_detection", "timestamp": (now | todate), "error": ("Story exceeded " + ($threshold | tostring) + " minute stale threshold")}]
                else . end)
            ' quantum.json
            $tmp | Set-Content -Path quantum.json -Encoding UTF8 -NoNewline
        }
    }
}

# ─── Main Loop ───
for ($iteration = 1; $iteration -le $MaxIterations; $iteration++) {
    Write-Host "`n=== Iteration $iteration / $MaxIterations ===" -ForegroundColor Green
    Write-Host ""

    # Detect stale stories before DAG query
    Detect-StaleStories

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
            Final-VerificationSweep
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

    # Mark story as in_progress and set startedAt
    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $tmp = jq --arg id $storyId --arg now $now '
        .stories |= map(if .id == $id then .status = "in_progress" | .startedAt = $now else . end) |
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
        Final-VerificationSweep
        Write-Host ""
        Write-Host "===========================================" -ForegroundColor Green
        Write-Host "  COMPLETE - All stories passed!" -ForegroundColor Green
        Write-Host "===========================================" -ForegroundColor Green
        Show-Summary
        exit 0
    }
    elseif ($output -match "<quantum>STORY_PASSED</quantum>") {
        Write-Host "Story $storyId PASSED. Continuing..." -ForegroundColor Green
        # Clear startedAt on completion
        $tmp = jq --arg id $storyId '.stories |= map(if .id == $id then .startedAt = null else . end)' quantum.json
        $tmp | Set-Content -Path quantum.json -Encoding UTF8 -NoNewline
    }
    elseif ($output -match "<quantum>STORY_FAILED</quantum>") {
        Write-Host "Story $storyId FAILED (attempt $([int]$storyAttempt + 1)). Will retry if attempts remain." -ForegroundColor Yellow
        # Clear startedAt on failure
        $tmp = jq --arg id $storyId '.stories |= map(if .id == $id then .startedAt = null else . end)' quantum.json
        $tmp | Set-Content -Path quantum.json -Encoding UTF8 -NoNewline
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

# ─── Generate Observations ───
function Generate-Observations {
    $branch = jq -r '.branchName' quantum.json
    $dateStr = (Get-Date -Format "yyyy-MM-dd")
    $safeBranch = $branch -replace '/', '-'
    $obsFile = "docs/post-mortems/$dateStr-$safeBranch-observations.md"

    if (-not (Test-Path "docs/post-mortems")) { New-Item -ItemType Directory -Path "docs/post-mortems" -Force | Out-Null }

    $total = jq '.stories | length' quantum.json
    $passed = jq '[.stories[] | select(.status == "passed")] | length' quantum.json
    $failed = jq '[.stories[] | select(.status == "failed")] | length' quantum.json
    $blocked = jq '[.stories[] | select(.status == "blocked")] | length' quantum.json

    $content = @"
# Execution Observations: $branch

**Date:** $dateStr
**Stories:** $passed passed, $failed failed, $blocked blocked (of $total total)
**Mode:** Sequential (PowerShell)

## Failure Summary

$(jq -r '.stories[] | select(.status == "failed" or .status == "blocked") | "- **\(.id)** \(.title) — \(.status) (\(.retries.attempts)/\(.retries.maxAttempts) retries)"' quantum.json 2>$null)

## Raw Data

<details>
<summary>Progress Log</summary>

``````json
$(jq '.progress' quantum.json)
``````

</details>
"@

    $content | Set-Content -Path $obsFile -Encoding UTF8
    git add $obsFile 2>$null
    git commit -m "docs: execution observations for $branch" 2>$null
    Write-Host "[OBSERVATIONS] Generated $obsFile" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Yellow
Write-Host "  MAX_ITERATIONS reached ($MaxIterations)." -ForegroundColor Yellow
Write-Host "===========================================" -ForegroundColor Yellow
Show-Summary
Generate-Observations
exit 2
