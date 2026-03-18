// lib/screens/alerts_screen.dart
//
// Feature 2 — Alert Screen
// Displays all alerts saved to RTDB:
//   alertLogs/{uid}/{deviceCode}/{pushId}
//     → type: 'deviation' | 'late' | 'absent' | 'anomaly' | 'sos'
//     → childName, message, distanceMeters?, routeName?, timestamp
//
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  String _filter = 'all'; // 'all' | 'deviation' | 'late' | 'absent' | 'anomaly' | 'sos'

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Alerts',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear all alerts',
            onPressed: () => _confirmClearAll(context, user.uid),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            color: Colors.red.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'All', Icons.notifications_outlined),
                  _filterChip('sos', 'SOS', Icons.emergency_outlined),
                  _filterChip('deviation', 'Off Route', Icons.route_outlined),
                  _filterChip('late', 'Late', Icons.watch_later_outlined),
                  _filterChip('absent', 'Absent', Icons.person_off_outlined),
                  _filterChip('anomaly', 'Anomaly', Icons.warning_amber_outlined),
                  _filterChip('silent', 'Device Silent', Icons.sensors_off_outlined),
                ],
              ),
            ),
          ),
          // Alert list — streams alertLogs AND live device names.
          // Bug fix: childName is baked into each alert at write time,
          // so renames never propagate. We load the live name map from
          // linkedDevices and substitute it at render time, falling back
          // to the stored name only if the device has been removed.
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance
                  .ref('linkedDevices')
                  .child(user.uid)
                  .child('devices')
                  .onValue,
              builder: (context, deviceSnap) {
                // Build a live deviceCode → childName map
                final liveNames = <String, String>{};
                if (deviceSnap.hasData &&
                    deviceSnap.data!.snapshot.value != null) {
                  final devData = deviceSnap.data!.snapshot.value
                      as Map<dynamic, dynamic>;
                  for (final e in devData.entries) {
                    if (e.value is Map) {
                      final name = (e.value as Map<dynamic, dynamic>)['childName']
                              ?.toString() ??
                          '';
                      if (name.isNotEmpty) {
                        liveNames[e.key.toString()] = name;
                      }
                    }
                  }
                }

                return StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance
                      .ref('alertLogs')
                      .child(user.uid)
                      .onValue,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData ||
                        snapshot.data!.snapshot.value == null) {
                      return _buildEmpty();
                    }

                    final allAlerts = <_AlertEntry>[];
                    final raw = snapshot.data!.snapshot.value
                        as Map<dynamic, dynamic>;

                    // Flatten: alertLogs/{uid}/{deviceCode}/{pushId} → list
                    for (final deviceEntry in raw.entries) {
                      final deviceCode =
                          deviceEntry.key.toString();
                      if (deviceEntry.value is! Map) continue;
                      final logs = deviceEntry.value
                          as Map<dynamic, dynamic>;
                      for (final logEntry in logs.entries) {
                        if (logEntry.value is! Map) continue;
                        final data = logEntry.value
                            as Map<dynamic, dynamic>;
                        final type =
                            data['type']?.toString() ?? 'unknown';
                        if (_filter != 'all' && type != _filter) {
                          continue;
                        }
                        // Bug fix: prefer live name, fall back to
                        // stored name if device was removed.
                        final storedName =
                            data['childName']?.toString() ??
                                'Unknown';
                        final childName =
                            liveNames[deviceCode] ?? storedName;

                        allAlerts.add(_AlertEntry(
                          pushId: logEntry.key.toString(),
                          deviceCode: deviceCode,
                          type: type,
                          childName: childName,
                          message: data['message']?.toString() ?? '',
                          timestamp: (data['timestamp'] as num?)
                                  ?.toInt() ??
                              0,
                          distanceMeters:
                              (data['distanceMeters'] as num?)
                                  ?.toDouble(),
                          routeName: data['routeName']?.toString(),
                        ));
                      }
                    }

                    if (allAlerts.isEmpty) return _buildEmpty();

                    // Sort newest first
                    allAlerts.sort(
                        (a, b) => b.timestamp.compareTo(a.timestamp));

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: allAlerts.length,
                      itemBuilder: (context, i) => _AlertCard(
                          alert: allAlerts[i], userId: user.uid),
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

  Widget _filterChip(String value, String label, IconData icon) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        avatar: Icon(icon, size: 16,
            color: selected ? Colors.white : Colors.red.shade700),
        label: Text(label),
        selectedColor: Colors.red.shade700,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.red.shade700,
          fontWeight: FontWeight.w600,
        ),
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 72, color: Colors.green.shade300),
          const SizedBox(height: 16),
          const Text('No alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _filter == 'all'
                ? 'Everything looks good! No alerts have been recorded.'
                : 'No $_filter alerts found.',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll(BuildContext context, String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear All Alerts?'),
        content: const Text(
            'This will permanently delete all saved alerts. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseDatabase.instance.ref('alertLogs').child(uid).remove();
      // FIX (minor): context may be stale after async gap — guard before use
      if (!context.mounted) return;
    }
  }
}

// ── Alert Card ────────────────────────────────────────────────
class _AlertCard extends StatelessWidget {
  final _AlertEntry alert;
  final String userId;

  const _AlertCard({required this.alert, required this.userId});

  @override
  Widget build(BuildContext context) {
    final config = _alertConfig(alert.type);
    final timeStr = _formatTimestamp(alert.timestamp);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: () => _confirmDelete(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon badge
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: config.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(config.icon, color: config.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          config.label,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: config.color,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          timeStr,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.childName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.message,
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    if (alert.distanceMeters != null &&
                        alert.routeName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${alert.distanceMeters!.toStringAsFixed(0)}m from "${alert.routeName}"',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade800),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Alert?'),
        content: const Text('Remove this alert from the history?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseDatabase.instance
          .ref('alertLogs')
          .child(userId)
          .child(alert.deviceCode)
          .child(alert.pushId)
          .remove();
      // FIX (minor): context may be stale after async gap — guard before use
      if (!context.mounted) return;
    }
  }

  _AlertConfig _alertConfig(String type) {
    switch (type) {
      case 'sos':
        return _AlertConfig(Icons.emergency, Colors.red.shade800, 'SOS Emergency');
      case 'deviation':
        return _AlertConfig(Icons.route, Colors.orange.shade700, 'Off Route');
      case 'late':
        return _AlertConfig(Icons.watch_later, Colors.amber.shade700, 'Late Arrival');
      case 'absent':
        return _AlertConfig(Icons.person_off, Colors.purple.shade600, 'Absent');
      case 'anomaly':
        return _AlertConfig(Icons.warning_amber, Colors.deepOrange.shade600, 'Anomaly');
      case 'silent':
        return _AlertConfig(Icons.sensors_off, Colors.deepPurple, 'Device Silent');
      default:
        return _AlertConfig(Icons.notifications, Colors.blueGrey, 'Alert');
    }
  }

  String _formatTimestamp(int ms) {
    if (ms == 0) return 'Unknown time';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24 && dt.day == now.day) {
      return 'Today at ${DateFormat('HH:mm').format(dt)}';
    }
    if (diff.inHours < 48 && dt.day == now.subtract(const Duration(days: 1)).day) {
      return 'Yesterday at ${DateFormat('HH:mm').format(dt)}';
    }
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  }
}

// ── Data models ───────────────────────────────────────────────
class _AlertEntry {
  final String pushId;
  final String deviceCode;
  final String type;
  final String childName;
  final String message;
  final int timestamp;
  final double? distanceMeters;
  final String? routeName;

  _AlertEntry({
    required this.pushId,
    required this.deviceCode,
    required this.type,
    required this.childName,
    required this.message,
    required this.timestamp,
    this.distanceMeters,
    this.routeName,
  });
}

class _AlertConfig {
  final IconData icon;
  final Color color;
  final String label;
  const _AlertConfig(this.icon, this.color, this.label);
}