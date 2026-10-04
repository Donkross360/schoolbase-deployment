import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';
import '../services/nfc_service.dart';
import '../utils/constants.dart';
import '../widgets/logout_dialog.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: const Icon(Icons.security, color: AppColors.primaryRed),
        title: const Text(
          "Admin Portal",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.primaryRed),
            onPressed: () => showLogoutDialog(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(50),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primaryRed, width: 8),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.nfc,
                size: 120,
                color: AppColors.primaryRed,
              ),
            ),
            const SizedBox(height: 40),
            const Text(
              "Card Management",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "Link physical NFC cards to registered students.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 80,
              child: ElevatedButton(
                onPressed: () => _showUserSearchSheet(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 5,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.add_link, color: Colors.white, size: 40),
                    SizedBox(width: 20),
                    Text(
                      "Link User Card",
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showUserSearchSheet(BuildContext context) {
    context.read<AdminProvider>().searchUsers("");
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const UserSearchSheet(),
    );
  }
}

class UserSearchSheet extends StatelessWidget {
  const UserSearchSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            "Select User",
            style: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            onChanged: (val) {
              context.read<AdminProvider>().searchUsers(val);
            },
            decoration: InputDecoration(
              hintText: "Search name...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey[100],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Consumer<AdminProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryRed,
                    ),
                  );
                }
                if (provider.users.isEmpty) {
                  return const Center(child: Text("No users found."));
                }
                return ListView.builder(
                  itemCount: provider.users.length,
                  itemBuilder: (ctx, i) {
                    final u = provider.users[i];
                    return Card(
                      color: Colors.grey[50],
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryRed,
                          child: Text(
                            (u['name'] ?? 'U')[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          u['name'] ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        // Shows Type (STUDENT/TEACHER)
                        subtitle: Text(
                          "${u['type'].toString().toUpperCase()} • ${u['school_id']}",
                          style: const TextStyle(color: Colors.grey),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _showScanDialog(context, u);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showScanDialog(BuildContext context, Map<String, dynamic> user) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ScanDialog(user: user),
    );
  }
}

class ScanDialog extends StatefulWidget {
  final Map<String, dynamic> user;
  const ScanDialog({super.key, required this.user});
  @override
  State<ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<ScanDialog> {
  final NfcService _nfcService = NfcService();
  String _status = "Tap Card to Link";
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _startLinking();
  }

  void _startLinking() {
    final adminProvider = context.read<AdminProvider>();
    _nfcService.startSession(
      onTagRead: (cardUid) async {
        setState(() => _status = "Card Found! Linking...");
        // Pass the user type (teacher/student) to the provider
        String? err = await adminProvider.linkCard(
          widget.user['id'].toString(),
          cardUid,
          widget.user['type'].toString(),
        );

        if (mounted) {
          if (err == null) {
            setState(() {
              _success = true;
              _status = "Successfully Linked!";
            });
            Future.delayed(
              const Duration(seconds: 2),
              () {
                if (mounted) Navigator.pop(context);
              },
            );
          } else {
            setState(() => _status = "Error: $err");
          }
        }
      },
      onError: (err) {
        if (mounted) setState(() => _status = "Scan Error. Try again.");
      },
    );
  }

  @override
  void dispose() {
    _nfcService.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(30),
        height: 350,
        child: Column(
          children: [
            Text(
              _success ? "Success" : "Link Card",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Assigning to: ${widget.user['name']}",
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const Spacer(),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _success ? Colors.green : AppColors.primaryRed,
                  width: 5,
                ),
              ),
              child: Icon(
                _success ? Icons.check : Icons.nfc,
                size: 60,
                color: _success ? Colors.green : AppColors.primaryRed,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (!_success)
              TextButton(
                onPressed: () {
                  _nfcService.stopSession();
                  Navigator.pop(context);
                },
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
