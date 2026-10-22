import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.needsPin = false});
  final String message;
  final int? status;
  final bool needsPin;
  @override
  String toString() => message;
}

/// Everything the rider app asks the website. Every call carries the rider's Supabase access token.
class Api {
  Api._();

  static SupabaseClient get db => Supabase.instance.client;
  static User? get user => db.auth.currentUser;

  static Map<String, String> _headers({bool json = false}) {
    final token = db.auth.currentSession?.accessToken;
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _decode(http.Response res) async {
    Map<String, dynamic> out = {};
    try {
      final d = jsonDecode(res.body);
      if (d is Map<String, dynamic>) out = d;
    } catch (_) {}
    if (res.statusCode >= 400) {
      throw ApiException('${out['error'] ?? 'Something went wrong. Please try again.'}', status: res.statusCode, needsPin: out['needsPin'] == true);
    }
    return out;
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    try {
      final res = await http.get(Uri.parse('${AppConfig.siteUrl}$path'), headers: _headers()).timeout(const Duration(seconds: 20));
      return await _decode(res);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('No connection. Check your internet.');
    }
  }

  static Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic> body = const {}]) async {
    try {
      final res = await http
          .post(Uri.parse('${AppConfig.siteUrl}$path'), headers: _headers(json: true), body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      return await _decode(res);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('No connection. Check your internet.');
    }
  }

  // ---- account -----------------------------------------------------------------------------------------------

  static String _phone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final ten = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
    return '${AppConfig.phoneCountryCode}$ten';
  }

  static Future<void> sendOtp(String phone) => db.auth.signInWithOtp(phone: _phone(phone));
  static Future<AuthResponse> verifyOtp(String phone, String code) => db.auth.verifyOTP(phone: _phone(phone), token: code.trim(), type: OtpType.sms);
  static Future<void> signOut() => db.auth.signOut();

  static Future<Me> me() async => Me.fromJson(await _get('/api/rider/me'));

  static Future<void> apply({
    required String fullName,
    required String phone,
    required String vehicleType,
    String? city,
    String? vehicleNumber,
    String? licenseNumber,
  }) =>
      _post('/api/rider/apply', {
        'fullName': fullName,
        'phone': phone,
        'vehicleType': vehicleType,
        'city': city,
        'vehicleNumber': vehicleNumber,
        'licenseNumber': licenseNumber,
      });

  /// Uploads one document photo as a multipart form.
  static Future<void> uploadDocument({required String kind, required Uint8List bytes, required String filename}) async {
    final req = http.MultipartRequest('POST', Uri.parse('${AppConfig.siteUrl}/api/rider/documents'))
      ..headers.addAll(_headers())
      ..fields['kind'] = kind
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _mediaType(filename)));
    try {
      final streamed = await req.send().timeout(const Duration(seconds: 90));
      await _decode(await http.Response.fromStream(streamed));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('The upload failed. Check your internet and try again.');
    }
  }

  static http.MediaType? _mediaType(String name) {
    final n = name.toLowerCase();
    final sub = n.endsWith('.png') ? 'png' : n.endsWith('.webp') ? 'webp' : n.endsWith('.pdf') ? 'pdf' : 'jpeg';
    return http.MediaType(sub == 'pdf' ? 'application' : 'image', sub);
  }

  // ---- working -----------------------------------------------------------------------------------------------

  static Future<void> setOnline(bool online) => _post('/api/rider/online', {'online': online});
  static Future<void> sendLocation(double lat, double lng) => _post('/api/rider/location', {'lat': lat, 'lng': lng});

  /// The delivery the rider is on, or the offers waiting for an answer.
  static Future<({Trip? active, List<Trip> offers})> offers() async {
    final j = await _get('/api/rider/offers');
    final active = j['active'] == null ? null : Trip.fromJson(Map<String, dynamic>.from(j['active'] as Map));
    final offers = ((j['offers'] as List?) ?? const []).map((o) => Trip.fromJson(Map<String, dynamic>.from(o as Map))).toList();
    return (active: active, offers: offers);
  }

  static Future<Trip> accept(String id) async => Trip.fromJson(Map<String, dynamic>.from((await _post('/api/rider/offers/$id/accept'))['trip'] as Map));
  static Future<void> decline(String id) => _post('/api/rider/offers/$id/decline');

  static Future<void> step(String tripId, String step, {String? pin, String? overrideReason}) =>
      _post('/api/rider/trips/$tripId/step', {'step': step, 'pin': pin, 'overrideReason': overrideReason});

  static Future<void> drop(String tripId) => _post('/api/rider/trips/$tripId/drop');

  static Future<Earnings> earnings() async => Earnings.fromJson(await _get('/api/rider/earnings'));

  /// The payouts Hyperpik has made to this rider, newest first.
  static Future<List<Payout>> payouts() async {
    final j = await _get('/api/rider/payouts');
    return ((j['payouts'] as List?) ?? const [])
        .map((p) => Payout(amount: _num((p as Map)['amount']), reference: '${p['reference']}', at: DateTime.tryParse('${p['at']}')?.toLocal() ?? DateTime.now()))
        .toList();
  }

  /// The bank account payouts go to (masked), or null when none is saved yet.
  static Future<BankAccount?> bank() async {
    final j = await _get('/api/rider/bank');
    final b = j['bank'];
    if (b is! Map) return null;
    return BankAccount(holderName: '${b['holderName']}', last4: '${b['last4']}', ifsc: '${b['ifsc']}');
  }

  static Future<BankAccount> saveBank({required String holderName, required String accountNumber, required String ifsc}) async {
    final j = await _post('/api/rider/bank', {'holderName': holderName, 'accountNumber': accountNumber, 'ifsc': ifsc});
    final b = Map<String, dynamic>.from(j['bank'] as Map);
    return BankAccount(holderName: '${b['holderName']}', last4: '${b['last4']}', ifsc: '${b['ifsc']}');
  }

  static num _num(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);
}
