"""Grounded comparisons of recorded days; all calculations stay on the server."""

from decimal import ROUND_HALF_UP, Decimal

from .models import DayView, InsightsView

CENT = Decimal("0.01")
TENTH = Decimal("0.1")


def format_tenge(value: str | Decimal) -> str:
    number = Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)
    rendered = f"{number:,.2f}".replace(",", " ").replace(".", ",")
    return rendered.removesuffix(",00") + " ₸"


def _one_decimal(value: Decimal) -> str:
    return str(value.quantize(TENTH, rounding=ROUND_HALF_UP)).removesuffix(".0").replace(".", ",")


def _signed_money(value: Decimal) -> str:
    return ("+" if value > 0 else "−" if value < 0 else "") + format_tenge(abs(value))


def _average_net(day: DayView) -> Decimal:
    return (Decimal(day.summary.net) / day.summary.trip_count).quantize(CENT, rounding=ROUND_HALF_UP)


def _net_change(current: Decimal, previous: Decimal) -> str:
    difference = current - previous
    if not difference:
        return f"На руки без изменений: {format_tenge(current)}."
    if not previous:
        return f"На руки: {_signed_money(difference)}. Раньше было 0 ₸, процент изменения не рассчитывается."
    percent = abs(difference) * 100 / previous
    # Tiny but nonzero changes must not misleadingly appear as +0% / −0%.
    percent_text = "<0,1" if percent < Decimal("0.05") else _one_decimal(percent)
    direction = "больше" if difference > 0 else "меньше"
    return f"На руки на {format_tenge(abs(difference))} {direction} ({percent_text}%)."


def explain_day(day: DayView, previous: DayView | None = None) -> InsightsView:
    summary = day.summary
    limitations = [
        "Без расходов на топливо и автомобиль.",
        "Учтены внесённые поездки; ожидание и полное время смены неизвестны.",
    ]
    if not summary.trip_count:
        return InsightsView(
            title="Сравнивать пока нечего",
            text="В этот день нет поездок. Это не означает падение заработка — день может быть не заполнен.",
            facts=[],
            limitations=limitations,
        )
    average = _average_net(day)
    if previous is None or previous.date >= day.date or not previous.summary.trip_count:
        duration = Decimal(summary.trip_minutes) / summary.trip_count
        commission_percent = Decimal(summary.commission) * 100 / Decimal(summary.revenue)
        return InsightsView(
            title="Отправная точка",
            text=(
                "Более ранних дней с поездками нет. "
                "Сравнение появится, когда будет с чем сопоставить результат."
            ),
            facts=[
                f"В среднем на поездку после комиссии: {format_tenge(average)}.",
                f"Средняя длительность поездки: около {_one_decimal(duration)} мин.",
                f"Доля комиссии в выручке: {_one_decimal(commission_percent)}%.",
            ],
            limitations=limitations,
        )

    earlier = previous.summary
    previous_average = _average_net(previous)
    count_change = summary.trip_count - earlier.trip_count
    count_delta = f"+{count_change}" if count_change > 0 else str(count_change).replace("-", "−")
    average_change = average - previous_average
    average_delta = _signed_money(average_change) if average_change else "без изменений"
    return InsightsView(
        title="Что изменилось",
        # Calendar dates stay outside facts: optional AI receives only aggregate
        # summary and candidate facts, never this local text.
        text=f"Сравнение с {previous.date:%d.%m.%Y} — предыдущим днём с поездками.",
        facts=[
            _net_change(Decimal(summary.net), Decimal(earlier.net)),
            f"Поездок: {summary.trip_count} вместо {earlier.trip_count} ({count_delta}).",
            f"В среднем на руки за поездку: {format_tenge(average)} вместо "
            f"{format_tenge(previous_average)} ({average_delta}).",
        ],
        limitations=limitations,
    )
