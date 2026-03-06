// app/SafeTrack/lib/screens/activity_log_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ActivityLogScreen extends StatefulWidget {
  final String? deviceCode;
  final String? childName;

  const ActivityLogScreen({
    super.key,
    this.deviceCode,
    this.childName,
  });

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  bool _isLoading = false;
  bool _showCachedLogs = false;
  List<Map<String, dynamic>> _activities = [];
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final List<Map<String, dynamic>> tempActivities = [];

      if (widget.deviceCode != null) {
        // Single device view
        await _loadDeviceLogs(
          user.uid,
          widget.deviceCode!,
          widget.childName ?? 'Unknown Child',
          tempActivities,
        );
      } else {
        // All devices view
        final linkedDevicesSnapshot = await _databaseRef
            .child('linkedDevices')
            .child(user.uid)
            .child('devices')
            .get();

        if (linkedDevicesSnapshot.exists) {
          final devicesData =
              linkedDevicesSnapshot.value as Map<dynamic, dynamic>;

          for (var entry in devicesData.entries) {
            final deviceCode = entry.key.toString();
            final deviceData = entry.value as Map<dynamic, dynamic>;
            final childName =
                deviceData['childName']?.toString() ?? 'Unknown Child';
            final isEnabled =
                deviceData['deviceEnabled']?.toString() == 'true';

            if (!isEnabled) continue;

            await _loadDeviceLogs(
                user.uid, deviceCode, childName, tempActivities);
          }
        }
      }

      // Sort newest first by lastUpdate (Firebase server timestamp Unix ms)
      tempActivities.sort((a, b) =>
          (b['lastUpdate'] as int).compareTo(a['lastUpdate'] as int));

      setState(() => _activities = tempActivities);
    } catch (e) {
      debugPrint('Error loading activities: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading activities: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Firmware field adapter ───────────────────────────────────────
  // Firmware writes these flat fields to every deviceLogs push entry:
  //   latitude, longitude, altitude, speed, accuracy,
  //   locationType ("gps" | "cached"), sos, batteryLevel,
  //   timestamp {.sv}, lastUpdate {.sv}
  //
  // There are NO nested currentLocation / lastLocation / gpsAvailable /
  // status fields in RTDB — those were derived in-memory only by the
  // old dashboard adapter and never existed on disk.
  //
  // This adapter translates raw firmware fields into the internal map
  // used by the activity list and detail dialog.
  Map<String, dynamic> _logEntryToActivity({
    required String logId,
    required String deviceCode,
    required String childName,
    required Map<dynamic, dynamic> raw,
  }) {
    final lat = (raw['latitude'] as num?)?.toDouble();
    final lng = (raw['longitude'] as num?)?.toDouble();
    final alt = (raw['altitude'] as num?)?.toDouble() ?? 0.0;
    final spd = (raw['speed'] as num?)?.toDouble() ?? 0.0;
    final acc = (raw['accuracy'] as num?)?.toDouble() ?? 0.0;

    // locationType is the firmware's source-of-truth for GPS vs cached.
    // "gps"    → live satellite fix
    // "cached" → last known position reused because fix was unavailable
    final locationType = raw['locationType']?.toString() ?? 'cached';
    final isGps = locationType == 'gps';
    final hasCoords = lat != null &&
        lng != null &&
        !(lat == 0.0 && lng == 0.0);
    final gpsAvailable = isGps && hasCoords;
    final isCached = locationType == 'cached';

    // lastUpdate is the Firebase server timestamp (Unix ms) written by
    // firmware as {".sv":"timestamp"} — resolved to an int by RTDB.
    final lastUpdate = _toInt(raw['lastUpdate']);

    // sos is written as a bool by the firmware
    final sosVal = raw['sos'];
    final sosActive = sosVal == true || sosVal == 'true';

    final batteryLevel =
        (raw['batteryLevel'] as num?)?.toDouble() ?? 0.0;

    return {
      'logId': logId,
      'deviceCode': deviceCode,
      'childName': childName,
      'lastUpdate': lastUpdate,
      'batteryLevel': batteryLevel,
      'gpsAvailable': gpsAvailable,
      'isCached': isCached,
      'locationType': locationType,
      'sos': sosActive,
      // Unified location: present whenever we have non-zero coords
      // regardless of whether this is a live fix or a cached one.
      'location': hasCoords
          ? {
              'latitude': lat,
              'longitude': lng,
              'altitude': alt,
            }
          : null,
      // Extra telemetry fields for the detail dialog
      'speed': spd,
      'accuracy': acc,
    };
  }

  int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  Future<void> _loadDeviceLogs(
    String userId,
    String deviceCode,
    String childName,
    List<Map<String, dynamic>> tempActivities,
  ) async {
    final logsSnapshot = await _databaseRef
        .child('deviceLogs')
        .child(userId)
        .child(deviceCode)
        .get();

    if (logsSnapshot.exists) {
      final logsData = logsSnapshot.value as Map<dynamic, dynamic>;

      logsData.forEach((key, value) {
        if (value is Map) {
          tempActivities.add(_logEntryToActivity(
            logId: key.toString(),
            deviceCode: deviceCode,
            childName: childName,
            raw: value as Map<dynamic, dynamic>,
          ));
        }
      });
    }
  }

  Future<void> _refreshData() async => _loadActivities();

  String _formatCoords(double lat, double lng) =>
      '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';

  // Filter: hide cached-location entries unless the user opts in
  List<Map<String, dynamic>> get _filteredActivities {
    if (_showCachedLogs) return _activities;
    return _activities
        .where((a) => a['isCached'] != true)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredActivities;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.childName != null
              ? '${widget.childName}\'s Activity Log'
              : 'Activity Log',
        ),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _showCachedLogs ? Icons.filter_alt : Icons.filter_alt_off,
              color: Colors.white,
            ),
            onPressed: () =>
                setState(() => _showCachedLogs = !_showCachedLogs),
            tooltip: _showCachedLogs
                ? 'Hide Cached Logs'
                : 'Show Cached Logs',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Summary card ───────────────────────────────
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on,
                                color: Colors.blue[800], size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.childName != null
                                        ? '${widget.childName}\'s Locations'
                                        : 'Location Activities',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${filtered.length} location update'
                                    '${filtered.length != 1 ? 's' : ''}',
                                    style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: filtered.isEmpty
                                              ? Colors.grey
                                              : Colors.green,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        filtered.isEmpty
                                            ? 'No data'
                                            : 'Tracking active',
                                        style: TextStyle(
                                          color: filtered.isEmpty
                                              ? Colors.grey
                                              : Colors.green,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_showCachedLogs) ...[
                          const Divider(height: 20),
                          Chip(
                            avatar: const Icon(Icons.info_outline,
                                size: 16),
                            label: const Text('Showing cached logs',
                                style: TextStyle(fontSize: 12)),
                            backgroundColor: Colors.blue[50],
                            deleteIcon:
                                const Icon(Icons.close, size: 16),
                            onDeleted: () => setState(
                                () => _showCachedLogs = false),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ── Activity list ──────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.history,
                                  size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              const Text('No activities yet',
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 16)),
                              const SizedBox(height: 8),
                              Text(
                                widget.childName != null
                                    ? 'No location updates for ${widget.childName}'
                                    : _showCachedLogs
                                        ? 'No location updates found'
                                        : 'Try showing cached logs',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refreshData,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) =>
                                _buildActivityItem(
                                    filtered[index], index),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildActivityItem(
      Map<String, dynamic> activity, int index) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
        activity['lastUpdate'] as int);
    final timeString =
        DateFormat('MMM dd, yyyy • h:mm a').format(timestamp);

    final location =
        activity['location'] as Map<String, dynamic>?;
    final gpsAvailable = activity['gpsAvailable'] as bool? ?? false;
    final isCached = activity['isCached'] as bool? ?? false;
    final batteryLevel =
        (activity['batteryLevel'] as num?)?.toDouble() ?? 0.0;
    final childName = activity['childName'] as String;
    final sosActive = activity['sos'] as bool? ?? false;

    // Location display string
    String locationName = 'No location';
    if (location != null) {
      locationName = _formatCoords(
        location['latitude'] as double,
        location['longitude'] as double,
      );
    }

    // Icon + colour logic driven by firmware's locationType field
    IconData icon;
    Color iconColor;
    Color bgColor;

    if (sosActive) {
      icon = Icons.warning;
      iconColor = Colors.red;
      bgColor = Colors.red[100]!;
    } else if (gpsAvailable) {
      // locationType == 'gps' AND valid coords
      icon = Icons.gps_fixed;
      iconColor = Colors.green;
      bgColor = Colors.green[100]!;
    } else if (isCached) {
      // locationType == 'cached'
      icon = Icons.cached;
      iconColor = Colors.orange;
      bgColor = Colors.orange[100]!;
    } else {
      icon = Icons.location_off;
      iconColor = Colors.grey;
      bgColor = Colors.grey[100]!;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: sosActive ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: sosActive
            ? const BorderSide(color: Colors.red, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Child name only in "all devices" view
            if (widget.deviceCode == null) ...[
              Text(
                childName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: sosActive ? Colors.red : Colors.blue[700],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    locationName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (sosActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'SOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(timeString),
            const SizedBox(height: 2),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                // FIX: chip label derived from gpsAvailable which comes
                // from firmware's locationType == 'gps' check — not from
                // a non-existent 'status' field.
                _buildStatusChip(
                  gpsAvailable ? 'GPS Fix' : 'No Fix',
                  gpsAvailable ? Colors.green : Colors.grey,
                ),
                // FIX: chip label from isCached (locationType == 'cached')
                // rather than a non-existent currentLocation.status field.
                _buildStatusChip(
                  isCached ? 'Cached' : 'Live',
                  isCached ? Colors.orange : Colors.blue,
                ),
                if (batteryLevel > 0)
                  _buildStatusChip(
                    '${batteryLevel.toStringAsFixed(0)}%',
                    batteryLevel < 20
                        ? Colors.red
                        : batteryLevel < 50
                            ? Colors.orange
                            : Colors.green,
                  ),
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
        onTap: () => _showActivityDetails(activity),
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showActivityDetails(Map<String, dynamic> activity) {
    final location =
        activity['location'] as Map<String, dynamic>?;
    final gpsAvailable =
        activity['gpsAvailable'] as bool? ?? false;
    final isCached = activity['isCached'] as bool? ?? false;
    final batteryLevel =
        (activity['batteryLevel'] as num?)?.toDouble() ?? 0.0;
    final sosActive = activity['sos'] as bool? ?? false;
    final speed =
        (activity['speed'] as num?)?.toDouble() ?? 0.0;
    final accuracy =
        (activity['accuracy'] as num?)?.toDouble() ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(
                  'Child Name', activity['childName'] as String),
              _buildDetailRow(
                  'Device Code', activity['deviceCode'] as String),
              const Divider(height: 20),

              // ── Location ──────────────────────────────────────
              // FIX: single unified location section replacing the
              // incorrect two-section split (currentLocation /
              // lastLocation) that relied on non-existent RTDB fields.
              Row(
                children: [
                  Text(
                    'Location',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: gpsAvailable
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      // Displays the raw locationType value from
                      // firmware: "gps" or "cached"
                      (activity['locationType'] as String? ??
                              'cached')
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        color: gpsAvailable
                            ? Colors.green
                            : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (location != null) ...[
                _buildDetailRow('Latitude',
                    (location['latitude'] as double)
                        .toStringAsFixed(6)),
                _buildDetailRow('Longitude',
                    (location['longitude'] as double)
                        .toStringAsFixed(6)),
                if ((location['altitude'] as double? ?? 0.0) != 0.0)
                  _buildDetailRow('Altitude',
                      '${(location['altitude'] as double).toStringAsFixed(1)} m'),
              ] else
                const Text('No location recorded',
                    style: TextStyle(color: Colors.grey)),

              const Divider(height: 20),

              // ── Telemetry ─────────────────────────────────────
              _buildDetailRow(
                  'GPS Fix', gpsAvailable ? 'Yes' : 'No'),
              _buildDetailRow(
                  'Location Type',
                  isCached ? 'Cached (no live fix)' : 'Live GPS'),
              if (speed > 0)
                _buildDetailRow(
                    'Speed', '${speed.toStringAsFixed(1)} km/h'),
              if (accuracy > 0)
                _buildDetailRow('Accuracy',
                    '±${accuracy.toStringAsFixed(0)} m'),
              _buildDetailRow('Battery',
                  '${batteryLevel.toStringAsFixed(0)}%'),
              _buildDetailRow(
                  'SOS Active', sosActive ? 'YES 🚨' : 'No'),

              const Divider(height: 20),
              _buildDetailRow(
                'Timestamp',
                DateFormat('MMM dd, yyyy at h:mm:ss a').format(
                  DateTime.fromMillisecondsSinceEpoch(
                      activity['lastUpdate'] as int),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Expanded(
            child:
                Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}