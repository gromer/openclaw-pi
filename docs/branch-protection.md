# Main-branch protection

Repository settings, rather than files in this repository, enforce merge gates.
For `main`, require pull requests, at least one approving review (two for
security-sensitive changes when practical), approval from `CODEOWNERS`, resolved
conversation threads, the `static` status check from `Validate`, and an
up-to-date branch. Dismiss stale approvals after new commits and block
force-pushes and direct pushes.

Protect the `release` environment with a required maintainer reviewer. Release
tags should be created only from reviewed commits. The release workflow has only
`contents: write` permission and publishes immutable, checksum-verified assets;
it does not request OIDC or attestation permissions because GitHub attestation
is unavailable for private user-owned repositories.

Review action SHAs, CI pins, and workflow changes under `.github/CODEOWNERS` during
dependency updates. The credential-free [`actions-policy-check.sh`](../scripts/actions-policy-check.sh)
fails CI if a workflow action, runner, or Dockerfile base image becomes mutable.
