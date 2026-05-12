# da-sync — DirectAdmin Backup SFTP Sync Script

**Automatically sync DirectAdmin backups to offsite SFTP storage with retention management.**

Built and maintained by [HostRainbow](https://hostrainbow.in) — Web Hosting & VPS Provider.

---

## What is da-sync?

DirectAdmin's built-in backup scheduler creates backups on your server but has **no native offsite transfer**. If your server gets compromised, hacked, or the disk fails — your backups are gone too.

`da-sync.sh` is a single lightweight bash script that runs after DirectAdmin finishes its backup and:

- Finds the backup archives DA just created
- Uploads them to any SFTP server (Hetzner Storage Box, any VPS, any SFTP host)
- Automatically deletes old backup folders based on your retention settings
- Skips already-uploaded files on re-runs (safe to run multiple times)
- Logs everything to `/var/log/da-sync.log`

No dependencies beyond `sshpass` and `sftp`. No database. No daemon. Just one script.

---

## Requirements

- DirectAdmin server (AlmaLinux, CentOS, CloudLinux, Ubuntu)
- DirectAdmin Admin Backup configured and running on a schedule
- `sshpass` — `yum install sshpass -y` or `apt install sshpass -y`
- `sftp` — usually pre-installed (`yum install openssh-clients -y`)
- Any SFTP destination: Hetzner Storage Box, another VPS, NAS, etc.

---

## Quick Start

```bash
# 1. Create directory and upload script
mkdir -p /opt/da-sync
# upload da-sync.sh here

# 2. Lock down permissions
chmod +x /opt/da-sync/da-sync.sh
chmod 600 /opt/da-sync/da-sync.sh   # protects your SFTP password

# 3. Edit config section at the top of the script
nano /opt/da-sync/da-sync.sh

# 4. Test with dry run — no files transferred
bash /opt/da-sync/da-sync.sh --dry-run

# 5. Run for real
bash /opt/da-sync/da-sync.sh

# 6. Add to cron — runs at 3:45 AM (after DA finishes at 2:00 AM)
echo "45 3 * * * root bash /opt/da-sync/da-sync.sh" > /etc/cron.d/da-sync
chmod 644 /etc/cron.d/da-sync
```

---

## Configuration

Edit the `CONFIG` section at the top of `da-sync.sh`:

```bash
# Path where DA stores backups (DA Admin Panel → Backup → Where)
DA_BACKUP_BASE="/home/your-admin-user/admin_backups"

# Must match your DA "Where" folder format setting
DA_FOLDER_FORMAT="fulldate"

# SFTP credentials — always use single quotes for password
SFTP_HOST="uXXXXXX.your-storagebox.de"
SFTP_PORT="23"
SFTP_USER="uXXXXXX"
SFTP_PASS='your-password-here'

# Retention
KEEP_LOCAL=7      # keep 7 days of backups on local server
KEEP_REMOTE=14    # keep 14 days of backups on remote SFTP
```

### DA Folder Format Options

Match this to your **DirectAdmin Admin Backup → Where** dropdown setting:

| DA Setting | Set `DA_FOLDER_FORMAT` to | Example path |
|---|---|---|
| Nothing | `nothing` | `/admin_backups/user.tar.zst` |
| Day of Week | `dow` | `/admin_backups/Monday/` |
| Day of Month | `dom` | `/admin_backups/11/` |
| Week of Month | `wom` | `/admin_backups/week-3/` |
| Month | `month` | `/admin_backups/May/` |
| Full Date | `fulldate` | `/admin_backups/2026-05-12/` |

### Password Special Characters

Always use **single quotes** for `SFTP_PASS`:

```bash
SFTP_PASS='my$ecure!Pass@word'   # correct — single quotes
SFTP_PASS="my$ecure!Pass@word"   # wrong — bash interprets $ and !
```

---

## Hetzner Storage Box Setup

Hetzner Storage Box is the recommended SFTP destination — fast transfers within Hetzner network, affordable pricing, and reliable.

```bash
# Recommended settings for Hetzner Storage Box
SFTP_HOST="uXXXXXX.your-storagebox.de"
SFTP_PORT="23"                          # use port 23, not 22
SFTP_USER="uXXXXXX"
SFTP_PASS='your-storagebox-password'
REMOTE_PATH="/"                         # use / if connecting as a subuser
```

**Subuser tip:** Create a dedicated subuser in Hetzner Console → Storage Box → Subaccounts. Restrict it to a specific folder. Set `REMOTE_PATH="/"` — the subuser's root is already their restricted folder.

---

## Usage

```bash
# Normal run
bash /opt/da-sync/da-sync.sh

# Dry run — simulate without transferring anything
bash /opt/da-sync/da-sync.sh --dry-run
```

### How re-run skipping works

After a successful upload, da-sync creates a `.synced` marker file next to each archive:

```
admin_backups/2026-05-12/user.bwinnirmal.tar.zst
admin_backups/2026-05-12/user.bwinnirmal.tar.zst.synced  ← created after upload
```

On the next run, files with a `.synced` marker are skipped. This means it's safe to run the script multiple times — it won't re-upload files already transferred.

To force a re-upload:
```bash
rm /home/admin/admin_backups/2026-05-12/*.synced
bash /opt/da-sync/da-sync.sh
```

---

## Retention

da-sync automatically removes old backup folders to prevent disk and Storage Box from filling up.

- **Local:** keeps the N most recent dated folders on your DA server (`KEEP_LOCAL=7` = 7 days)
- **Remote:** keeps the N most recent dated folders on SFTP (`KEEP_REMOTE=14` = 14 days)

Rotation runs at the end of every sync automatically.

---

## Cron Timing

DirectAdmin runs backups at the time you configured (e.g. 2:00 AM). Schedule da-sync to run **after** DA finishes — 3:45 AM is a safe buffer for most setups:

```bash
# /etc/cron.d/da-sync
45 3 * * * root bash /opt/da-sync/da-sync.sh
```

For servers with many large accounts, use 4:00 AM to be safe:
```bash
0 4 * * * root bash /opt/da-sync/da-sync.sh
```

---

## Supported Archive Formats

DA creates backups in different formats depending on version. da-sync detects all of them:

- `.tar.zst` — DirectAdmin default (newer versions, Zstandard compression)
- `.tar.gz` — older DirectAdmin versions
- `.tar.bz2` — bzip2 compressed
- `.zip` — zip format

---

## Log Output Example

```
[2026-05-12 03:45:01] ========================================
[2026-05-12 03:45:01] da-sync.sh — HostRainbow (hostrainbow.in)
[2026-05-12 03:45:01] Source  : /home/admin/admin_backups/2026-05-12
[2026-05-12 03:45:01] Remote  : uXXXXXX.your-storagebox.de:2026-05-12
[2026-05-12 03:45:01] Files   : 8
[2026-05-12 03:45:02] UPLOAD: user1.tar.zst (4.2G)
[2026-05-12 03:45:18] OK: user1.tar.zst
[2026-05-12 03:45:18] UPLOAD: user2.tar.zst (8.1G)
[2026-05-12 03:45:41] OK: user2.tar.zst
[2026-05-12 03:47:14] --- Local retention: keeping 7 most recent ---
[2026-05-12 03:47:14] DELETE local folder: /home/admin/admin_backups/2026-05-04
[2026-05-12 03:47:14] --- Remote retention: keeping 14 most recent ---
[2026-05-12 03:47:15] Remote has 8 folder(s) — no cleanup needed
[2026-05-12 03:47:15] ========================================
[2026-05-12 03:47:15] Done — Synced: 8 | Skipped: 0 | Errors: 0
[2026-05-12 03:47:15] ========================================
```

---

## Security

- **`chmod 600 da-sync.sh`** — SFTP password is stored in the script; make it readable only by root
- Never commit `da-sync.sh` with real credentials to a public repository
- For passwordless auth, Hetzner Storage Box supports SSH keys — upload via `cat ~/.ssh/id_ed25519.pub | ssh -p23 uXXXXXX@uXXXXXX.your-storagebox.de install-ssh-key` then leave `SFTP_PASS` blank and add `-o IdentityFile=~/.ssh/id_ed25519` to the sftp options

---

## Troubleshooting

**"Backup folder not found"**
DA hasn't finished running yet, or `DA_FOLDER_FORMAT` doesn't match your DA setting. Check:
```bash
ls /home/your-admin-user/admin_backups/
# See what folder name DA created, match DA_FOLDER_FORMAT accordingly
```

**"Permission denied" on SFTP**
Password is wrong, or double quotes are breaking special characters. Use single quotes:
```bash
SFTP_PASS='your$password!'   # single quotes always
```

**Files uploading again even after success**
The `.synced` marker files were deleted. This is safe — they'll be recreated after upload.

**Script runs but nothing uploads (dry-run mode)**
Remove `--dry-run` from your cron entry or manual run command.

---

## About HostRainbow

[HostRainbow](https://hostrainbow.in) is a web hosting provider based in India offering shared hosting, VPS, dedicated servers, and offshore hosting. This script was built and battle-tested on our own DirectAdmin infrastructure.

- Website: [hostrainbow.in](https://hostrainbow.in)
- Hosting: Shared, VPS, Dedicated, Offshore

---

## License

MIT License — free to use, modify, and distribute. Attribution appreciated.

---

## Contributing

Pull requests welcome. If you've tested this with a specific SFTP provider or DA version, feel free to add notes to the README.
