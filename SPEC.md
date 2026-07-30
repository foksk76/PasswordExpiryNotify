# Spec: PasswordExpiryNotify Refactoring

## Objective

Рефакторинг существующего PowerShell-скрипта для повышения читаемости, поддерживаемости и тестируемости без изменения внешнего поведения.

Текущие проблемы:
- Вся логика в одном monolithic блоке
- Порог жёстко зашит (14 дней)
- Нет логгирования ошибок
- Сообщение только на русском, зашито в теле скрипта
- `try/catch` глотает все ошибки без следа
- MessageBox отображается внутри функции проверки
- Нет `Set-StrictMode` — неинициализированные переменные не отлавливаются

## Assumptions

- ОС — Windows, домен-joined машины (не workgroup)
- PowerShell 5.1+ (версия, встроенная в Windows 10/11)
- Запуск — unattended (logon script или scheduled task), без интерактивного пользователя
- Никаких внешних модулей — только встроенные ADSI и PresentationFramework
- ADSI-запрос через SID текущего пользователя, без прав администратора
- Язык сообщения по умолчанию — русский

## Tech Stack

- PowerShell 5.1+
- ADSI (Active Directory Service Interfaces) — встроен в Windows
- `PresentationFramework` — для MessageBox (только на Windows)

## Commands

Текущий запуск без изменений:
```powershell
powershell -File PasswordExpiryNotify.ps1
powershell -File PasswordExpiryNotify.ps1 -Threshold 10
powershell -File PasswordExpiryNotify.ps1 -Message "Ваш пароль истекает через {0} дн."
```

Никаких `build`, `test`, `lint` — скрипт не имеет toolchain.

## Project Structure

Без изменений — один файл:
```
PasswordExpiryNotify.ps1   — точка входа и единственный файл
```

Если новый код превысит ~80 строк — вынести логику AD в отдельную функцию, логгирование — в отдельную функцию, но держать всё в одном файле.

## Code Style

```powershell
function Get-UserSid {
    return [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Get-PasswordExpiryDate {
    param([string]$Sid)

    $user = [ADSI]"LDAP://<SID=$Sid>"
    $expiryFileTime = [int64]$user.'msDS-UserPasswordExpiryTimeComputed'.Value
    return [datetime]::FromFileTime($expiryFileTime)
}
```

Ключевые правила:
- `PascalCase` для функций и параметров
- `camelCase` для локальных переменных
- Комментарии только там, где логика неочевидна (магические числа — 9223372036854775807)
- Одна пустая строка между функциями
- `param()` блок наверху скрипта для всех параметров
- `Write-Output` не используется (скрипт не возвращает данных в pipeline)

## Testing Strategy

PowerShell Pester тесты, если пользователь явно запросит. По умолчанию — без тестов (нет CI, нет runner).

Верификация:
- Прогнать `Set-StrictMode -Version Latest` — не должно быть ошибок
- Проверить `Invoke-PSScriptAnalyzer` (если установлен) — без нарушений
- Ручной прогон — проверка, что скрипт выходит без ошибок при любой комбинации параметров

## Boundaries

- Always:
  - Сохранить поведение silent exit при ошибках
  - Не добавлять внешние модули
  - Сохранить Windows-совместимость (PowerShell 5.1)
  - Параметризовать threshold
  - `Set-StrictMode -Version Latest` в начале скрипта

- Ask first:
  - Изменение текста сообщения по умолчанию или локализация
  - Замена MessageBox на другой механизм (toast, balloon tip)
  - Добавление Pester-тестов

- Never:
  - Удалять silent exit на ошибках (скрипт работает в unattended режиме)
  - Добавлять зависимости от PowerShellGet/Microsoft.Graph
  - Менять логику определения AD-пользователя (SID → LDAP query)

## Success Criteria

- [ ] `$threshold` задаётся через параметр `-Threshold` с дефолтом 14
- [ ] `-Message` принимает шаблон с `{0}` для подстановки дней, дефолт — русский текст
- [ ] `-Title` принимает заголовок MessageBox, дефолт — русский
- [ ] `Set-StrictMode -Version Latest` в начале скрипта
- [ ] Функции выделены: Get-ADUserExpiry, Show-ExpiryWarning
- [ ] `try/catch` логирует ошибку в `Write-Warning` (silent exit сохранён)
- [ ] Код проходится `Invoke-PSScriptAnalyzer` без ошибок
- [ ] Поведение идентично текущему: те же условия, то же сообщение, то же silent exit
