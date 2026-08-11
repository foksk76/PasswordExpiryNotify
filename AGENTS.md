# AGENTS.md

## What this is

Two PowerShell scripts that warn domain users about expiring passwords. Windows-only, domain-joined machines. Choose the script at deploy time depending on infosec (ИБ) policy:

- `PasswordExpiryNotify.ps1` — warning only (for orgs where client-side password change is forbidden)
- `PasswordExpiryNotifyChange.ps1` — warning + in-script password change via clipboard paste (for orgs where it's allowed)

## Files

- `PasswordExpiryNotify.ps1` — warning-only script
- `PasswordExpiryNotifyChange.ps1` — warning + password-change dialog (based on the first; keep them in sync — see spec `SPEC.md`)
- `SPEC.md` / `PLAN.md` — spec and plan for the change-dialog feature

## How it works (both scripts)

- Queries AD via ADSI with current user's SID
- Reads `msDS-UserPasswordExpiryTimeComputed`
  - `9223372036854775807` — password never expires → silent exit
  - `0` or `$null` — checks `userAccountControl` for DONT_EXPIRE_PASSWD (0x10000); if not set, falls back to `pwdLastSet` + domain `maxPwdAge`
- Fallback uses `InvokeGet("pwdLastSet")` and `InvokeGet("maxPwdAge")` (not direct property access — ADSI returns `IADsLargeInteger` COM objects that require `HighPart`/`LowPart` conversion via `InvokeMember`)
- `Get-LargeIntegerValue` helper converts `IADsLargeInteger` to `[int64]` using `[int64]$high * 4294967296 + ([int64]$low -band 0xFFFFFFFF)`
- Shows a warning when expiry ≤ `-Threshold`
- Silent exit on any error (logged via `Write-Warning`)
- Early exit if not domain-joined (`Win32_ComputerSystem.PartOfDomain`)

## How the change script differs

- Warning is a WPF window with «Сменить пароль» / «Позже» buttons (custom dialog, because MessageBox can't have custom buttons)
- «Сменить пароль» opens a WPF dialog with three `PasswordBox` fields (current / new / confirm), each with a «Вставить из буфера» button reading `Get-Clipboard -Raw`; plain `Ctrl+V` also works
- Password is changed via `IADsUser.ChangePassword` on the already-bound `LDAP://<SID=...>` object; on error falls back to `WinNT://$env:USERDOMAIN/$env:USERNAME` (SANS ISC 28036). No admin rights — do NOT use `SetPassword` / `Set-ADAccountPassword` / `net user`
- Validates: all fields non-empty, new == confirm; errors (wrong old password, domain password policy) are shown inline and the dialog stays open
- Clears the clipboard (`Set-Clipboard $null`) only after a successful change
- Passwords stay in memory only (`PasswordBox.Password` / locals); never logged or written to disk
- Requires the interactive user session (scheduled task under User Configuration) — WPF `ShowDialog()` needs an STA thread (powershell.exe 5.1 default)

## Usage

```powershell
# Run once (logon script or scheduled task) — same params for both scripts
powershell -ExecutionPolicy AllSigned -File PasswordExpiryNotify.ps1
powershell -ExecutionPolicy AllSigned -File PasswordExpiryNotifyChange.ps1 -Threshold 10
powershell -ExecutionPolicy AllSigned -File PasswordExpiryNotifyChange.ps1 -Message "Custom text with {0} days"
```

## Parameters

- `-Threshold` — warning period in days (default: 14; validated `[ValidateRange(1, [int]::MaxValue)]`)
- `-Message` — message template with `{0}` placeholder for days count (default: Russian; validated `[ValidateScript({ $_ -match '\{0(:[^}]*)?\}' })]` — format specifiers like `{0:00}` are allowed)
- `-Title` — window title (default: Russian)

## Constraints

- Requires `PresentationFramework` — available on Windows by default
- No external modules, no test suite
- `Set-StrictMode -Version Latest` must be present at the top of the script, **after** `param()` — PowerShell requires `param()` to be the first executable statement
- `-Message` must contain a `{0}` placeholder for the `-f` operator (format specifiers like `{0:00}` are allowed) — an agent should never hardcode a days count
- `-Threshold` must stay ≥ 1 — a negative or zero threshold silently disables the warning (`$days -ge 0 -and $days -le $Threshold` can never match)
- See `README.md#проблема-rdp` — logon scripts don't re-run on RDP reconnect. Solution: deploy via Scheduled Task with RemoteConnect trigger

## Security: signing

- The deployment enforces `AllSigned` via GPO ("Turn on Script Execution" → "Allow only signed scripts") — unsigned scripts are rejected on client machines even with `-ExecutionPolicy Bypass`
- The deployed script (`PasswordExpiryNotify.ps1` OR `PasswordExpiryNotifyChange.ps1`, per ИБ policy) MUST be signed with a code-signing certificate before every deployment; any edit to the file invalidates the signature, so **re-sign after every change** (see `README.md#1-подпись-скрипта`)
- Sign a *deployed copy* (deploy folder or NETLOGON), not the repo file — `Set-AuthenticodeSignature` modifies the file, which would dirty the git tree; keep the repo file unsigned
- For a self-signed code-signing certificate, client machines need it in BOTH Trusted Root and TrustedPublisher stores, or `AllSigned` rejects the signature (see `README.md#2-запрет-запуска-неподписанных-скриптов-gpo`)
- Never use `-ExecutionPolicy Bypass` in docs, scheduled tasks, or examples — use `AllSigned`
