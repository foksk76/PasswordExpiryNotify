# AGENTS.md

## What this is

A single PowerShell script that warns domain users about expiring passwords. Windows-only, domain-joined machines.

## File

- `PasswordExpiryNotify.ps1` — entrypoint and only file

## How it works

- Queries AD via ADSI with current user's SID
- Reads `msDS-UserPasswordExpiryTimeComputed` — null/0/9223372036854775807 means password never expires
- Shows a `MessageBox` warning when expiry ≤ `-Threshold`
- Silent exit on any error (logged via `Write-Warning`)

## Usage

```powershell
# Run once (logon script or scheduled task)
powershell -File PasswordExpiryNotify.ps1
powershell -File PasswordExpiryNotify.ps1 -Threshold 10
powershell -File PasswordExpiryNotify.ps1 -Message "Custom text with {0} days"
```

## Parameters

- `-Threshold` — warning period in days (default: 14)
- `-Message` — message template with `{0}` placeholder for days count (default: Russian)
- `-Title` — MessageBox title (default: Russian)

## Constraints

- Requires `PresentationFramework` — available on Windows by default
- No external modules, no test suite
- `Set-StrictMode -Version Latest` must be present at the top of the script, **after** `param()` — PowerShell requires `param()` to be the first executable statement
- `-Message` must contain `{0}` for `-f` operator — an agent should never hardcode a days count
- See `RDP-NOTIFICATION-PROBLEM.md` — logon scripts don't re-run on RDP reconnect. Solution: deploy via Scheduled Task with SessionUnlock trigger
