# Security Policy

## Scope

os-doctor runs as your user (and occasionally with elevated privileges) to configure your shell, install tools, and harden the OS. Because of that, vulnerabilities here can directly affect a developer's workstation. Please take the following classes of issue seriously:

- Command injection via unquoted expansion in shell profiles or install scripts
- Privilege escalation bugs in `doctor fix`, `install`, or the `optimize_*` scripts
- Downloads from untrusted sources, missing checksum/signature verification
- Hardening actions that silently weaken security (e.g., disabling a firewall, lowering TLS minimums)
- Insecure defaults that leak credentials, tokens, or SSH keys

## Reporting a vulnerability

**Please do not open a public GitHub issue for security problems.**

Instead, report privately via GitHub's "Report a vulnerability" button on the Security tab of this repository, or email the maintainer.

Include:
- A description of the issue and its impact
- Steps to reproduce (platform, shell, exact commands)
- Any suggested mitigation

You can expect an acknowledgement within a reasonable timeframe and a status update as the fix progresses. Once patched, we will credit you in the release notes unless you prefer to remain anonymous.

## Supported versions

Only the latest `main` branch is supported. Fixes are not backported.

## Safe-by-default principles

Contributions should preserve these invariants:

- Destructive actions (`docker-nuke`, `rm`) require confirmation
- Elevation is requested up front, not partway through a script
- Hardening profiles default to the safer option; stricter profiles are opt-in
- No credentials, tokens, or keys are ever logged or echoed
- All network downloads use HTTPS and, where available, verify checksums or signatures
