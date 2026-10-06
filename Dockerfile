FROM debian:bookworm-slim AS web
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch 3.47.6 https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}" CI=true
RUN flutter config --no-analytics && flutter precache --web
WORKDIR /build
COPY client/pubspec.yaml client/pubspec.lock ./
RUN flutter pub get
COPY client/ ./
RUN flutter build web --release --no-web-resources-cdn

FROM python:3.14-slim AS app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 ARQA_DB_PATH=/app/var/arqa.sqlite3
WORKDIR /app/backend
COPY backend/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --create-home --uid 10001 app \
    && mkdir -p /app/var && chown app:app /app/var
COPY backend/app ./app
COPY data /app/data
COPY --from=web /build/build/web /app/client/build/web
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)"
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
