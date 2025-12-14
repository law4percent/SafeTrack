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
        (b['timestamp'] as int).compareTo(a['timestamp'] as int)
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
    final locationSnapshot = await _databaseRef
        .child('deviceLogs')
        .child(userId)
        .child(deviceCode)
        .get();

    if (locationSnapshot.exists) {
      final locationData = locationSnapshot.value as Map<dynamic, dynamic>;
      
      locationData.forEach((key, value) {
        if (value is Map) {
          if (value.containsKey('timestamp')) {
            // New format with push IDs
            tempActivities.add({
              'deviceCode': deviceCode,
              'childName': childName,
              'latitude': value['latitude'],
              'longitude': value['longitude'],
              'accuracy': value['accuracy'],
              'locationType': value['locationType'] ?? 'unknown',
              'timestamp': value['timestamp'],
              'altitude': value['altitude'],
              'speed': value['speed'],
            });
          } else {
            // Old format with date keys
            value.forEach((timeKey, timeData) {
              if (timeData is Map) {
                try {
                  final dateParts = key.toString().split('-');
                  final timeParts = timeKey.toString().split(':');
                  
                  if (dateParts.length == 3 && timeParts.length == 2) {
                    final dateTime = DateTime(
                      int.parse(dateParts[2]), // year
                      int.parse(dateParts[0]), // month
                      int.parse(dateParts[1]), // day
                      int.parse(timeParts[0]), // hour
                      int.parse(timeParts[1]), // minute
                    );
                    
                    tempActivities.add({
                      'deviceCode': deviceCode,
                      'childName': childName,
                      'latitude': timeData['latitude'],
                      'longitude': timeData['longitude'],
                      'accuracy': 0,
                      'locationType': 'gps',
                      'timestamp': dateTime.millisecondsSinceEpoch,
                      'altitude': timeData['altitude'],
                      'speed': timeData['speed'],
                    });
                  }
                } catch (e) {
                  debugPrint('Error parsing date-time entry: $e');
                }
              }
            });
          }
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

  @override
  Widget build(BuildContext context) {
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
                    child: Row(
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
                                '${_activities.length} location update${_activities.length != 1 ? 's' : ''}',
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
                                      color: _activities.isEmpty ? Colors.grey : Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _activities.isEmpty ? 'No data' : 'Tracking active',
                                    style: TextStyle(
                                      color: _activities.isEmpty ? Colors.grey : Colors.green,
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
                  ),
                ),
                
                // Activities List
                Expanded(
                  child: _activities.isEmpty
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
                                    : 'Location updates will appear here',
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
                            itemCount: _activities.length,
                            itemBuilder: (context, index) {
                              final activity = _activities[index];
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
    final timestamp = DateTime.fromMillisecondsSinceEpoch(activity['timestamp']);
    final timeString = DateFormat('MMM dd, yyyy • h:mm a').format(timestamp);
    final locationType = activity['locationType'] as String;
    final locationName = _getLocationName(
      activity['latitude'] as double, 
      activity['longitude'] as double
    );
    final childName = activity['childName'] as String;
    
    // Determine icon and color based on location type
    IconData icon;
    Color iconColor;
    Color bgColor;
    
    switch (locationType.toLowerCase()) {
      case 'gps':
        icon = Icons.gps_fixed;
        iconColor = Colors.green;
        bgColor = Colors.green[100]!;
        break;
      case 'network':
        icon = Icons.wifi;
        iconColor = Colors.blue;
        bgColor = Colors.blue[100]!;
        break;
      case 'ip':
        icon = Icons.public;
        iconColor = Colors.orange;
        bgColor = Colors.orange[100]!;
        break;
      default:
        icon = Icons.location_on;
        iconColor = Colors.grey;
        bgColor = Colors.grey[100]!;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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
                  color: Colors.blue[700],
                  fontSize: 14,
                ),
              ),
            if (widget.deviceCode == null)
              const SizedBox(height: 2),
            Text(
              locationName,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(timeString),
            if (activity['accuracy'] != null && activity['accuracy'] != 0)
              Text(
                'Type: ${locationType.toUpperCase()} • Accuracy: ${activity['accuracy']}m',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              )
            else
              Text(
                'Type: ${locationType.toUpperCase()}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.grey[400],
        ),
        onTap: () {
          _showActivityDetails(activity);
        },
      ),
    );
  }

  void _showActivityDetails(Map<String, dynamic> activity) {
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
              _buildDetailRow('Latitude', activity['latitude'].toString()),
              _buildDetailRow('Longitude', activity['longitude'].toString()),
              if (activity['accuracy'] != null && activity['accuracy'] != 0)
                _buildDetailRow('Accuracy', '${activity['accuracy']}m'),
              _buildDetailRow('Type', activity['locationType']),
              if (activity['altitude'] != null && activity['altitude'] != 0)
                _buildDetailRow('Altitude', '${activity['altitude']}m'),
              if (activity['speed'] != null && activity['speed'] != 0)
                _buildDetailRow('Speed', '${activity['speed']} m/s'),
              const Divider(height: 20),
              _buildDetailRow(
                'Timestamp',
                DateFormat('MMM dd, yyyy at h:mm:ss a').format(
                  DateTime.fromMillisecondsSinceEpoch(activity['timestamp'])
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
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}