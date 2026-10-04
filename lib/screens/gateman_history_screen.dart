import 'package:flutter/material.dart';
import '../services/attendance_service.dart';
import '../services/database_helper.dart';
import '../widgets/logout_dialog.dart';

class GatemanHistoryScreen extends StatefulWidget {
  const GatemanHistoryScreen({super.key});
  @override
  State<GatemanHistoryScreen> createState() => _GatemanHistoryScreenState();
}

class _GatemanHistoryScreenState extends State<GatemanHistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    var r = await DatabaseHelper.instance.getAllUnsynced();
    if (!mounted) return;
    setState(() => _records = r.reversed.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Offline History",
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () => showLogoutDialog(context),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _records.length,
        itemBuilder: (c, i) => ListTile(
          title: Text("ID: ${_records[i]['nfc_tag']}"),
          subtitle: Text(_records[i]['timestamp']),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.sync),
        onPressed: () async {
          String res = await AttendanceService().syncOfflineRecords();
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(res)));
            _load();
          }
        },
      ),
    );
  }
}
