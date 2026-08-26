# Disaster recovery

1. Obtain a replacement Pi 5, install current 64-bit Raspberry Pi OS, patch it,
   and restore the administrative SSH key.
2. Recover this repository from its remote or a verified archive. If the
   controller was lost, create a clean controller and reinstall Ansible/SOPS;
   never copy untrusted caches.
3. Retrieve the age identity from offline encrypted custody, verify its public
   recipient matches `.sops.yaml`, set `SOPS_AGE_KEY_FILE`, and decrypt only in
   memory via Ansible. Never place the identity in the repository or on the Pi.
4. Update production inventory for the new Pi address. If the Mac address or
   hostname changed, update `inference_host` and `inference_base_url`, then test
   its API from the Pi network.
5. Run `make check`, `make diff`, and `make provision`. Confirm services are
   healthy before restoring state.
6. List Restic snapshots, select an explicit known-good ID, and restore into an
   empty staging directory. Verify files, dates, and ownership. Stop OpenClaw,
   retain a copy of any new state, and deliberately copy staged mutable state to
   `/var/lib/openclaw`; never restore over a running database.
7. Re-run provisioning to enforce ownership, then `make verify`. Test the SSH
   tunnel, gateway authentication, inference response, SearXNG host connectivity,
   sandbox network denial, a new backup, and `restic check`.

Perform a recovery drill at least quarterly: restore a selected snapshot to
staging, validate age recovery from each escrow location, record recovery time,
and delete the staging copy securely. Annually rehearse replacement-Pi recovery.

