#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="$HOME/.config-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# --- Ghostty config (layer 1 of 3-layer title fix) ---
GHOSTTY_DIR="$HOME/.config/ghostty"
mkdir -p "$GHOSTTY_DIR"
[[ -f "$GHOSTTY_DIR/config" ]] && cp "$GHOSTTY_DIR/config" "$BACKUP_DIR/ghostty-config"

cat > "$GHOSTTY_DIR/config" <<'GHOSTTY_EOF'
# Ghostty configuration — macOS Apple Silicon

# --- Shell integration ---
# Disable title-setting to prevent a 3-way conflict with Oh My Zsh's
# termsupport.zsh and Claude Code's terminal-title updates.
shell-integration-features = no-title

# --- Font ---
font-family = JetBrains Mono
font-size = 14

# --- Theme ---
theme = "Catppuccin Macchiato"

# --- macOS behavior ---
# Treat Option as Alt so word-jumping (Alt+B/F) and other
# readline/zsh shortcuts work correctly.
macos-option-as-alt = true

# Restore all windows/tabs on relaunch.
window-save-state = always

# Quit Ghostty when the last terminal window closes.
quit-after-last-window-closed = true
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
# Layer 2 of the 3-layer title fix (Ghostty + Claude Code + OMZ).
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

# Layer 2b of the title fix: settings.json's "env" key only reliably
# reaches tool-call subprocesses, not Claude Code's own startup
# environment, so the title override needs a real shell-level export too.
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

# --- Claude settings.json merge (layer 3 of title fix) ---
mkdir -p "$HOME/.claude"
[[ -f "$HOME/.claude/settings.json" ]] && cp "$HOME/.claude/settings.json" "$BACKUP_DIR/claude-settings.json"

python3 - "$HOME/.claude/settings.json" <<'PY_EOF'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])

data = {}
if path.exists() and path.stat().st_size:
    with path.open() as f:
        data = json.load(f)

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

if grep -q '^shell-integration-features = no-title$' "$GHOSTTY_DIR/config"; then
  echo "[OK] Ghostty: shell-integration-features = no-title"
else
  echo "[FAIL] Ghostty: missing no-title setting"
fi

if grep -q '^theme = "Catppuccin Macchiato"$' "$GHOSTTY_DIR/config"; then
  echo "[OK] Ghostty: theme = Catppuccin Macchiato"
else
  echo "[FAIL] Ghostty: Catppuccin Macchiato theme missing"
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
