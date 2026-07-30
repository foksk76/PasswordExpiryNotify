Set-StrictMode -Version Latest

param(
    [int]$Threshold = 14,
    [string]$Message = "Ваш пароль доменной учетной записи истекает через {0} дн.`n`nДля смены пароля нажмите:`nCtrl + Alt + End → Изменить пароль",
    [string]$Title = "Срок действия пароля"
)

function Get-ADUserExpiry {
    param([string]$Sid)

    $user = [ADSI]"LDAP://<SID=$Sid>"
    $expiryFileTime = [int64]$user.'msDS-UserPasswordExpiryTimeComputed'.Value

    # 0 — атрибут не задан; 9223372036854775807 (MaxValue FileTime) — never expires
    if ($expiryFileTime -eq 0 -or $expiryFileTime -eq 9223372036854775807) {
        return $null
    }

    return [datetime]::FromFileTime($expiryFileTime)
}

function Show-ExpiryWarning {
    param([int]$Days, [string]$Template, [string]$Title)

    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        $Template -f $Days,
        $Title,
        'OK',
        'Warning'
    ) | Out-Null
}

try {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $expiry = Get-ADUserExpiry -Sid $sid

    if ($null -eq $expiry) {
        exit
    }

    $days = ($expiry.Date - (Get-Date).Date).Days

    if ($days -le $Threshold -and $days -ge 0) {
        Show-ExpiryWarning -Days $days -Template $Message -Title $Title
    }
}
catch {
    Write-Warning "PasswordExpiryNotify: $_"
}
