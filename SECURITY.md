# Security Policy

## Supported Versions

JblOnMac has no tagged releases yet. Only the latest commit on `master` gets security fixes.

| Version         | Supported          |
| --------------- | ------------------ |
| `master`        | :white_check_mark: |
| Older commits   | :x:                |

## Reporting a Vulnerability

Please don't report vulnerabilities in public issues, pull requests, or discussions.

Report them privately through GitHub: go to the
[Security tab](https://github.com/aimpr0xy/jbl-on-mac/security) and select **Report a vulnerability**.
Include:

- What the issue is and what an attacker could do with it.
- Steps to reproduce, and the macOS version, Mac model, and headphone model you used.
- Any logs or packet captures that show the problem. Bluetooth traces can include data from other
  nearby devices and your Apple Account details, so trim them to the relevant packets first
  (see [CONTRIBUTING.md](CONTRIBUTING.md)).

### What to expect

This is a hobby project maintained in spare time, so these are targets, not guarantees:

- A first reply within 7 days.
- An update at least every 14 days until the report is resolved.
- If the report is accepted, a fix on `master` and a GitHub security advisory that credits you,
  unless you'd rather stay anonymous. Please don't disclose the issue publicly until the fix is out.
- If the report is declined, an explanation of why.

### Scope

In scope: the JblOnMac app and its code in this repository, for example how it parses data from
headphones over Bluetooth, what it writes to logs, and its sandbox entitlements.

Out of scope: vulnerabilities in JBL firmware, the headphones' Bluetooth stack, or macOS itself.
Report those to Harman or Apple.
