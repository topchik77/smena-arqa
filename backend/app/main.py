import logging
import os
import sqlite3
from contextlib import asynccontextmanager, closing
from datetime import date
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from .ai_insights import explain_with_optional_ai
from .insights import explain_day
from .models import DatesView, DayView, InsightsView, TripInput, TripView
from .repository import TripConflict, TripRepository

ROOT = Path(__file__).resolve().parents[2]
logger = logging.getLogger(__name__)


def create_app(db_path: Path | str | None = None, web_path: Path | None = None) -> FastAPI:
    repository = TripRepository(Path(db_path or os.getenv("ARQA_DB_PATH", ROOT / "var" / "arqa.sqlite3")))

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        repository.initialize()
        yield

    app = FastAPI(
        title="Смена · Дневник водителя",
        version="1.0.0",
        description=(
            "Однопользовательский дневник завершённых поездок. "
            "Денежные ответы — десятичные строки в тенге. "
            "День определяется началом поездки в Asia/Almaty."
        ),
        lifespan=lifespan,
    )
    app.state.repository = repository
    origins = [value.strip() for value in os.getenv("ARQA_CORS_ORIGINS", "").split(",") if value.strip()]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type"],
    )

    @app.exception_handler(RequestValidationError)
    async def validation_error(request: Request, exc: RequestValidationError):
        return JSONResponse(
            status_code=422,
            content={
                "detail": "Проверьте данные запроса.",
                "errors": [
                    {"field": ".".join(str(part) for part in error["loc"]), "message": error["msg"]}
                    for error in exc.errors()
                ],
            },
        )

    @app.exception_handler(TripConflict)
    async def trip_conflict(request: Request, exc: TripConflict):
        return JSONResponse(
            status_code=409,
            content={"detail": "Поездка с этим id уже существует с другими данными."},
        )

    @app.exception_handler(sqlite3.OperationalError)
    async def database_error(request: Request, exc: sqlite3.OperationalError):
        logger.error("Database operation failed: %s", type(exc).__name__)
        return JSONResponse(
            status_code=503,
            headers={"Retry-After": "1"},
            content={"detail": "Хранилище временно недоступно. Повторите запрос."},
        )

    @app.get("/health", tags=["System"])
    def health() -> dict[str, str]:
        with closing(repository.connect()) as connection:
            connection.execute("SELECT 1 FROM trips LIMIT 1")
        return {"status": "ok"}

    @app.get("/api/v1/dates", response_model=DatesView, tags=["Diary"])
    def dates() -> DatesView:
        return DatesView(dates=repository.dates())

    @app.get("/api/v1/days/{selected_date}", response_model=DayView, tags=["Diary"])
    def day(selected_date: date) -> DayView:
        return repository.day(selected_date)

    @app.post(
        "/api/v1/trips",
        response_model=TripView,
        status_code=201,
        responses={200: {"description": "Identical trip already saved"}, 409: {"description": "ID conflict"}},
        tags=["Diary"],
    )
    def add_trip(trip: TripInput, response: Response) -> TripView:
        result, created = repository.add(trip)
        response.status_code = 201 if created else 200
        response.headers["Location"] = f"/api/v1/days/{trip.canonical()[6]}"
        return result

    @app.post("/api/v1/days/{selected_date}/insights", response_model=InsightsView, tags=["Insights"])
    def insights(selected_date: date) -> InsightsView:
        snapshot, previous = repository.day_with_previous(selected_date)
        return explain_with_optional_ai(snapshot, explain_day(snapshot, previous))

    # Keep unknown API paths as JSON 404s even when serving the Flutter build.
    @app.api_route("/api/{unknown_path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
    def unknown_api(unknown_path: str):
        raise HTTPException(status_code=404, detail="API-маршрут не найден.")

    client_build = web_path if web_path is not None else ROOT / "client" / "build" / "web"
    if client_build.is_dir():
        app.mount("/", StaticFiles(directory=client_build, html=True), name="client")
    return app


app = create_app()
