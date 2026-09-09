#!/usr/bin/env python3
"""Merge the repository's managed settings into an existing settings.json.

install-home.sh used to install settings.json with a plain `cp`. That is right
for a CLAUDE.md and wrong for settings: the live file carries machine state the
repository has never heard of - the model, enabled plugins, statusLine, MCP
server enablement - and copying over it deletes every one of them. The backup
lets you recover by hand; it does not stop the loss.

The policy here is additive, and deliberately so:

  objects   merged key by key, recursively.
  arrays    unioned, existing order first. A deny rule already on the machine
            survives an install that does not mention it.
  scalars   the repository wins, but only for a key the repository actually
            supplies. Everything else is left exactly as it was found.

The cost of "additive" is that it never removes anything. Dropping a managed
deny rule from home/settings.json does not drop it from an installed machine;
that needs an explicit migration. Prefer that over an installer that can delete
a protection nobody remembered was there.

Invalid JSON in either file is an error, not a reason to overwrite: a settings
file we cannot parse is a settings file we must not replace.

Usage: merge-settings.py <existing> <managed> <output>
"""

import json
import sys
from pathlib import Path


def merge(existing, managed):
    if isinstance(existing, dict) and isinstance(managed, dict):
        result = dict(existing)
        for key, value in managed.items():
            result[key] = merge(result[key], value) if key in result else value
        return result
    if isinstance(existing, list) and isinstance(managed, list):
        result = list(existing)
        for value in managed:
            if value not in result:
                result.append(value)
        return result
    return managed


def read_object(path, missing_ok=False):
    if missing_ok and not path.exists():
        return {}
    try:
        value = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f'{path}: not valid JSON ({exc}); refusing to replace it')
    if not isinstance(value, dict):
        raise SystemExit(f'{path}: settings must be a JSON object')
    return value


def main(argv):
    if len(argv) != 3:
        raise SystemExit('usage: merge-settings.py <existing> <managed> <output>')
    existing_path, managed_path, output_path = map(Path, argv)
    existing = read_object(existing_path, missing_ok=True)
    managed = read_object(managed_path)
    output_path.write_text(json.dumps(merge(existing, managed), indent=2) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
