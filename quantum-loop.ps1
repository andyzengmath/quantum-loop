<#
.SYNOPSIS
    Quantum-Loop autonomous development loop for Windows (native PowerShell).

.DESCRIPTION
    Sequential execution of stories from quantum.json via Claude Code CLI.
    Each iteration spawns a fresh Claude Code instance with CLAUDE.md instructions.
    No bash, no WSL, no Git Bash required.

    PS1/SH PARITY DIVERGENCE (v0.7.0 / G17 / US-005):
    quantum-loop.sh ships a `--audit` flag that emits 7 maintenance metrics
    (branches-local, branches-remote, orphan-worktrees, readme-conflicts,
    cpc-files, test-suites, pre-impl-review-coverage). The PS1 shim does NOT
    implement `--audit` — the diagnostic is bash-only. Operators on Windows
    who want the audit output should run `bash quantum-loop.sh --audit` from
    Git Bash / WSL. This divergence is intentional and tracked as acceptable
    per the v0.7.0 PRD (US-005 / T-004 PS1 parity is optional).

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
    [string]$Model = "",
    [string]$Tool = "claude",
    [ValidateSet("auto","codex","gemini","claude","none")]
    [string]$Critic = "auto",
    [ValidateSet("auto","codex","gemini","claude")]
    [string]$Planner = "auto",
    [ValidateSet("auto","codex","gemini","claude")]
    [string]$Executor = "auto",
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

# P5.A2 / US-002 + P5.B1 / US-009 — Per-role provider availability check.
# auto -> existing tier-driven dispatch; none -> skip critic; explicit
# values resolve via Get-Command. Missing binary -> WARN + degrade
# (critic to 'none', planner/executor to 'claude').
if ($Critic -eq "codex" -or $Critic -eq "gemini") {
    if (-not (Get-Command $Critic -ErrorAction SilentlyContinue)) {
        Write-Warning "WARN: critic provider $Critic not available, falling back to none"
        $Critic = "none"
    }
}
if ($Planner -eq "codex" -or $Planner -eq "gemini") {
    if (-not (Get-Command $Planner -ErrorAction SilentlyContinue)) {
        Write-Warning "WARN: per-role routing: planner provider $Planner not available, falling back to claude"
        $Planner = "claude"
    }
}
if ($Executor -eq "codex" -or $Executor -eq "gemini") {
    if (-not (Get-Command $Executor -ErrorAction SilentlyContinue)) {
        Write-Warning "WARN: per-role routing: executor provider $Executor not available, falling back to claude"
        $Executor = "claude"
    }
}
$env:QL_CRITIC = $Critic
$env:QL_PLANNER = $Planner
$env:QL_EXECUTOR = $Executor

# ─── Dependency Check ───
if (-not (Get-Command "jq" -ErrorAction SilentlyContinue)) {
    Write-Error "jq not found. Install it: https://jqlang.github.io/jq/download/"
    exit 1
}

if (-not (Test-Path "quantum.json")) {
    Write-Error "quantum.json not found. Run /quantum-loop:plan first."
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunnersDir = Join-Path $ScriptDir "runners"

# ─── Load Runner Manifest ───
$ManifestPath = Join-Path $RunnersDir "$Tool.json"
if (-not (Test-Path $ManifestPath)) {
    $available = (Get-ChildItem -Path $RunnersDir -Filter "*.json" -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName }) -join ", "
    Write-Error "Unknown runner '$Tool'. Available: $available"
    exit 1
}

$Manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
$RunnerName = $Manifest.name
$RunnerBinary = $Manifest.binary
$RunnerTier = $Manifest.tier
$RunnerPromptDelivery = $Manifest.invocation.promptDelivery
$RunnerPromptFlag = $Manifest.invocation.promptFlag
$RunnerHeadlessFlags = $Manifest.invocation.headlessFlags
$RunnerAutoApproveFlags = $Manifest.invocation.autoApproveFlags
$RunnerStdinPipe = $Manifest.invocation.stdinPipe
$RunnerNative = $Manifest.instructionFile.native
$RunnerFallback = $Manifest.instructionFile.fallbackFrom
$RunnerAutoGenerate = $Manifest.instructionFile.autoGenerate
$RunnerPreambleInjection = $Manifest.signals.preambleInjection
$RunnerHeuristicFallback = $Manifest.signals.heuristicFallback

# Validate binary
if (-not (Get-Command $RunnerBinary -ErrorAction SilentlyContinue)) {
    Write-Error "$RunnerBinary not found. Install with: $($Manifest.installHint)"
    exit 1
}

# Experimental warning
if ($RunnerTier -eq "experimental" -and -not $NonInteractive) {
    Write-Host "`nWARNING: Runner '$RunnerName' is experimental (tier: $RunnerTier)." -ForegroundColor Yellow
    Write-Host "Experimental runners may not reliably emit quantum signals." -ForegroundColor Yellow
    Write-Host "Press Enter to continue or Ctrl-C to abort..."
    Read-Host
}

# Instruction file auto-generation
if ($RunnerFallback -and $RunnerNative -ne $RunnerFallback -and -not (Test-Path $RunnerNative)) {
    if (Test-Path $RunnerFallback) {
        $marker = "<!-- .ql-generated: Auto-generated from CLAUDE.md by quantum-loop. Do not edit manually. -->"
        $content = "$marker`n`n" + (Get-Content -Path $RunnerFallback -Raw)
        Set-Content -Path $RunnerNative -Value $content -Encoding UTF8
        Write-Host "[RUNNER] Generated $RunnerNative from $RunnerFallback"
    }
}

# Build preamble if needed
$PreamblePath = Join-Path $RunnersDir "preamble.md"
$PreambleContent = ""
if ($RunnerPreambleInjection -and (Test-Path $PreamblePath)) {
    $PreambleContent = Get-Content -Path $PreamblePath -Raw
}

# Prompt file (for Claude, read CLAUDE.md; for others, read the native instruction file)
$PromptFile = $RunnerNative
if (-not (Test-Path $PromptFile)) {
    $PromptFile = Join-Path $ScriptDir $RunnerNative
    if (-not (Test-Path $PromptFile)) {
        if (Test-Path "CLAUDE.md") { $PromptFile = "CLAUDE.md" }
        else { Write-Error "$RunnerNative not found."; exit 1 }
    }
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
Write-Host "  Runner:      $RunnerName ($RunnerBinary)"
Write-Host "  Tier:        $RunnerTier"
Write-Host "  Instruction: $RunnerNative"
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

    # Build prompt with optional preamble
    $agentPrompt = "Implement story $storyId from quantum.json. This is iteration $iteration."
    $finalPrompt = $agentPrompt
    if ($PreambleContent) {
        $finalPrompt = "$PreambleContent`n`n---`n`n$agentPrompt"
    }

    Write-Host "Spawning $RunnerName for story $storyId..."

    # Build and execute runner command based on delivery method
    $output = ""
    try {
        switch ($RunnerPromptDelivery) {
            "flag" {
                $runnerArgs = @()
                foreach ($f in $RunnerHeadlessFlags) { $runnerArgs += $f }
                foreach ($f in $RunnerAutoApproveFlags) { $runnerArgs += $f }
                if ($SkipPermissions -and $RunnerName -eq "claude") { $runnerArgs += "--dangerously-skip-permissions" }
                if ($Model -and $RunnerName -eq "claude") { $runnerArgs += @("--model", $Model) }
                $runnerArgs += @($RunnerPromptFlag, $finalPrompt)
                $output = & $RunnerBinary @runnerArgs 2>&1 | Out-String
            }
            "positional" {
                $runnerArgs = @()
                foreach ($f in $RunnerHeadlessFlags) { $runnerArgs += $f }
                foreach ($f in $RunnerAutoApproveFlags) { $runnerArgs += $f }
                $runnerArgs += $finalPrompt
                $output = & $RunnerBinary @runnerArgs 2>&1 | Out-String
            }
            "stdin" {
                $runnerArgs = @()
                foreach ($f in $RunnerHeadlessFlags) { $runnerArgs += $f }
                foreach ($f in $RunnerAutoApproveFlags) { $runnerArgs += $f }
                $output = $finalPrompt | & $RunnerBinary @runnerArgs 2>&1 | Out-String
            }
        }
    } catch {
        Write-Host "$RunnerName process error: $_" -ForegroundColor Red
    }

    # Process output signals (relaxed whitespace regex + heuristic fallback)
    $signalResult = $null
    $signalRegex = '<quantum>\s*(STORY_PASSED|STORY_FAILED|COMPLETE|BLOCKED)\s*</quantum>'
    $matches_found = [regex]::Matches($output, $signalRegex)
    if ($matches_found.Count -gt 0) {
        $signalResult = $matches_found[$matches_found.Count - 1].Groups[1].Value  # last wins
    } elseif ($RunnerHeuristicFallback) {
        # Heuristic fallback: check for commit and test patterns
        $hasCommit = (git log --oneline -1 2>$null) -match "feat:"
        $hasTestPass = $output -match "(0 failures|0 failed|all.*pass|tests? passed)"
        $hasErrors = $output -match "(error|FAIL:|failed|exception|panic)"
        if ($hasCommit -and $hasTestPass -and -not $hasErrors) { $signalResult = "STORY_PASSED" }
        elseif ($hasCommit -and $hasErrors) { $signalResult = "STORY_FAILED" }
        elseif ($hasCommit) { $signalResult = "STORY_PASSED" }
        else { $signalResult = "STORY_FAILED" }
    }

    switch ($signalResult) {
        "COMPLETE" {
            Final-VerificationSweep
            Write-Host ""
            Write-Host "===========================================" -ForegroundColor Green
            Write-Host "  COMPLETE - All stories passed!" -ForegroundColor Green
            Write-Host "===========================================" -ForegroundColor Green
            Show-Summary
            exit 0
        }
        "STORY_PASSED" {
            Write-Host "Story $storyId PASSED. Continuing..." -ForegroundColor Green
            $tmp = jq --arg id $storyId '.stories |= map(if .id == $id then .startedAt = null else . end)' quantum.json
            $tmp | Set-Content -Path quantum.json -Encoding UTF8 -NoNewline
        }
        "STORY_FAILED" {
            Write-Host "Story $storyId FAILED (attempt $([int]$storyAttempt + 1)). Will retry if attempts remain." -ForegroundColor Yellow
            $tmp = jq --arg id $storyId '.stories |= map(if .id == $id then .startedAt = null else . end)' quantum.json
            $tmp | Set-Content -Path quantum.json -Encoding UTF8 -NoNewline
        }
        "BLOCKED" {
            Write-Host ""
            Write-Host "===========================================" -ForegroundColor Red
            Write-Host "  BLOCKED - Agent reports no executable stories." -ForegroundColor Red
            Write-Host "===========================================" -ForegroundColor Red
            Show-Summary
            exit 1
        }
        default {
            Write-Host "WARNING: No recognized signal. Story may not have completed cleanly." -ForegroundColor Yellow
            $lastLines = ($output -split "`n") | Select-Object -Last 10
            Write-Host "Last 10 lines:"
            $lastLines | ForEach-Object { Write-Host "  $_" }
        }
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

## Progress Log

$(
  $rows = jq -r '
    [
      (.stories[] | select(.retries.failureLog // [] | length > 0)
        | .id as $sid
        | (.retries.failureLog // [])[]
        | [ $sid, (.phase // "unknown"), ((.error // "") | gsub("\\|"; "/") | .[0:80]), "", "", "" ]
        | @tsv),
      (.progress // [] | .[]
        | [ (.storyId // "(pipeline)"), (.action // "unknown"), ((.details // "") | gsub("\\|"; "/") | .[0:80]), "", "", (.learnings // "") ]
        | @tsv)
    ] | .[]
  ' quantum.json 2>$null
  if ($rows) {
    $header = "| Story | Phase / Action | Error / Detail | Root cause | Fix applied | Lesson |" + "`n" + "|-------|----------------|----------------|-----------|-------------|--------|"
    $body = ($rows -split "`n" | Where-Object { $_ -match '.' } | ForEach-Object {
      $f = $_ -split "`t"
      "| " + ($f[0..5] -join " | ") + " |"
    }) -join "`n"
    "$header`n$body"
  } else {
    "_No failed / retried stories. Progress log is empty._"
  }
)

## Raw Data

<details>
<summary>Progress JSON</summary>

``````json
$(jq '.progress' quantum.json)
``````

</details>
"@

    $content | Set-Content -Path $obsFile -Encoding UTF8
    git add $obsFile 2>$null
    git commit -m "docs: execution observations for $branch" 2>$null
    Write-Host "[OBSERVATIONS] Generated $obsFile" -ForegroundColor Cyan

    # Phase 6 / P1.7 — promote generalizable lessons into codebasePatterns
    # (parity with bash generate_observations)
    $newPatterns = jq '[.progress // [] | .[] | select(.learnings? and (.learnings | length > 0)) | .learnings]' quantum.json 2>$null
    if ($newPatterns -and $newPatterns -ne "[]") {
        $tmpFile = [System.IO.Path]::GetTempFileName()
        $updated = jq --argjson newlessons $newPatterns '.codebasePatterns = ((.codebasePatterns // []) + $newlessons | unique)' quantum.json 2>$null
        if ($updated) {
            $updated | Set-Content -Path $tmpFile -Encoding UTF8
            Move-Item -Force -Path $tmpFile -Destination quantum.json
            $count = jq 'length' <<< $newPatterns
            Write-Host "[OBSERVATIONS] Promoted $count lessons into codebasePatterns." -ForegroundColor Cyan
        } else {
            Remove-Item -Force -Path $tmpFile -ErrorAction SilentlyContinue
        }
    }

    # Check if observations contain issues worth reporting
    $hasBlocked = [int](jq '[.stories[] | select(.status == "blocked" or .status == "failed")] | length' quantum.json)
    if ($hasBlocked -gt 0) {
        # Skip if non-interactive (piped input)
        if ([Environment]::UserInteractive -eq $false) {
            Write-Host "[OBSERVATIONS] Skipping GitHub issue prompt (non-interactive)." -ForegroundColor Yellow
            return
        }
        $response = Read-Host "File observations as GitHub issue on quantum-loop? [y/N]"
        if ($response -match '^[Yy]$') {
            if (Get-Command "gh" -ErrorAction SilentlyContinue) {
                try {
                    $body = Get-Content $obsFile -Raw
                    gh issue create --repo andyzengmath/quantum-loop --title "Execution observations: $branch ($dateStr)" --body $body --label "execution-feedback" 2>$null
                    Write-Host "[OBSERVATIONS] GitHub issue filed." -ForegroundColor Green
                } catch {
                    Write-Host "[OBSERVATIONS] Failed to file GitHub issue. Local doc available." -ForegroundColor Yellow
                }
            } else {
                Write-Host "[OBSERVATIONS] gh CLI not found. Local doc available at $obsFile" -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Yellow
Write-Host "  MAX_ITERATIONS reached ($MaxIterations)." -ForegroundColor Yellow
Write-Host "===========================================" -ForegroundColor Yellow
Show-Summary
Generate-Observations
exit 2
