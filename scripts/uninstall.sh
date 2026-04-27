#!/usr/bin/env bash
# bdx uninstaller — reverse the bdx installer.
#
# Prompts for each teardown step. By design this script does NOT touch your
# shell profile (BEADS_DIR / AGENT_HOME exports stay until you remove them by
# hand). Defaults are conservative: destructive ops default to "no".
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/zeejers/bdx-plugin/main/scripts/uninstall.sh)
#   curl -fsSL https://raw.githubusercontent.com/zeejers/bdx-plugin/main/scripts/uninstall.sh | bash
#   ./uninstall.sh                # interactive
#   ./uninstall.sh --yes          # accept the default at every prompt (binaries: yes, data: no)
#   ./uninstall.sh --dry-run      # print what would be removed; touch nothing
#
# Note: --yes accepts DEFAULTS, not "yes to everything." Destructive prompts
# (deleting $BEADS_DIR / $AGENT_HOME) default to no, so --yes will NOT delete
# data. To force-delete data without prompts, run interactively and answer y.
#
# Steps (each prompted independently):
#   1. Stop the running dolt server, if any
#   2. Remove the bd binary
#   3. Remove the dolt binary (brew uninstall on macOS when applicable)
#   4. Remove $BEADS_DIR (DESTRUCTIVE — all issues, history, dolt data)
#   5. Remove $AGENT_HOME (DESTRUCTIVE — all plans, contexts, summaries)

set -eu

main() {
  local YES=0 DRY=0
  for arg in "$@"; do
    case "$arg" in
      --yes|-y)     YES=1 ;;
      --dry-run|-n) DRY=1 ;;
      --help|-h)    sed -n '2,25p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null | sed 's/^# \{0,1\}//' || true; return 0 ;;
      *) printf 'unknown flag: %s (try --help)\n' "$arg" >&2; return 2 ;;
    esac
  done

  local warn_no_tty=0
  if [ ! -t 0 ]; then
    if (exec </dev/tty) 2>/dev/null; then
      exec </dev/tty
    else
      YES=1
      warn_no_tty=1
    fi
  fi

  bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
  info() { printf '  %s\n' "$*"; }
  ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
  warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
  danger() { printf '  \033[31m!!\033[0m %s\n' "$*"; }

  ask_yn() {
    local q="$1" d="${2:-N}" prompt ans
    case "$d" in Y|y) prompt="[Y/n]" ;; *) prompt="[y/N]" ;; esac
    if [ "$YES" = 1 ]; then case "$d" in Y|y) return 0 ;; *) return 1 ;; esac; fi
    printf '  %s %s ' "$q" "$prompt" >&2
    read -r ans || ans=""
    ans="${ans:-$d}"
    case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
  }

  run() {
    if [ "$DRY" = 1 ]; then
      info "[dry-run] would run: $*"
      return 0
    fi
    "$@"
  }

  bold "bdx uninstaller"
  if [ "$warn_no_tty" = 1 ]; then
    warn "no controlling terminal — running non-interactive (--yes implied)"
  fi
  if [ "$DRY" = 1 ]; then
    info "dry-run mode: nothing will be removed"
  fi
  if [ "$YES" = 1 ] && [ "$DRY" = 0 ]; then
    info "--yes accepts defaults at every prompt (data deletion still defaults to no)"
  fi

  # --- 1. dolt server -----------------------------------------------------
  bold "1/5  stop dolt server"
  local dolt_running=0
  if command -v bd >/dev/null 2>&1 && bd dolt status 2>/dev/null | grep -q 'running'; then
    dolt_running=1
  elif pgrep -f 'dolt sql-server' >/dev/null 2>&1; then
    dolt_running=1
  fi
  if [ "$dolt_running" = 0 ]; then
    info "no dolt server running"
  elif ask_yn "Stop the running dolt server?" Y; then
    if command -v bd >/dev/null 2>&1; then
      run bd dolt stop || warn "bd dolt stop failed; trying pkill"
    fi
    pgrep -f 'dolt sql-server' >/dev/null 2>&1 && run pkill -f 'dolt sql-server' || true
    ok "dolt server stopped"
  else
    info "skipped — left running"
  fi

  # --- 2. bd binary -------------------------------------------------------
  bold "2/5  bd binary"
  local bd_path
  bd_path=$(command -v bd 2>/dev/null || true)
  if [ -z "$bd_path" ]; then
    info "bd not on PATH — nothing to remove"
  else
    info "found: $bd_path"
    if ask_yn "Remove the bd binary?" Y; then
      run rm -f "$bd_path" && ok "removed $bd_path"
    else
      info "skipped"
    fi
  fi

  # --- 3. dolt binary -----------------------------------------------------
  bold "3/5  dolt binary"
  local dolt_path
  dolt_path=$(command -v dolt 2>/dev/null || true)
  if [ -z "$dolt_path" ]; then
    info "dolt not on PATH — nothing to remove"
  else
    info "found: $dolt_path"
    # Detect homebrew install — uninstall properly to avoid leaving a brew stub
    local via_brew=0
    if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx dolt; then
      via_brew=1
    fi
    if [ "$via_brew" = 1 ]; then
      if ask_yn "Run 'brew uninstall dolt'?" Y; then
        run brew uninstall dolt && ok "brew uninstalled dolt"
      else
        info "skipped"
      fi
    else
      if ask_yn "Remove the dolt binary?" Y; then
        run rm -f "$dolt_path" && ok "removed $dolt_path"
      else
        info "skipped"
      fi
    fi
  fi

  # --- 4. $BEADS_DIR (DESTRUCTIVE) ---------------------------------------
  bold "4/5  remove \$BEADS_DIR (issues + dolt data)"
  local beads_dir="${BEADS_DIR:-$HOME/.beads}"
  if [ ! -d "$beads_dir" ]; then
    info "$beads_dir does not exist — nothing to remove"
  else
    danger "this will permanently delete: $beads_dir"
    danger "contents include all bd issues, comments, dependencies, and the full dolt history"
    if ask_yn "Delete $beads_dir?" N; then
      run rm -rf "$beads_dir" && ok "removed $beads_dir"
    else
      info "skipped — left intact at $beads_dir"
    fi
  fi

  # --- 5. $AGENT_HOME (DESTRUCTIVE) --------------------------------------
  bold "5/5  remove \$AGENT_HOME (plans, contexts, summaries, inbox)"
  local agent_home="${AGENT_HOME:-$HOME/.bdx-agent}"
  if [ ! -d "$agent_home" ]; then
    info "$agent_home does not exist — nothing to remove"
  else
    danger "this will permanently delete: $agent_home"
    danger "contents include all plan/, context/, summary/, inbox/ markdown files"
    if [ "$agent_home" = "$HOME/Dropbox/Notes/agent" ] || [[ "$agent_home" == *"Dropbox"* ]] || [[ "$agent_home" == *"iCloud"* ]]; then
      danger "this path looks synced (Dropbox/iCloud) — deletion will propagate to other machines"
    fi
    if ask_yn "Delete $agent_home?" N; then
      run rm -rf "$agent_home" && ok "removed $agent_home"
    else
      info "skipped — left intact at $agent_home"
    fi
  fi

  # --- manual cleanup reminder -------------------------------------------
  bold "manual cleanup (not handled by this script)"
  info "shell profile: remove the BEADS_DIR / AGENT_HOME exports from your shell rc by hand"
  info "claude plugin: 'claude plugin remove bdx' if you installed it via a marketplace"
  info "launchd agent (macOS): 'launchctl unload ~/Library/LaunchAgents/com.<you>.beads.dolt.plist' + delete the plist if you set one up"

  bold "done"
}

main "$@"
exit $?
