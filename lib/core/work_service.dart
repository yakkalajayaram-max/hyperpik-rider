import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

const _kRefresh = 'rt';
const _kAccess = 'at';
const _kAccessExp = 'atx';
const _kLastOffer = 'lastoffer';

/// Keeps a rider findable and told about deliveries while the app is closed.
///
/// An Android foreground service (with its permanent "you are online" notification) runs a small task every few seconds:
/// it sends the rider's position and checks for a new delivery offer, raising a loud notification when one arrives. The
/// screen does the same work itself while it is open, so the two never depend on each other.
///
/// The service has its own copy of the sign-in. Supabase rotates the refresh token on every exchange, so both sides keep
/// the newest one in the shared store and read it fresh before using it ([syncSession]).
class WorkService {
  static bool get supported => Platform.isAndroid;

  static Future<void> configure() async {
    if (!supported) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rider_online',
        channelName: 'You are online',
        channelDescription: 'Shown while you are online so Hyperpik can send you deliveries.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(6000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Shares the current sign-in with the service. Call whenever the session changes.
  static Future<void> syncSession(Session? s) async {
    if (!supported || s == null) return;
    await FlutterForegroundTask.saveData(key: _kRefresh, value: s.refreshToken ?? '');
    await FlutterForegroundTask.saveData(key: _kAccess, value: s.accessToken);
    await FlutterForegroundTask.saveData(key: _kAccessExp, value: (s.expiresAt ?? 0).toString());
  }

  /// The newest refresh token the service holds, so the screen can adopt it after the app was closed for a while.
  static Future<String?> latestRefreshToken() async {
    if (!supported) return null;
    final v = await FlutterForegroundTask.getData<String>(key: _kRefresh);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> start() async {
    if (!supported) return;
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      notificationTitle: 'You are online',
      notificationText: 'Waiting for deliveries near you',
      callback: _startCallback,
    );
  }

  static Future<void> stop() async {
    if (!supported) return;
    await FlutterForegroundTask.stopService();
  }

  static Future<bool> get isRunning async => supported && await FlutterForegroundTask.isRunningService;
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_RiderTaskHandler());
}

class _RiderTaskHandler extends TaskHandler {
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    await _notifications.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    const channel = AndroidNotificationChannel(
      'rider_offers',
      'New deliveries',
      description: 'A delivery is waiting for your answer.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  }

  /// A valid access token, refreshing with the shared refresh token when the current one is about to lapse.
  Future<String?> _token() async {
    final access = await FlutterForegroundTask.getData<String>(key: _kAccess);
    final exp = int.tryParse(await FlutterForegroundTask.getData<String>(key: _kAccessExp) ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (access != null && access.isNotEmpty && exp - now > 90) return access;

    final refresh = await FlutterForegroundTask.getData<String>(key: _kRefresh);
    if (refresh == null || refresh.isEmpty) return null;
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.supabaseUrl}/auth/v1/token?grant_type=refresh_token'),
        headers: {'apikey': AppConfig.supabaseAnonKey, 'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refresh}),
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      await FlutterForegroundTask.saveData(key: _kAccess, value: '${j['access_token']}');
      await FlutterForegroundTask.saveData(key: _kRefresh, value: '${j['refresh_token']}');
      await FlutterForegroundTask.saveData(key: _kAccessExp, value: '${j['expires_at'] ?? (now + 3000)}');
      return '${j['access_token']}';
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    final token = await _token();
    if (token == null) return;
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/json'};

    try {
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)));
      await http
          .post(Uri.parse('${AppConfig.siteUrl}/api/rider/location'), headers: headers, body: jsonEncode({'lat': pos.latitude, 'lng': pos.longitude}))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // No fix this time; the next tick tries again.
    }

    try {
      final res = await http.get(Uri.parse('${AppConfig.siteUrl}/api/rider/offers'), headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final offers = (j['offers'] as List?) ?? const [];
      if (offers.isEmpty) return;
      final first = offers.first as Map<String, dynamic>;
      final id = '${first['id']}';
      final seen = await FlutterForegroundTask.getData<String>(key: _kLastOffer);
      if (seen == id) return;
      await FlutterForegroundTask.saveData(key: _kLastOffer, value: id);

      final order = first['order'] as Map<String, dynamic>? ?? const {};
      final fee = (first['fee'] as num?)?.toStringAsFixed(0) ?? '';
      await _notifications.show(
        7001,
        'New delivery · ₹$fee',
        '${order['shopName'] ?? 'A shop'} · ${first['distanceKm'] ?? '?'} km. Open the app to accept.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'rider_offers',
            'New deliveries',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            playSound: true,
            enableVibration: true,
            timeoutAfter: 60000,
          ),
        ),
      );
      FlutterForegroundTask.updateService(notificationTitle: 'New delivery waiting', notificationText: '₹$fee · tap to open');
    } catch (_) {}
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}
