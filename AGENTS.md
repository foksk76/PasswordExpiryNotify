# AGENTS.md

## What this is

A single PowerShell script that warns domain users about expiring passwords. Windows-only, domain-joined machines.

## File

- `PasswordExpiryNotify.ps1` — entrypoint and only file

## How it works

- Queries AD via ADSI with current user's SID
- Reads `msDS-UserPasswordExpiryTimeComputed`
  - `9223372036854775807` — password never expires → silent exit
  - `0` or `$null` — checks `userAccountControl` for DONT_EXPIRE_PASSWD (0x10000); if not set, falls back to `pwdLastSet` + domain `maxPwdAge`
- Fallback uses `InvokeGet("pwdLastSet")` and `InvokeGet("maxPwdAge")` (not direct property access — ADSI returns `IADsLargeInteger` COM objects that require `HighPart`/`LowPart` conversion via `InvokeMember`)
- `Get-LargeIntegerValue` helper converts `IADsLargeInteger` to `[int64]` using `[int64]$high * 4294967296 + ([int64]$low -band 0xFFFFFFFF)`
- Shows a `MessageBox` warning when expiry ≤ `-Threshold`
- Silent exit on any error (logged via `Write-Warning`)
- Early exit if not domain-joined (`Win32_ComputerSystem.PartOfDomain`)

## Usage

```powershell
# Run once (logon script or scheduled task)
powershell -ExecutionPolicy Bypass -File PasswordExpiryNotify.ps1
powershell -ExecutionPolicy Bypass -File PasswordExpiryNotify.ps1 -Threshold 10
powershell -ExecutionPolicy Bypass -File PasswordExpiryNotify.ps1 -Message "Custom text with {0} days"
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
- See `README.md#проблема-rdp` — logon scripts don't re-run on RDP reconnect. Solution: deploy via Scheduled Task with RemoteConnect trigger
