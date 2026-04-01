#!/usr/bin/env bash
# copilot-hooks.sh — Pre-spawn hook for GitHub Copilot CLI.
# Appends autopilot flags for fully autonomous operation.

pre_spawn() {
  RUNNER_EXTRA_FLAGS="${RUNNER_EXTRA_FLAGS:+$RUNNER_EXTRA_FLAGS }--autopilot --no-ask-user"
}
