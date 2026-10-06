import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

class EarningsPanel extends StatelessWidget {
  const EarningsPanel({super.key, required this.summary});
  final DaySummary summary;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: ink,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: lime,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Итог дня',
                style: TextStyle(
                  color: ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              tripsLabel(summary.tripCount),
              style: const TextStyle(color: Color(0xFFCAD2C7), fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 25),
        const Text(
          'На руки',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'На руки: ${moneyLabel(summary.net)}',
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                moneyLabel(summary.net),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 47,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -1.7,
                  height: 1.12,
                  fontFeatures: moneyFeatures,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'После комиссии, без учёта расходов',
          style: TextStyle(color: Color(0xFFBAC4B8), fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 27),
        const Divider(color: Color(0xFF3B453E)),
        const SizedBox(height: 17),
        _heroLine('Выручка', moneyLabel(summary.revenue)),
        const SizedBox(height: 10),
        _heroLine('Комиссия', '− ${moneyLabel(summary.commission)}'),
      ],
    ),
  );

  Widget _heroLine(String label, String value) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFFCAD2C7), fontSize: 13),
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFeatures: moneyFeatures,
          ),
        ),
      ),
    ],
  );
}

class PaymentsPanel extends StatelessWidget {
  const PaymentsPanel({super.key, required this.summary});
  final DaySummary summary;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 27, horizontal: 3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Способы оплаты',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 15),
        Semantics(
          label:
              'Выручка: наличные ${moneyLabel(summary.cash)}, карта ${moneyLabel(summary.card)}',
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 8,
                child: summary.revenue == 0
                    ? const ColoredBox(color: rule)
                    : Row(
                        children: [
                          if (summary.cash > 0)
                            Expanded(
                              flex: summary.cash,
                              child: const ColoredBox(
                                color: ink,
                                child: SizedBox.expand(),
                              ),
                            ),
                          if (summary.cash > 0 && summary.card > 0)
                            const SizedBox(width: 3),
                          if (summary.card > 0)
                            Expanded(
                              flex: summary.card,
                              child: const ColoredBox(
                                color: Color(0xFFA6BD66),
                                child: SizedBox.expand(),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _amount('Наличные', summary.cash, ink)),
            const SizedBox(width: 16),
            Expanded(
              child: _amount('Карта', summary.card, const Color(0xFF6C8138)),
            ),
          ],
        ),
        const SizedBox(height: 15),
        const Text(
          'Распределение выручки до комиссии',
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _amount(String label, int value, Color marker) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: marker, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        moneyLabel(value),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          fontFeatures: moneyFeatures,
        ),
      ),
    ],
  );
}

class TripLedger extends StatelessWidget {
  const TripLedger({super.key, required this.day, required this.onAdd});
  final DriverDay day;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth >= 560 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.25;
      final trips = [...day.trips]..sort((a, b) => b.start.compareTo(a.start));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Поездки',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                '${day.summary.tripCount}'.padLeft(2, '0'),
                style: const TextStyle(
                  color: muted,
                  fontSize: 18,
                  fontFeatures: moneyFeatures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            trips.isEmpty
                ? 'Здесь будет история вашего дня'
                : 'От последних к первым · ${durationLabel(day.summary.tripMinutes)} в поездках',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 24),
          if (trips.isEmpty)
            _EmptyLedger(onAdd: onAdd)
          else ...[
            if (wide)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                child: Row(
                  children: [
                    const Expanded(flex: 4, child: _ColumnLabel('ВРЕМЯ')),
                    const Expanded(flex: 3, child: _ColumnLabel('ОПЛАТА')),
                    const Expanded(
                      flex: 3,
                      child: _ColumnLabel('ВЫРУЧКА', right: true),
                    ),
                    const Expanded(
                      flex: 3,
                      child: _ColumnLabel('НА РУКИ', right: true),
                    ),
                  ],
                ),
              ),
            const Divider(),
            for (final trip in trips) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 19),
                child: wide ? _wideTrip(trip) : _compactTrip(trip),
              ),
              const Divider(),
            ],
            const SizedBox(height: 17),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Учтено в итоге дня: ${tripsLabel(day.summary.tripCount)}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );

  Widget _wideTrip(Trip trip) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(flex: 4, child: _time(trip)),
      Expanded(
        flex: 3,
        child: Align(
          alignment: Alignment.centerLeft,
          child: PaymentChip(payment: trip.payment),
        ),
      ),
      Expanded(
        flex: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              moneyLabel(trip.amount),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                fontFeatures: moneyFeatures,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Комиссия ${moneyLabel(trip.commission)}',
              style: const TextStyle(
                color: muted,
                fontSize: 12,
                fontFeatures: moneyFeatures,
              ),
            ),
          ],
        ),
      ),
      Expanded(
        flex: 3,
        child: Text(
          moneyLabel(trip.net),
          textAlign: TextAlign.right,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFeatures: moneyFeatures,
          ),
        ),
      ),
    ],
  );

  Widget _compactTrip(Trip trip) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _time(trip)),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  moneyLabel(trip.net),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.4,
                    fontFeatures: moneyFeatures,
                  ),
                ),
                const Text(
                  'на руки',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 13),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PaymentChip(payment: trip.payment),
          Text(
            '${moneyLabel(trip.amount)} − ${moneyLabel(trip.commission)} комиссии',
            style: const TextStyle(
              color: muted,
              fontSize: 11,
              fontFeatures: moneyFeatures,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _time(Trip trip) {
    final dayOffset = dayOnly(
      almatyLocal(trip.end),
    ).difference(dayOnly(almatyLocal(trip.start))).inDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${clockLabel(trip.start)} → ${clockLabel(trip.end)}${dayOffset > 0 ? ' +$dayOffset' : ''}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFeatures: moneyFeatures,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          durationLabel(trip.minutes),
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel(this.text, {this.right = false});
  final String text;
  final bool right;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: right ? TextAlign.right : TextAlign.left,
    style: const TextStyle(
      color: muted,
      fontSize: 10,
      fontWeight: FontWeight.w500,
      letterSpacing: .8,
    ),
  );
}

class PaymentChip extends StatelessWidget {
  const PaymentChip({super.key, required this.payment});
  final String payment;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      border: Border.all(color: rule),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          payment == 'cash'
              ? Icons.payments_outlined
              : Icons.credit_card_rounded,
          size: 13,
          color: muted,
        ),
        const SizedBox(width: 5),
        Text(
          payment == 'cash' ? 'Наличные' : 'Карта',
          style: const TextStyle(fontSize: 11),
        ),
      ],
    ),
  );
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 38),
    decoration: BoxDecoration(
      border: Border.all(color: rule),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFE6E9DC),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.route_outlined, size: 27),
        ),
        const SizedBox(height: 20),
        const Text(
          'День с чистого листа',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        const Text(
          'За эту дату пока нет поездок.\nДобавьте первую — сводка обновится.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 19),
          label: const Text('Добавить поездку'),
        ),
      ],
    ),
  );
}

class InsightPanel extends StatelessWidget {
  const InsightPanel({
    super.key,
    required this.insight,
    required this.loading,
    required this.error,
    required this.onLoad,
  });
  final DayInsight? insight;
  final bool loading;
  final String? error;
  final VoidCallback onLoad;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      border: Border.all(color: rule),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 29,
              height: 29,
              decoration: BoxDecoration(
                color: lime,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.insights_rounded, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Разбор дня',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        if (insight == null) ...[
          const Text(
            'Посмотрите, из чего сложился ваш результат.',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: danger, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: loading ? null : onLoad,
              child: loading
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Flexible(child: Text('Готовим разбор…')),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            error == null ? 'Посмотреть разбор' : 'Повторить',
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
            ),
          ),
        ] else ...[
          Text(
            insight!.source == 'ai'
                ? 'ИИ-разбор по данным дневника'
                : 'По данным дневника',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Text(
            insight!.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(insight!.text, style: const TextStyle(fontSize: 13)),
          if (insight!.facts.isNotEmpty) ...[
            const SizedBox(height: 15),
            for (final fact in insight!.facts)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 4, color: muted),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(fact, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
          if (insight!.limitations.isNotEmpty) ...[
            const SizedBox(height: 9),
            const Divider(),
            const SizedBox(height: 12),
            for (final limitation in insight!.limitations)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  limitation,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ],
      ],
    ),
  );
}

class LoadingDay extends StatelessWidget {
  const LoadingDay({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Загружаем поездки и сводку',
    liveRegion: true,
    child: const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: Column(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2, color: ink),
            ),
            SizedBox(height: 18),
            Text(
              'Загружаем ваш день…',
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );
}
