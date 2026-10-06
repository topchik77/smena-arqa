import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.uncertain = false});
  final String message;

  /// A write may have reached the server; preserve its id and payload for retry.
  final bool uncertain;
  @override
  String toString() => message;
}

abstract interface class DiaryRepository {
  Future<List<DateTime>> getDates();
  Future<DriverDay> getDay(DateTime date);
  Future<void> addTrip(Map<String, dynamic> payload);
  Future<DayInsight> getInsight(DateTime date);
  void close();
}

class DiaryApi implements DiaryRepository {
  DiaryApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = (baseUrl ?? _defaultBaseUrl()).replaceFirst(RegExp(r'/$'), '');
  final http.Client _client;
  final String _baseUrl;

  static String _defaultBaseUrl() {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) return Uri.base.origin;
    return defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
  }

  Future<dynamic> _request(
    String path, {
    Map<String, dynamic>? payload,
    Set<int>? acceptedStatuses,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1$path');
    try {
      final response =
          await (payload == null
                  ? _client.get(uri, headers: {'Accept': 'application/json'})
                  : _client.post(
                      uri,
                      headers: {
                        'Content-Type': 'application/json',
                        'Accept': 'application/json',
                      },
                      body: jsonEncode(payload),
                    ))
              .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (acceptedStatuses != null &&
            !acceptedStatuses.contains(response.statusCode)) {
          throw const ApiException(
            'Сохранение пока не подтверждено. Повторите попытку.',
            uncertain: true,
          );
        }
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
      if (response.statusCode == 409) {
        throw const ApiException(
          'Поездка с таким идентификатором уже существует с другими данными.',
        );
      }
      if (response.statusCode == 422 || response.statusCode == 400) {
        throw const ApiException(
          'Сервер отклонил данные. Проверьте время, сумму и комиссию.',
        );
      }
      if (response.statusCode == 429) {
        throw const ApiException(
          'Слишком много запросов. Попробуйте немного позже.',
        );
      }
      throw ApiException(
        'Сервер временно недоступен. Повторите попытку.',
        uncertain: payload != null && response.statusCode >= 500,
      );
    } on TimeoutException {
      throw ApiException(
        'Ответ сервера не получен. Проверьте соединение.',
        uncertain: payload != null,
      );
    } on http.ClientException {
      throw ApiException(
        'Не удалось подключиться к серверу. Проверьте соединение.',
        uncertain: payload != null,
      );
    } on FormatException {
      throw ApiException(
        'Сервер вернул неожиданный ответ. Повторите попытку.',
        uncertain: payload != null,
      );
    }
  }

  @override
  Future<List<DateTime>> getDates() async {
    final json = await _request('/dates') as Map<String, dynamic>;
    return (json['dates'] as List<dynamic>)
        .map((item) => parseDay(item as String))
        .toList()
      ..sort();
  }

  @override
  Future<DriverDay> getDay(DateTime date) async => DriverDay.fromJson(
    await _request('/days/${dateKey(date)}') as Map<String, dynamic>,
  );
  @override
  Future<void> addTrip(Map<String, dynamic> payload) async {
    final json = await _request(
      '/trips',
      payload: payload,
      acceptedStatuses: {200, 201},
    );
    try {
      final saved = Trip.fromJson(json as Map<String, dynamic>);
      final expected = Trip.fromJson(payload);
      if (saved.id != expected.id ||
          saved.start != expected.start ||
          saved.end != expected.end ||
          saved.amount != expected.amount ||
          saved.commission != expected.commission ||
          saved.payment != expected.payment) {
        throw const FormatException(
          'Trip acknowledgment does not match request',
        );
      }
    } catch (_) {
      throw const ApiException(
        'Сервер не подтвердил данные поездки. Повторите сохранение.',
        uncertain: true,
      );
    }
  }

  @override
  Future<DayInsight> getInsight(DateTime date) async => DayInsight.fromJson(
    await _request('/days/${dateKey(date)}/insights', payload: {})
        as Map<String, dynamic>,
  );
  @override
  void close() => _client.close();
}
