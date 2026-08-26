# Intentional workspace seed

The role-managed `AGENTS.md`, `SOUL.md`, and `TOOLS.md` live under
`roles/openclaw/files/`. Runtime memory and state are private mutable data under
`/var/lib/openclaw` and are covered by Restic, never Git.

