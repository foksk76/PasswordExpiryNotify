# Проблема: уведомление об истечении пароля не видно при RDP

## Сценарий

Windows 10/11, доменная машина. Пользователь подключается по RDP к своей сессии. Пароль истекает через 5–15 дней. Уведомление (MessageBox) появляется и быстро исчезает, пока пользователь не смотрит на экран.

При повторном подключении RDP пользователь попадает в уже существующую (disconnected) сессию — логон-скрипт не запускается, уведомления нет.

## Доказанные причины

### 1. Логон-скрипт не выполняется при реконнекте
Скрипт запускается один раз при создании новой сессии. При подключении к disconnected-сессии — не запускается.

### 2. Встроенный GPO не помогает
Политика *Interactive logon: Prompt user to change password before expiration* срабатывает только при интерактивном входе. Реконнект к RDP-сессии таковым не является.

### 3. MessageBox за экраном блокировки
Если сессия заблокирована (Win+L, screensaver) — окно предупреждения висит за экраном входа, пользователь его не видит.

### 4. MessageBox теряется среди окон
При переключении внимания или окон предупреждение может быть закрыто или остаться под другими окнами.

### 5. Ctrl+Alt+Del vs Ctrl+Alt+End
В RDP нужно нажимать Ctrl+Alt+End (не Ctrl+Alt+Del). Пользователи не знают этой комбинации.

## Источники

- [ServerFault: Enabling password expiry notification for RDP connections](https://serverfault.com/questions/828232/enabling-password-expiry-notification-for-rdp-connections)
- [Microsoft Learn: Prompt user to change password before expiration](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/interactive-logon-prompt-user-to-change-password-before-expiration)
- [Woshub: How to Change a User Password in RDP Session](https://woshub.com/change-user-password-rdp-session-windows/)
- [Spiceworks: Remote user not getting password expiration notification](https://community.spiceworks.com/t/fully-remote-user-not-getting-windows-password-expiration-notification/949414)
- [SpecopsSoft: Password expiration notifications for remote users](https://specopssoft.com/blog/password-expiration-notification)

## Решение: Scheduled Task с триггером на unlock

Скрипт без изменений. Деплой — через GPO Preferences → Scheduled Tasks. Триггеры:

- **At logon** — для новых сессий
- **At unlock** — срабатывает при реконнекте к disconnected-сессии (пользователь разблокирует экран)
- **Every 4 hours** — для длинных сессий

### XML шаблон для импорта в Task Scheduler

```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Password expiry notification</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
    <SessionStateChangeTrigger>
      <StateChange>SessionUnlock</StateChange>
      <Enabled>true</Enabled>
    </SessionStateChangeTrigger>
    <CalendarTrigger>
      <Repetition>
        <Interval>PT4H</Interval>
        <Duration>P1D</Duration>
      </Repetition>
      <Enabled>true</Enabled>
    </CalendarTrigger>
  </Triggers>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell</Command>
      <Arguments>-WindowStyle Hidden -File "\\domain.local\sysvol\scripts\PasswordExpiryNotify.ps1" -Threshold 14</Arguments>
    </Exec>
  </Actions>
</Task>
```

### Деплой через GPO

```
Computer Config → Preferences → Control Panel Settings → Scheduled Tasks
  → New → Scheduled Task (Windows 10+)
    Name: PasswordExpiryNotify
    Security options: Run only when user is logged on
    Configure for: Windows 10
    Triggers:
      - Begin task: At logon
      - Begin task: At unlock
      - Daily, repeat every 4 hours, duration: 1 day
    Action: Start a program
      Program: powershell
      Arguments: -WindowStyle Hidden -File "\\domain.local\NETLOGON\PasswordExpiryNotify.ps1" -Threshold 14
```

### Ручная установка на одной машине

```powershell
# SessionStateChange (unlock) не поддерживается New-ScheduledTaskTrigger
# Используем schtasks.exe:
schtasks /create /tn "PasswordExpiryNotify" /xml "C:\scripts\task.xml" /ru "%USERDOMAIN%\%USERNAME%"

# Или через Register-ScheduledTask с XML:
Register-ScheduledTask -TaskName "PasswordExpiryNotify" `
  -Xml (Get-Content "C:\scripts\task.xml" -Raw) `
  -Force
```

### Альтернативы (без изменения скрипта)

- **Email-уведомления** — SMTP-письма не зависят от RDP-сессии
- **Ярлык смены пароля** — .lnk на рабочем столе, вызывающий `(New-Object -COM Shell.Application).WindowsSecurity()`
- **RDWeb** — страница смены пароля через RD Web Access
