import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Where the Node API lives. Override at run time, e.g.
///   flutter run --dart-define=API_BASE=http://10.0.2.2:4000      (Android emulator)
///   flutter run --dart-define=API_BASE=https://api.example.com   (production)
const apiBase =
    String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:4000');

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class Api {
  static String? _device;
  static String? _token;
  static final sessionExpired = ValueNotifier<bool>(false);

  /// Anonymous id that lets the app list "my reports" without a login.
  static Future<String> deviceId() async {
    if (_device != null) return _device!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      final r = Random.secure();
      id =
          'dev-${List.generate(4, (_) => r.nextInt(1 << 30).toRadixString(36)).join()}';
      await prefs.setString('device_id', id);
    }
    return _device = id;
  }

  static dynamic _handle(http.Response res) {
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {}
    if (res.statusCode >= 400) {
      throw ApiException(
        body is Map && body['error'] is String
            ? body['error'] as String
            : 'Request failed (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    return body;
  }

  static Future<dynamic> _guard(Future<http.Response> Function() call) async {
    try {
      return _handle(await call().timeout(const Duration(seconds: 20)));
    } on ApiException catch (e) {
      if (e.statusCode == 401 && _token != null) {
        await _clearSession(expired: true);
      }
      rethrow;
    } catch (_) {
      throw ApiException(
          'Can’t reach the server. Check your connection and try again.');
    }
  }

  /* ── The phone number used for "My reports" ── */

  static Future<String?> savedPhone() async =>
      (await SharedPreferences.getInstance()).getString('my_phone');
  static Future<void> savePhone(String phone) async =>
      (await SharedPreferences.getInstance()).setString('my_phone', phone);
  static Future<void> clearPhone() async =>
      (await SharedPreferences.getInstance()).remove('my_phone');
  static Future<int> savedCitizenTab() async {
    final tab = (await SharedPreferences.getInstance()).getInt('citizen_tab');
    return tab != null && tab >= 0 && tab <= 2 ? tab : 0;
  }

  static Future<void> saveCitizenTab(int tab) async =>
      (await SharedPreferences.getInstance()).setInt('citizen_tab', tab);

  static Uri _uri(String path, [Map<String, String>? q]) =>
      Uri.parse('$apiBase$path').replace(queryParameters: q);
  static Map<String, String> get _auth =>
      _token == null ? {} : {'Authorization': 'Bearer $_token'};

  static Future<DashboardUser?> restoreDashboardSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('dashboard_token');
    if (_token == null || _token!.isEmpty) return null;
    try {
      return DashboardUser.fromJson(
          await _guard(() => http.get(_uri('/api/auth/me'), headers: _auth))
              as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 401) return null;
      rethrow;
    }
  }

  static Future<DashboardUser> login(String userNumber, String password) async {
    final data = await _guard(() => http.post(
          _uri('/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'userNumber': userNumber, 'password': password}),
        )) as Map<String, dynamic>;
    _token = data['token'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dashboard_token', _token!);
    sessionExpired.value = false;
    return DashboardUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  static Future<void> logout() async {
    try {
      if (_token != null) {
        await _guard(() => http.post(_uri('/api/auth/logout'), headers: _auth));
      }
    } finally {
      await _clearSession();
    }
  }

  static Future<void> _clearSession({bool expired = false}) async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dashboard_token');
    sessionExpired.value = expired;
  }

  /* ── Citizen app ── */

  static Future<ReportSummary> createReport({
    required String leakType,
    required String severity,
    required double lat,
    required double lng,
    required String phone,
    String? name,
    String? notes,
    Uint8List? photo,
    String? photoName,
  }) async {
    final device = await deviceId();
    final data = await _guard(() async {
      final req = http.MultipartRequest('POST', _uri('/api/reports'))
        ..headers['X-Device-Id'] = device
        ..fields.addAll({
          'leak_type': leakType,
          'severity': severity,
          'lat': '$lat',
          'lng': '$lng',
          if (name != null && name.isNotEmpty) 'name': name,
          'phone': phone,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        });
      if (photo != null) {
        req.files.add(http.MultipartFile.fromBytes('photo', photo,
            filename: photoName ?? 'photo.jpg'));
      }
      return http.Response.fromStream(await req.send());
    });
    return ReportSummary.fromJson(data as Map<String, dynamic>);
  }

  /// Every report made with this phone number, including ones sent from other devices.
  static Future<List<ReportSummary>> myReports(String phone) async {
    final device = await deviceId();
    final data = await _guard(() => http.post(
          _uri('/api/reports/lookup'),
          headers: {'X-Device-Id': device, 'Content-Type': 'application/json'},
          body: jsonEncode({'phone': phone}),
        ));
    return (data as List)
        .map((e) => ReportSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<CityReport>> searchCityReports(String city) async {
    final data = await _guard(() => http.get(
          _uri('/api/reports/city', {'city': city}),
        ));
    return (data as List)
        .map((e) => CityReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /* ── Operations dashboard ── */

  static Future<List<Incident>> incidents({String q = ''}) async {
    final data = await _guard(() => http.get(
        _uri('/api/admin/incidents', q.isEmpty ? null : {'q': q}),
        headers: _auth));
    return (data as List)
        .map((e) => Incident.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<Stats> stats() async {
    final data =
        await _guard(() => http.get(_uri('/api/admin/stats'), headers: _auth));
    return Stats.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<ActivityItem>> activity() async {
    final data = await _guard(() =>
        http.get(_uri('/api/admin/activity', {'limit': '8'}), headers: _auth));
    return (data as List)
        .map((e) => ActivityItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Team>> teams() async {
    final data =
        await _guard(() => http.get(_uri('/api/admin/teams'), headers: _auth));
    return (data as List)
        .map((e) => Team.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> createTeam({
    required String name,
    String? lead,
  }) async {
    await _guard(() => http.post(
          _uri('/api/admin/teams'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode({'name': name, 'lead': lead}),
        ));
  }

  static Future<List<DashboardUser>> users() async {
    final data =
        await _guard(() => http.get(_uri('/api/admin/users'), headers: _auth));
    return (data as List)
        .map((e) => DashboardUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> createStaff({
    required String userNumber,
    required String displayName,
    required String password,
  }) async {
    await _guard(() => http.post(
          _uri('/api/admin/users'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'userNumber': userNumber,
            'displayName': displayName,
            'password': password,
          }),
        ));
  }

  /// Send only the fields that changed. A null value clears that field on the server.
  static Future<void> updateIncident(
      String id, Map<String, dynamic> changes) async {
    await _guard(() => http.patch(
          _uri('/api/admin/incidents/$id'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode(changes),
        ));
  }

  static Future<void> updateStatus(String id, String status) =>
      updateIncident(id, {'status': status});
}
