#!/bin/bash
# Adds two hooks to Claude Code:
#  - when Claude finishes, the pad flashes orange until you press a key
#  - when Claude asks for permission, the pad flashes yellow
# Edits ~/.claude/settings.json (a backup copy is made first).
set -e
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak-micropad"

/usr/bin/python3 - "$SETTINGS" <<'EOF'
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
hooks = data.setdefault("hooks", {})

def add(event, cmd):
    entries = hooks.setdefault(event, [])
    for e in entries:
        for h in e.get("hooks", []):
            if "micropad://" in h.get("command", ""):
                h["command"] = cmd
                return
    entries.append({"hooks": [{"type": "command", "command": cmd}]})

add("Stop", "open -g 'micropad://flash?color=d97757&times=0&speed=350'")
add("Notification", "open -g 'micropad://flash?color=ffd60a&times=0&speed=150'")

with open(path, "w") as f:
    json.dump(data, f, indent=2)
print("Hooks added to", path)
EOF
