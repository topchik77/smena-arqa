import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

/// Lives outside the modal, so closing a failed form cannot lose a retry key.
class TripSubmission extends ChangeNotifier {
  TripSubmission(this.repository);
  final DiaryRepository repository;
  Map<String, dynamic>? pending;
  String? error;
  bool sending = false;
  bool restoring = true;
  bool _disposed = false;
  bool _wasUncertain = false;
  static const _storageKey = 'smena.pendingTrip.v1';

  Future<void> restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString(_storageKey);
      if (stored != null) {
        final decoded = jsonDecode(stored) as Map<String, dynamic>;
        const requiredKeys = [
          'id',
          'start',
          'end',
          'amount',
          'commission',
          'payment',
        ];
        if (requiredKeys.every((key) => decoded[key] is String) &&
            _validDraft(decoded)) {
          pending = Map<String, dynamic>.unmodifiable({
            for (final key in requiredKeys) key: decoded[key],
          });
          _wasUncertain = true;
          error =
              'Есть поездка без подтверждения сохранения. Повторите отправку.';
        } else {
          await preferences.remove(_storageKey);
        }
      }
    } catch (_) {
      // Storage may be unavailable (for example, browser privacy settings).
      // The diary stays usable; submission itself checks durable write below.
    }
    restoring = false;
    if (!_disposed) notifyListeners();
  }

  bool _validDraft(Map<String, dynamic> payload) {
    try {
      final trip = Trip.fromJson(payload);
      final timestamp = RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$',
      );
      return trip.id.isNotEmpty &&
          trip.id.length <= 128 &&
          timestamp.hasMatch(payload['start'] as String) &&
          timestamp.hasMatch(payload['end'] as String) &&
          trip.end.isAfter(trip.start) &&
          trip.amount > 0 &&
          trip.amount <= 10000000000 &&
          trip.commission <= trip.amount &&
          {'card', 'cash'}.contains(trip.payment);
    } catch (_) {
      return false;
    }
  }

  Future<bool> submit(Map<String, dynamic> payload) async {
    if (sending || restoring) return false;
    pending ??= Map<String, dynamic>.unmodifiable(payload);
    sending = true;
    error = null;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      final persisted = await preferences.setString(
        _storageKey,
        jsonEncode(pending),
      );
      if (!persisted) {
        throw const ApiException(
          'Не удалось сохранить черновик на устройстве. Повторите попытку.',
        );
      }
      await repository.addTrip(pending!);
      await preferences.remove(_storageKey);
      pending = null;
      _wasUncertain = false;
      sending = false;
      if (!_disposed) notifyListeners();
      return true;
    } catch (exception) {
      sending = false;
      if (exception is ApiException) {
        error = exception.message;
        _wasUncertain = _wasUncertain || exception.uncertain;
        if (!_wasUncertain) {
          pending = null;
          try {
            final preferences = await SharedPreferences.getInstance();
            await preferences.remove(_storageKey);
          } catch (_) {
            /* A retry remains safe if storage cleanup is unavailable. */
          }
        }
      } else {
        _wasUncertain = true;
        error = 'Ответ сервера не получен. Повторите сохранение.';
      }
      if (!_disposed) notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
