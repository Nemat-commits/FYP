import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../models/walk_models.dart';
import '../services/native_tracker_bridge.dart';

/// Live telemetry from the Kotlin foreground service (EventChannel).
class TelemetryNotifier extends Notifier<TelemetryState> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  TelemetryState build() {
    _sub ??= NativeTrackerBridge.telemetryStream.listen(
      (event) => state = TelemetryState.fromMap(event),
      onError: (_) {},
    );
    ref.onDispose(() => _sub?.cancel());
    return const TelemetryState();
  }

  Future<Map<String, dynamic>> startWalk() async {
    final res = await NativeTrackerBridge.startWalk();
    state = TelemetryState.fromMap(res);
    return res;
  }

  Future<Map<String, dynamic>> pauseWalk() async {
    final res = await NativeTrackerBridge.pauseWalk();
    state = TelemetryState.fromMap(res);
    return res;
  }

  Future<Map<String, dynamic>> resumeWalk() async {
    final res = await NativeTrackerBridge.resumeWalk();
    state = TelemetryState.fromMap(res);
    return res;
  }

  Future<Map<String, dynamic>> finishWalk() async {
    final res = await NativeTrackerBridge.finishWalk();
    ref.read(sessionsProvider.notifier).refresh();
    return res;
  }
}

final telemetryProvider =
    NotifierProvider<TelemetryNotifier, TelemetryState>(TelemetryNotifier.new);

/// Saved walk sessions from Room (MethodChannel getSavedSessions).
class SessionsNotifier extends Notifier<AsyncValue<List<WalkSession>>> {
  @override
  AsyncValue<List<WalkSession>> build() {
    Future.microtask(refresh);
    return const AsyncValue.loading();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final raw = await NativeTrackerBridge.getSavedSessions();
      state = AsyncValue.data(raw.map(WalkSession.fromMap).toList());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Map<String, dynamic>> generateDemoWalk() async {
    final res = await NativeTrackerBridge.generateDemoWalk();
    await refresh();
    return res;
  }

  Future<SessionDetail> getDetail(String sessionId) async {
    final raw = await NativeTrackerBridge.getSessionDetail(sessionId);
    return SessionDetail.fromMap(raw);
  }

  Future<String> exportToDownloads(String sessionId) async {
    return NativeTrackerBridge.exportToDownloads(sessionId);
  }
}

final sessionsProvider =
    NotifierProvider<SessionsNotifier, AsyncValue<List<WalkSession>>>(SessionsNotifier.new);

/// Native diagnostics (sensors, baseline, last fix).
class DiagnosticsNotifier extends Notifier<AsyncValue<Map<String, dynamic>>> {
  @override
  AsyncValue<Map<String, dynamic>> build() {
    Future.microtask(refresh);
    return const AsyncValue.loading();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await NativeTrackerBridge.getDiagnostics());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final diagnosticsProvider =
    NotifierProvider<DiagnosticsNotifier, AsyncValue<Map<String, dynamic>>>(
        DiagnosticsNotifier.new);

/// Effective Mapbox public token (dart-define wins, else in-app setting).
class MapboxTokenNotifier extends Notifier<AsyncValue<String>> {
  @override
  AsyncValue<String> build() {
    Future.microtask(refresh);
    return const AsyncValue.loading();
  }

  Future<void> refresh() async {
    state = AsyncValue.data(await AppConfig.getEffectiveMapboxToken());
  }

  Future<void> save(String token) async {
    await AppConfig.saveMapboxToken(token);
    state = AsyncValue.data(await AppConfig.getEffectiveMapboxToken());
  }
}

final mapboxTokenProvider =
    NotifierProvider<MapboxTokenNotifier, AsyncValue<String>>(MapboxTokenNotifier.new);
