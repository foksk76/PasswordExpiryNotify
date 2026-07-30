param(
    [int]$Threshold = 14,
    [string]$Message = "Ваш пароль доменной учетной записи истекает через {0} дней`n`nДля смены пароля нажмите:`nCtrl + Alt + End → Изменить пароль",
    [string]$Title = "Срок действия пароля"
)

Set-StrictMode -Version Latest

function Get-LargeIntegerValue {
    param($ComObject)
    if ($null -eq $ComObject) { return 0 }
    $type = $ComObject.GetType()
    $high = [int]$type.InvokeMember("HighPart", [System.Reflection.BindingFlags]::GetProperty, $null, $ComObject, $null)
    $low  = [int]$type.InvokeMember("LowPart",  [System.Reflection.BindingFlags]::GetProperty, $null, $ComObject, $null)
    return [int64]$high * 4294967296 + ([int64]$low -band 0xFFFFFFFF)
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
    $user = [ADSI]"LDAP://<SID=$sid>"

    $expiryObj = $user.'msDS-UserPasswordExpiryTimeComputed'.Value

    if ($null -ne $expiryObj) {
        $expiryFileTime = [int64]$expiryObj
        if ($expiryFileTime -eq 9223372036854775807) { exit }
        if ($expiryFileTime -ne 0) {
            $expiryDate = [datetime]::FromFileTime($expiryFileTime)
            $days = ($expiryDate.Date - (Get-Date).Date).Days
            if ($days -le $Threshold -and $days -ge 0) {
                Show-ExpiryWarning -Days $days -Template $Message -Title $Title
            }
            exit
        }
    }

    $uac = [int]$user.userAccountControl.Value
    if ($uac -band 0x10000) { exit }

    $pwdLastSetTicks = Get-LargeIntegerValue ($user.InvokeGet("pwdLastSet"))
    if ($pwdLastSetTicks -eq 0 -or $pwdLastSetTicks -eq 9223372036854775807) { exit }

    $rootDSE = [ADSI]"LDAP://RootDSE"
    $domain = [ADSI]"LDAP://$($rootDSE.defaultNamingContext)"
    $maxPwdAgeTicks = Get-LargeIntegerValue ($domain.InvokeGet("maxPwdAge"))
    if ($maxPwdAgeTicks -lt 0) { $maxPwdAgeTicks = -$maxPwdAgeTicks }
    if ($maxPwdAgeTicks -gt 0) {
        $pwdLastSet = [datetime]::FromFileTime($pwdLastSetTicks)
        $expiryDate = $pwdLastSet.AddTicks($maxPwdAgeTicks)
        $days = ($expiryDate.Date - (Get-Date).Date).Days
        if ($days -le $Threshold -and $days -ge 0) {
            Show-ExpiryWarning -Days $days -Template $Message -Title $Title
        }
    }
}
catch {
    Write-Warning "PasswordExpiryNotify: $_"
}
