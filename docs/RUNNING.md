# Запуск и подключение клиента

## Быстрый запуск

### Docker

Нужен запущенный Docker Engine с Compose:

```sh
docker compose up --build
```

Откройте **http://127.0.0.1:8000**. Документация API — **http://127.0.0.1:8000/docs**.

Первый запуск скачивает Flutter и зависимости, поэтому занимает заметно больше времени. Данные сохраняются в Docker volume `diary`. Стартовая команда повторяемо импортирует официальный пример и отдельный демонстрационный набор; существующие записи не перезаписывает. `docker compose down` сохраняет данные. Внешний ИИ не нужен для запуска.

### Локально

Проверяемая конфигурация: Python 3.14, Flutter 3.47.6 / Dart 3.13.5. Backend рассчитан на Python 3.12+. Для Android также нужны JDK 17 и Android SDK; для браузера Android SDK не требуется.

Windows, из корня проекта:

```powershell
./scripts/start.ps1
```

Linux/macOS:

```sh
sh scripts/start.sh
```

Скрипт создаёт Python venv, устанавливает зависимости, собирает Flutter Web, импортирует примеры и запускает API с клиентом на одном адресе. В Windows можно использовать `./scripts/start.ps1 -SkipBuild`, если веб-клиент уже собран. Скрипты не устанавливают сам Python или Flutter.

Ручной запуск сервера (PowerShell):

```powershell
python -m venv backend/.venv
backend/.venv/Scripts/python.exe -m pip install -r backend/requirements.txt
cd backend
.venv/Scripts/python.exe -m app.import_data ../data/trips.json
.venv/Scripts/python.exe -m app.import_data ../data/demo-trips.json
.venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

База по умолчанию — `var/arqa.sqlite3`. Путь можно изменить переменной `ARQA_DB_PATH`. Сервер сам не добавляет демонстрационные данные: это делает явная команда импорта либо стартовый скрипт.

Сборка браузерного клиента, из `client/`:

```sh
flutter pub get
flutter build web --release --no-web-resources-cdn
```

После первой сборки перезапустите сервер, чтобы он подключил `client/build/web`. Шрифт и CanvasKit находятся в сборке; внешние CDN при открытии не требуются. Клиент обращается к API на том же адресе.

Для разработки с отдельным Flutter web-server задайте backend `ARQA_CORS_ORIGINS=http://localhost:5173`, затем:

```sh
flutter run -d web-server --web-hostname localhost --web-port 5173 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## Android на телефоне

Демонстрационная release-сборка использует стандартную debug-подпись Flutter: подходит для установки вручную, не предназначена для публикации в магазине.

Сервер должен работать на компьютере. Подключите телефон по USB, разрешите отладку и выполните:

```sh
adb devices
adb reverse tcp:8000 tcp:8000
```

Из `client/`:

```sh
flutter build apk --release --dart-define=API_BASE_URL=http://127.0.0.1:8000
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Откройте «Смена» на телефоне. USB-проброс нужен снова после отключения устройства. Без `--dart-define` Android-клиент использует `http://10.0.2.2:8000` для стандартного эмулятора.

Для удалённого API пересоберите с `--dart-define=API_BASE_URL=https://your-api.example`. HTTP в release разрешён только для localhost и адреса эмулятора; удалённый сервер должен использовать HTTPS. Перед открытием сервиса другим пользователям нужны авторизация и разделение данных — текущая версия рассчитана на одного водителя.

