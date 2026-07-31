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

### 1. Подпись скрипта

PowerShell при политике `AllSigned` запускает только подписанные скрипты.
Скрипт нужно подписать сертификатом подписи кода **при каждом изменении**
(подпись «ломается» от любой правки файла).

Выполните **один** из двух вариантов получения сертификата.

**Вариант А — сертификат от доменного ЦС (рекомендуется; домен с AD CS):**
автоматически доверяется всеми машинами домена.

```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.NotAfter -gt (Get-Date) } |
    Select-Object -First 1
```

**Вариант Б — самоподписанный (только малые домены / одна машина):** `.cer`
затем разворачивается на клиентах (см. шаг 2).

```powershell
$cert = New-SelfSignedCertificate -Type CodeSigningCert `
    -Subject "CN=PasswordExpiryNotify" `
    -CertStoreLocation Cert:\LocalMachine\My
Export-Certificate -Cert $cert -FilePath "C:\PasswordExpiryNotify.cer"
# Импорт на этой же машине — для проверки подписи (требует прав администратора)
Import-Certificate -FilePath "C:\PasswordExpiryNotify.cer" `
    -CertStoreLocation Cert:\LocalMachine\Root            # в доверенные корневые
Import-Certificate -FilePath "C:\PasswordExpiryNotify.cer" `
    -CertStoreLocation Cert:\LocalMachine\TrustedPublisher # и в доверенных издателей
```

Подпись и проверка. Подписывается **копия** для развёртывания:
`Set-AuthenticodeSignature` меняет файл, поэтому в репозитории хранится
неподписанный оригинал (подписанный файл «ломает» git-копию).

```powershell
Copy-Item ".\PasswordExpiryNotify.ps1" "C:\deploy\PasswordExpiryNotify.ps1"
Set-AuthenticodeSignature -FilePath "C:\deploy\PasswordExpiryNotify.ps1" -Certificate $cert
Get-AuthenticodeSignature "C:\deploy\PasswordExpiryNotify.ps1"   # Status = Valid
```

> Подпись действительна, пока действителен сертификат (у самоподписанного
> срок по умолчанию небольшой). Чтобы подпись пережила истечение сертификата,
> добавьте timestamp-сервер (если есть доступ в интернет):
> `Set-AuthenticodeSignature ... -TimeStampServer "http://timestamp.digicert.com"`.

### 2. Запрет запуска неподписанных скриптов (GPO)

Политикой выполнения через GPO запрещается запуск неподписанных скриптов
PowerShell на всех машинах домена (локальный `Bypass` из командной строки
политикой GPO перекрывается):

```
Конфигурация компьютера → Административные шаблоны → Компоненты Windows
  → Windows PowerShell → «Включить выполнение сценариев» → Включено
    Политика выполнения: «Разрешить только подписанные сценарии» (AllSigned)

Конфигурация пользователя → Административные шаблоны → Компоненты Windows
  → Windows PowerShell → «Включить выполнение сценариев» → Включено
    Политика выполнения: «Разрешить только подписанные сценарии» (AllSigned)
```

Для самоподписанного сертификата (вариант Б) разверните `.cer` на всех
машинах домена через GPO в **оба** хранилища — без любого из них `AllSigned`
отклонит подпись:

- `Конфигурация компьютера → Параметры безопасности → Политики открытых ключей
  → Доверенные корневые центры сертификации` → импорт `.cer` — иначе цепочка
  сертификатов не строится («ненадёжный корневой сертификат»)
- `Конфигурация компьютера → Параметры безопасности → Политики открытых ключей
  → Доверенные издатели` → импорт `.cer` — иначе издатель не считается
  доверенным

Примените политику: `gpupdate /force`. После этого клиентские машины
отклоняют любой неподписанный скрипт PowerShell, в том числе переданный
через `-ExecutionPolicy Bypass`.

### 3. Проверка (ручной запуск)

Запускается подписанная копия из `C:\deploy` — неподписанный оригинал
в репозитории политика `AllSigned` не пропустит:

```powershell
powershell -ExecutionPolicy AllSigned -File C:\deploy\PasswordExpiryNotify.ps1 -Threshold 14
```

Порог, текст сообщения и заголовок можно передать параметрами:

```powershell
powershell -ExecutionPolicy AllSigned -File C:\deploy\PasswordExpiryNotify.ps1 -Threshold 10 -Message "Новый текст с {0} днями" -Title "Заголовок"
```

### 4. Через групповую политику (GPO)

1. Положите **подписанную** копию `PasswordExpiryNotify.ps1` в сетевую папку (например, `\\domain.local\NETLOGON\`)
2. Создайте запланированное задание в GPO (в **Конфигурации пользователя** —
   задание должно выполняться в сеансе пользователя, иначе окно предупреждения
   не будет показано):
   ```
   Конфигурация пользователя → Параметры → Настройки панели управления
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
            -WindowStyle Hidden -ExecutionPolicy AllSigned -File "\\domain.local\NETLOGON\PasswordExpiryNotify.ps1" -Threshold 14
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
      <Arguments>-WindowStyle Hidden -ExecutionPolicy AllSigned -File "\\domain.local\NETLOGON\PasswordExpiryNotify.ps1" -Threshold 14</Arguments>
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
| `-Threshold` | 14 | За сколько дней до истечения показывать предупреждение. Должен быть ≥ 1 (`[ValidateRange]`; 0 или отрицательное значение отклоняется) |
| `-Message` | (русский) | Текст сообщения. Обязательно должен содержать `{0}` (проверяется `[ValidateScript]`, иначе запуск завершится ошибкой) |
| `-Title` | (русский) | Заголовок окна |

## Требования

- Только для **доменных учётных записей**. На локальных пользователях скрипт
  беззвучно завершается.
- Windows 10/11, компьютер в домене
- PowerShell 5.1+
- Права на чтение Active Directory (есть у любого доменного пользователя)
- Без дополнительных модулей, без RSAT
