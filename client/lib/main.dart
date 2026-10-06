import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/add_trip.dart';
import 'src/api.dart';
import 'src/day_widgets.dart';
import 'src/diary_controller.dart';
import 'src/models.dart';
import 'src/theme.dart';
import 'src/trip_submission.dart';

void main() => runApp(const SmenaApp());

class SmenaApp extends StatelessWidget {
  const SmenaApp({super.key, this.repository});
  final DiaryRepository? repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Смена — дневник водителя',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: DiaryScreen(repository: repository ?? DiaryApi()),
  );
}

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key, required this.repository});
  final DiaryRepository repository;
  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  late final DiaryController _controller;
  late final TripSubmission _submission;
  @override
  void initState() {
    super.initState();
    _controller = DiaryController(widget.repository)..addListener(_changed);
    _submission = TripSubmission(widget.repository)..addListener(_changed);
    _controller.initialize();
    _submission.restore();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _submission.removeListener(_changed);
    _submission.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addTrip() async {
    if (_submission.restoring || _submission.sending) return;
    final form = AddTripForm(
      date: _controller.selectedDate,
      submission: _submission,
    );
    final DateTime? savedDate;
    if (MediaQuery.sizeOf(context).width < 650) {
      savedDate = await showModalBottomSheet<DateTime>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: paper,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .95,
        ),
        builder: (_) => form,
      );
    } else {
      savedDate = await showDialog<DateTime>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          backgroundColor: paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 510),
            child: form,
          ),
        ),
      );
    }
    if (savedDate != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Поездка сохранена в дневнике')),
      );
      await _controller.selectDate(savedDate);
    }
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _controller.selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Выберите день',
      confirmText: 'Показать',
      cancelText: 'Отмена',
    );
    if (date != null && mounted) await _controller.selectDate(date);
  }

  Widget _addButton() => FilledButton.icon(
    onPressed: _submission.restoring ? null : _addTrip,
    icon: Icon(
      _submission.pending != null ? Icons.refresh_rounded : Icons.add_rounded,
      size: 19,
    ),
    label: Text(
      _submission.pending != null ? 'Повторить сохранение' : 'Добавить поездку',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide =
        width >= 1000 && MediaQuery.textScalerOf(context).scale(1) < 1.5;
    final mobile = width < 650;
    final day = _controller.day;
    final date = _controller.selectedDate;
    return Scaffold(
      bottomNavigationBar: mobile
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: const BoxDecoration(
                  color: paper,
                  border: Border(top: BorderSide(color: rule)),
                ),
                child: _addButton(),
              ),
            )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _controller.reload,
          color: ink,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: mobile ? 20 : 38),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: mobile ? 21 : 26,
                        ),
                        child: Row(
                          children: [
                            const BrandMark(),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 24,
                                runSpacing: 4,
                                children: [
                                  if (!mobile)
                                    const Text(
                                      'Личный дневник водителя',
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  const Text(
                                    'Время Алматы',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      SizedBox(height: mobile ? 26 : 37),
                      const Text(
                        'ДНЕВНИК ПОЕЗДОК',
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!wide) ...[
                        _dateTitle(date),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 20,
                          runSpacing: 12,
                          children: [
                            _dateControls(),
                            if (!mobile) _addButton(),
                          ],
                        ),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: _dateTitle(date)),
                            _dateControls(),
                            const SizedBox(width: 20),
                            _addButton(),
                          ],
                        ),
                      SizedBox(height: mobile ? 26 : 34),
                      if (_submission.pending != null) ...[
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9ECCF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.sync_rounded, size: 20),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Одна поездка ожидает подтверждения. Повторите сохранение — дубликат не появится.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],
                      if (_controller.loading)
                        const LoadingDay()
                      else if (_controller.error != null)
                        _errorPanel()
                      else if (day != null)
                        wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TripLedger(
                                      day: day,
                                      onAdd: _addTrip,
                                    ),
                                  ),
                                  const SizedBox(width: 48),
                                  SizedBox(
                                    width: 340,
                                    child: Column(
                                      children: [
                                        EarningsPanel(summary: day.summary),
                                        PaymentsPanel(summary: day.summary),
                                        _insight(),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  EarningsPanel(summary: day.summary),
                                  PaymentsPanel(summary: day.summary),
                                  const SizedBox(height: 8),
                                  TripLedger(day: day, onAdd: _addTrip),
                                  const SizedBox(height: 32),
                                  _insight(),
                                ],
                              ),
                      SizedBox(height: mobile ? 34 : 48),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Wrap(
                          spacing: 24,
                          runSpacing: 8,
                          children: [
                            const Text(
                              'Смена. Каждый день считается.',
                              style: TextStyle(color: muted, fontSize: 11),
                            ),
                            if (day != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_rounded,
                                    size: 14,
                                    color: muted,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      'Данные за ${humanDate(date)} загружены',
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateTitle(DateTime date) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(humanDate(date), style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 7),
      Text(
        '${weekdays[date.weekday - 1]}, ${date.year}',
        style: const TextStyle(color: muted, fontSize: 13),
      ),
    ],
  );

  Widget _dateControls() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: rule),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Предыдущий день',
              onPressed: !_controller.selectedDate.isAfter(DateTime.utc(2000))
                  ? null
                  : () => _controller.selectDate(
                      _controller.selectedDate.subtract(
                        const Duration(days: 1),
                      ),
                    ),
              icon: const Icon(Icons.chevron_left_rounded, size: 21),
            ),
            IconButton(
              tooltip: 'Выбрать дату',
              onPressed: _chooseDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
            ),
            IconButton(
              tooltip: 'Следующий день',
              onPressed:
                  !_controller.selectedDate.isBefore(DateTime.utc(2100, 12, 31))
                  ? null
                  : () => _controller.selectDate(
                      _controller.selectedDate.add(const Duration(days: 1)),
                    ),
              icon: const Icon(Icons.chevron_right_rounded, size: 21),
            ),
          ],
        ),
      ),
      TextButton(
        onPressed: dateKey(_controller.selectedDate) == dateKey(almatyNow())
            ? null
            : () => _controller.selectDate(dayOnly(almatyNow())),
        child: const Text('Сегодня'),
      ),
      IconButton(
        tooltip: 'Обновить дневник',
        onPressed: _controller.loading ? null : _controller.reload,
        icon: const Icon(Icons.refresh_rounded, size: 21),
      ),
    ],
  );

  Widget _insight() => InsightPanel(
    insight: _controller.insight,
    loading: _controller.insightLoading,
    error: _controller.insightError,
    onLoad: _controller.loadInsight,
  );

  Widget _errorPanel() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 45, horizontal: 24),
    decoration: BoxDecoration(
      border: Border.all(color: rule),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_outlined, size: 36, color: muted),
        const SizedBox(height: 18),
        const Text(
          'Не удалось загрузить день',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        Text(
          _controller.error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _controller.reload,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Попробовать снова'),
        ),
      ],
    ),
  );
}
