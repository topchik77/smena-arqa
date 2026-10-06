"""Validated input and public API schemas. Money is never calculated with floats."""

import re
from datetime import UTC, date, datetime
from decimal import Decimal, InvalidOperation
from typing import Annotated, Literal
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

TIMEZONE = "Asia/Almaty"
LOCAL_TZ = ZoneInfo(TIMEZONE)
MAX_AMOUNT = Decimal("100000000")
MoneyText = Annotated[str, Field(pattern=r"^\d+\.\d{2}$", examples=["2400.00"])]


def money_text(tiyn: int) -> str:
    return f"{tiyn // 100}.{tiyn % 100:02d}"


class TripInput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(min_length=1, max_length=100, pattern=r"^[A-Za-z0-9][A-Za-z0-9_.:-]*$")
    start: datetime
    end: datetime
    amount: Decimal = Field(gt=0, le=MAX_AMOUNT)
    payment: Literal["cash", "card"]
    commission: Decimal = Field(ge=0, le=MAX_AMOUNT)

    @field_validator("amount", "commission", mode="before")
    @classmethod
    def exact_money(cls, value: object) -> Decimal:
        if isinstance(value, bool) or not isinstance(value, (str, int, float, Decimal)):
            raise ValueError("Сумма должна быть числом в тенге.")
        if isinstance(value, str) and len(value) > 40:
            raise ValueError("Слишком длинное значение суммы.")
        try:
            number = Decimal(str(value))
        except InvalidOperation as exc:
            raise ValueError("Сумма должна быть числом в тенге.") from exc
        if not number.is_finite():
            raise ValueError("Сумма должна быть конечным числом.")
        if number.copy_abs() > MAX_AMOUNT:
            raise ValueError("Сумма не может превышать 100 000 000 ₸.")
        if number != number.quantize(Decimal("0.01")):
            raise ValueError("Допустимо не более двух знаков после запятой.")
        return number

    @field_validator("start", "end", mode="before")
    @classmethod
    def timestamp_type(cls, value: object) -> object:
        if not isinstance(value, (str, datetime)):
            raise ValueError("Укажите дату и время ISO 8601 с часовым поясом.")
        if isinstance(value, str) and not re.fullmatch(
            r"\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:[Zz]|[+-]\d{2}:\d{2})", value
        ):
            raise ValueError("Укажите дату и время ISO 8601 с секундами и часовым поясом.")
        return value

    @field_validator("start", "end")
    @classmethod
    def aware_time(cls, value: datetime) -> datetime:
        if value.utcoffset() is None:
            raise ValueError("Укажите часовой пояс, например +05:00.")
        if not 2000 <= value.year <= 2100:
            raise ValueError("Дата должна быть между 2000 и 2100 годами.")
        value = value.astimezone(UTC)
        if not 2000 <= value.year <= 2100:
            raise ValueError("Дата должна быть между 2000 и 2100 годами.")
        return value

    @model_validator(mode="after")
    def validate_trip(self) -> "TripInput":
        if self.end <= self.start:
            raise ValueError("Окончание поездки должно быть позже начала.")
        if self.commission > self.amount:
            raise ValueError("Комиссия не может превышать сумму поездки.")
        return self

    @property
    def amount_tiyn(self) -> int:
        return int(self.amount * 100)

    @property
    def commission_tiyn(self) -> int:
        return int(self.commission * 100)

    def canonical(self) -> tuple[str, str, str, int, str, int, str]:
        return (
            self.id,
            self.start.isoformat(timespec="microseconds"),
            self.end.isoformat(timespec="microseconds"),
            self.amount_tiyn,
            self.payment,
            self.commission_tiyn,
            self.start.astimezone(LOCAL_TZ).date().isoformat(),
        )


class TripView(BaseModel):
    id: str
    start: datetime
    end: datetime
    amount: MoneyText
    payment: Literal["cash", "card"]
    commission: MoneyText


class Summary(BaseModel):
    trip_count: int
    revenue: MoneyText
    commission: MoneyText
    net: MoneyText
    cash: MoneyText
    card: MoneyText
    trip_minutes: int


class DayView(BaseModel):
    date: date
    timezone: str = TIMEZONE
    trips: list[TripView]
    summary: Summary


class DatesView(BaseModel):
    dates: list[date]


class InsightsView(BaseModel):
    source: Literal["local", "ai"] = "local"
    title: str
    text: str
    facts: list[str]
    limitations: list[str]
