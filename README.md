# PasswordExpiryNotify

Предупреждает **доменных** пользователей об истечении срока действия пароля.
На локальных учётных записях завершается без сообщения.
Показывает окно с предупреждением, когда до окончания осталось N дней.

## Как это работает

Скрипт определяет дату истечения пароля через ADSI (встроенный интерфейс
Windows, никаких дополнительных модулей не нужно). Если атрибут
`msDS-UserPasswordExpiryTimeComputed` недоступен (домены младше Windows Server
2012), автоматически используется запасной вариант: `pwdLastSet` + `maxPwdAge`
домена.

Значения `9223372036854775807` (FileTime) и признак `DONT_EXPIRE_PASSWD`
(0x10000) в `userAccountControl` означают, что пароль никогда не истекает.
Скрипт завершается без предупреждения.

Ошибки записываются в `Write-Warning` — никаких окон, никаких прерываний
работы пользователя.

## Проблема RDP

При подключении к существующей (отключённой) RDP-сессии сценарий входа **не
выполняется**. Пользователь возвращается в незавершённую сессию и не видит
предупреждения. Встроенная групповая политика *Интерактивный вход: напоминать
пользователям об истечении срока действия пароля* тоже не помогает —
повторное подключение RDP не считается интерактивным входом.

**Решение:** запланированное задание с двумя запусками:

- **При входе в систему** — новая сессия
- **При подключении к сессии (RemoteConnect)** — возврат в отключённую RDP-сессию

## Установка

### Проверка (ручной запуск)

```powershell
powershell -ExecutionPolicy Bypass -File .\PasswordExpiryNotify.ps1 -Threshold 14
```

Порог, текст сообщения и заголовок можно передать параметрами:

```powershell
powershell -ExecutionPolicy Bypass -File .\PasswordExpiryNotify.ps1 -Threshold 10 -Message "Новый текст с {0} днями" -Title "Заголовок"
```

### Через групповую политику (GPO)

1. Положите `PasswordExpiryNotify.ps1` в сетевую папку (например, `\\domain.local\NETLOGON\`)
2. Создайте запланированное задание в GPO:
   ```
   Конфигурация компьютера → Параметры → Настройки панели управления
     → Запланированные задания → Создать → Запланированное задание (Windows 10+)
       Имя: PasswordExpiryNotify
       Параметры безопасности: Выполнять только при входе пользователя
       Настроить для: Windows 10
       Триггеры:
         - Начать задачу: При входе в систему
         - Начать задачу: При подключении к сессии (RemoteConnect)
       Действие: Запуск программы
         Программа: powershell
          Аргументы:
            -WindowStyle Hidden -ExecutionPolicy Bypass -File "\\domain.local\NETLOGON\PasswordExpiryNotify.ps1" 14
   ```

### На одной машине (вручную)

Сохраните XML в файл и выполните команду:

```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <URI>\PasswordExpiryNotify</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
    <SessionStateChangeTrigger>
      <Enabled>true</Enabled>
      <StateChange>RemoteConnect</StateChange>
    </SessionStateChangeTrigger>
  </Triggers>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell</Command>
      <Arguments>-WindowStyle Hidden -ExecutionPolicy Bypass -File "\\domain.local\NETLOGON\PasswordExpiryNotify.ps1" -Threshold 14</Arguments>
    </Exec>
  </Actions>
</Task>
```

```powershell
Register-ScheduledTask -TaskName "PasswordExpiryNotify" `
  -Xml (Get-Content "C:\Temp\PasswordExpiryNotify.xml" -Raw) -Force
```

## Как сменить пароль после предупреждения

При подключении по RDP обычное нажатие `Ctrl + Alt + Del` не работает — оно
перехватывается локальным компьютером. Вместо этого:

| Откуда подключаетесь | Что нажать |
|---|---|
| Windows (штатный клиент RDP) | `Ctrl + Alt + End` |
| Linux — xfreerdp | `Ctrl + Alt + End` (если оконная среда не перехватывает) |
| macOS | `Ctrl + Alt + Fn + Backspace` |

Универсальный способ (работает в любой RDP-сессии):

```cmd
wscript.exe -e:VBScript "CreateObject(""Shell.Application"").WindowsSecurity()"
```

Либо через «Выполнить» (Win+R):
```
explorer.exe shell:::{2559a1f2-21d7-11d4-bdaf-00c04f60b9f0}
```

## Параметры

| Параметр | По умолчанию | Описание |
|---|---|---|
| `-Threshold` | 14 | За сколько дней до истечения показывать предупреждение |
| `-Message` | (русский) | Текст сообщения. Обязательно должен содержать `{0}` |
| `-Title` | (русский) | Заголовок окна |

## Требования

- Только для **доменных учётных записей**. На локальных пользователях скрипт
  беззвучно завершается.
- Windows 10/11, компьютер в домене
- PowerShell 5.1+
- Права на чтение Active Directory (есть у любого доменного пользователя)
- Без дополнительных модулей, без RSAT
