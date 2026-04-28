#!/usr/bin/env bash
# G22 / US-001 (v0.7.0) — severity-rubric calibration parse-script.
#
# Reads metrics/pre-impl-review-findings.csv and emits a per-stage histogram
# of severity counts across all populated cycles. Cited by §Methodology of
# references/severity-rubric-calibration-v0.7.0.md.
#
# Output format (3 sections, each markdown table):
#   ## design / prd / plan
#   | Cycle (timestamp date) | total | critical | high | medium | low |
#
# CSV columns: timestamp,stage,source_path,count,critical,high,medium,low

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
CSV="$REPO_ROOT/metrics/pre-impl-review-findings.csv"

if [[ ! -f "$CSV" ]]; then
  echo "ERROR: $CSV not found" >&2
  exit 1
fi

emit_stage_table() {
  local stage="$1"
  printf '## %s\n\n' "$stage"
  printf '| Date | total | critical | high | medium | low |\n'
  printf '|------|------:|---------:|-----:|-------:|----:|\n'
  awk -F',' -v stage="$stage" '
    NR == 1 { next }    # header
    $2 == stage {
      # timestamp like 2026-04-27T18:35:56Z; take date portion
      split($1, ts, "T")
      printf "| %s | %s | %s | %s | %s | %s |\n", ts[1], $4, $5, $6, $7, $8
    }
  ' "$CSV"
  printf '\n'

  # Aggregate totals row.
  # N21 / US-004 (v0.7.1) — track row count and suppress the **Aggregate**
  # line when no rows matched the stage. Soliton-pr-review caught at
  # confidence 75 on PR #71 (v0.7.0 sub-threshold; v0.7.1 carry-over).
  awk -F',' -v stage="$stage" '
    NR == 1 { next }
    $2 == stage {
      total += $4; crit += $5; high += $6; med += $7; low += $8
      rows++
    }
    END {
      if (rows == 0) exit
      printf "**Aggregate**: total=%d critical=%d high=%d medium=%d low=%d\n\n", total, crit, high, med, low
    }
  ' "$CSV"
}

emit_stage_table design
emit_stage_table prd
emit_stage_table plan

# Per-severity tier global aggregate
printf '## All-stages aggregate\n\n'
awk -F',' '
  NR == 1 { next }
  {
    total += $4; crit += $5; high += $6; med += $7; low += $8
    by_stage[$2 "_total"] += $4
    by_stage[$2 "_crit"]  += $5
    by_stage[$2 "_high"]  += $6
    by_stage[$2 "_med"]   += $7
    by_stage[$2 "_low"]   += $8
    rows++
  }
  END {
    printf "Rows: %d  Total findings: %d\n\n", rows, total
    printf "By severity (across all stages):\n"
    printf "  critical: %d (%.1f%%)\n", crit, (total > 0 ? crit*100.0/total : 0)
    printf "  high:     %d (%.1f%%)\n", high, (total > 0 ? high*100.0/total : 0)
    printf "  medium:   %d (%.1f%%)\n", med,  (total > 0 ? med*100.0/total : 0)
    printf "  low:      %d (%.1f%%)\n", low,  (total > 0 ? low*100.0/total : 0)
  }
' "$CSV"
