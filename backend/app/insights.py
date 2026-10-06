"""Grounded local day explanation; it does not pretend to be an AI model."""

from decimal import ROUND_HALF_UP, Decimal

from .models import DayView, InsightsView


def format_tenge(value: str) -> str:
    number = Decimal(value)
    rendered = f"{number:,.2f}".replace(",", " ").replace(".", ",")
    return rendered.removesuffix(",00") + " ₸"


def explain_day(day: DayView) -> InsightsView:
    summary = day.summary
    limitations = [
        "«На руки» — выручка за вычетом комиссии, до расходов на топливо и автомобиль.",
        "Длительность поездок не включает ожидание и дорогу до пассажира.",
        "По данным одного дня нельзя надёжно рекомендовать время и районы для работы.",
    ]
    if not summary.trip_count:
        return InsightsView(
            title="Пока нет данных для разбора",
            text="Добавьте завершённую поездку — здесь появятся итоги выбранного дня.",
            facts=[],
            limitations=limitations,
        )
    percent = (Decimal(summary.commission) * 100 / Decimal(summary.revenue)).quantize(
        Decimal("0.1"), rounding=ROUND_HALF_UP
    )
    percent_text = str(percent).removesuffix(".0").replace(".", ",")
    facts = [
        f"Выручка: {format_tenge(summary.revenue)}.",
        f"Комиссия: {format_tenge(summary.commission)} — {percent_text}% выручки.",
        f"Наличные: {format_tenge(summary.cash)}; карта: {format_tenge(summary.card)}.",
        f"Время в завершённых поездках: {summary.trip_minutes} мин.",
    ]
    return InsightsView(
        title="Ваш день в цифрах",
        text=(
            f"После комиссии осталось {format_tenge(summary.net)}. "
            f"Учтено поездок: {summary.trip_count}. "
            "Наличные и карта показывают способ оплаты пассажиром, а не баланс вашего счёта."
        ),
        facts=facts,
        limitations=limitations,
    )
