#!/usr/bin/env bash
# copilot-hooks.sh — Pre-spawn hook for GitHub Copilot CLI.
# Appends autonomous, scripting-safe flags for non-interactive dispatch.

pre_spawn() {
  RUNNER_EXTRA_FLAGS="${RUNNER_EXTRA_FLAGS:+$RUNNER_EXTRA_FLAGS }--autopilot --max-autopilot-continues 0 --no-ask-user --silent --no-color --stream off --no-remote"
}
