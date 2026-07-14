#!/usr/bin/env bash
set -euo pipefail

echo "Removing duplicate MCP server registrations..."

echo "  context7: removing user and local scopes (keeping project)"
claude mcp remove context7 -s user 2>/dev/null || true
claude mcp remove context7 -s local 2>/dev/null || true

echo "  playwright: removing user and local scopes (keeping project)"
claude mcp remove playwright -s user 2>/dev/null || true
claude mcp remove playwright -s local 2>/dev/null || true

echo "  github: removing user and project scopes (keeping local)"
claude mcp remove github -s user 2>/dev/null || true
claude mcp remove github -s project 2>/dev/null || true

echo "  taskmaster-ai: removing user and local scopes (keeping project)"
claude mcp remove taskmaster-ai -s user 2>/dev/null || true
claude mcp remove taskmaster-ai -s local 2>/dev/null || true

echo ""
echo "Done. Verify with: claude mcp list"
