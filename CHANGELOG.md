# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v4.7.2] - 2026-01-10

### Fixed
- **Critical:** Fixed exit code masking in `ensure_nftables_strict` by separating variable declaration and assignment.
- Updated documentation to reference the correct script name `install.sh` and version `v4.7.2`.

## [v4.7.1] - 2026-01-10

### Fixed
- **Critical:** `detect_ext_ip` now safely checks for `curl` or `wget` existence before execution to prevent crash on minimal systems.
- **Safety:** Replaced unsafe `sed` regex in `read_env_kv` with `grep -F` for robust key-value parsing.
- **Performance:** `detect_asterisk_uid_gid` checks for local docker image existence before attempting run/pull.

## [v4.7.0] - 2026-01-10

### Added
- **Docker Compose V2 Support:** Auto-detection of `docker compose` vs `docker-compose`.
- **NFTables Backups:** Existing tables are backed up to project dir before replacement.
- **Safety:** Atomic file writes using `safe_write` with trap cleanup.
- **Dependencies:** Early check for critical commands (`ss`, `openssl`, `nft`, `docker`).
- **Config:** Added `--asterisk-uidgid` and `--cert-path` options.

### Changed
- **Network:** Switched to absolute paths in `docker-compose.yml` for reliability.
- **TLS:** Made TLS methods configurable via variable.

## [v4.6.2] - 2026-01-09

### Added
- **Safe Mode:** NFTables configuration no longer flushes the entire ruleset, protecting Docker container networking.
- **Structure:** Added `examples/`, `configs/`, `tests/` directories.
- **Docs:** Added `LICENSE` (MIT) and `CONTRIBUTING.md`.
- **Localization:** Added Russian and Ukrainian documentation.

### Security
- **Fail2Ban:** Integration with `iptables-allports` action.
- **SIP:** Enforced TLS 1.3 and SRTP.

## [4.7.3] - 2026-01-23
### Changed
- Enforced 100MB log limit for Systemd Journal (SystemMaxUse=100M).
- Enforced 100MB log limit for Docker containers (20MB x 5 files) via daemon.json.
- Fixed typo in README commands (ft -> nft).
