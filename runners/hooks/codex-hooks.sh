#!/usr/bin/env bash
# codex-hooks.sh — Pre-spawn hook for OpenAI Codex CLI.
# Warns about sandbox network restrictions in full-auto mode.

pre_spawn() {
  echo "[RUNNER] NOTE: Codex sandbox blocks network access in full-auto mode. Ensure dependencies are pre-installed." >&2
}
