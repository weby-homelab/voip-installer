# 2. Use Alpine Linux Base Image

Date: 2026-01-10

## Status

Accepted

## Context

Traditional VoIP distributions (FreePBX, Issabel) are monolithic ISOs based on CentOS or Debian. They include:
* Apache/Nginx (Web Server)
* MySQL/MariaDB (Database)
* PHP (Scripting)
* NodeJS (Realtime features)
* Fail2Ban (Python)
* Asterisk (C)

This stack often exceeds 1GB in size and presents a massive attack surface. Vulnerabilities in PHP or Apache can compromise the PBX. For a "set and forget" secure server, this complexity is a liability.

## Decision

We will use the `andrius/asterisk` image based on **Alpine Linux**.

## Consequences

**Positive:**
* **Size:** ~60MB vs >1GB. Faster downloads and backups.
* **Security:** No Web UI, no SQL database, no PHP. The only exposed attack surface is the SIP stack itself.
* **Performance:** Alpine uses `musl` libc, which is lightweight and memory-efficient.

**Negative:**
* **Usability:** No GUI. All configuration must be done via config files (IaC).
* **Compatibility:** Some proprietary binary codecs (e.g., G.729) might be harder to install on `musl` systems than `glibc`.

**Mitigation:**
We use a shell script generator (`install.sh`) to abstract the complexity of configuration files, providing a CLI-based setup experience that rivals a GUI in speed, if not in discoverability.
