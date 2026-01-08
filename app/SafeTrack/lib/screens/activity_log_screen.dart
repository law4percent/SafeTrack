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
  bool _showCurrentLocation = false;
  List<Map<String, dynamic>> _activities = [];
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      List<Map<String, dynamic>> tempActivities = [];

      if (widget.deviceCode != null) {
        // Load logs for specific device only
        await _loadDeviceLogs(
          user.uid,
          widget.deviceCode!,
          widget.childName ?? 'Unknown Child',
          tempActivities,
        );
      } else {
        // Load logs for all devices
        final linkedDevicesSnapshot = await _databaseRef
            .child('linkedDevices')
            .child(user.uid)
            .child('devices')
            .get();

        if (linkedDevicesSnapshot.exists) {
          final devicesData = linkedDevicesSnapshot.value as Map<dynamic, dynamic>;

          for (var entry in devicesData.entries) {
            final deviceCode = entry.key.toString();
            final deviceData = entry.value as Map<dynamic, dynamic>;
            final childName = deviceData['childName']?.toString() ?? 'Unknown Child';
            final isEnabled = deviceData['deviceEnabled']?.toString() == 'true';

            if (!isEnabled) continue;

            await _loadDeviceLogs(user.uid, deviceCode, childName, tempActivities);
          }
        }
      }

      // Sort by timestamp (newest first)
      tempActivities.sort((a, b) => 
        (b['lastUpdate'] as int).compareTo(a['lastUpdate'] as int)
      );

      setState(() {
        _activities = tempActivities;
      });
    } catch (e) {
      debugPrint('Error loading activities: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading activities: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
          final currentLocation = value['currentLocation'] as Map<dynamic, dynamic>?;
          final lastLocation = value['lastLocation'] as Map<dynamic, dynamic>?;
          final locationStatus = currentLocation?['status']?.toString() ?? 'unknown';
          
          tempActivities.add({
            'logId': key.toString(),
            'deviceCode': deviceCode,
            'childName': childName,
            'lastUpdate': value['lastUpdate'] as int? ?? 0,
            'batteryLevel': (value['batteryLevel'] as num?)?.toDouble() ?? 0.0,
            'gpsAvailable': value['gpsAvailable'] as bool? ?? false,
            'sos': value['sos'] as bool? ?? false,
            'currentLocation': currentLocation != null ? {
              'latitude': (currentLocation['latitude'] as num?)?.toDouble() ?? 0.0,
              'longitude': (currentLocation['longitude'] as num?)?.toDouble() ?? 0.0,
              'altitude': (currentLocation['altitude'] as num?)?.toDouble() ?? 0.0,
              'status': locationStatus,
            } : null,
            'lastLocation': lastLocation != null ? {
              'latitude': (lastLocation['latitude'] as num?)?.toDouble() ?? 0.0,
              'longitude': (lastLocation['longitude'] as num?)?.toDouble() ?? 0.0,
              'altitude': (lastLocation['altitude'] as num?)?.toDouble() ?? 0.0,
            } : null,
            'isCached': locationStatus == 'cached',
          });
        }
      });
    }
  }

  Future<void> _refreshData() async {
    await _loadActivities();
  }

  void _handleRefreshButton() {
    _refreshData();
  }

  String _getLocationName(double latitude, double longitude) {
    return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
  }

  List<Map<String, dynamic>> get _filteredActivities {
    if (_showCachedLogs) {
      return _activities;
    }
    return _activities.where((activity) => activity['isCached'] != true).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredActivities = _filteredActivities;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.childName != null 
              ? '${widget.childName}\'s Activity Log' 
              : 'Activity Log'
        ),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _showCachedLogs ? Icons.filter_alt : Icons.filter_alt_off,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _showCachedLogs = !_showCachedLogs;
              });
            },
            tooltip: _showCachedLogs ? 'Hide Cached Logs' : 'Show Cached Logs',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _handleRefreshButton,
            tooltip: 'Refresh Activities',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info Card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on, color: Colors.blue[800], size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                    '${filteredActivities.length} location update${filteredActivities.length != 1 ? 's' : ''}',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: filteredActivities.isEmpty ? Colors.grey : Colors.green,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        filteredActivities.isEmpty ? 'No data' : 'Tracking active',
                                        style: TextStyle(
                                          color: filteredActivities.isEmpty ? Colors.grey : Colors.green,
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
                        
                        // Filter Info
                        if (_showCachedLogs || _showCurrentLocation) ...[
                          const Divider(height: 20),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (_showCachedLogs)
                                Chip(
                                  avatar: const Icon(Icons.info_outline, size: 16),
                                  label: const Text('Showing cached logs', style: TextStyle(fontSize: 12)),
                                  backgroundColor: Colors.blue[50],
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  onDeleted: () {
                                    setState(() {
                                      _showCachedLogs = false;
                                    });
                                  },
                                ),
                              if (_showCurrentLocation)
                                Chip(
                                  avatar: const Icon(Icons.my_location, size: 16),
                                  label: const Text('Showing current location', style: TextStyle(fontSize: 12)),
                                  backgroundColor: Colors.green[50],
                                  deleteIcon: const Icon(Icons.close, size: 16),
                                  onDeleted: () {
                                    setState(() {
                                      _showCurrentLocation = false;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Activities List
                Expanded(
                  child: filteredActivities.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No activities yet',
                                style: TextStyle(color: Colors.grey, fontSize: 16),
                              ),
                              SizedBox(height: 8),
                              Text(
                                widget.childName != null
                                    ? 'No location updates for ${widget.childName}'
                                    : _showCachedLogs 
                                        ? 'No location updates found'
                                        : 'Try showing cached logs',
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refreshData,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredActivities.length,
                            itemBuilder: (context, index) {
                              final activity = filteredActivities[index];
                              return _buildActivityItem(activity, index);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> activity, int index) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(activity['lastUpdate']);
    final timeString = DateFormat('MMM dd, yyyy • h:mm a').format(timestamp);
    final lastLocation = activity['lastLocation'] as Map<String, dynamic>?;
    final currentLocation = activity['currentLocation'] as Map<String, dynamic>?;
    final locationStatus = currentLocation?['status'] as String? ?? 'unknown';
    final isCached = activity['isCached'] as bool? ?? false;
    final gpsAvailable = activity['gpsAvailable'] as bool? ?? false;
    final batteryLevel = (activity['batteryLevel'] as num?)?.toDouble() ?? 0.0;
    final childName = activity['childName'] as String;
    final sosActive = activity['sos'] as bool? ?? false;
    
    String locationName = 'No location';
    if (lastLocation != null) {
      locationName = _getLocationName(
        lastLocation['latitude'] as double, 
        lastLocation['longitude'] as double
      );
    }
    
    // Determine icon and color based on location status and GPS
    IconData icon;
    Color iconColor;
    Color bgColor;
    
    if (sosActive) {
      icon = Icons.warning;
      iconColor = Colors.red;
      bgColor = Colors.red[100]!;
    } else if (gpsAvailable) {
      icon = Icons.gps_fixed;
      iconColor = Colors.green;
      bgColor = Colors.green[100]!;
    } else if (isCached) {
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
        side: sosActive ? BorderSide(color: Colors.red, width: 2) : BorderSide.none,
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
            if (widget.deviceCode == null) // Show child name only if viewing all devices
              Text(
                childName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: sosActive ? Colors.red : Colors.blue[700],
                  fontSize: 14,
                ),
              ),
            if (widget.deviceCode == null)
              const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    locationName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,  // ← ADD THIS
                    maxLines: 1,                       // ← ADD THIS
                  ),
                ),
                if (sosActive) ...[
                  const SizedBox(width: 8),           // ← ADD THIS for spacing
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                _buildStatusChip(
                  gpsAvailable ? 'GPS Available' : 'GPS Unavailable',
                  gpsAvailable ? Colors.green : Colors.grey,
                ),
                _buildStatusChip(
                  locationStatus == 'success' ? 'Success' : 'Cached',
                  locationStatus == 'success' ? Colors.blue : Colors.orange,
                ),
                if (batteryLevel > 0)
                  _buildStatusChip(
                    '${batteryLevel.toStringAsFixed(0)}%',  // ← Correct: percentage
                    batteryLevel < 20 ? Colors.red : batteryLevel < 50 ? Colors.orange : Colors.green,  // ← Correct thresholds
                  ),
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
        onTap: () {
          _showActivityDetails(activity);
        },
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
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
    final lastLocation = activity['lastLocation'] as Map<String, dynamic>?;
    final currentLocation = activity['currentLocation'] as Map<String, dynamic>?;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Child Name', activity['childName']),
              _buildDetailRow('Device Code', activity['deviceCode']),
              const Divider(height: 20),
              
              // Last Location (Always shown)
              const Text(
                'Last Known Location (GPS Success)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              if (lastLocation != null) ...[
                _buildDetailRow('Latitude', lastLocation['latitude'].toString()),
                _buildDetailRow('Longitude', lastLocation['longitude'].toString()),
                if (lastLocation['altitude'] != null && lastLocation['altitude'] != 0)
                  _buildDetailRow('Altitude', '${lastLocation['altitude']}m'),
              ] else
                const Text('No GPS location recorded', style: TextStyle(color: Colors.grey)),
              
              // Current Location (Toggle-able)
              if (_showCurrentLocation && currentLocation != null) ...[
                const Divider(height: 20),
                Row(
                  children: [
                    const Text(
                      'Current Location',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: currentLocation['status'] == 'success' 
                            ? Colors.green.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        currentLocation['status']?.toString().toUpperCase() ?? 'UNKNOWN',
                        style: TextStyle(
                          fontSize: 10,
                          color: currentLocation['status'] == 'success' 
                              ? Colors.green 
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDetailRow('Latitude', currentLocation['latitude'].toString()),
                _buildDetailRow('Longitude', currentLocation['longitude'].toString()),
                if (currentLocation['altitude'] != null && currentLocation['altitude'] != 0)
                  _buildDetailRow('Altitude', '${currentLocation['altitude']}m'),
              ],
              
              const Divider(height: 20),
              _buildDetailRow('GPS Available', activity['gpsAvailable'] ? 'Yes' : 'No'),
              _buildDetailRow('Battery Level', '${(activity['batteryLevel'] as num).toStringAsFixed(0)}%'),
              _buildDetailRow('SOS Active', activity['sos'] ? 'YES' : 'No'),
              const Divider(height: 20),
              _buildDetailRow(
                'Timestamp',
                DateFormat('MMM dd, yyyy at h:mm:ss a').format(
                  DateTime.fromMillisecondsSinceEpoch(activity['lastUpdate'])
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (currentLocation != null)
            TextButton.icon(
              icon: Icon(
                _showCurrentLocation ? Icons.visibility_off : Icons.visibility,
                size: 18,
              ),
              label: Text(
                _showCurrentLocation ? 'Hide' : 'Show',
                style: const TextStyle(fontSize: 13),
              ),
              onPressed: () {
                setState(() {
                  _showCurrentLocation = !_showCurrentLocation;
                });
                Navigator.pop(context);
                _showActivityDetails(activity);
              },
            ),
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}