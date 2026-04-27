#!/usr/bin/env bash
# bdx installer — one-shot bootstrap for the bdx workflow.
#
#   1. bd          (beads CLI, via gastownhall/beads)
#   2. dolt        (homebrew on macOS when available, official installer otherwise)
#   3. env         (BEADS_DIR + AGENT_HOME exports in your shell rc, with prompts)
#   4. bd init     (initialize the global beads repo at $BEADS_DIR, shared-server)
#   5. templates   (seed example manifest + DHH/Linus personas into $AGENT_HOME)
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/zeejers/bdx-plugin/refs/heads/development/scripts/install.sh)
#   curl -fsSL https://raw.githubusercontent.com/zeejers/bdx-plugin/refs/heads/development/scripts/install.sh | bash
#   ./install.sh                  # interactive
#   ./install.sh --yes            # non-interactive, accept defaults
#   ./install.sh --skip-env       # skip the shell-profile prompts
#   ./install.sh --skip-bd        # skip bd install
#   ./install.sh --skip-dolt      # skip dolt install
#   ./install.sh --skip-init      # skip the bd init step
#   ./install.sh --skip-templates # skip the manifest/personas seeding
#
# Safe to re-run; everything is idempotent.

set -eu

# Everything lives inside main() so bash buffers the entire script while
# parsing — necessary so `curl ... | bash` doesn't hang when prompts redirect
# stdin to /dev/tty mid-execution. Same trick rustup / nvm / homebrew use.
main() {
  local YES=0 SKIP_ENV=0 SKIP_BD=0 SKIP_DOLT=0 SKIP_INIT=0 SKIP_TEMPLATES=0
  for arg in "$@"; do
    case "$arg" in
      --yes|-y)         YES=1 ;;
      --skip-env)       SKIP_ENV=1 ;;
      --skip-bd)        SKIP_BD=1 ;;
      --skip-dolt)      SKIP_DOLT=1 ;;
      --skip-init)      SKIP_INIT=1 ;;
      --skip-templates) SKIP_TEMPLATES=1 ;;
      --help|-h)        sed -n '2,21p' "${BASH_SOURCE[0]:-$0}" 2>/dev/null | sed 's/^# \{0,1\}//' || true; return 0 ;;
      *) printf 'unknown flag: %s (try --help)\n' "$arg" >&2; return 2 ;;
    esac
  done

  # Re-attach stdin to the terminal when piped via `curl | bash`.
  # Guarded: if /dev/tty isn't openable (CI, sandbox, no controlling tty),
  # fall through to non-interactive mode.
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

  # --- platform ----------------------------------------------------------
  local OS ARCH PLATFORM
  OS=$(uname -s)
  ARCH=$(uname -m)
  case "$OS" in
    Darwin) PLATFORM=macos ;;
    Linux)  PLATFORM=linux ;;
    *) die "unsupported OS: $OS (macOS and Linux only)" ;;
  esac

  bold "bdx installer — $PLATFORM/$ARCH"
  if [ "$warn_no_tty" = 1 ]; then
    warn "no controlling terminal — running non-interactive (defaults accepted)"
  fi

  # --- 1. bd (beads) -----------------------------------------------------
  bold "1/5  beads (bd)"
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
      # Try the conventional install path so step 4 still works in this shell.
      if [ -x "$HOME/.local/bin/bd" ]; then
        export PATH="$HOME/.local/bin:$PATH"
        ok "bd installed: $(bd --version 2>/dev/null | head -1 || echo 'ok') (added ~/.local/bin to PATH for this run)"
      else
        warn "bd installer ran but 'bd' is not on PATH yet — open a new shell, or check ~/.local/bin"
      fi
    fi
  fi

  # --- 2. dolt -----------------------------------------------------------
  bold "2/5  dolt"
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

  # --- 3. shell profile env vars ----------------------------------------
  bold "3/5  shell profile (BEADS_DIR, AGENT_HOME)"
  local rc shell_name chosen_beads_dir="" chosen_agent_home=""
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

    # BEADS_DIR — always ~/.beads when we set it. Skip the prompt entirely if
    # the user already has BEADS_DIR exported (synced from another machine,
    # configured manually, etc) — they've already made the choice and a
    # different path is the most likely reason it's set.
    if [ -n "${BEADS_DIR:-}" ]; then
      ok "BEADS_DIR already set in env: $BEADS_DIR — using existing"
      chosen_beads_dir="$BEADS_DIR"
    elif ask_yn "Add 'export BEADS_DIR=~/.beads' to your shell profile?" Y; then
      chosen_beads_dir="$HOME/.beads"
      add_export BEADS_DIR "$chosen_beads_dir"
    fi
    # AGENT_HOME — same detection. If the user has it set (commonly to a
    # synced path like ~/Dropbox/Notes/agent), honor that and skip the prompt.
    if [ -n "${AGENT_HOME:-}" ]; then
      ok "AGENT_HOME already set in env: $AGENT_HOME — using existing"
      chosen_agent_home="$AGENT_HOME"
    elif ask_yn "Add AGENT_HOME to your shell profile?" Y; then
      chosen_agent_home=$(ask_value "AGENT_HOME" "$HOME/.bdx-agent")
      add_export AGENT_HOME "$chosen_agent_home"
    fi
  fi

  # --- 4. bd init (global beads repo) -----------------------------------
  # Beads refuses to init from inside a `.beads/` cwd, so we run from $HOME
  # and let BEADS_DIR direct it to the global location. --database beads_global
  # uses the shared db that --shared-server provisions; --stealth keeps it
  # out of any per-repo git tracking; --quiet silences the wizard banners.
  bold "4/5  bd init (global beads repo)"
  if [ "$SKIP_INIT" = 1 ]; then
    info "skipped (--skip-init)"
  elif ! command -v bd >/dev/null 2>&1; then
    warn "bd not on PATH — skipping init. Open a new shell and re-run this installer."
  else
    local target="${BEADS_DIR:-${chosen_beads_dir:-$HOME/.beads}}"
    if [ -f "$target/beads.db" ] || [ -d "$target/.beads" ]; then
      ok "$target already initialized (found existing beads.db / .beads/)"
    else
      info "target path: $target"
      info "flags:       --quiet --stealth (role pre-set via git config)"
      if ask_yn "Run bd init now with these settings?" Y; then
        mkdir -p "$target"
        # Lock down to owner-only — BEADS_DIR holds credentials + dolt data.
        # Done before bd init so the dir's mode is correct from creation.
        chmod 700 "$target"
        # Pre-set the maintainer role in global git config. bd init's --role
        # flag only applies inside a git repo (isGitRepo() guard); at $HOME
        # without a repo, the role wizard would fire even with --role passed.
        # Setting beads.role in ~/.gitconfig makes bd pick it up regardless.
        if command -v git >/dev/null 2>&1; then
          git config --global beads.role maintainer 2>/dev/null || true
        fi
        if ( cd "$HOME" && BEADS_DIR="$target" bd init --quiet --stealth ); then
          ok "initialized $target (mode 700)"
          info "to change the prefix later: bd config set issue-prefix <new>"
        else
          warn "bd init failed — re-run with: git config --global beads.role maintainer && cd \$HOME && BEADS_DIR=$target bd init --quiet --stealth"
        fi
      else
        info "skipped — run: git config --global beads.role maintainer && cd \$HOME && BEADS_DIR=$target bd init --quiet --stealth"
      fi
    fi
  fi

  # --- 5. seed example templates ----------------------------------------
  # Pull the manifest + persona examples from the repo into $AGENT_HOME so
  # /bdx:plan, /bdx:scope, and /bdx:summarize have starter content. Each
  # file is fetched independently and skipped if it already exists, so this
  # is safe to re-run and won't clobber user customizations.
  bold "5/5  example manifest + personas (optional starter content)"
  if [ "$SKIP_TEMPLATES" = 1 ]; then
    info "skipped (--skip-templates)"
  else
    local target_ah="${AGENT_HOME:-${chosen_agent_home:-$HOME/.bdx-agent}}"
    local templates_branch="${BDX_TEMPLATES_BRANCH:-development}"
    local base_url="https://raw.githubusercontent.com/zeejers/bdx-plugin/refs/heads/${templates_branch}/examples"
    local has_manifest=0 has_personas=0
    [ -f "$target_ah/manifest.md" ] && has_manifest=1
    [ -d "$target_ah/personas" ] && ls "$target_ah/personas"/*.md >/dev/null 2>&1 && has_personas=1
    if [ "$has_manifest" = 1 ] && [ "$has_personas" = 1 ]; then
      ok "$target_ah already has manifest + personas — leaving untouched"
    else
      info "target:         $target_ah"
      info "from branch:    $templates_branch (override with BDX_TEMPLATES_BRANCH=...)"
      info "files:          manifest.md, personas/dhh.md, personas/linus.md"
      info "(existing files are never overwritten)"
      if ask_yn "Seed example manifest + personas into $target_ah?" Y; then
        mkdir -p "$target_ah/personas"
        fetch_template() {
          local url="$1" dest="$2" label="$3"
          if [ -f "$dest" ]; then
            info "$label already exists — skipped"
            return 0
          fi
          if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
            ok "$label → $dest"
          else
            warn "failed to fetch $label from $url"
            rm -f "$dest"
          fi
        }
        fetch_template "$base_url/manifest.md"        "$target_ah/manifest.md"        "manifest.md"
        fetch_template "$base_url/personas/dhh.md"    "$target_ah/personas/dhh.md"    "personas/dhh.md"
        fetch_template "$base_url/personas/linus.md"  "$target_ah/personas/linus.md"  "personas/linus.md"
      else
        info "skipped — copy from examples/ in the repo when ready"
      fi
    fi
  fi

  bold "done"
  if [ "$SKIP_ENV" = 0 ]; then
    info "open a new shell (or 'source ${rc:-<your shell rc>}') to pick up env changes"
  fi
  info "next: install the bdx Claude Code plugin —"
  info "      claude plugin marketplace add zeejers/bdx-plugin && claude plugin install bdx@bdx-marketplace"
}

main "$@"
exit $?
