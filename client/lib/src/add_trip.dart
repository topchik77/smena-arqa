import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'theme.dart';
import 'trip_submission.dart';

class AddTripForm extends StatefulWidget {
  const AddTripForm({super.key, required this.date, required this.submission});
  final DateTime date;
  final TripSubmission submission;
  @override
  State<AddTripForm> createState() => _AddTripFormState();
}

class _AddTripFormState extends State<AddTripForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _amount;
  late final TextEditingController _commission;
  late final DateTime _date;
  late final String _id;
  String _payment = 'card';
  bool _nextDay = false;

  @override
  void initState() {
    super.initState();
    final pending = widget.submission.pending;
    _id = pending?['id'] as String? ?? newTripId();
    _date = pending == null
        ? widget.date
        : parseDay((pending['start'] as String).substring(0, 10));
    _start = TextEditingController(
      text: pending == null
          ? '09:00'
          : (pending['start'] as String).substring(11, 16),
    );
    _end = TextEditingController(
      text: pending == null
          ? '09:30'
          : (pending['end'] as String).substring(11, 16),
    );
    _amount = TextEditingController(text: pending?['amount'] as String? ?? '');
    _commission = TextEditingController(
      text: pending?['commission'] as String? ?? '',
    );
    _payment = pending?['payment'] as String? ?? 'card';
    _nextDay =
        pending != null &&
        (pending['end'] as String).substring(0, 10) != dateKey(_date);
    widget.submission.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.submission.removeListener(_changed);
    for (final controller in [_start, _end, _amount, _commission]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? _minutes(String? value) {
    if (value == null || !RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value.trim())) {
      return null;
    }
    final parts = value.trim().split(':').map(int.parse).toList();
    if (parts[0] > 23 || parts[1] > 59) return null;
    return parts[0] * 60 + parts[1];
  }

  String _timestamp(String text, DateTime date) {
    return almatyTimestamp(date, _minutes(text)!);
  }

  Future<void> _save() async {
    if (widget.submission.pending == null &&
        !_formKey.currentState!.validate()) {
      return;
    }
    final payload =
        widget.submission.pending ??
        <String, dynamic>{
          'id': _id,
          'start': _timestamp(_start.text, _date),
          'end': _timestamp(
            _end.text,
            _nextDay ? _date.add(const Duration(days: 1)) : _date,
          ),
          'amount': moneyDecimal(parseMoney(_amount.text)),
          'commission': moneyDecimal(parseMoney(_commission.text)),
          'payment': _payment,
        };
    final success = await widget.submission.submit(payload);
    if (mounted && success) Navigator.of(context).pop(_date);
  }

  @override
  Widget build(BuildContext context) {
    final submission = widget.submission;
    final frozen = submission.pending != null || submission.sending;
    return PopScope(
      canPop: !submission.sending,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Новая поездка',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть форму',
                      onPressed: submission.sending
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${humanDate(_date)} ${_date.year} · время Алматы',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 26),
                const Text(
                  'Время поездки',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _start,
                        enabled: !frozen,
                        decoration: const InputDecoration(
                          labelText: 'Начало',
                          hintText: '09:00',
                        ),
                        keyboardType: TextInputType.datetime,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                          LengthLimitingTextInputFormatter(5),
                        ],
                        validator: (value) =>
                            _minutes(value) == null ? 'Формат: 09:00' : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextFormField(
                        controller: _end,
                        enabled: !frozen,
                        decoration: const InputDecoration(
                          labelText: 'Окончание',
                          hintText: '09:30',
                        ),
                        keyboardType: TextInputType.datetime,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                          LengthLimitingTextInputFormatter(5),
                        ],
                        validator: (value) {
                          final end = _minutes(value);
                          final start = _minutes(_start.text);
                          if (end == null) return 'Формат: 09:30';
                          if (start != null &&
                              end + (_nextDay ? 1440 : 0) <= start) {
                            return 'Позже начала';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  value: _nextDay,
                  onChanged:
                      frozen || !_date.isBefore(DateTime.utc(2100, 12, 31))
                      ? null
                      : (value) => setState(() => _nextDay = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Окончание на следующий день',
                    style: TextStyle(fontSize: 13),
                  ),
                  activeTrackColor: ink,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _amount,
                  enabled: !frozen,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(12),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Стоимость поездки',
                    suffixText: '₸',
                    hintText: 'Например, 2 400',
                  ),
                  validator: (value) {
                    try {
                      final amount = parseMoney(value ?? '');
                      if (amount > 10000000000) return 'Максимум 100 000 000 ₸';
                      return amount > 0
                          ? null
                          : 'Сумма должна быть больше нуля';
                    } on FormatException {
                      return 'Введите сумму, например 2400 или 2400,50';
                    }
                  },
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _commission,
                  enabled: !frozen,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(12),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Комиссия',
                    suffixText: '₸',
                    helperText: 'Укажите сумму комиссии, а не процент',
                    hintText: 'Например, 360',
                  ),
                  validator: (value) {
                    try {
                      final fee = parseMoney(value ?? '');
                      try {
                        if (fee > parseMoney(_amount.text)) {
                          return 'Комиссия не может превышать стоимость';
                        }
                      } on FormatException {
                        /* Amount field shows its own validation. */
                      }
                      return null;
                    } on FormatException {
                      return 'Введите комиссию, например 360 или 0';
                    }
                  },
                ),
                const SizedBox(height: 22),
                const Text(
                  'Способ оплаты',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'card',
                        label: Text('Карта'),
                        icon: Icon(Icons.credit_card_rounded),
                      ),
                      ButtonSegment(
                        value: 'cash',
                        label: Text('Наличные'),
                        icon: Icon(Icons.payments_outlined),
                      ),
                    ],
                    selected: {_payment},
                    onSelectionChanged: frozen
                        ? null
                        : (value) => setState(() => _payment = value.first),
                    style: ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? lime
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
                if (submission.error != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6E9DA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          submission.error!,
                          style: const TextStyle(
                            color: danger,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (submission.pending != null) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Повторите сохранение с теми же данными: в дневнике останется одна поездка. Можно закрыть форму и вернуться к ней позже.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: submission.sending ? null : _save,
                    icon: submission.sending
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            submission.pending == null
                                ? Icons.add_rounded
                                : Icons.refresh_rounded,
                            size: 20,
                          ),
                    label: Text(
                      submission.sending
                          ? 'Сохраняем…'
                          : submission.pending != null
                          ? 'Повторить сохранение'
                          : 'Добавить поездку',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Сохранится в дне начала поездки. В сводке учитываются только завершённые поездки.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
