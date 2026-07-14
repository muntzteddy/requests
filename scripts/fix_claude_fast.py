import sys

path = sys.argv[1]

with open(path) as f:
    content = f.read()

OLD_ALIAS = (
    '# Claude fast profile (low token, haiku, effort low)\n'
    'alias claude-fast=\'CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.fast.json" claude\'\n'
)
NEW_ALIAS = (
    '# Claude fast profile (low token, haiku, effort low)\n'
    'alias claude-fast=\'ANTHROPIC_MODEL="claude-haiku-4-5" CLAUDE_SETTINGS_FILE="$HOME/.claude/settings.fast.json" claude\'\n'
)

if OLD_ALIAS not in content:
    sys.exit("ABORT: exact alias block not found -- no changes made. Check the file manually.")

content = content.replace(OLD_ALIAS, NEW_ALIAS, 1)

FUNC_START = '# Claude auto-profile wrapper\nfunction claude() {\n'
if FUNC_START not in content:
    sys.exit("ABORT: exact function-start block not found -- alias was updated, but function was NOT removed. Check the file manually.")

start_idx = content.index(FUNC_START)
open_brace_idx = content.index('{', start_idx)

depth = 0
i = open_brace_idx
while i < len(content):
    if content[i] == '{':
        depth += 1
    elif content[i] == '}':
        depth -= 1
        if depth == 0:
            break
    i += 1
else:
    sys.exit("ABORT: could not find matching closing brace -- no changes written.")

end_idx = i + 1
if end_idx < len(content) and content[end_idx] == '\n':
    end_idx += 1

removed_block = content[start_idx:end_idx]
content = content[:start_idx] + content[end_idx:]

with open(path, 'w') as f:
    f.write(content)

print("REMOVED BLOCK:")
print(removed_block)
print("--- done ---")
