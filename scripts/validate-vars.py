#!/usr/bin/env python3
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[1]
text = "\n".join(p.read_text() for p in root.glob("roles/**/templates/*") if p.is_file())
used = set(re.findall(r"{{\s*([a-zA-Z_][a-zA-Z0-9_]*)", text))
defs = "\n".join(p.read_text() for p in list(root.glob("roles/**/defaults/main.yml")) + [root / "inventories/example/group_vars/all.yml"])
missing = sorted(v for v in used if not re.search(rf"(?m)^{re.escape(v)}:", defs) and v not in {"item", "path", "ansible_distribution_release", "openclaw_secrets"})
if missing:
    print("undefined template variables:", ", ".join(missing), file=sys.stderr); sys.exit(1)
print("template variables: ok")
