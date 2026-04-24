#!/usr/bin/env bash
# lib/reaper.sh — platform-aware subprocess reaper (P2.11, orphan fix).
#
# Addresses three confirmed root causes of orphan `claude.exe` processes:
#
#   1. Subshell-PID capture in lib/spawn.sh:
#        (cd ... && claude --print -p ...) &
#        pid=$!                          # <- SUBSHELL PID, not claude.exe
#      Fix: prepend `exec` inside the subshell so $! becomes the real
#      claude PID. This library's write_agent_pidfile assumes that fix
#      is in place (see lib/spawn.sh after Phase 20).
#
#   2. MSYS vs Windows dual-PID space on Git Bash.
#      `$!` is an MSYS pid; `claude.exe` runs under a separate Windows pid
#      exposed at /proc/<msyspid>/winpid. `kill $MSYS_PID` against a native
#      Windows binary often no-ops. Reference: Cygwin User's Guide §4,
#      git-for-windows #1055.
#      Fix: write both PIDs to the pidfile. Reap via `taskkill //F //T
#      //PID $WINPID` on Windows; `kill -TERM -$PGID` on POSIX with setsid.
#
#   3. Parent trap only cascades when running from quantum-loop.sh; Agent-
#      tool spawns don't land in AGENT_PIDS[]. Fix: durable pidfile at
#      $PID_DIR/<story>.pid so a separate housekeep pass can reap anything
#      the live trap missed (terminal close, crashed parent, Agent-spawn
#      grandchildren).
#
# Anthropic docs explicitly recommend managing subprocess lifecycle outside
# the SDK via OS primitives — there is no --pid-file flag on the Claude CLI
# and hooks have no PID access. See:
#   https://code.claude.com/docs/en/headless.md
#   github.com/anthropics/claude-code#45717 (known signal bug)
#
# Library contract: no shell flags at source time. Strict mode only in the
# CLI-entry block at file bottom.

REAPER_LIB_DIR="${REAPER_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
: "${REAPER_PID_DIR:=.ql-agent-pids}"
: "${REAPER_GRACE_SECS:=5}"    # SIGTERM grace before SIGKILL
: "${REAPER_STALE_SECS:=3600}" # pidfiles older than this are always stale

# detect_platform()
# Echoes "posix-setsid" | "posix-plain" | "msys" | "cygwin".
# posix-setsid has `setsid` available; plain is mac/BSD default.
detect_platform() {
  local u
  u=$(uname -s 2>/dev/null || echo unknown)
  case "$u" in
    MINGW*|MSYS*)  printf "msys" ;;
    CYGWIN*)       printf "cygwin" ;;
    Linux*)
      if command -v setsid &>/dev/null; then printf "posix-setsid"
      else printf "posix-plain"
      fi
      ;;
    Darwin*|*BSD*)
      if command -v setsid &>/dev/null; then printf "posix-setsid"
      else printf "posix-plain"
      fi
      ;;
    *) printf "unknown" ;;
  esac
}

# _msys_to_winpid(msys_pid)
# On Git Bash, translates an MSYS pid to the Windows pid via /proc/<pid>/winpid.
# Echoes the winpid or "" on failure / non-MSYS platform.
_msys_to_winpid() {
  local msys_pid="${1:?msys_pid required}"
  [[ -r "/proc/$msys_pid/winpid" ]] || { printf ""; return 0; }
  cat "/proc/$msys_pid/winpid" 2>/dev/null | tr -d '[:space:]'
}

# _proc_start_epoch(pid)
# Echoes a per-process start-time signature used to defeat PID reuse.
# Returns "" if the process is gone.
#
# IMPORTANT: previously this used `stat -c %Y /proc/$pid` as a portable
# approximation, but on MSYS2/Git Bash the /proc VFS reports the SAME
# mtime for every process (the MSYS session start), making the PID-reuse
# guard a no-op on exactly the platform reaper.sh was designed to fix
# (Soliton PR #29 correctness finding). Read field 22 of /proc/$pid/stat
# instead — that's the per-process start-tick on both Linux procfs and
# MSYS2's Linux-compatible procfs.
_proc_start_epoch() {
  local pid="${1:?pid required}"
  if [[ -r "/proc/$pid/stat" ]]; then
    # Field 22 is `starttime` (clock ticks since boot). Per-process.
    # Portable across Linux and MSYS2/Cygwin.
    awk '{print $22}' "/proc/$pid/stat" 2>/dev/null | head -1
  elif [[ "$(uname -s 2>/dev/null)" == "Darwin" ]]; then
    ps -o lstart= -p "$pid" 2>/dev/null | head -1
  else
    ps -p "$pid" -o lstart= 2>/dev/null | head -1
  fi
}

# write_agent_pidfile(pid_dir, story_id, msys_pid, winpid, cmd)
# Atomically writes the pidfile at $pid_dir/<story_id>.pid in TSV format:
#   <msys_pid>\t<winpid>\t<start_epoch>\t<cmd>
# Using TSV (not JSON) so stale cleanup doesn't need jq.
write_agent_pidfile() {
  local pid_dir="${1:?pid_dir required}"
  local sid="${2:?story_id required}"
  local msys_pid="${3:?msys_pid required}"
  local winpid="${4:-}"
  local cmd="${5:-}"
  mkdir -p "$pid_dir"
  local start
  start=$(_proc_start_epoch "$msys_pid")
  local tmp="$pid_dir/$sid.pid.tmp"
  local final="$pid_dir/$sid.pid"
  # TSV — escape tabs in cmd
  local safe_cmd="${cmd//$'\t'/ }"
  printf '%s\t%s\t%s\t%s\n' "$msys_pid" "$winpid" "$start" "$safe_cmd" > "$tmp"
  mv -f "$tmp" "$final"
  printf "%s" "$final"
}

# read_agent_pidfile(pid_dir, story_id)
# Emits JSON {msys_pid, winpid, start_epoch, cmd} or "{}" if missing.
read_agent_pidfile() {
  local pid_dir="${1:?pid_dir required}"
  local sid="${2:?story_id required}"
  local file="$pid_dir/$sid.pid"
  [[ -f "$file" ]] || { printf "{}"; return 0; }
  local msys winpid start cmd
  IFS=$'\t' read -r msys winpid start cmd < "$file"
  jq -cn --arg m "$msys" --arg w "$winpid" --arg s "$start" --arg c "$cmd" \
    '{msys_pid: $m, winpid: $w, start_epoch: $s, cmd: $c}'
}

# _is_alive_posix(pid, [start_epoch])
# Returns 0 if the PID is alive AND (if start_epoch given) its current
# start time matches — defeats PID reuse.
_is_alive_posix() {
  local pid="$1"
  local want_start="${2:-}"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  [[ -z "$want_start" ]] && return 0
  local cur_start
  cur_start=$(_proc_start_epoch "$pid")
  [[ "$cur_start" == "$want_start" ]]
}

# _is_alive_windows(winpid, [start_epoch])
# Uses tasklist to check a Windows PID. start_epoch is ignored (tasklist
# can give create time but parsing is inconsistent across locales).
_is_alive_windows() {
  local winpid="$1"
  [[ -n "$winpid" && "$winpid" != "null" ]] || return 1
  if command -v tasklist.exe &>/dev/null || command -v tasklist &>/dev/null; then
    tasklist //fi "PID eq $winpid" //nh 2>/dev/null | grep -q "$winpid"
  else
    return 1
  fi
}

# is_agent_alive(pid_dir, story_id)
# Exit 0 if the pidfile points at a still-running process (optionally
# verified by start_epoch). Exit 1 if pidfile missing, process dead, or
# start_epoch mismatched (PID reuse detected).
is_agent_alive() {
  local pid_dir="${1:?pid_dir required}"
  local sid="${2:?story_id required}"
  local entry
  entry=$(read_agent_pidfile "$pid_dir" "$sid")
  [[ "$entry" == "{}" ]] && return 1
  local msys winpid start
  msys=$(jq -r '.msys_pid' <<< "$entry")
  winpid=$(jq -r '.winpid' <<< "$entry")
  start=$(jq -r '.start_epoch' <<< "$entry")
  local plat
  plat=$(detect_platform)
  case "$plat" in
    msys|cygwin)
      # Prefer winpid check — MSYS PIDs vanish when the bash session ends
      if [[ -n "$winpid" && "$winpid" != "null" && "$winpid" != "" ]]; then
        _is_alive_windows "$winpid" && return 0
      fi
      _is_alive_posix "$msys" "$start"
      ;;
    *)
      _is_alive_posix "$msys" "$start"
      ;;
  esac
}

# reap_agent(pid_dir, story_id)
# SIGTERM → grace → SIGKILL. Removes pidfile on success.
# Returns 0 if reaped or already-gone; 1 if unable to terminate.
reap_agent() {
  local pid_dir="${1:?pid_dir required}"
  local sid="${2:?story_id required}"
  local entry
  entry=$(read_agent_pidfile "$pid_dir" "$sid")
  [[ "$entry" == "{}" ]] && { printf "[REAPER] no pidfile for %s\n" "$sid" >&2; return 0; }
  if ! is_agent_alive "$pid_dir" "$sid"; then
    rm -f "$pid_dir/$sid.pid"
    printf "[REAPER] %s already exited; pidfile cleaned\n" "$sid" >&2
    return 0
  fi
  local msys winpid plat
  msys=$(jq -r '.msys_pid' <<< "$entry")
  winpid=$(jq -r '.winpid' <<< "$entry")
  plat=$(detect_platform)

  case "$plat" in
    msys|cygwin)
      # Prefer taskkill //T //F — walks the kernel's PPID tree
      if [[ -n "$winpid" && "$winpid" != "null" && "$winpid" != "" ]] && \
         (command -v taskkill.exe &>/dev/null || command -v taskkill &>/dev/null); then
        # Graceful: taskkill without //F requests close
        taskkill //PID "$winpid" //T >/dev/null 2>&1
        sleep "$REAPER_GRACE_SECS"
        # Force if still alive
        _is_alive_windows "$winpid" && \
          taskkill //F //T //PID "$winpid" >/dev/null 2>&1
      else
        kill -TERM "$msys" 2>/dev/null
        sleep "$REAPER_GRACE_SECS"
        kill -KILL "$msys" 2>/dev/null
      fi
      ;;
    posix-setsid|posix-plain)
      # Best effort: kill pid group then pid
      kill -TERM -- -"$msys" 2>/dev/null || kill -TERM "$msys" 2>/dev/null
      sleep "$REAPER_GRACE_SECS"
      if _is_alive_posix "$msys"; then
        kill -KILL -- -"$msys" 2>/dev/null || kill -KILL "$msys" 2>/dev/null
      fi
      ;;
  esac

  # Post-kill verification
  if is_agent_alive "$pid_dir" "$sid"; then
    printf "[REAPER] FAILED to kill %s (msys=%s winpid=%s)\n" "$sid" "$msys" "$winpid" >&2
    return 1
  fi
  rm -f "$pid_dir/$sid.pid"
  printf "[REAPER] reaped %s (msys=%s winpid=%s)\n" "$sid" "$msys" "$winpid" >&2
  return 0
}

# reap_orphans(pid_dir)
# Scans every pidfile; reaps any whose process is still alive past the
# stale threshold (orphans from a prior crashed session). Also cleans up
# pidfiles whose process is already gone.
# Exit code: count of reaped orphans (0 = clean).
reap_orphans() {
  local pid_dir="${1:-$REAPER_PID_DIR}"
  [[ -d "$pid_dir" ]] || { printf "[REAPER] no pidfile dir %s — nothing to reap\n" "$pid_dir" >&2; return 0; }
  local count=0
  local now
  now=$(date +%s)
  local f
  for f in "$pid_dir"/*.pid; do
    [[ -f "$f" ]] || continue
    local sid
    sid=$(basename "$f" .pid)
    # If process is not alive, just rm the stale pidfile
    if ! is_agent_alive "$pid_dir" "$sid"; then
      rm -f "$f"
      continue
    fi
    # If process is alive and older than REAPER_STALE_SECS, reap.
    # Use PIDFILE mtime (when spawn wrote the file) for wall-clock age —
    # NOT the per-process start_epoch stored inside the pidfile, which
    # after the Phase 21 fix is clock-ticks-since-boot (a uniqueness
    # token, not a timestamp).
    local spawn_epoch
    spawn_epoch=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    if [[ "$spawn_epoch" -gt 0 ]]; then
      local age=$(( now - spawn_epoch ))
      if (( age >= REAPER_STALE_SECS )); then
        reap_agent "$pid_dir" "$sid" && count=$((count + 1))
      fi
    fi
  done
  printf "%s" "$count"
}

# ------------------------------------------------------------------------------
# CLI entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    platform)      detect_platform; printf "\n" ;;
    winpid)        _msys_to_winpid "$@"; printf "\n" ;;
    write)         write_agent_pidfile "$@"; printf "\n" ;;
    read)          read_agent_pidfile "$@" ;;
    alive)         is_agent_alive "$@" ;;
    reap)          reap_agent "$@" ;;
    reap-orphans)  reap_orphans "$@"; printf "\n" ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/reaper.sh <subcmd> [args...]
  platform                             — detect OS/signal capability
  winpid MSYS_PID                      — translate MSYS pid to Windows pid
  write PID_DIR SID MSYS WIN CMD       — write pidfile (atomic)
  read  PID_DIR SID                    — read pidfile as JSON
  alive PID_DIR SID                    — exit 0 if alive (with PID-reuse guard)
  reap  PID_DIR SID                    — SIGTERM → grace → SIGKILL → cleanup
  reap-orphans PID_DIR                 — scan + reap stale pidfiles
USAGE
      exit 2
      ;;
  esac
fi
