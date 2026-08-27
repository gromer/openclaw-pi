# Contributing

Thanks for helping improve OpenClaw Pi.

## Scope and safety

- Keep changes focused and idempotent.
- Never commit secrets, private keys, decrypted SOPS data, or machine-specific
  confidential data.
- Treat Docker-group trust boundaries and network exposure changes as
  security-sensitive and document them clearly in `README.md` or `docs/`.

## Local validation

Run the checks appropriate to your change before opening a pull request:

- `make syntax`
- `make lint`
- `make secrets-check`
- `make verify` (requires target host access)

For a full static local pass, run:

```sh
make check
```

Hardware-dependent checks must only be marked as passed if they were run on a
target Raspberry Pi environment.

## Secrets and inventory handling

- `inventories/example` is illustrative and safe to commit.
- `inventories/production` is ignored (except its README) and should remain
  machine-local.
- Store production secrets only in SOPS-encrypted files.

## Branches and pull requests

- Do not work directly on `main`.
- Branch from `origin/main` using a short lowercase prefix:
  `feat/`, `fix/`, `docs/`, `chore/`, `refactor/`, or `security/`.
- Keep commits focused and use imperative commit subjects.
- Open pull requests against `main` unless maintainers direct otherwise.
- In PR descriptions, list checks you ran and explicitly call out any checks you
  could not run (for example, missing Raspberry Pi hardware or credentials).
