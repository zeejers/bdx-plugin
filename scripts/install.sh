#!/usr/bin/env bash
# bdx installer — one-shot bootstrap for the bdx workflow.
#
#   1. bd     (beads CLI, via gastownhall/beads)
#   2. dolt   (homebrew on macOS when available, official installer otherwise)
#   3. env    (BEADS_DIR + AGENT_HOME exports in your shell rc, with prompts)
#
# Usage (curl | bash also works — prompts read from /dev/tty):
#   curl -fsSL https://raw.githubusercontent.com/zeejers/bdx-plugin/main/scripts/install.sh | bash
#   ./install.sh                # interactive
#   ./install.sh --yes          # non-interactive, accept defaults
#   ./install.sh --skip-env     # skip the shell-profile prompts
#   ./install.sh --skip-bd      # skip bd install
#   ./install.sh --skip-dolt    # skip dolt install
#
# Safe to re-run; everything is idempotent.

set -eu

YES=0
SKIP_ENV=0
SKIP_BD=0
SKIP_DOLT=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y)    YES=1 ;;
    --skip-env)  SKIP_ENV=1 ;;
    --skip-bd)   SKIP_BD=1 ;;
    --skip-dolt) SKIP_DOLT=1 ;;
    --help|-h)   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# Re-attach stdin to the terminal when piped via `curl | bash` so prompts work.
# Guarded: if /dev/tty isn't openable (CI, sandbox, no controlling tty), fall
# through and rely on --yes / defaults instead of crashing.
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
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

ask_yn() {
  # ask_yn "question" default(Y|N) -> 0 yes, 1 no
  local q="$1" d="${2:-Y}" prompt ans
  case "$d" in Y|y) prompt="[Y/n]" ;; *) prompt="[y/N]" ;; esac
  if [ "$YES" = 1 ]; then case "$d" in Y|y) return 0 ;; *) return 1 ;; esac; fi
  printf '  %s %s ' "$q" "$prompt" >&2
  read -r ans || ans=""
  ans="${ans:-$d}"
  case "$ans" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

ask_value() {
  # ask_value "label" "default" -> echoes chosen value
  local label="$1" def="$2" ans
  if [ "$YES" = 1 ]; then printf '%s' "$def"; return; fi
  printf '  %s [%s]: ' "$label" "$def" >&2
  read -r ans || ans=""
  printf '%s' "${ans:-$def}"
}

# --- platform -------------------------------------------------------------
OS=$(uname -s)
ARCH=$(uname -m)
case "$OS" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *) die "unsupported OS: $OS (macOS and Linux only)" ;;
esac

bold "bdx installer — $PLATFORM/$ARCH"
if [ "${warn_no_tty:-0}" = 1 ]; then
  warn "no controlling terminal — running non-interactive (defaults accepted)"
fi

# --- 1. bd (beads) --------------------------------------------------------
bold "1/3  beads (bd)"
if [ "$SKIP_BD" = 1 ]; then
  info "skipped (--skip-bd)"
elif command -v bd >/dev/null 2>&1; then
  ok "bd already installed: $(bd --version 2>/dev/null | head -1 || echo 'present')"
else
  info "installing via gastownhall/beads installer..."
  curl -fsSL https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh | bash
  if command -v bd >/dev/null 2>&1; then
    ok "bd installed: $(bd --version 2>/dev/null | head -1 || echo 'ok')"
  else
    warn "bd installer ran but 'bd' is not on PATH yet — open a new shell, or check ~/.local/bin"
  fi
fi

# --- 2. dolt --------------------------------------------------------------
bold "2/3  dolt"
if [ "$SKIP_DOLT" = 1 ]; then
  info "skipped (--skip-dolt)"
elif command -v dolt >/dev/null 2>&1; then
  ok "dolt already installed: $(dolt version 2>/dev/null | head -1)"
else
  case "$PLATFORM" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        info "installing via homebrew..."
        brew install dolt
      else
        info "homebrew not found — using the official dolt installer (sudo required)..."
        curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | sudo bash
      fi
      ;;
    linux)
      info "installing via the official dolt installer (sudo required)..."
      curl -fsSL https://github.com/dolthub/dolt/releases/latest/download/install.sh | sudo bash
      ;;
  esac
  command -v dolt >/dev/null 2>&1 && ok "dolt installed: $(dolt version 2>/dev/null | head -1)"
fi

# --- 3. shell profile env vars -------------------------------------------
bold "3/3  shell profile (BEADS_DIR, AGENT_HOME)"
if [ "$SKIP_ENV" = 1 ]; then
  info "skipped (--skip-env)"
else
  shell_name=$(basename "${SHELL:-/bin/bash}")
  case "$shell_name" in
    zsh)  rc="$HOME/.zshrc" ;;
    bash) if [ "$PLATFORM" = macos ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
    fish) rc="$HOME/.config/fish/config.fish" ;;
    *)    rc="$HOME/.profile" ;;
  esac
  info "shell rc: $rc"

  add_export() {
    local var="$1" val="$2" line
    if [ "$shell_name" = "fish" ]; then
      line="set -gx $var \"$val\""
    else
      line="export $var=\"$val\""
    fi
    if [ -f "$rc" ] && grep -qE "^[[:space:]]*(export[[:space:]]+|set[[:space:]]+-gx[[:space:]]+)?$var(=|[[:space:]])" "$rc"; then
      warn "$var already set in $rc — leaving untouched"
      return
    fi
    mkdir -p "$(dirname "$rc")"
    printf '\n# bdx installer\n%s\n' "$line" >> "$rc"
    ok "added $var=\"$val\" to $rc"
  }

  if ask_yn "Add BEADS_DIR to your shell profile?" Y; then
    val=$(ask_value "BEADS_DIR" "$HOME/.beads")
    add_export BEADS_DIR "$val"
  fi
  if ask_yn "Add AGENT_HOME to your shell profile?" Y; then
    val=$(ask_value "AGENT_HOME" "$HOME/.bdx-agent")
    add_export AGENT_HOME "$val"
  fi
fi

bold "done"
if [ "$SKIP_ENV" = 0 ]; then
  info "open a new shell (or 'source ${rc:-<your shell rc>}') to pick up env changes"
fi
info "next: install the bdx Claude Code plugin — see README.md"
