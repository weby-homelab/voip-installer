# 🛠️ VoIP Installer Tools

A collection of utility scripts to maintain, develop, and manage the **VoIP Installer** project.

---

## 🚀 Release Manager (`release.sh`)

Automates the version bump process across the codebase and trilingual documentation.

### Why use it?
The project maintains documentation in **English**, **Russian**, and **Ukrainian**. Manually updating version numbers in `install.sh` and 3 separate `README` files is error-prone. This tool ensures consistency.

### Usage

Run from the project root:

```bash
./tools/release.sh <new_version>
```

### Example

To upgrade from `v4.7.6` to `v4.7.7`:

```bash
./tools/release.sh 4.7.7
```

**What it does:**
1.  Updates the `VERSION` variable in `install.sh`.
2.  Updates the Version Header in `README.md`, `README_RUS.md`, and `README_UKR.md`.
3.  Replaces all text references (e.g., "script v4.7.6") in documentation.
4.  Generates the git commands to commit and tag the release.

---

## 🔄 SSH Port Changer (`ssh-port-changer`)

*(Located in `ssh-port-changer/` subdirectory)*

A standalone utility to safely change the SSH port on remote servers, updating firewall rules (UFW/NFTables) automatically to prevent lockouts.

---

### 📂 Directory Structure

```text
tools/
├── release.sh          # Version automation
├── README.md           # This file
└── ssh-port-changer/   # SSH Port Helper
```

---

<br>
<p align="center">
  Built in Ukraine under air raid sirens &amp; blackouts ⚡<br>
  &copy; 2026 Weby Homelab
</p>
