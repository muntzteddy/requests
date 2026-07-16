#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="$HOME/.config-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# --- Ghostty config ---
# Terminal title fix: Ghostty's `title = "Ghostty"` (below) is the one
# layer confirmed to actually hold. shell-integration's no-title,
# DISABLE_AUTO_TITLE, and CLAUDE_CODE_DISABLE_TERMINAL_TITLE (.zshrc +
# settings.json) are kept as defense-in-depth -- they stop their own
# mechanism from attempting a title change at all, which is harmless
# and keeps things consistent if the Ghostty-level lock is ever
# removed, but per Ghostty's docs none of them can have any observable
# effect on the displayed title while the lock is in place.
GHOSTTY_DIR="$HOME/.config/ghostty"
mkdir -p "$GHOSTTY_DIR"
[[ -f "$GHOSTTY_DIR/config" ]] && cp "$GHOSTTY_DIR/config" "$BACKUP_DIR/ghostty-config"

# Ghostty loads `config` and `config.ghostty` from this XDG directory, and
# for singular keys the later-loaded one wins outright rather than merging
# -- a pre-existing config.ghostty here silently overrode our
# shell-integration-features (no-cursor beat no-title) for this session's
# entire duration. Fold it into this single file and neutralize it so
# there's exactly one source of truth going forward.
if [[ -f "$GHOSTTY_DIR/config.ghostty" ]]; then
  cp "$GHOSTTY_DIR/config.ghostty" "$BACKUP_DIR/ghostty-config.ghostty"
  rm -f "$GHOSTTY_DIR/config.ghostty"
fi

# Ghostty on macOS ALSO loads config/config.ghostty from a second,
# completely separate directory (Application Support), loaded *after* the
# XDG path above and overriding it on conflicts -- confirmed via
# https://ghostty.org/docs/config: "Note that all macOS-specific files are
# loaded after all XDG files." Neutralize this too, for the same reason as
# above: leaving it unchecked would let the exact same class of silent
# override recur through a path this script never touched.
MACOS_GHOSTTY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
if [[ -d "$MACOS_GHOSTTY_DIR" ]]; then
  for f in config config.ghostty; do
    if [[ -f "$MACOS_GHOSTTY_DIR/$f" ]]; then
      cp "$MACOS_GHOSTTY_DIR/$f" "$BACKUP_DIR/ghostty-macos-$f"
      rm -f "$MACOS_GHOSTTY_DIR/$f"
    fi
  done
fi

cat > "$GHOSTTY_DIR/config" <<'GHOSTTY_EOF'
# Ghostty configuration — macOS Apple Silicon
# Merged from a pre-existing personal config.ghostty (window sizing,
# quick terminal, keybindings) plus this session's title-fix/theme work.

# --- Layout and window behaviour ---
window-width = 160
window-height = 36
window-padding-x = 12
window-padding-y = 8
window-save-state = always
window-theme = auto
macos-titlebar-style = tabs
macos-non-native-fullscreen = true
# Treat Option as Alt so word-jumping (Alt+B/F) and other
# readline/zsh shortcuts work correctly.
macos-option-as-alt = true
# Quit Ghostty when the last terminal window closes.
quit-after-last-window-closed = true

# --- Theme, contrast, colorspace ---
theme = "Catppuccin Macchiato"
minimum-contrast = 2
window-colorspace = srgb
background-blur-radius = 0

# --- Font and rendering ---
font-family = "JetBrainsMonoNerdFont"
font-size = 14
font-thicken = false
font-thicken-strength = 1
adjust-cell-height = 2

# --- Cursor and shell integration ---
shell-integration = detect
# no-cursor: pre-existing preference (disables shell-integration's
#   auto bar-cursor-on-prompt behavior).
# no-title: defense-in-depth, prevents Ghostty's own shell-integration
#   from attempting to set the tab title from the running command/cwd
#   in the first place. The `title = "Ghostty"` lock below is what
#   actually guarantees the title stays fixed either way.
shell-integration-features = no-cursor,no-title
cursor-style = block
cursor-style-blink = false
cursor-opacity = 0.8
cursor-click-to-move = true

# --- Fixed title ---
# CLAUDE_CODE_DISABLE_TERMINAL_TITLE (see anthropics/claude-code issues
# #16572, #21677, #29349, #3396, #4765 -- multiple open reports the flag
# doesn't reliably stop the title change, including on Ghostty/macOS) is
# not dependable enough to rely on alone. This forces the title to a
# fixed string regardless of what any program sends, per Ghostty's own
# docs (https://ghostty.org/docs/config/reference, `title` option:
# "Ghostty will ignore any set title escape sequences programs...may
# send"), closing the gap at the terminal level instead of depending on
# the upstream flag actually working. This is the one layer confirmed
# (empirically, on this machine) to actually hold regardless of whether
# the other three below do anything.
title = "Ghostty"

# --- Mouse ergonomics ---
mouse-hide-while-typing = false

# --- Quick terminal ---
quick-terminal-position = top
quick-terminal-screen = mouse
quick-terminal-autohide = true
quick-terminal-animation-duration = 0
keybind = ctrl+grave_accent=toggle_quick_terminal

# --- Tabs and splits ---
keybind = cmd+t=new_tab
keybind = cmd+w=close_surface
keybind = cmd+shift+left=previous_tab
keybind = cmd+shift+right=next_tab
keybind = cmd+d=new_split:right
keybind = cmd+shift+d=new_split:down
keybind = cmd+alt+left=goto_split:left
keybind = cmd+alt+right=goto_split:right
keybind = cmd+alt+up=goto_split:top
keybind = cmd+alt+down=goto_split:bottom
keybind = cmd+shift+e=equalize_splits
keybind = cmd+shift+f=toggle_split_zoom

# --- Font size controls ---
keybind = cmd+plus=increase_font_size:1
keybind = cmd+minus=decrease_font_size:1
keybind = cmd+zero=reset_font_size

# --- Config reload ---
keybind = cmd+shift+comma=reload_config
GHOSTTY_EOF
echo "Ghostty config written to $GHOSTTY_DIR/config"

# --- .zshrc (layer 2 of title fix + all zsh fixes) ---
[[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$BACKUP_DIR/zshrc"

cat > "$HOME/.zshrc" <<'ZSHRC_EOF'
# ~/.zshrc — macOS + Ghostty + Oh My Zsh + Claude Code

# ============================================================
# 1. Pre-OMZ settings (must come before sourcing Oh My Zsh)
# ============================================================

# Prevent Oh My Zsh termsupport.zsh from setting terminal title.
# Defense-in-depth alongside the Ghostty `title` lock (see
# scripts/setup-terminal.sh's Ghostty-config comment) -- harmless
# either way, not independently load-bearing.
DISABLE_AUTO_TITLE="true"

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git brew macos)

source "$ZSH/oh-my-zsh.sh"

# ============================================================
# 2. PATH — Homebrew, pipx, Go
# ============================================================

eval "$(/opt/homebrew/bin/brew shellenv)"
export GOPATH="$HOME/go"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$GOPATH/bin:$PATH"

# ============================================================
# 2b. mathiasbynens/dotfiles shell config (if installed via
#     scripts/install-mathiasbynens-dotfiles.zsh --apply)
# ============================================================

# Mirrors that repo's own .bash_profile loader, minus .bash_prompt
# (bash-specific prompt formatting; we use Oh My Zsh's theme instead).
# Placed before section 3 below so this session's explicit choices
# (locale, editor) always win over whatever .exports sets.
for file in "$HOME"/.{path,exports,aliases,functions,extra}; do
  [ -r "$file" ] && [ -f "$file" ] && source "$file"
done

# ============================================================
# 3. Environment variables
# ============================================================

export LANG=en_AU.UTF-8
export LC_ALL=en_AU.UTF-8
export EDITOR=nano

# Defense-in-depth alongside the Ghostty `title` lock: settings.json's
# "env" key alone did not reliably stop the title change when tested
# directly on this machine (see anthropics/claude-code issues #16572,
# #21677, #29349), so this shell-level export is added too. Neither
# is independently sufficient -- the Ghostty-level lock is what
# actually holds regardless of whether this flag works upstream.
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1

# ============================================================
# 4. Aliases
# ============================================================

alias ll='ls -lah'

# Claude fast profile (low token, haiku, effort low)
alias claude-fast='ANTHROPIC_MODEL="claude-haiku-4-5" CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.fast.json" claude'

# ============================================================
# 5. Functions (inline — only two, not worth autoload)
# ============================================================

mkcd() {
  mkdir -p -- "$1" && cd -- "$1"
}

croot() {
  cd "$(git rev-parse --show-toplevel)"
}
ZSHRC_EOF
echo ".zshrc written to $HOME/.zshrc"

# --- Claude settings.json merge (defense-in-depth for title fix) ---
mkdir -p "$HOME/.claude"
[[ -f "$HOME/.claude/settings.json" ]] && cp "$HOME/.claude/settings.json" "$BACKUP_DIR/claude-settings.json"

python3 - "$HOME/.claude/settings.json" <<'PY_EOF'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = {}
if path.exists() and path.stat().st_size:
    try:
        with path.open() as f:
            loaded = json.load(f)
    except json.JSONDecodeError as e:
        print(f"WARNING: {path} is not valid JSON ({e}); already backed up, "
              "starting fresh instead of crashing.", file=sys.stderr)
        loaded = {}
    if isinstance(loaded, dict):
        data = loaded
    else:
        print(f"WARNING: {path} top level is a {type(loaded).__name__}, not "
              "an object; already backed up, starting fresh instead of crashing.",
              file=sys.stderr)

env = data.setdefault("env", {})
env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] = "1"

with path.open("w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"Claude settings updated: {path}")
print("  env.CLAUDE_CODE_DISABLE_TERMINAL_TITLE = 1")
PY_EOF

# --- Validation ---
echo ""
echo "=== Validation ==="

if grep -q 'shell-integration-features = no-cursor,no-title' "$GHOSTTY_DIR/config"; then
  echo "[OK] Ghostty: shell-integration-features includes no-title"
else
  echo "[FAIL] Ghostty: shell-integration-features missing no-title"
fi

if grep -q '^theme = "Catppuccin Macchiato"$' "$GHOSTTY_DIR/config"; then
  echo "[OK] Ghostty: theme = Catppuccin Macchiato"
else
  echo "[FAIL] Ghostty: Catppuccin Macchiato theme missing"
fi

if grep -q '^title = "Ghostty"$' "$GHOSTTY_DIR/config"; then
  echo "[OK] Ghostty: fixed title set (works around buggy CLAUDE_CODE_DISABLE_TERMINAL_TITLE)"
else
  echo "[FAIL] Ghostty: fixed title missing"
fi

if [[ ! -f "$GHOSTTY_DIR/config.ghostty" ]]; then
  echo "[OK] Ghostty: no competing config.ghostty file"
else
  echo "[FAIL] Ghostty: config.ghostty still present, will override this config"
fi

if [[ ! -f "$MACOS_GHOSTTY_DIR/config" && ! -f "$MACOS_GHOSTTY_DIR/config.ghostty" ]]; then
  echo "[OK] Ghostty: no competing config in Application Support"
else
  echo "[FAIL] Ghostty: config still present in Application Support, will override this config"
fi

if grep -q 'DISABLE_AUTO_TITLE="true"' "$HOME/.zshrc"; then
  echo "[OK] Zsh: DISABLE_AUTO_TITLE set"
else
  echo "[FAIL] Zsh: DISABLE_AUTO_TITLE missing"
fi

if grep -q '^export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1$' "$HOME/.zshrc"; then
  echo "[OK] Zsh: CLAUDE_CODE_DISABLE_TERMINAL_TITLE exported"
else
  echo "[FAIL] Zsh: CLAUDE_CODE_DISABLE_TERMINAL_TITLE export missing"
fi

if python3 -c '
import json, sys
from pathlib import Path
path = Path.home() / ".claude" / "settings.json"
data = json.loads(path.read_text())
sys.exit(0 if data.get("env", {}).get("CLAUDE_CODE_DISABLE_TERMINAL_TITLE") == "1" else 1)
' 2>/dev/null; then
  echo "[OK] Claude: CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1"
else
  echo "[FAIL] Claude: terminal title env var missing"
fi

if grep -q 'NODE_ENV' "$HOME/.zshrc"; then
  echo "[WARN] Zsh: NODE_ENV still set globally"
else
  echo "[OK] Zsh: no global NODE_ENV"
fi

if grep -q 'claude-fast' "$HOME/.zshrc"; then
  echo "[OK] Zsh: claude-fast alias present"
else
  echo "[FAIL] Zsh: claude-fast alias missing"
fi

if grep -q '\.local/bin' "$HOME/.zshrc"; then
  echo "[OK] Zsh: ~/.local/bin in PATH"
else
  echo "[FAIL] Zsh: ~/.local/bin missing from PATH"
fi

mkcd_count=$(grep -c '^mkcd() {$' "$HOME/.zshrc" || true)
if [[ "$mkcd_count" -eq 1 ]]; then
  echo "[OK] Zsh: mkcd defined exactly once"
else
  echo "[FAIL] Zsh: mkcd defined $mkcd_count times"
fi

if grep -q 'autoload.*mkcd' "$HOME/.zshrc"; then
  echo "[FAIL] Zsh: stale autoload for mkcd found"
else
  echo "[OK] Zsh: no conflicting autoload"
fi

if zsh -n "$HOME/.zshrc"; then
  echo "[OK] Zsh: .zshrc syntax check passed"
else
  echo "[FAIL] Zsh: .zshrc has a syntax error"
fi

echo ""
echo "Backups saved to: $BACKUP_DIR"
echo "Restart Ghostty (or run 'exec zsh') and open a new tab to apply changes."
