# Implementation Plan: PasswordExpiryNotify Refactoring

## Overview

Рефакторинг единственного файла `PasswordExpiryNotify.ps1`: параметризация threshold и текста, выделение функций, `Set-StrictMode`, логгирование ошибок.

## Architecture Decisions

- **Один файл** — скрипт остаётся монолитным, функции объявляются в начале
- **Никаких модулей** — без Pester, без модульной структуры
- **Скрипт остаётся совместимым с PowerShell 5.1** — никакого синтаксиса PS7+

## Task List

### Phase 1: Foundation

- [ ] Task 1: Добавить `Set-StrictMode` и `param()` блок с `-Threshold` и `-Message`

### Checkpoint: Foundation
- [ ] `Set-StrictMode` без ошибок при пустом запуске
- [ ] Параметры принимают корректные значения

### Phase 2: Core

- [ ] Task 2: Выделить функцию `Get-ADUserExpiry`
- [ ] Task 3: Выделить функцию `Show-ExpiryWarning` и переписать main body

### Checkpoint: Complete
- [ ] Все acceptance criteria из SPEC.md выполнены
- [ ] Скрипт проходит `Invoke-PSScriptAnalyzer`
- [ ] Поведение идентично оригиналу

## Task Details

### Task 1: Добавить `Set-StrictMode` и `param()` блок

**Description:** В начало скрипта добавляется `Set-StrictMode -Version Latest` и блок `param()` с `-Threshold` (default 14) и `-Message` (default — текущий русский текст).

**Acceptance criteria:**
- [ ] `Set-StrictMode -Version Latest` на первой строке после комментариев
- [ ] `param([int]$Threshold = 14, [string]$Message = "...")` определён
- [ ] Запуск `powershell -File PasswordExpiryNotify.ps1 -Threshold 10` подставляет 10
- [ ] Запуск `powershell -File PasswordExpiryNotify.ps1` использует дефолты

**Verification:**
- [ ] `$Threshold` доступен внутри скрипта
- [ ] `-Message` с `{0}` корректно передаётся в `-f` оператор

**Dependencies:** None

**Files likely touched:**
- `PasswordExpiryNotify.ps1`

**Estimated scope:** XS (1 файл, 3 строки)

---

### Task 2: Выделить функцию `Get-ADUserExpiry`

**Description:** Переместить ADSI-запрос и конвертацию `FileTime` в дату в отдельную функцию. Логика без изменений.

**Acceptance criteria:**
- [ ] Функция `function Get-ADUserExpiry { param([string]$Sid) ... }` возвращает `[datetime]` или `$null` (при never-expires)
- [ ] Значения 0 и 9223372036854775807 возвращают `$null`
- [ ] Основной код вызывает функцию вместо inline-запроса

**Verification:**
- [ ] `powershell -File PasswordExpiryNotify.ps1` работает как раньше

**Dependencies:** Task 1

**Files likely touched:**
- `PasswordExpiryNotify.ps1`

**Estimated scope:** XS (1 файл, ~10 строк)

---

### Task 3: Выделить функцию `Show-ExpiryWarning` и переписать main body

**Description:** Вынести MessageBox в функцию. Main body становится последовательным вызовом: SID → AD запрос → проверка дней → уведомление. `try/catch` оборачивает весь main body, логирует ошибку через `Write-Warning`.

**Acceptance criteria:**
- [ ] `function Show-ExpiryWarning { param([int]$Days, [string]$Message) ... }` показывает MessageBox
- [ ] `$Message` форматируется через `-f $Days`
- [ ] `try/catch` пишет `Write-Warning "Error: $_"` и делает `exit 0` (silent)
- [ ] Main body лаконичный: получение SID → вызов `Get-ADUserExpiry` → проверка дней → вызов `Show-ExpiryWarning`

**Verification:**
- [ ] Скрипт проходит `Invoke-PSScriptAnalyzer`
- [ ] Поведение идентично: те же условия, то же сообщение, тот же silent exit

**Dependencies:** Task 2

**Files likely touched:**
- `PasswordExpiryNotify.ps1`

**Estimated scope:** XS (1 файл, ~15 строк)

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| `Set-StrictMode` ломает существующий код | Med | Проверить на тестовой AD-учётке перед деплоем |

## Verification

- [x] Every task has acceptance criteria
- [x] Every task has a verification step
- [x] Task dependencies are identified and ordered correctly
- [x] No task touches more than ~5 files (все — 1 файл)
- [x] The spec is approved
