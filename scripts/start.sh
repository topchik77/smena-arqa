#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
python3 -m venv backend/.venv
backend/.venv/bin/python -m pip install -r backend/requirements.txt
(cd client && flutter pub get && flutter build web --release --no-web-resources-cdn)
cd backend
.venv/bin/python -m app.import_data ../data/trips.json
.venv/bin/python -m app.import_data ../data/demo-trips.json
exec .venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
