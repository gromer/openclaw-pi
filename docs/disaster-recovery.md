# Disaster recovery

1. Obtain a replacement Pi 5, install current 64-bit Raspberry Pi OS, patch it,
   and restore the administrative SSH key.
2. Recover this repository from its remote or a verified archive. If the
   controller was lost, create a clean controller and reinstall Ansible/SOPS;
   never copy untrusted caches.
3. Choose your SOPS custody mode before recovery:
   - convenience/local mode: restore the root-only identity to
     `/root/.config/sops/age/keys.txt` on the Pi, then back it up offline again;
   - controller mode (stronger): keep the private identity off-Pi and stage it on
     the Pi only for explicit decrypt/provision steps, then remove it.
   In both modes, verify the public recipient with `age-keygen -y` and confirm it
   matches `.sops.yaml` before decrypting.
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

If any age identity copy is missing, tampered, or exposed: freeze changes, rotate
the age identity and SOPS recipient, re-encrypt secrets, regenerate service
tokens, reprovision, and invalidate leaked credentials.

Perform a recovery drill at least quarterly: restore a selected snapshot to
staging, validate age recovery from each escrow location, record recovery time,
and delete the staging copy securely. Annually rehearse replacement-Pi recovery.
