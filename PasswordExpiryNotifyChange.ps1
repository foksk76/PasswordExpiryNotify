param(
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Threshold = 14,
    [ValidateScript({ $_ -match '\{0(:[^}]*)?\}' })]
    [string]$Message = "Ваш пароль доменной учетной записи истекает через {0} дней`n`nДля смены пароля нажмите кнопку «Сменить пароль»`nили используйте Ctrl + Alt + End → Изменить пароль",
    [string]$Title = "Срок действия пароля"
)

Set-StrictMode -Version Latest

$cs = Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue
if (-not $cs -or -not $cs.PartOfDomain) { exit }

Add-Type -AssemblyName PresentationFramework

function Get-LargeIntegerValue {
    param($ComObject)
    if ($null -eq $ComObject) { return 0 }
    $type = $ComObject.GetType()
    $high = [int]$type.InvokeMember("HighPart", [System.Reflection.BindingFlags]::GetProperty, $null, $ComObject, $null)
    $low  = [int]$type.InvokeMember("LowPart",  [System.Reflection.BindingFlags]::GetProperty, $null, $ComObject, $null)
    # IADsLargeInteger: high * 2^32 + low (as unsigned)
    return [int64]$high * 4294967296 + ([int64]$low -band 0xFFFFFFFF)
}

function Show-WarningDialog {
    param([int]$Days, [string]$Template, [string]$Title)
    # Окно предупреждения на обычном рабочем столе (не secure desktop).
    # Возвращает $true, если нажата кнопка «Сменить пароль».
    $window = New-Object System.Windows.Window
    $window.Title = $Title
    $window.ResizeMode = 'CanResize'
    $window.WindowStartupLocation = 'CenterScreen'
    $window.Topmost = $true
    $window.SizeToContent = 'Height'
    $window.Width = 560
    $window.MaxHeight = 480
    $window.MinWidth = 480

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness -ArgumentList 16

    $text = New-Object System.Windows.Controls.TextBlock
    $text.Text = $Template -f $Days
    $text.TextWrapping = 'Wrap'
    $text.FontSize = 13
    $text.Margin = New-Object System.Windows.Thickness -ArgumentList 0,0,0,16

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = New-Object System.Windows.Thickness -ArgumentList 16,8,16,16

    $btnChange = New-Object System.Windows.Controls.Button
    $btnChange.Content = 'Сменить пароль'
    $btnChange.Width = 140
    $btnChange.IsDefault = $true
    $btnChange.Add_Click({ $window.DialogResult = $true })

    $btnLater = New-Object System.Windows.Controls.Button
    $btnLater.Content = 'Позже'
    $btnLater.Width = 100
    $btnLater.Margin = New-Object System.Windows.Thickness -ArgumentList 8,0,0,0
    $btnLater.IsCancel = $true
    $btnLater.Add_Click({ $window.DialogResult = $false })

    $buttons.Children.Add($btnChange) | Out-Null
    $buttons.Children.Add($btnLater) | Out-Null
    $panel.Children.Add($text) | Out-Null

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.Content = $panel

    # Кнопки вне скролла: фиксированная нижняя строка, скроллится только контент
    $root = New-Object System.Windows.Controls.Grid
    $rowContent = New-Object System.Windows.Controls.RowDefinition
    $rowContent.Height = New-Object System.Windows.GridLength -ArgumentList 1, ([System.Windows.GridUnitType]::Star)
    $rowButtons = New-Object System.Windows.Controls.RowDefinition
    $rowButtons.Height = New-Object System.Windows.GridLength -ArgumentList 0, ([System.Windows.GridUnitType]::Auto)
    $root.RowDefinitions.Add($rowContent) | Out-Null
    $root.RowDefinitions.Add($rowButtons) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($scroll, 0)
    [System.Windows.Controls.Grid]::SetRow($buttons, 1)
    $root.Children.Add($scroll) | Out-Null
    $root.Children.Add($buttons) | Out-Null
    $window.Content = $root

    return ($window.ShowDialog() -eq $true)
}

function Change-ADPassword {
    param($AdUser, [string]$OldPassword, [string]$NewPassword)
    # Смена собственного пароля без прав администратора (IADsUser.ChangePassword).
    # Сначала LDAP-провайдер; при ошибке — фолбэк на WinNT:// (SANS ISC 28036).
    try {
        $AdUser.ChangePassword($OldPassword, $NewPassword)
    }
    catch {
        $winnt = [ADSI]"WinNT://$env:USERDOMAIN/$env:USERNAME"
        $winnt.ChangePassword($OldPassword, $NewPassword)
    }
}

function Set-FromClipboard {
    param([System.Windows.Controls.PasswordBox]$Box)
    $clip = Get-Clipboard -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrEmpty($clip)) {
        # Убираем только перевод строки в конце копии (пробелы в пароле допустимы)
        $Box.Password = ($clip -replace '[\r\n]+$', '')
    }
}

function Show-ChangePasswordDialog {
    param($AdUser, [string]$Title)
    # Диалог на обычном рабочем столе: вставка из буфера обмена работает,
    # в отличие от secure desktop (Ctrl+Alt+Del/End). Возвращает $true при успехе.
    $window = New-Object System.Windows.Window
    $window.Title = "$Title — смена пароля"
    $window.ResizeMode = 'CanResize'
    $window.WindowStartupLocation = 'CenterScreen'
    $window.SizeToContent = 'Height'
    $window.Width = 600
    $window.MaxHeight = 480
    # Минимум по содержимому ряда: подпись 170 + кнопка вставки 150 + поле 200 + паддинги
    $window.MinWidth = 560
    $window.MinHeight = 240

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = New-Object System.Windows.Thickness -ArgumentList 16

    $head = New-Object System.Windows.Controls.TextBlock
    $head.Text = 'Введите текущий и новый пароль.'
    $head.TextWrapping = 'Wrap'
    $head.FontSize = 13
    $head.Margin = New-Object System.Windows.Thickness -ArgumentList 0,0,0,12

    $lblOld = New-Object System.Windows.Controls.TextBlock
    $lblOld.Text = 'Текущий пароль:'
    $lblOld.Width = 170
    $lblOld.FontSize = 13
    $lblOld.VerticalAlignment = 'Center'

    $btnPasteOld = New-Object System.Windows.Controls.Button
    $btnPasteOld.Content = 'Вставить из буфера'
    $btnPasteOld.Width = 150
    $btnPasteOld.Margin = New-Object System.Windows.Thickness -ArgumentList 8,0,0,0

    $txtOld = New-Object System.Windows.Controls.PasswordBox
    $txtOld.Height = 24
    $txtOld.MinWidth = 200
    $txtOld.VerticalAlignment = 'Center'
    $btnPasteOld.Add_Click({ Set-FromClipboard $txtOld })

    $rowOld = New-Object System.Windows.Controls.DockPanel
    $rowOld.Margin = New-Object System.Windows.Thickness -ArgumentList 0,0,0,8
    [System.Windows.Controls.DockPanel]::SetDock($lblOld, 'Left')
    [System.Windows.Controls.DockPanel]::SetDock($btnPasteOld, 'Right')
    $rowOld.Children.Add($lblOld) | Out-Null
    $rowOld.Children.Add($btnPasteOld) | Out-Null
    $rowOld.Children.Add($txtOld) | Out-Null

    $lblNew = New-Object System.Windows.Controls.TextBlock
    $lblNew.Text = 'Новый пароль:'
    $lblNew.Width = 170
    $lblNew.FontSize = 13
    $lblNew.VerticalAlignment = 'Center'

    $btnPasteNew = New-Object System.Windows.Controls.Button
    $btnPasteNew.Content = 'Вставить из буфера'
    $btnPasteNew.Width = 150
    $btnPasteNew.Margin = New-Object System.Windows.Thickness -ArgumentList 8,0,0,0

    $txtNew = New-Object System.Windows.Controls.PasswordBox
    $txtNew.Height = 24
    $txtNew.MinWidth = 200
    $txtNew.VerticalAlignment = 'Center'
    $btnPasteNew.Add_Click({ Set-FromClipboard $txtNew })

    $rowNew = New-Object System.Windows.Controls.DockPanel
    $rowNew.Margin = New-Object System.Windows.Thickness -ArgumentList 0,0,0,8
    [System.Windows.Controls.DockPanel]::SetDock($lblNew, 'Left')
    [System.Windows.Controls.DockPanel]::SetDock($btnPasteNew, 'Right')
    $rowNew.Children.Add($lblNew) | Out-Null
    $rowNew.Children.Add($btnPasteNew) | Out-Null
    $rowNew.Children.Add($txtNew) | Out-Null

    $lblConfirm = New-Object System.Windows.Controls.TextBlock
    $lblConfirm.Text = 'Подтверждение:'
    $lblConfirm.Width = 170
    $lblConfirm.FontSize = 13
    $lblConfirm.VerticalAlignment = 'Center'

    $btnPasteConfirm = New-Object System.Windows.Controls.Button
    $btnPasteConfirm.Content = 'Вставить из буфера'
    $btnPasteConfirm.Width = 150
    $btnPasteConfirm.Margin = New-Object System.Windows.Thickness -ArgumentList 8,0,0,0

    $txtConfirm = New-Object System.Windows.Controls.PasswordBox
    $txtConfirm.Height = 24
    $txtConfirm.MinWidth = 200
    $txtConfirm.VerticalAlignment = 'Center'
    $btnPasteConfirm.Add_Click({ Set-FromClipboard $txtConfirm })

    $rowConfirm = New-Object System.Windows.Controls.DockPanel
    $rowConfirm.Margin = New-Object System.Windows.Thickness -ArgumentList 0,0,0,8
    [System.Windows.Controls.DockPanel]::SetDock($lblConfirm, 'Left')
    [System.Windows.Controls.DockPanel]::SetDock($btnPasteConfirm, 'Right')
    $rowConfirm.Children.Add($lblConfirm) | Out-Null
    $rowConfirm.Children.Add($btnPasteConfirm) | Out-Null
    $rowConfirm.Children.Add($txtConfirm) | Out-Null

    $lblError = New-Object System.Windows.Controls.TextBlock
    $lblError.Foreground = [System.Windows.Media.Brushes]::Red
    $lblError.TextWrapping = 'Wrap'
    $lblError.FontSize = 13
    $lblError.Margin = New-Object System.Windows.Thickness -ArgumentList 0,0,0,8
    $lblError.Visibility = 'Collapsed'

    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $buttons.HorizontalAlignment = 'Right'
    $buttons.Margin = New-Object System.Windows.Thickness -ArgumentList 16,8,16,16

    $btnOk = New-Object System.Windows.Controls.Button
    $btnOk.Content = 'Сменить'
    $btnOk.Width = 100
    $btnOk.IsDefault = $true

    $btnCancel = New-Object System.Windows.Controls.Button
    $btnCancel.Content = 'Отмена'
    $btnCancel.Width = 100
    $btnCancel.Margin = New-Object System.Windows.Thickness -ArgumentList 8,0,0,0
    $btnCancel.IsCancel = $true

    $btnOk.Add_Click({
        $old = $txtOld.Password
        $new = $txtNew.Password
        $confirm = $txtConfirm.Password
        $err = $null
        if ([string]::IsNullOrEmpty($old) -or [string]::IsNullOrEmpty($new) -or [string]::IsNullOrEmpty($confirm)) {
            $err = 'Заполните все поля.'
        }
        elseif ($new -cne $confirm) {
            $err = 'Новый пароль и подтверждение не совпадают.'
        }
        else {
            try {
                Change-ADPassword -AdUser $AdUser -OldPassword $old -NewPassword $new
            }
            catch {
                $err = 'Не удалось сменить пароль: ' + $_.Exception.Message
            }
        }
        $old = $null; $new = $null; $confirm = $null
        if ($null -ne $err) {
            $lblError.Text = $err
            $lblError.Visibility = 'Visible'
        }
        else {
            try { Set-Clipboard $null }
            catch { Write-Warning 'PasswordExpiryNotify: не удалось очистить буфер обмена после смены пароля' }
            [System.Windows.MessageBox]::Show('Пароль изменён.', $Title, 'OK', 'Information') | Out-Null
            $window.DialogResult = $true
        }
    })

    $buttons.Children.Add($btnOk) | Out-Null
    $buttons.Children.Add($btnCancel) | Out-Null
    $panel.Children.Add($head) | Out-Null
    $panel.Children.Add($rowOld) | Out-Null
    $panel.Children.Add($rowNew) | Out-Null
    $panel.Children.Add($rowConfirm) | Out-Null
    $panel.Children.Add($lblError) | Out-Null

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.Content = $panel

    # Кнопки вне скролла: фиксированная нижняя строка, скроллится только контент
    $root = New-Object System.Windows.Controls.Grid
    $rowContent = New-Object System.Windows.Controls.RowDefinition
    $rowContent.Height = New-Object System.Windows.GridLength -ArgumentList 1, ([System.Windows.GridUnitType]::Star)
    $rowButtons = New-Object System.Windows.Controls.RowDefinition
    $rowButtons.Height = New-Object System.Windows.GridLength -ArgumentList 0, ([System.Windows.GridUnitType]::Auto)
    $root.RowDefinitions.Add($rowContent) | Out-Null
    $root.RowDefinitions.Add($rowButtons) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($scroll, 0)
    [System.Windows.Controls.Grid]::SetRow($buttons, 1)
    $root.Children.Add($scroll) | Out-Null
    $root.Children.Add($buttons) | Out-Null
    $window.Content = $root

    $window.Add_Loaded({ $txtOld.Focus() })

    $window.ShowDialog() | Out-Null
}

try {
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $user = [ADSI]"LDAP://<SID=$sid>"

    $expiryObj = $user.'msDS-UserPasswordExpiryTimeComputed'.Value

    if ($null -ne $expiryObj) {
        $expiryFileTime = [int64]$expiryObj
        # Max FileTime — password never expires
        if ($expiryFileTime -eq 9223372036854775807) { exit }
        if ($expiryFileTime -ne 0) {
            $expiryDate = [datetime]::FromFileTime($expiryFileTime)
            $days = ($expiryDate.Date - (Get-Date).Date).Days
            if ($days -le $Threshold -and $days -ge 0) {
                if (Show-WarningDialog -Days $days -Template $Message -Title $Title) {
                    Show-ChangePasswordDialog -AdUser $user -Title $Title
                }
            }
            exit
        }
    }

    $uac = [int]$user.userAccountControl.Value
    # DONT_EXPIRE_PASSWD flag (0x10000) — password never expires
    if ($uac -band 0x10000) { exit }

    $pwdLastSetTicks = Get-LargeIntegerValue ($user.InvokeGet("pwdLastSet"))
    # 0 = never set, Max FileTime = password never expires
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
            if (Show-WarningDialog -Days $days -Template $Message -Title $Title) {
                Show-ChangePasswordDialog -AdUser $user -Title $Title
            }
        }
    }
}
catch {
    Write-Warning "PasswordExpiryNotify: $_"
}
