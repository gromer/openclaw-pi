# Intentional workspace seed

The role-managed starter `AGENTS.md`, `SOUL.md`, and `TOOLS.md` live under
`roles/openclaw/files/` and are installed only when the destination file is
absent. Runtime memory and state are private mutable data under
`/home/gromer/.openclaw`; include them in a protected Restic backup only after
configuring and rehearsing that backup. They never belong in Git.

