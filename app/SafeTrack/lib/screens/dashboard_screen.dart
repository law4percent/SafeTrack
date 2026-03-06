// app/SafeTrack/lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:async';
import '../services/auth_service.dart';
import '../widgets/quick_actions_grid.dart';
import 'live_location_screen.dart';
import 'my_children_screen.dart';
import 'settings_screen.dart';
import 'package:intl/intl.dart';
import 'activity_log_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

final FirebaseDatabase rtdbInstance = FirebaseDatabase.instance;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const DashboardHome(),
      const LiveLocationsScreen(),
      const MyChildrenScreen(),
      const SettingsScreen(),
    ];
  }

  void setCurrentIndex(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Image.asset(
              'assets/images/my_app_logo.png',
              height: MediaQuery.of(context).size.width * 0.20,
              width: MediaQuery.of(context).size.width * 0.20,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.school,
                  color: Colors.white,
                  size: MediaQuery.of(context).size.width * 0.10,
                );
              },
            ),
            SizedBox(width: MediaQuery.of(context).size.width * 0.02),
            Text(
              'SafeTrack - Student Safety',
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width * 0.038,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        centerTitle: false,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: Stack(
        children: [
          _screens[_currentIndex],
          if (_currentIndex == 0) const QuickActionsGrid(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index < _screens.length) {
            setState(() => _currentIndex = index);
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue[700],
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'Live Location',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.child_care),
            label: 'My Children',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// =============================================================
// DASHBOARD HOME
// =============================================================
class DashboardHome extends StatelessWidget {
  const DashboardHome({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    if (user == null) {
      return const Center(child: Text('User not logged in.'));
    }

    return StreamBuilder<DatabaseEvent>(
      stream: rtdbInstance
          .ref('linkedDevices')
          .child(user.uid)
          .child('devices')
          .onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const DashboardContent(childDevices: []);
        }

        final devicesData =
            snapshot.data!.snapshot.value as Map<dynamic, dynamic>;

        final List<Map<String, dynamic>> childDevices = [];
        devicesData.forEach((key, value) {
          final deviceData = value as Map<dynamic, dynamic>;
          final isEnabled =
              deviceData['deviceEnabled']?.toString() == 'true';
          if (isEnabled) {
            childDevices.add({
              'deviceCode': key.toString(),
              'data': deviceData,
            });
          }
        });

        return DashboardContent(childDevices: childDevices);
      },
    );
  }
}

// =============================================================
// DASHBOARD CONTENT
// =============================================================
class DashboardContent extends StatelessWidget {
  final List<Map<String, dynamic>> childDevices;
  const DashboardContent({super.key, required this.childDevices});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final isDesktop = screenWidth > 1024;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(isDesktop ? 24.0 : isTablet ? 20.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMonitoringStatus(isTablet, isDesktop),
            SizedBox(height: isDesktop ? 40.0 : isTablet ? 30.0 : 20.0),
            _buildMyChildrenSection(context, isTablet, isDesktop),
            SizedBox(height: isDesktop ? 30.0 : isTablet ? 25.0 : 20.0),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoringStatus(bool isTablet, bool isDesktop) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getAllChildrenStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            elevation: 2,
            child: ListTile(
              leading: const CircularProgressIndicator(),
              title: Text(
                'Monitoring your children\'s safety at school',
                style: TextStyle(
                    fontSize: isDesktop ? 18.0 : isTablet ? 16.0 : 14.0),
              ),
              subtitle: const Text('Checking status...'),
            ),
          );
        }

        final childrenStatus = snapshot.data ?? [];
        final bool hasEmergency =
            childrenStatus.any((child) => child['sosActive'] == true);
        final bool allChildrenOnline = childrenStatus.isNotEmpty &&
            childrenStatus.every((child) => child['isOnline'] == true);
        final bool someChildrenOffline = childrenStatus.isNotEmpty &&
            childrenStatus.any((child) => child['isOnline'] == false);
        final bool noDevices = childrenStatus.isEmpty;

        String statusText;
        Color statusColor;
        IconData statusIcon;

        if (hasEmergency) {
          statusText = 'EMERGENCY DETECTED!';
          statusColor = Colors.red;
          statusIcon = Icons.warning;
        } else if (noDevices) {
          statusText = 'No Devices Linked Yet';
          statusColor = Colors.orange;
          statusIcon = Icons.device_unknown;
        } else if (allChildrenOnline) {
          statusText = 'All Children Safe & Online';
          statusColor = Colors.green;
          statusIcon = Icons.security;
        } else if (someChildrenOffline) {
          statusText = 'Some Children Offline';
          statusColor = Colors.orange;
          statusIcon = Icons.signal_wifi_off;
        } else {
          statusText = 'Monitoring Status';
          statusColor = Colors.blue;
          statusIcon = Icons.monitor_heart;
        }

        return Card(
          elevation: hasEmergency ? 8 : 2,
          color: hasEmergency ? Colors.red.shade50 : null,
          child: ListTile(
            leading: Icon(
              statusIcon,
              color: hasEmergency ? Colors.red : statusColor,
              size: isDesktop ? 32.0 : isTablet ? 28.0 : 24.0,
            ),
            title: Text(
              'Monitoring your children\'s safety at school',
              style: TextStyle(
                fontSize: isDesktop ? 18.0 : isTablet ? 16.0 : 14.0,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              statusText,
              style: TextStyle(
                color: hasEmergency ? Colors.red : statusColor,
                fontWeight: FontWeight.bold,
                fontSize: isDesktop ? 16.0 : isTablet ? 14.0 : 12.0,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMyChildrenSection(
      BuildContext context, bool isTablet, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Children',
          style: TextStyle(
            fontSize: isDesktop ? 24.0 : isTablet ? 22.0 : 20.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: isDesktop ? 16.0 : isTablet ? 12.0 : 8.0),
        if (childDevices.isEmpty)
          _buildEmptyState(isTablet, isDesktop)
        else
          _buildChildrenList(context, isTablet, isDesktop),
      ],
    );
  }

  Widget _buildEmptyState(bool isTablet, bool isDesktop) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
            vertical: isDesktop ? 40.0 : isTablet ? 30.0 : 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_other,
              size: isDesktop ? 60.0 : isTablet ? 50.0 : 40.0,
              color: Colors.grey,
            ),
            SizedBox(height: isDesktop ? 16.0 : isTablet ? 12.0 : 8.0),
            Text(
              'No children linked yet.',
              style: TextStyle(
                fontSize: isDesktop ? 18.0 : isTablet ? 16.0 : 14.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isDesktop ? 8.0 : isTablet ? 6.0 : 4.0),
            Text(
              'Go to My Children to link a device.',
              style: TextStyle(
                fontSize: isDesktop ? 14.0 : isTablet ? 13.0 : 12.0,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildrenList(
      BuildContext context, bool isTablet, bool isDesktop) {
    if (isDesktop) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
          childAspectRatio: 2.5,
        ),
        itemCount: childDevices.length,
        itemBuilder: (context, index) => ChildCard(
          deviceCode: childDevices[index]['deviceCode'],
          deviceData: childDevices[index]['data'],
          isTablet: isTablet,
          isDesktop: isDesktop,
        ),
      );
    } else if (isTablet) {
      final isLandscape =
          MediaQuery.of(context).orientation == Orientation.landscape;
      if (isLandscape) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12.0,
            mainAxisSpacing: 12.0,
            childAspectRatio: 3.0,
          ),
          itemCount: childDevices.length,
          itemBuilder: (context, index) => ChildCard(
            deviceCode: childDevices[index]['deviceCode'],
            deviceData: childDevices[index]['data'],
            isTablet: isTablet,
            isDesktop: isDesktop,
          ),
        );
      } else {
        return Column(
          children: childDevices
              .map((device) => Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: ChildCard(
                      deviceCode: device['deviceCode'],
                      deviceData: device['data'],
                      isTablet: isTablet,
                      isDesktop: isDesktop,
                    ),
                  ))
              .toList(),
        );
      }
    } else {
      return Column(
        children: childDevices
            .map((device) => Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: ChildCard(
                    deviceCode: device['deviceCode'],
                    deviceData: device['data'],
                    isTablet: isTablet,
                    isDesktop: isDesktop,
                  ),
                ))
            .toList(),
      );
    }
  }

  // Reads SOS from linkedDevices/deviceStatus/sos.
  // Reads online status from deviceLogs using 'lastUpdate' field
  // (written by firmware as a Firebase server timestamp).
  Stream<List<Map<String, dynamic>>> _getAllChildrenStatus() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      yield [];
      return;
    }

    final deviceCodes =
        childDevices.map((d) => d['deviceCode'] as String).toList();

    await for (final _ in rtdbInstance
        .ref('linkedDevices')
        .child(user.uid)
        .child('devices')
        .onValue) {
      final List<Map<String, dynamic>> statuses = [];

      for (final deviceCode in deviceCodes) {
        try {
          bool isOnline = false;
          bool hasSOS = false;

          // SOS lives in linkedDevices/{uid}/devices/{code}/deviceStatus/sos
          final deviceSnapshot = await rtdbInstance
              .ref('linkedDevices')
              .child(user.uid)
              .child('devices')
              .child(deviceCode)
              .child('deviceStatus')
              .get();

          if (deviceSnapshot.exists) {
            final deviceStatus =
                deviceSnapshot.value as Map<dynamic, dynamic>;
            final sosVal = deviceStatus['sos'];
            hasSOS = sosVal == true || sosVal == 'true';
          }

          // Online status: scan deviceLogs for the highest 'lastUpdate'
          // (firmware writes lastUpdate as a Firebase server timestamp in
          //  every deviceLogs push entry — online if within 5 minutes)
          final logsSnapshot = await rtdbInstance
              .ref('deviceLogs')
              .child(user.uid)
              .child(deviceCode)
              .get();

          if (logsSnapshot.exists) {
            final logsData =
                logsSnapshot.value as Map<dynamic, dynamic>;
            int highestTimestamp = 0;

            for (var entry in logsData.entries) {
              final logData = entry.value as Map<dynamic, dynamic>;
              final timestamp = logData['lastUpdate'] as int? ?? 0;
              if (timestamp > highestTimestamp) {
                highestTimestamp = timestamp;
              }
            }

            if (highestTimestamp > 0) {
              final now = DateTime.now().millisecondsSinceEpoch;
              isOnline = (now - highestTimestamp) < 300000; // 5 min
            }
          }

          statuses.add({
            'deviceCode': deviceCode,
            'sosActive': hasSOS,
            'isOnline': isOnline,
          });
        } catch (e) {
          debugPrint('Error getting status for $deviceCode: $e');
          statuses.add({
            'deviceCode': deviceCode,
            'sosActive': false,
            'isOnline': false,
          });
        }
      }

      yield statuses;
    }
  }
}

// =============================================================
// CHILD CARD
// =============================================================
class ChildCard extends StatefulWidget {
  final String deviceCode;
  final Map<dynamic, dynamic> deviceData;
  final bool isTablet;
  final bool isDesktop;

  const ChildCard({
    super.key,
    required this.deviceCode,
    required this.deviceData,
    required this.isTablet,
    required this.isDesktop,
  });

  @override
  State<ChildCard> createState() => _ChildCardState();
}

class _ChildCardState extends State<ChildCard> {
  Map<String, dynamic>? _latestLog;
  bool _hasSOS = false;
  bool _isLoading = true;
  StreamSubscription<DatabaseEvent>? _logListener;
  StreamSubscription<DatabaseEvent>? _sosListener;

  @override
  void initState() {
    super.initState();
    _loadLatestStatus();
    _listenToDeviceLogs();
    _listenToSOS();
  }

  @override
  void dispose() {
    _logListener?.cancel();
    _sosListener?.cancel();
    super.dispose();
  }

  // Watches linkedDevices/.../deviceStatus/sos in real time.
  // Firmware writes sos as a bool to this path every 30s and
  // immediately on SOS activation.
  void _listenToSOS() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _sosListener = rtdbInstance
        .ref('linkedDevices')
        .child(user.uid)
        .child('devices')
        .child(widget.deviceCode)
        .child('deviceStatus')
        .child('sos')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final sosVal = event.snapshot.value;
      final isSOS = sosVal == true || sosVal == 'true';
      debugPrint('🚨 SOS update for ${widget.deviceCode}: $isSOS');
      setState(() => _hasSOS = isSOS);
    });
  }

  // ── Firmware field adapter ────────────────────────────────────
  // Firmware writes flat fields to every deviceLogs push entry:
  //   latitude, longitude, altitude, speed, accuracy,
  //   locationType ("gps" | "cached"), sos, batteryLevel,
  //   timestamp {.sv}, lastUpdate {.sv}
  //
  // This adapter derives the dashboard-friendly map from those
  // raw fields. It is the single source of truth for field name
  // translation so no other method needs to know raw field names.
  //
  //   gpsAvailable   → locationType == 'gps' AND coords non-zero
  //   currentLocation→ non-null only when live GPS fix available
  //   lastLocation   → always the best known position (lat/lng/alt)
  //   lastUpdate     → Unix ms integer (server timestamp)
  //   batteryLevel   → int percentage from firmware
  Map<String, dynamic> _logEntryToLatestLog(
      Map<dynamic, dynamic> log) {
    final lat = (log['latitude'] as num?)?.toDouble();
    final lng = (log['longitude'] as num?)?.toDouble();
    final alt = (log['altitude'] as num?)?.toDouble();
    final locationType =
        log['locationType']?.toString() ?? 'cached';
    final isGps = locationType == 'gps';
    final hasCoords = lat != null &&
        lng != null &&
        !(lat == 0.0 && lng == 0.0);

    return {
      'lastUpdate': _toInt(log['lastUpdate']),
      'batteryLevel':
          (log['batteryLevel'] as num?)?.toDouble() ?? 0.0,
      // gpsAvailable: true only when firmware reports a live fix
      'gpsAvailable': isGps && hasCoords,
      // currentLocation: present only on a live GPS fix
      'currentLocation': (isGps && hasCoords)
          ? {'latitude': lat, 'longitude': lng}
          : null,
      // lastLocation: always the best known position
      'lastLocation': hasCoords
          ? {
              'latitude': lat,
              'longitude': lng,
              'altitude': alt ?? 0.0,
            }
          : null,
    };
  }

  int _toInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  // Watches deviceLogs for battery, GPS, and location fields.
  // SOS is intentionally excluded — handled by _listenToSOS() only.
  void _listenToDeviceLogs() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _logListener = rtdbInstance
        .ref('deviceLogs')
        .child(user.uid)
        .child(widget.deviceCode)
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.exists) {
        final logsData =
            event.snapshot.value as Map<dynamic, dynamic>;

        MapEntry<dynamic, dynamic>? latestEntry;
        int highestTimestamp = 0;

        for (var entry in logsData.entries) {
          final logData = entry.value as Map<dynamic, dynamic>;
          final timestamp = logData['lastUpdate'] as int? ?? 0;
          if (timestamp > highestTimestamp) {
            highestTimestamp = timestamp;
            latestEntry = entry;
          }
        }

        if (latestEntry != null) {
          final latestLogEntry =
              latestEntry.value as Map<dynamic, dynamic>;
          setState(() {
            _latestLog = _logEntryToLatestLog(latestLogEntry);
          });
        }
      } else {
        // No logs yet — fall back to cached deviceStatus snapshot
        // (non-SOS fields only; SOS managed by _listenToSOS)
        final cachedStatus =
            widget.deviceData['deviceStatus'] as Map<dynamic, dynamic>?;
        if (cachedStatus != null) {
          final ll = cachedStatus['lastLocation'];
          setState(() {
            _latestLog = {
              'lastUpdate': _toInt(cachedStatus['lastUpdate']),
              'batteryLevel':
                  (cachedStatus['batteryLevel'] as num?)?.toDouble() ??
                      0.0,
              'gpsAvailable': false,
              'currentLocation': null,
              'lastLocation': ll,
            };
          });
        }
      }
    });
  }

  Future<void> _loadLatestStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Load initial SOS state from linkedDevices/deviceStatus/sos
      final deviceSnapshot = await rtdbInstance
          .ref('linkedDevices')
          .child(user.uid)
          .child('devices')
          .child(widget.deviceCode)
          .child('deviceStatus')
          .get();

      if (deviceSnapshot.exists) {
        final deviceStatus =
            deviceSnapshot.value as Map<dynamic, dynamic>;
        final sosVal = deviceStatus['sos'];
        _hasSOS = sosVal == true || sosVal == 'true';
      }

      // Load latest deviceLog entry for battery/GPS/location
      final logsSnapshot = await rtdbInstance
          .ref('deviceLogs')
          .child(user.uid)
          .child(widget.deviceCode)
          .get();

      if (mounted) {
        setState(() {
          if (logsSnapshot.exists) {
            final logsData =
                logsSnapshot.value as Map<dynamic, dynamic>;

            MapEntry<dynamic, dynamic>? latestEntry;
            int highestTimestamp = 0;

            for (var entry in logsData.entries) {
              final logData = entry.value as Map<dynamic, dynamic>;
              final timestamp = logData['lastUpdate'] as int? ?? 0;
              if (timestamp > highestTimestamp) {
                highestTimestamp = timestamp;
                latestEntry = entry;
              }
            }

            if (latestEntry != null) {
              _latestLog = _logEntryToLatestLog(
                  latestEntry.value as Map<dynamic, dynamic>);
            }
          } else {
            // Fallback: no logs yet, use cached deviceStatus
            final cachedStatus = widget.deviceData['deviceStatus']
                as Map<dynamic, dynamic>?;
            if (cachedStatus != null) {
              final ll = cachedStatus['lastLocation'];
              _latestLog = {
                'lastUpdate': _toInt(cachedStatus['lastUpdate']),
                'batteryLevel':
                    (cachedStatus['batteryLevel'] as num?)?.toDouble() ??
                        0.0,
                'gpsAvailable': false,
                'currentLocation': null,
                'lastLocation': ll,
              };
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading status for ${widget.deviceCode}: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isDeviceOnline() {
    if (_latestLog == null) return false;
    final lastUpdate = _latestLog!['lastUpdate'] as int? ?? 0;
    if (lastUpdate == 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastUpdate) < 300000; // 5 min threshold
  }

  void _showDeviceInfo(BuildContext context) {
    final addedAt = (widget.deviceData['addedAt'] as num?)?.toInt();
    final addedDate = addedAt != null
        ? DateFormat('MMM dd, yyyy - hh:mm a')
            .format(DateTime.fromMillisecondsSinceEpoch(addedAt))
        : 'Unknown';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('Device Information'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Device Code:', widget.deviceCode),
              const SizedBox(height: 8),
              _buildInfoRow('Added On:', addedDate),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Status:',
                widget.deviceData['deviceEnabled']?.toString() == 'true'
                    ? 'Enabled'
                    : 'Disabled',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
            child:
                Text(value, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  void _showFullScreenImage(
      BuildContext context,
      String childName,
      ImageProvider? imageProvider) {
    if (imageProvider == null) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(
              widget.isDesktop
                  ? 40.0
                  : widget.isTablet
                      ? 30.0
                      : 20.0),
          child: Stack(
            children: [
              Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black87,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 3.0,
                        child: Center(
                          child: Image(
                            image: imageProvider,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(Icons.error,
                                  color: Colors.white,
                                  size: widget.isDesktop
                                      ? 60.0
                                      : widget.isTablet
                                          ? 50.0
                                          : 40.0);
                            },
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(widget.isDesktop
                          ? 20.0
                          : widget.isTablet
                              ? 16.0
                              : 12.0),
                      child: Text(
                        childName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: widget.isDesktop
                              ? 20.0
                              : widget.isTablet
                                  ? 18.0
                                  : 16.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: widget.isDesktop
                    ? 50.0
                    : widget.isTablet
                        ? 40.0
                        : 30.0,
                right: widget.isDesktop
                    ? 30.0
                    : widget.isTablet
                        ? 20.0
                        : 10.0,
                child: IconButton(
                  icon: Icon(Icons.close,
                      color: Colors.white,
                      size: widget.isDesktop
                          ? 35.0
                          : widget.isTablet
                              ? 30.0
                              : 25.0),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ImageProvider? _getImageProvider(String? imageBase64) {
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(imageBase64);
        return MemoryImage(bytes);
      } catch (e) {
        debugPrint('Error decoding base64 image: $e');
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final childName =
        widget.deviceData['childName']?.toString() ?? 'Unknown Child';
    final yearLevel =
        widget.deviceData['yearLevel']?.toString() ?? '';
    final section =
        widget.deviceData['section']?.toString() ?? '';
    final imageBase64 =
        widget.deviceData['imageProfileBase64']?.toString();

    final batteryLevel =
        _latestLog?['batteryLevel'] as double? ?? 0.0;
    final sosActive = _hasSOS;
    final isOnline = _isDeviceOnline();

    String gradeSection = '';
    if (yearLevel.isNotEmpty) {
      gradeSection = 'Grade $yearLevel';
      if (section.isNotEmpty) gradeSection += ' - $section';
    } else if (section.isNotEmpty) {
      gradeSection = section;
    }

    final ImageProvider? imageProvider =
        _getImageProvider(imageBase64);
    final Color avatarBgColor =
        Theme.of(context).primaryColor.withValues(alpha: 0.2);

    if (_isLoading) {
      return Card(
        elevation: 2,
        margin: EdgeInsets.only(
            bottom: widget.isDesktop
                ? 16.0
                : widget.isTablet
                    ? 12.0
                    : 8.0),
        child: Padding(
          padding: EdgeInsets.all(widget.isDesktop
              ? 16.0
              : widget.isTablet
                  ? 12.0
                  : 10.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: widget.isDesktop
                    ? 56.0
                    : widget.isTablet
                        ? 48.0
                        : 40.0,
                backgroundColor: avatarBgColor,
                backgroundImage: imageProvider,
                child: imageProvider == null
                    ? Icon(Icons.person,
                        size: (widget.isDesktop
                                ? 56.0
                                : widget.isTablet
                                    ? 48.0
                                    : 40.0) *
                            0.6)
                    : null,
              ),
              SizedBox(
                  width: widget.isDesktop
                      ? 16.0
                      : widget.isTablet
                          ? 12.0
                          : 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      childName,
                      style: TextStyle(
                        fontSize: widget.isDesktop
                            ? 18.0
                            : widget.isTablet
                                ? 16.0
                                : 14.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const CircularProgressIndicator(strokeWidth: 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildChildCard(
      context,
      childName,
      gradeSection,
      sosActive,
      isOnline,
      batteryLevel,
      imageProvider,
      avatarBgColor,
    );
  }

  Widget _buildChildCard(
    BuildContext context,
    String childName,
    String gradeSection,
    bool sosActive,
    bool isOnline,
    double batteryLevel,
    ImageProvider? imageProvider,
    Color avatarBgColor,
  ) {
    final avatarSize =
        widget.isDesktop ? 56.0 : widget.isTablet ? 48.0 : 40.0;
    final iconSize =
        widget.isDesktop ? 20.0 : widget.isTablet ? 18.0 : 16.0;
    final fontSizeTitle =
        widget.isDesktop ? 18.0 : widget.isTablet ? 16.0 : 14.0;
    final fontSizeSubtitle =
        widget.isDesktop ? 14.0 : widget.isTablet ? 13.0 : 12.0;

    return Card(
      elevation: sosActive ? 8 : 2,
      margin: EdgeInsets.only(
          bottom: widget.isDesktop
              ? 16.0
              : widget.isTablet
                  ? 12.0
                  : 8.0),
      color: sosActive ? Colors.red.shade50 : null,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ActivityLogScreen(
                deviceCode: widget.deviceCode,
                childName: childName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Container(
              decoration: sosActive
                  ? BoxDecoration(
                      border:
                          Border.all(color: Colors.red, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              child: Padding(
                padding: EdgeInsets.all(widget.isDesktop
                    ? 16.0
                    : widget.isTablet
                        ? 12.0
                        : 10.0),
                child: Row(
                  children: [
                    // ── Avatar ──────────────────────────────────
                    GestureDetector(
                      onTap: () => _showFullScreenImage(
                          context, childName, imageProvider),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: avatarSize,
                            backgroundColor: sosActive
                                ? Colors.red.withValues(alpha: 0.3)
                                : avatarBgColor,
                            backgroundImage: imageProvider,
                            child: imageProvider == null
                                ? Icon(
                                    sosActive
                                        ? Icons.warning
                                        : Icons.person,
                                    size: avatarSize * 0.6,
                                    color: sosActive
                                        ? Colors.red
                                        : Colors.blueGrey,
                                  )
                                : null,
                          ),
                          if (sosActive && imageProvider != null)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red
                                      .withValues(alpha: 0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.warning,
                                    color: Colors.white,
                                    size: avatarSize * 0.5),
                              ),
                            ),
                        ],
                      ),
                    ),

                    SizedBox(
                        width: widget.isDesktop
                            ? 16.0
                            : widget.isTablet
                                ? 12.0
                                : 10.0),

                    // ── Info column ─────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name + info button
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  childName,
                                  style: TextStyle(
                                    fontSize: fontSizeTitle,
                                    fontWeight: sosActive
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: sosActive
                                        ? Colors.red
                                        : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.info_outline,
                                    size: iconSize,
                                    color: Colors.blue),
                                onPressed: () =>
                                    _showDeviceInfo(context),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),

                          // Grade / section
                          if (gradeSection.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.school,
                                    size: iconSize,
                                    color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(
                                  gradeSection,
                                  style: TextStyle(
                                    fontSize: fontSizeSubtitle,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 6),

                          // Online status
                          Row(
                            children: [
                              Icon(Icons.circle,
                                  color: isOnline
                                      ? Colors.green
                                      : Colors.grey,
                                  size: iconSize * 0.7),
                              const SizedBox(width: 4),
                              Text(
                                isOnline ? 'Active' : 'Offline',
                                style: TextStyle(
                                  color: isOnline
                                      ? Colors.green
                                      : Colors.grey,
                                  fontSize: fontSizeSubtitle,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 4),

                          // Battery
                          if (batteryLevel > 0)
                            Row(
                              children: [
                                Icon(
                                  batteryLevel > 80
                                      ? Icons.battery_full
                                      : batteryLevel > 50
                                          ? Icons.battery_std
                                          : batteryLevel > 20
                                              ? Icons
                                                  .battery_charging_full
                                              : Icons.battery_alert,
                                  size: iconSize,
                                  color: batteryLevel < 20
                                      ? Colors.red
                                      : batteryLevel < 50
                                          ? Colors.orange
                                          : Colors.green,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${batteryLevel.round()}%',
                                  style: TextStyle(
                                    fontSize: fontSizeSubtitle,
                                    color: batteryLevel < 20
                                        ? Colors.red
                                        : batteryLevel < 50
                                            ? Colors.orange
                                            : Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),

                          const SizedBox(height: 4),

                          // GPS status
                          // FIX: derived from gpsAvailable (which itself
                          // comes from firmware's locationType field via
                          // _logEntryToLatestLog). No 'status' field exists
                          // in the firmware payload.
                          Row(
                            children: [
                              Icon(
                                _latestLog?['gpsAvailable'] == true
                                    ? Icons.gps_fixed
                                    : Icons.gps_off,
                                size: iconSize,
                                color:
                                    _latestLog?['gpsAvailable'] == true
                                        ? Colors.green
                                        : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _latestLog?['gpsAvailable'] == true
                                    ? 'GPS Available'
                                    : 'GPS Unavailable',
                                style: TextStyle(
                                  fontSize: fontSizeSubtitle,
                                  color:
                                      _latestLog?['gpsAvailable'] ==
                                              true
                                          ? Colors.green
                                          : Colors.orange,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                          // Location coordinates
                          // FIX: use gpsAvailable (from adapter) to decide
                          // icon and label instead of the non-existent
                          // currentLocation['status'] field.
                          if (_latestLog != null)
                            Builder(builder: (context) {
                              final isGps =
                                  _latestLog!['gpsAvailable'] == true;
                              final currentLoc =
                                  _latestLog!['currentLocation']
                                      as Map<dynamic, dynamic>?;
                              final lastLoc =
                                  _latestLog!['lastLocation']
                                      as Map<dynamic, dynamic>?;
                              final location = currentLoc ?? lastLoc;

                              if (location != null) {
                                final lat =
                                    (location['latitude'] as num?)
                                            ?.toDouble() ??
                                        0.0;
                                final lon =
                                    (location['longitude'] as num?)
                                            ?.toDouble() ??
                                        0.0;
                                return Row(
                                  children: [
                                    Icon(
                                      // FIX: was reading status == 'success'
                                      // which was always 'unknown' from RTDB.
                                      // Now correctly uses gpsAvailable.
                                      isGps
                                          ? Icons.location_on
                                          : Icons.location_searching,
                                      size: iconSize,
                                      color: isGps
                                          ? Colors.blue
                                          : Colors.orange,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        // FIX: was appending '(Cached)' based
                                        // on status == 'cached' which was never
                                        // set. Now uses gpsAvailable correctly.
                                        'Lat: ${lat.toStringAsFixed(4)}, '
                                        'Lon: ${lon.toStringAsFixed(4)}'
                                        '${!isGps ? ' (Cached)' : ''}',
                                        style: TextStyle(
                                          fontSize:
                                              fontSizeSubtitle * 0.9,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                );
                              }
                              return const SizedBox.shrink();
                            }),

                          // Tap hint
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.touch_app,
                                  size: iconSize * 0.8,
                                  color: Colors.blue[300]),
                              const SizedBox(width: 4),
                              Text(
                                'Tap to view activity log',
                                style: TextStyle(
                                  fontSize: fontSizeSubtitle * 0.85,
                                  color: Colors.blue[300],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── SOS / SAFE chip ─────────────────────────
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: widget.isDesktop
                                ? 16
                                : widget.isTablet
                                    ? 12
                                    : 10,
                            vertical: widget.isDesktop
                                ? 8
                                : widget.isTablet
                                    ? 6
                                    : 5,
                          ),
                          decoration: BoxDecoration(
                            color: sosActive
                                ? Colors.red
                                : Colors.green,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            sosActive ? 'SOS' : 'SAFE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: fontSizeSubtitle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}