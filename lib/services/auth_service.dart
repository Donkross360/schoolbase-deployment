import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'api_config.dart';

class AuthService {
  Future<String?> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$schoolBaseApiBase/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        String? token = data['access_token']?.toString();
        if (token == null && data['data'] != null) {
          token = data['data']['access_token']?.toString();
        }

        if (token != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
          final tokens = data['data'] is Map ? data['data'] as Map : data as Map;
          if (tokens['refresh_token'] != null) {
            await prefs.setString('refresh_token', tokens['refresh_token'].toString());
          }
          final user = data['user'] ?? data['data']?['user'];
          if (user is Map && user['role'] != null) {
            final roles = user['role'] is List ? user['role'] as List : [user['role']];
            if (roles.isNotEmpty) {
              final role = roles.map((value) => value.toString().toLowerCase()).firstWhere(
                (value) => value == 'teacher' || value == 'admin',
                orElse: () => roles.first.toString().toLowerCase(),
              );
              await prefs.setString('user_role', role);
            }
            await prefs.setString('user_name', '${user['first_name']} ${user['last_name']}');
          } else {
            await _fetchAndSaveRole(token);
          }
          return null;
        }
      }
      return "Login failed. Check credentials.";
    } catch (e) {
      return 'Connection Error: $e';
    }
  }

  Future<void> _fetchAndSaveRole(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$schoolBaseApiBase/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String role = 'student';
        var userData = (data['data'] != null) ? data['data'] : data;
        if (userData['role'] != null) {
          List roles = (userData['role'] is List)
              ? userData['role']
              : [userData['role']];
          if (roles.isNotEmpty) {
            role = roles.map((value) => value.toString().toLowerCase()).firstWhere(
              (value) => value == 'teacher' || value == 'admin',
              orElse: () => roles.first.toString().toLowerCase(),
            );
          }
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', role);
        await prefs.setString(
          'user_name',
          "${userData['first_name']} ${userData['last_name']}",
        );
      }
    } catch (e) {
      debugPrint("Role error: $e");
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
