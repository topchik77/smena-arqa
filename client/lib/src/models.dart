import 'dart:math';

import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

/// Money is represented in tiyn everywhere in the client. No floating point
/// parsing or formatting is involved in money calculations.
int parseMoney(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) {
    throw const FormatException('Введите сумму с точностью до двух знаков');
  }
  final parts = normalized.split('.');
  final result =
      int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  if (result > 9007199254740991) {
    throw const FormatException('Сумма слишком большая');
  }
  return result;
}

String moneyDecimal(int value) =>
    '${value ~/ 100}.${(value.abs() % 100).toString().padLeft(2, '0')}';

String moneyLabel(int value, {bool currency = true}) {
  final absolute = value.abs();
  final digits = (absolute ~/ 100).toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '\u00a0',
  );
  final fraction = absolute % 100;
  final decimal = fraction == 0
      ? ''
      : ',${fraction.toString().padLeft(2, '0')}';
  return '${value < 0 ? '−' : ''}$grouped$decimal${currency ? ' ₸' : ''}';
}

final timezone.Location _almaty = () {
  timezone_data.initializeTimeZones();
  return timezone.getLocation('Asia/Almaty');
}();
DateTime almatyLocal(DateTime value) =>
    timezone.TZDateTime.from(value, _almaty);
DateTime almatyNow() => timezone.TZDateTime.now(_almaty);

String almatyTimestamp(DateTime date, int minutes) {
  final local = timezone.TZDateTime(
    _almaty,
    date.year,
    date.month,
    date.day,
    minutes ~/ 60,
    minutes % 60,
  );
  final offset = local.timeZoneOffset.inMinutes;
  final hours = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  final offsetHours = (offset.abs() ~/ 60).toString().padLeft(2, '0');
  final offsetMinutes = (offset.abs() % 60).toString().padLeft(2, '0');
  return '${dateKey(date)}T$hours:$minute:00${offset >= 0 ? '+' : '-'}$offsetHours:$offsetMinutes';
}

DateTime dayOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
String dateKey(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
DateTime parseDay(String value) => dayOnly(DateTime.parse(value));

const months = <String>[
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];
const weekdays = <String>[
  'понедельник',
  'вторник',
  'среда',
  'четверг',
  'пятница',
  'суббота',
  'воскресенье',
];
String humanDate(DateTime day) => '${day.day} ${months[day.month - 1]}';
String clockLabel(DateTime value) {
  final local = almatyLocal(value);
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String durationLabel(int minutes) => minutes < 60
    ? '$minutes мин'
    : '${minutes ~/ 60} ч${minutes % 60 == 0 ? '' : ' ${minutes % 60} мин'}';
String tripsLabel(int count) {
  if (count % 100 >= 11 && count % 100 <= 14) return '$count поездок';
  return switch (count % 10) {
    1 => '$count поездка',
    2 || 3 || 4 => '$count поездки',
    _ => '$count поездок',
  };
}

String newTripId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class Trip {
  const Trip({
    required this.id,
    required this.start,
    required this.end,
    required this.amount,
    required this.commission,
    required this.payment,
  });
  final String id;
  final DateTime start;
  final DateTime end;
  final int amount;
  final int commission;
  final String payment;
  int get net => amount - commission;
  int get minutes => end.difference(start).inMinutes;
  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
    id: json['id'] as String,
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
    amount: parseMoney(json['amount'].toString()),
    commission: parseMoney(json['commission'].toString()),
    payment: json['payment'] as String,
  );
}

class DaySummary {
  const DaySummary({
    required this.tripCount,
    required this.revenue,
    required this.commission,
    required this.net,
    required this.cash,
    required this.card,
    required this.tripMinutes,
  });
  final int tripCount;
  final int revenue;
  final int commission;
  final int net;
  final int cash;
  final int card;
  final int tripMinutes;
  factory DaySummary.fromJson(Map<String, dynamic> json) => DaySummary(
    tripCount: json['trip_count'] as int,
    revenue: parseMoney(json['revenue'].toString()),
    commission: parseMoney(json['commission'].toString()),
    net: parseMoney(json['net'].toString()),
    cash: parseMoney(json['cash'].toString()),
    card: parseMoney(json['card'].toString()),
    tripMinutes: json['trip_minutes'] as int,
  );
}

class DriverDay {
  const DriverDay({
    required this.date,
    required this.trips,
    required this.summary,
  });
  final DateTime date;
  final List<Trip> trips;
  final DaySummary summary;
  factory DriverDay.fromJson(Map<String, dynamic> json) => DriverDay(
    date: parseDay(json['date'] as String),
    trips: (json['trips'] as List<dynamic>)
        .map((item) => Trip.fromJson(item as Map<String, dynamic>))
        .toList(),
    summary: DaySummary.fromJson(json['summary'] as Map<String, dynamic>),
  );
}

class DayInsight {
  const DayInsight({
    required this.source,
    required this.title,
    required this.text,
    required this.facts,
    required this.limitations,
  });
  final String source;
  final String title;
  final String text;
  final List<String> facts;
  final List<String> limitations;
  factory DayInsight.fromJson(Map<String, dynamic> json) => DayInsight(
    source: json['source'] as String,
    title: json['title'] as String,
    text: json['text'] as String,
    facts: List<String>.from(json['facts'] as List<dynamic>),
    limitations: List<String>.from(json['limitations'] as List<dynamic>),
  );
}
