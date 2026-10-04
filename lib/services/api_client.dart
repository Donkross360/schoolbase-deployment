import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class ApiClient {
  static Future<bool>? _refreshInProgress;

  static Future<http.Response> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$schoolBaseApiBase$path').replace(queryParameters: query);
    var response = await _send(method, uri, body);
    if (response.statusCode == 401 && await _refresh()) {
      response = await _send(method, uri, body);
    }
    return response;
  }

  static Future<http.Response> _send(String method, Uri uri, Object? body) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null || token.isEmpty) throw StateError('Please sign in again');
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    if (method == 'GET') {
      return http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    }
    return http.post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
  }

  static Future<bool> _refresh() async {
    final pending = _refreshInProgress;
    if (pending != null) return pending;
    final attempt = _doRefresh();
    _refreshInProgress = attempt;
    try {
      return await attempt;
    } finally {
      _refreshInProgress = null;
    }
  }

  static Future<bool> _doRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) return false;
    try {
      final response = await http.post(
        Uri.parse('$schoolBaseApiBase/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body) as Map;
      final tokens = decoded['data'] is Map ? decoded['data'] as Map : decoded;
      final access = tokens['access_token']?.toString();
      final refresh = tokens['refresh_token']?.toString();
      if (access == null || refresh == null) return false;
      await prefs.setString('auth_token', access);
      await prefs.setString('refresh_token', refresh);
      return true;
    } catch (_) {
      return false;
    }
  }
}
