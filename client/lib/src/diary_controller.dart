import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

class DiaryController extends ChangeNotifier {
  DiaryController(this.repository) : selectedDate = dayOnly(almatyNow());
  final DiaryRepository repository;
  DateTime selectedDate;
  DriverDay? day;
  DayInsight? insight;
  String? error;
  String? insightError;
  bool loading = true;
  bool insightLoading = false;
  int _request = 0;
  int _insightRequest = 0;
  bool _disposed = false;
  bool _initialized = false;

  Future<void> initialize() async {
    final request = ++_request;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final dates = await repository.getDates();
      if (_disposed || request != _request) return;
      _initialized = true;
      await selectDate(dates.isEmpty ? dayOnly(almatyNow()) : dates.last);
    } catch (exception) {
      if (_disposed || request != _request) return;
      error = _message(exception);
      loading = false;
      notifyListeners();
    }
  }

  Future<void> reload() =>
      _initialized ? selectDate(selectedDate) : initialize();

  Future<void> selectDate(DateTime date) async {
    _initialized = true;
    final request = ++_request;
    ++_insightRequest;
    selectedDate = dayOnly(date);
    day = null;
    insight = null;
    error = null;
    insightError = null;
    loading = true;
    insightLoading = false;
    notifyListeners();
    try {
      final result = await repository.getDay(selectedDate);
      if (_disposed || request != _request) return;
      day = result;
    } catch (exception) {
      if (_disposed || request != _request) return;
      error = _message(exception);
    }
    if (_disposed || request != _request) return;
    loading = false;
    notifyListeners();
  }

  Future<void> loadInsight() async {
    if (insightLoading || day == null) return;
    final request = ++_insightRequest;
    insightLoading = true;
    insightError = null;
    notifyListeners();
    try {
      final result = await repository.getInsight(selectedDate);
      if (_disposed || request != _insightRequest) return;
      insight = result;
    } catch (exception) {
      if (_disposed || request != _insightRequest) return;
      insightError = _message(exception);
    }
    if (_disposed || request != _insightRequest) return;
    insightLoading = false;
    notifyListeners();
  }

  static String _message(Object exception) => exception is ApiException
      ? exception.message
      : 'Не удалось прочитать данные. Повторите попытку.';

  @override
  void dispose() {
    _disposed = true;
    repository.close();
    super.dispose();
  }
}
