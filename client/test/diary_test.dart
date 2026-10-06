import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smena/main.dart';
import 'package:smena/src/api.dart';
import 'package:smena/src/diary_controller.dart';
import 'package:smena/src/models.dart';
import 'package:smena/src/trip_submission.dart';

DriverDay sampleDay(String date) => DriverDay.fromJson({
  'date': date,
  'trips': [
    {
      'id': 'trip-1',
      'start': '${date}T09:00:00+05:00',
      'end': '${date}T09:30:00+05:00',
      'amount': '2400.00',
      'commission': '360.00',
      'payment': 'card',
    },
    {
      'id': 'trip-2',
      'start': '${date}T10:00:00+05:00',
      'end': '${date}T10:25:00+05:00',
      'amount': '1500.00',
      'commission': '225.00',
      'payment': 'cash',
    },
  ],
  'summary': {
    'trip_count': 2,
    'revenue': '3900.00',
    'commission': '585.00',
    'net': '3315.00',
    'cash': '1500.00',
    'card': '2400.00',
    'trip_minutes': 55,
  },
});

class FakeRepository implements DiaryRepository {
  final List<Map<String, dynamic>> writes = [];
  final Map<String, Completer<DriverDay>> delayedDays = {};
  bool failWrite = false;
  bool failRead = false;
  ApiException? writeError;
  Completer<List<DateTime>>? delayedDates;
  @override
  Future<List<DateTime>> getDates() async =>
      delayedDates?.future ?? Future.value([parseDay('2026-10-06')]);
  @override
  Future<DriverDay> getDay(DateTime date) async {
    if (failRead) throw const ApiException('Нет соединения');
    return delayedDays[dateKey(date)]?.future ??
        Future.value(sampleDay(dateKey(date)));
  }

  @override
  Future<void> addTrip(Map<String, dynamic> payload) async {
    writes.add(Map.of(payload));
    if (writeError != null) throw writeError!;
    if (failWrite) throw const ApiException('Ответ потерян', uncertain: true);
  }

  @override
  Future<DayInsight> getInsight(DateTime date) async => const DayInsight(
    source: 'local',
    title: 'Результат дня',
    text: 'На руки 3 315 ₸.',
    facts: ['Две поездки'],
    limitations: ['Без учёта расходов'],
  );
  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('money stays exact down to one tiyn and rejects ambiguous input', () {
    expect(parseMoney('2400,50'), 240050);
    expect(parseMoney('0.01') + parseMoney('0.02'), 3);
    expect(moneyDecimal(3), '0.03');
    expect(moneyLabel(331500), '3\u00a0315 ₸');
    expect(moneyLabel(331501), '3\u00a0315,01 ₸');
    expect(() => parseMoney('12.345'), throwsFormatException);
    expect(() => parseMoney('-1'), throwsFormatException);
    expect(() => parseMoney('1e3'), throwsFormatException);
    expect(() => parseMoney(''), throwsFormatException);
  });

  test(
    'late response cannot replace newly selected day or show stale totals',
    () async {
      final repository = FakeRepository();
      final controller = DiaryController(repository);
      await controller.initialize();
      expect(controller.day!.summary.net, 331500);
      final first = Completer<DriverDay>();
      final second = Completer<DriverDay>();
      repository.delayedDays['2026-10-05'] = first;
      repository.delayedDays['2026-10-04'] = second;
      final firstLoad = controller.selectDate(parseDay('2026-10-05'));
      expect(controller.day, isNull);
      final secondLoad = controller.selectDate(parseDay('2026-10-04'));
      second.complete(sampleDay('2026-10-04'));
      await secondLoad;
      first.complete(sampleDay('2026-10-05'));
      await firstLoad;
      expect(dateKey(controller.selectedDate), '2026-10-04');
      expect(dateKey(controller.day!.date), '2026-10-04');
      controller.dispose();
    },
  );

  test(
    'uncertain write survives restart and retries exact saved payload',
    () async {
      final repository = FakeRepository()..failWrite = true;
      final submission = TripSubmission(repository);
      await submission.restore();
      final payload = <String, dynamic>{
        'id': 'stable-key',
        'start': '2026-10-06T23:50:00+05:00',
        'end': '2026-10-07T00:10:00+05:00',
        'amount': '2400.50',
        'commission': '360.00',
        'payment': 'card',
      };
      expect(await submission.submit(payload), isFalse);
      expect(submission.pending, payload);
      submission.dispose();

      final restarted = TripSubmission(repository);
      await restarted.restore();
      expect(restarted.pending, payload);
      repository.failWrite = false;
      repository.writeError = const ApiException('Слишком много запросов');
      expect(await restarted.submit({'id': 'new-wrong-key'}), isFalse);
      expect(
        restarted.pending,
        payload,
        reason:
            'A rejected retry does not prove that the original write failed',
      );
      repository.writeError = null;
      expect(await restarted.submit({'id': 'new-wrong-key'}), isTrue);
      expect(repository.writes, [payload, payload, payload]);
      expect(restarted.pending, isNull);

      final afterSuccess = TripSubmission(repository);
      await afterSuccess.restore();
      expect(afterSuccess.pending, isNull);
      restarted.dispose();
      afterSuccess.dispose();
    },
  );

  test('historical Almaty timezone and form timestamps agree', () {
    expect(clockLabel(DateTime.parse('2023-10-06T23:30:00+06:00')), '23:30');
    expect(
      almatyTimestamp(parseDay('2023-10-06'), 23 * 60 + 30),
      '2023-10-06T23:30:00+06:00',
    );
    expect(
      almatyTimestamp(parseDay('2026-10-06'), 23 * 60 + 30),
      '2026-10-06T23:30:00+05:00',
    );
  });

  test(
    'manual date selection during startup remains selected on refresh',
    () async {
      final repository = FakeRepository()
        ..delayedDates = Completer<List<DateTime>>();
      final controller = DiaryController(repository);
      final initialization = controller.initialize();
      await controller.selectDate(parseDay('2026-10-04'));
      repository.delayedDates!.complete([parseDay('2026-10-06')]);
      await initialization;
      await controller.reload();
      expect(dateKey(controller.selectedDate), '2026-10-04');
      controller.dispose();
    },
  );

  test('only a matching trip acknowledgment clears an API write', () async {
    final payload = <String, dynamic>{
      'id': 'stable-key',
      'start': '2026-10-06T09:00:00+05:00',
      'end': '2026-10-06T09:30:00+05:00',
      'amount': '2400.00',
      'commission': '360.00',
      'payment': 'card',
    };
    for (final body in [
      <String, dynamic>{},
      {...payload, 'id': 'wrong-id'},
      {...payload, 'amount': '2500.00'},
    ]) {
      final api = DiaryApi(
        baseUrl: 'http://example.test',
        client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
      );
      await expectLater(
        api.addTrip(payload),
        throwsA(
          isA<ApiException>().having(
            (error) => error.uncertain,
            'uncertain',
            isTrue,
          ),
        ),
      );
      api.close();
    }
    final api = DiaryApi(
      baseUrl: 'http://example.test',
      client: MockClient((_) async => http.Response(jsonEncode(payload), 201)),
    );
    await api.addTrip(payload);
    api.close();
  });

  test('invalid stored drafts cannot break the form', () async {
    SharedPreferences.setMockInitialValues({
      'smena.pendingTrip.v1': jsonEncode({
        'id': 'x',
        'start': 'x',
        'end': 'x',
        'amount': 'x',
        'commission': '0',
        'payment': 'card',
      }),
    });
    final submission = TripSubmission(FakeRepository());
    await submission.restore();
    expect(submission.pending, isNull);
    expect(submission.restoring, isFalse);
    submission.dispose();
  });

  for (final config in [
    (360.0, 1.0),
    (360.0, 1.5),
    (760.0, 1.0),
    (1280.0, 1.0),
  ]) {
    testWidgets(
      'diary and form fit ${config.$1}px at text scale ${config.$2}',
      (tester) async {
        tester.view.physicalSize = Size(config.$1, 1000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.$2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(SmenaApp(repository: FakeRepository()));
        await tester.pumpAndSettle();
        expect(find.text('6 октября'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Добавить поездку').first);
        await tester.pumpAndSettle();
        expect(find.text('Новая поездка'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Закрыть форму'));
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -700),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('connection failure is not presented as zero earnings', (
    tester,
  ) async {
    await tester.pumpWidget(
      SmenaApp(repository: FakeRepository()..failRead = true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить день'), findsOneWidget);
    expect(find.text('0 ₸'), findsNothing);
    expect(find.text('Попробовать снова'), findsOneWidget);
  });

  testWidgets(
    'form saves fractional money and midnight crossing with one stable id',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeRepository();
      await tester.pumpWidget(SmenaApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Добавить поездку').first);
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '23:50');
      await tester.enterText(fields.at(1), '00:10');
      await tester.enterText(fields.at(2), '2400,50');
      await tester.enterText(fields.at(3), '360');
      await tester.tap(find.text('Окончание на следующий день'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Добавить поездку').last);
      await tester.tap(find.text('Добавить поездку').last);
      await tester.pumpAndSettle();
      expect(repository.writes, hasLength(1));
      final saved = repository.writes.single;
      expect(saved['amount'], '2400.50');
      expect(saved['commission'], '360.00');
      expect(saved['start'], '2026-10-06T23:50:00+05:00');
      expect(saved['end'], '2026-10-07T00:10:00+05:00');
      expect(saved['id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(find.text('Новая поездка'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
