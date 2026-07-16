#!/usr/bin/env bash
set -euo pipefail

ROOT="${PROJECT_ROOT:-${HOME}/work/project}"
mkdir -p "${ROOT}"/{.claude,notes,scripts}
cd "${ROOT}"

cat > CLAUDE.md <<'EOF'
# Project rules

- Keep responses concise.
- Prefer patch-style changes.
- Use progress.md for active work.
- Use session_summary.md when closing a session.
- Use compact summaries, not huge pasted logs.
- For docs/API questions, use context7.
- For whole-repo context, use repomix.
- For repo state, use GitHub MCP.
- For browser bugs, use Playwright MCP.
EOF

cat > progress.md <<'EOF'
# Progress

## Active goal
-

## Completed
-

## Next
-

## Open questions
-
EOF

cat > session_summary.md <<'EOF'
# Session summary

## What changed
-

## Decisions
-

## Follow-ups
-

## Token notes
-
EOF

cat > .mcp.json <<'EOF'
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    },
    "taskmaster-ai": {
      "command": "npx",
      "args": ["-y", "task-master-ai"]
    }
  }
}
EOF

cat > .claude/settings.json <<'EOF'
{
  "enableAllProjectMcpServers": false,
  "enabledMcpjsonServers": ["context7", "playwright", "taskmaster-ai"],
  "permissions": {
    "allow": [
      "mcp__context7__*",
      "mcp__playwright__browser_snapshot",
      "mcp__github__*",
      "mcp__taskmaster-ai__*",
      "Read",
      "Bash(git log:*)",
      "Bash(git diff:*)"
    ],
    "deny": [
      "Bash(rm:*)",
      "Bash(find:*delete*)",
      "Bash(find:*exec*)"
    ]
  }
}
EOF

cat > .claude/settings.local.json <<'EOF'
{
  "permissions": {
    "allow": [],
    "deny": []
  }
}
EOF

cat > .gitignore <<'EOF'
.claude/settings.local.json
notes/token-log.md
EOF

touch notes/token-log.md

if ! xcode-select -p >/dev/null 2>&1; then xcode-select --install || true; fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew missing. Install it first: https://brew.sh" >&2
  exit 1
fi

brew update

if brew list --cask claude-code >/dev/null 2>&1; then :; else brew install --cask claude-code; fi
if ! command -v git >/dev/null 2>&1 && ! brew list git >/dev/null 2>&1; then brew install git; fi
if ! brew list python >/dev/null 2>&1; then brew install python; fi
if ! brew list node >/dev/null 2>&1; then brew install node; fi

# Verify installs actually landed before relying on them below.
for cmd in git node python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd missing" >&2; exit 1; }
done

command -v claude >/dev/null 2>&1 || { echo "claude not found after install" >&2; exit 1; }

if ! command -v pipx >/dev/null 2>&1; then brew install pipx; fi
export PATH="$HOME/.local/bin:$PATH"
pipx ensurepath >/dev/null 2>&1 || true
if ! command -v headroom >/dev/null 2>&1; then pipx install "headroom-ai[all]"; fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm missing; cannot install repomix/ccusage" >&2
  exit 1
fi
if ! command -v repomix >/dev/null 2>&1; then npm install -g repomix; fi
if ! command -v ccusage >/dev/null 2>&1; then npm install -g ccusage; fi

command -v repomix >/dev/null 2>&1 || { echo "repomix not found after install" >&2; exit 1; }
command -v ccusage >/dev/null 2>&1 || { echo "ccusage not found after install" >&2; exit 1; }
command -v headroom >/dev/null 2>&1 || { echo "headroom not found after install" >&2; exit 1; }

if command -v claude >/dev/null 2>&1; then claude mcp add context7 -- npx -y @upstash/context7-mcp@latest || true; fi
if command -v claude >/dev/null 2>&1; then claude mcp add playwright -- npx -y @playwright/mcp@latest || true; fi
if command -v claude >/dev/null 2>&1; then
  if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    echo "GITHUB_PERSONAL_ACCESS_TOKEN not set; skipping 'claude mcp add github' (export it and re-run, or add manually later)" >&2
  else
    claude mcp add --transport http github https://api.githubcopilot.com/mcp/ --header "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" || true
  fi
fi
if command -v claude >/dev/null 2>&1; then claude mcp add taskmaster-ai -- npx -y task-master-ai || true; fi

mkdir -p ~/src
if [ ! -d ~/src/openwolf ]; then git clone https://github.com/cytostack/openwolf.git ~/src/openwolf; fi
if [ ! -d ~/src/claude-mem ]; then git clone https://github.com/thedotmack/claude-mem.git ~/src/claude-mem; fi
if [ ! -d ~/src/everything-claude-code ]; then git clone https://github.com/affaan-m/everything-claude-code.git ~/src/everything-claude-code; fi

cat > scripts/repo-pack.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
repomix "${1:-.}"
EOF
chmod +x scripts/repo-pack.sh

cat > scripts/token-report.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ccusage
EOF
chmod +x scripts/token-report.sh

cat > scripts/claude-wrap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
headroom wrap claude
EOF
chmod +x scripts/claude-wrap.sh

echo "Bootstrap complete in ${ROOT}"
echo "Next:"
echo "  cd ${ROOT}"
echo "  claude"
