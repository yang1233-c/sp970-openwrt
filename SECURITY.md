# Security policy

## Reporting

Please report security issues privately through GitHub's **Report a
vulnerability** feature rather than a public issue. Include the affected commit,
hardware revision and a minimal reproduction.

## Repository hygiene

Do not attach factory dumps, modem NV content, rollback preimages, SIM
identifiers, device serials, access tokens, SSH keys, RF captures or private
network inventories to issues or pull requests. Redact host usernames and local
paths from logs.

## Deployment boundary

Deployment scripts validate expected hashes and retain rollback metadata, but
partition layout and factory content vary between devices. Confirm the target
partition map and preserve readback-verified preimages before persistent writes.
