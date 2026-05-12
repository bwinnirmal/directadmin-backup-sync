# da-sync — DirectAdmin Backup SFTP Sync Script

**Automatically sync DirectAdmin backups to offsite SFTP storage with Telegram notifications and retention management.**

Built and maintained by [HostRainbow](https://hostrainbow.in) — Web Hosting & VPS Provider.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-blue.svg)](da-sync.sh)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-lightgrey.svg)](da-sync.sh)

---

## What is da-sync?

DirectAdmin's built-in backup scheduler creates backups on your server but has **no native offsite transfer**. If your server gets compromised, hacked, or the disk fails — your backups are gone too.

`da-sync.sh` is a single lightweight bash script that runs after DirectAdmin finishes its backup and:

- 📦 Finds the backup archives DA just created
- ☁️ Uploads them to any SFTP server (Hetzner Storage Box, any VPS, any SFTP host)
- 🗑️ Automatically deletes old backup folders based on your retention settings
- 🔔 Sends Telegram notifications — success, failure, partial, or skipped
- ⏭️ Skips already-uploaded files on re-runs (safe to run multiple times)
- 📝 Logs everything to `/var/log/da-sync.log`

No dependencies beyond `sshpass`, `sftp`, and `curl`. No database. No daemon. Just one script.

---

## Requirements

- DirectAdmin server (AlmaLinux, CentOS, CloudLinux, Ubuntu)
- DirectAdmin Admin Backup configured and running on a schedule
- `sshpass` — `yum install sshpass -y` or `apt install sshpass -y`
- `sftp` — usually pre-installed (`yum install openssh-clients -y`)
- `curl` — for Telegram notifications (`yum install curl -y`)
- Any SFTP destination: Hetzner Storage Box, another VPS, NAS, etc.

---

## Quick Start

```bash
# 1. Create directory and upload script
mkdir -p /opt/da-sync

# 2. Upload da-sync.sh then lock down permissions
chmod +x /opt/da-sync/da-sync.sh
chmod 600 /opt/da-sync/da-sync.sh   # protects your SFTP password

# 3. Edit the config section at the top of the script
nano /opt/da-sync/da-sync.sh

# 4. Test with dry run — no files transferred, no Telegram sent
bash /opt/da-sync/da-sync.sh --dry-run

# 5. Run for real
bash /opt/da-sync/da-sync.sh

# 6. Add to cron — runs at 3:45 AM (after DA finishes at 2:00 AM)
echo "45 3 * * * root bash /opt/da-sync/da-sync.sh" > /etc/cron.d/da-sync
chmod 644 /etc/cron.d/da-sync
```

---

## Configuration

Edit the `CONFIG` section at the top of `da-sync.sh`. Everything is in one place — no separate config file.

### DA Backup Settings

```bash
# Path where DA stores backups (DA Admin Panel → Backup → Where)
DA_BACKUP_BASE="/home/your-admin-user/admin_backups"

# Must match your DA "Where" folder format setting
DA_FOLDER_FORMAT="fulldate"
```

### DA Folder Format Options

Match this to your **DirectAdmin → Admin Backup and Restore → Where** dropdown:

| DA Panel Setting | `DA_FOLDER_FORMAT` value | Example path created |
|---|---|---|
| Nothing | `nothing` | `/admin_backups/user.tar.zst` |
| Day of Week | `dow` | `/admin_backups/Monday/` |
| Day of Month | `dom` | `/admin_backups/11/` |
| Week of Month | `wom` | `/admin_backups/week-3/` |
| Month | `month` | `/admin_backups/May/` |
| Full Date | `fulldate` | `/admin_backups/2026-05-12/` |

### SFTP Settings

```bash
SFTP_HOST="uXXXXXX.your-storagebox.de"
SFTP_PORT="23"
SFTP_USER="uXXXXXX"
SFTP_PASS='your-sftp-password'   # single quotes always — see note below
REMOTE_PATH="/"
```

> ⚠️ **Always use single quotes for `SFTP_PASS`.** Double quotes cause bash to interpret special characters like `$`, `!`, `@` in your password, breaking authentication silently.
>
> ```bash
> SFTP_PASS='my$ecure!Pass'   # correct
> SFTP_PASS="my$ecure!Pass"   # wrong — bash interprets $ and !
> ```

### Retention Settings

```bash
KEEP_LOCAL=7     # keep 7 days of backups on local server
KEEP_REMOTE=14   # keep 14 days of backups on remote SFTP
```

---

## Telegram Notifications

da-sync sends Telegram messages after every run so you always know your backups are safe.

### Setup

**Step 1** — Create a bot via [@BotFather](https://t.me/BotFather) on Telegram:
```
/newbot → follow prompts → copy the token
```

**Step 2** — Get your Chat ID. Add the bot to your group or start a direct chat, send any message, then run:
```bash
curl "https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates"
# Look for: "chat":{"id": -1001234567890}
```

**Step 3** — Enable in config:
```bash
TELEGRAM_ENABLED=true
TELEGRAM_BOT_TOKEN='123456789:AABBccDDeeffGGhhIIjj'
TELEGRAM_CHAT_ID='-1001234567890'
```

### Notification Types

| Event | Message | Controlled by |
|---|---|---|
| All files synced | ✅ Backup Sync OK | `TELEGRAM_ON_SUCCESS=true` |
| Some synced, some failed | ⚠️ Backup Sync PARTIAL | `TELEGRAM_ON_FAILURE=true` |
| All uploads failed | ❌ Backup Sync FAILED | `TELEGRAM_ON_FAILURE=true` |
| All files already synced | ⏭️ Backup Sync Skipped | `TELEGRAM_ON_SKIP=false` |
| Script error (folder missing etc.) | ❌ DA-Sync ERROR | always sent |

### Example Success Message

```
✅ Backup Sync OK — srv119.yourdomain.com

Date: 2026-05-12
Host: srv119.yourdomain.com
Remote: uXXXXXX.your-storagebox.de:2026-05-12

Files synced (2):
  • admin.root.tar.zst (40K)
  • user.hostrainbow.tar.zst (303M)

Retention: Local 7d / Remote 14d
Duration: 134s

HostRainbow — hostrainbow.in
```

---

## Hetzner Storage Box Setup

Hetzner Storage Box is the recommended SFTP destination — fast internal transfers within the Hetzner network, affordable, and reliable.

```bash
SFTP_HOST="uXXXXXX.your-storagebox.de"
SFTP_PORT="23"
SFTP_USER="uXXXXXX"
SFTP_PASS='your-password'
REMOTE_PATH="/"
```

**Recommended: use a subuser** — create a dedicated subuser in Hetzner Console → Storage Box → Subaccounts. Restrict it to a specific folder with SFTP access only. Set `REMOTE_PATH="/"` so dated backup folders land right at the subuser root.

**SSH key auth (optional)** — Hetzner Storage Box supports SSH keys on port 23:

```bash
cat ~/.ssh/id_ed25519.pub | ssh -p23 uXXXXXX@uXXXXXX.your-storagebox.de install-ssh-key
```

---

## Usage

```bash
# Normal run
bash /opt/da-sync/da-sync.sh

# Dry run — simulate without transferring anything or sending Telegram
bash /opt/da-sync/da-sync.sh --dry-run
```

### Re-run Skipping

After a successful upload, da-sync creates a `.synced` marker file next to each archive. On the next run, those files are skipped. To force a re-upload:

```bash
rm /home/admin/admin_backups/2026-05-12/*.synced
bash /opt/da-sync/da-sync.sh
```

---

## Supported Archive Formats

| Format | Description |
|---|---|
| `.tar.zst` | Default in newer DirectAdmin versions (Zstandard) |
| `.tar.gz` | Older DirectAdmin versions (gzip) |
| `.tar.bz2` | bzip2 compressed |
| `.zip` | zip format |

---

## Cron Timing

```bash
# /etc/cron.d/da-sync
# DA runs at 2:00 AM — sync at 3:45 AM gives a safe buffer
45 3 * * * root bash /opt/da-sync/da-sync.sh

# For large servers with many accounts, use 4:00 AM
0 4 * * * root bash /opt/da-sync/da-sync.sh
```

---

## Log Output Example

```
[2026-05-12 03:45:01] ========================================
[2026-05-12 03:45:01] da-sync.sh — HostRainbow (hostrainbow.in)
[2026-05-12 03:45:01] DRY_RUN : false
[2026-05-12 03:45:01] Source  : /home/admin/admin_backups/2026-05-12
[2026-05-12 03:45:01] Remote  : uXXXXXX.your-storagebox.de:2026-05-12
[2026-05-12 03:45:01] Files   : 2
[2026-05-12 03:45:02] UPLOAD: admin.root.tar.zst (40K)
[2026-05-12 03:45:02] OK: admin.root.tar.zst
[2026-05-12 03:45:02] UPLOAD: user.hostrainbow.tar.zst (303M)
[2026-05-12 03:45:16] OK: user.hostrainbow.tar.zst
[2026-05-12 03:45:16] --- Local retention: keeping 7 most recent ---
[2026-05-12 03:45:16] --- Remote retention: keeping 14 most recent ---
[2026-05-12 03:45:17] Remote has 1 folder(s) — no cleanup needed
[2026-05-12 03:45:17] ========================================
[2026-05-12 03:45:17] Done — Synced: 2 | Skipped: 0 | Errors: 0
[2026-05-12 03:45:17] Duration: 16s
[2026-05-12 03:45:17] ========================================
```

---

## Security

- `chmod 600 da-sync.sh` — SFTP password lives in the script; make it root-readable only
- Never commit a configured script with real credentials to a public repo
- The `.gitignore` excludes `*.synced` marker files and logs automatically

---

## Troubleshooting

**"Backup folder not found"**
```bash
ls /home/your-admin-user/admin_backups/
# Match what you see to the DA_FOLDER_FORMAT table above
```

**"Permission denied" on SFTP**

Use single quotes for the password — double quotes break special characters.

**Telegram notification not arriving**
```bash
# Test manually
curl "https://api.telegram.org/bot<TOKEN>/sendMessage" \
  -d "chat_id=<CHAT_ID>" -d "text=test"

# Also check the log
tail -50 /var/log/da-sync.log
```

---

## About HostRainbow

[HostRainbow](https://hostrainbow.in) is a web hosting provider based in India offering shared hosting, VPS, dedicated servers, and offshore hosting. This script was built and battle-tested on our own DirectAdmin production infrastructure.

- 🌐 [hostrainbow.in](https://hostrainbow.in)
- 🖥️ Shared Hosting · VPS · Dedicated · Offshore Hosting

---

## License

MIT — free to use, modify, and distribute. Attribution appreciated.

---

## Contributing

Pull requests welcome. Tested on a different distro, DA version, or SFTP provider? Open a PR or issue.