# Kolyan Archive

Личный iOS-архиватор для iPhone. Проект редактируется на Windows в VS Code,
отправляется через GitHub Desktop и собирается в GitHub Actions на macOS.

## Идентификаторы

- Display Name: `Kolyan Archive`
- Bundle ID: `app.aquarius2773.mangosteen9164`
- Team ID из предоставленного provisioning profile: `972972V967`
- Минимальная iOS: 16.0

В профиле было показано значение `application-identifier`:
`972972V967.app.aquarius2773.mangosteen9164`.

## Что уже есть

- SwiftUI-интерфейс в тёмной теме.
- Импорт файла через системный Files picker.
- Просмотр списка содержимого ZIP.
- ZIP-сервис с методами создания и распаковки.
- GitHub Actions workflow для сборки неподписанного IPA.

## Что ещё не реализовано

- RAR-распаковка: UnrarKit ещё не интегрирован и требует проверки совместимости с текущим iOS SDK.
- ZIP-пароли: ZIPFoundation сам по себе не реализует создание/чтение зашифрованных архивов.
- Кнопки создания/распаковки в интерфейсе и выбор нескольких файлов — следующий этап разработки.

## Сборка

1. Создай пустой репозиторий GitHub.
2. Открой эту папку в GitHub Desktop и опубликуй репозиторий.
3. Открой вкладку Actions на GitHub.
4. Запусти `Build Kolyan Archive IPA`.
5. Скачай artifact `KolyanArchive-unsigned-IPA`.
6. Импортируй IPA в GBox и проверь, что GBox принимает Bundle ID и твой профиль.

## Важно о подписи

GitHub Actions собирает неподписанный IPA. Сертификат `.p12`, пароль и provisioning
profile не добавляй в репозиторий. Подписание выполняй в GBox на iPhone.
Перед установкой проверь совместимость профиля, сертификата и Bundle ID.
