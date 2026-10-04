import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../services/attendance_service.dart';
import '../widgets/logout_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _userRole = 'student';
  String _userName = 'User';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('user_role') ?? 'student';
      _userName = prefs.getString('user_name') ?? 'User';
    });
  }

  void _handleSync() async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Syncing offline records...")));
    final AttendanceService service = AttendanceService();
    String result = await service.syncOfflineRecords();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 30),
          Center(
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: AppColors.primaryRed,
                  child: Icon(Icons.person, size: 50, color: Colors.white),
                ),
                const SizedBox(height: 15),
                Text(
                  _userName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Chip(
                  label: Text(_userRole.toUpperCase()),
                  backgroundColor: Colors.grey[200],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          ListTile(
            leading: const Icon(Icons.sync, color: Colors.blue),
            title: const Text("Sync Offline Data"),
            subtitle: const Text("Upload saved records"),
            onTap: _handleSync,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Logout", style: TextStyle(color: Colors.red)),
            onTap: () => showLogoutDialog(context),
          ),
        ],
      ),
    );
  }
}
