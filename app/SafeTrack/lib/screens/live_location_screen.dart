// app/SafeTrack/lib/screens/live_location_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

// Firebase Realtime Database instance
final FirebaseDatabase rtdbInstance = FirebaseDatabase.instance;

class LiveLocationsScreen extends StatelessWidget {
  const LiveLocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Live Locations'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Please log in first')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Locations', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: rtdbInstance.ref('linkedDevices').child(user.uid).child('devices').onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return _buildEmptyState();
          }

          final devicesData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
          
          // Filter enabled devices only
          final List<Map<String, String>> enabledDevices = [];
          devicesData.forEach((key, value) {
            final deviceData = value as Map<dynamic, dynamic>;
            final isEnabled = deviceData['deviceEnabled']?.toString() == 'true';
            if (isEnabled) {
              enabledDevices.add({
                'deviceCode': key.toString(),
                'childName': deviceData['childName']?.toString() ?? 'Unknown',
              });
            }
          });

          if (enabledDevices.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: enabledDevices.length,
            itemBuilder: (context, index) {
              return DeviceLocationCard(
                deviceCode: enabledDevices[index]['deviceCode']!,
                childName: enabledDevices[index]['childName']!,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_off, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 20),
          Text(
            'No Devices to Track',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Link a device in My Children to start tracking',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

class DeviceLocationCard extends StatefulWidget {
  final String deviceCode;
  final String childName;

  const DeviceLocationCard({
    super.key,
    required this.deviceCode,
    required this.childName,
  });

  @override
  State<DeviceLocationCard> createState() => _DeviceLocationCardState();
}

class _DeviceLocationCardState extends State<DeviceLocationCard> {
  Map<String, dynamic>? _latestLocation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLatestLocation();
  }

  Future<void> _loadLatestLocation() async {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null) return;

    try {
      final snapshot = await rtdbInstance
          .ref('deviceLogs')
          .child(user.uid)
          .child(widget.deviceCode)
          .get();

      if (snapshot.exists) {
        final locationData = snapshot.value as Map<dynamic, dynamic>;
        Map<String, dynamic>? latestEntry;
        int latestTimestamp = 0;

        // Find the most recent location
        locationData.forEach((key, value) {
          if (value is Map) {
            if (value.containsKey('timestamp')) {
              // New format with push IDs
              final timestamp = value['timestamp'] as int;
              if (timestamp > latestTimestamp) {
                latestTimestamp = timestamp;
                latestEntry = {
                  'latitude': value['latitude'],
                  'longitude': value['longitude'],
                  'accuracy': value['accuracy'],
                  'locationType': value['locationType'] ?? 'unknown',
                  'timestamp': timestamp,
                  'altitude': value['altitude'],
                  'speed': value['speed'],
                };
              }
            } else {
              // Old format with date keys - parse each time entry
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
                      
                      final timestamp = dateTime.millisecondsSinceEpoch;
                      if (timestamp > latestTimestamp) {
                        latestTimestamp = timestamp;
                        latestEntry = {
                          'latitude': timeData['latitude'],
                          'longitude': timeData['longitude'],
                          'accuracy': 0,
                          'locationType': 'gps',
                          'timestamp': timestamp,
                          'altitude': timeData['altitude'],
                          'speed': timeData['speed'],
                        };
                      }
                    }
                  } catch (e) {
                    debugPrint('Error parsing date-time: $e');
                  }
                }
              });
            }
          }
        });

        setState(() {
          _latestLocation = latestEntry;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading location: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isOnline() {
    if (_latestLocation == null) return false;
    
    final timestamp = _latestLocation!['timestamp'] as int;
    final lastUpdate = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(lastUpdate).inMinutes;
    
    return difference < 5; // Online if updated within 5 minutes
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        elevation: 4,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final isOnline = _isOnline();
    final latitude = _latestLocation?['latitude'] as double?;
    final longitude = _latestLocation?['longitude'] as double?;
    final accuracy = _latestLocation?['accuracy'] as int?;
    final locationType = _latestLocation?['locationType'] as String?;
    final altitude = _latestLocation?['altitude'] as double?;
    final speed = _latestLocation?['speed'] as double?;
    
    String? lastUpdate;
    if (_latestLocation != null) {
      final timestamp = _latestLocation!['timestamp'] as int;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      lastUpdate = _formatDateTime(date);
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: isOnline ? Colors.green : Colors.grey,
                  child: Icon(
                    isOnline ? Icons.location_on : Icons.location_off,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.childName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 12,
                            color: isOnline ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: isOnline ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Location Type Badge
                if (locationType != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getLocationTypeColor(locationType).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getLocationTypeColor(locationType),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getLocationTypeIcon(locationType),
                          size: 16,
                          color: _getLocationTypeColor(locationType),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          locationType.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _getLocationTypeColor(locationType),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (latitude != null && longitude != null) ...[
              _buildInfoRow(Icons.my_location, 'Latitude', latitude.toStringAsFixed(6)),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.explore, 'Longitude', longitude.toStringAsFixed(6)),
              const SizedBox(height: 8),
              if (accuracy != null && accuracy > 0)
                _buildInfoRow(Icons.gps_fixed, 'Accuracy', '$accuracy meters'),
              if (accuracy != null && accuracy > 0)
                const SizedBox(height: 8),
              if (altitude != null && altitude != 0)
                _buildInfoRow(Icons.terrain, 'Altitude', '${altitude.toStringAsFixed(2)}m'),
              if (altitude != null && altitude != 0)
                const SizedBox(height: 8),
              if (speed != null && speed != 0)
                _buildInfoRow(Icons.speed, 'Speed', '${speed.toStringAsFixed(2)} m/s'),
              if (speed != null && speed != 0)
                const SizedBox(height: 8),
            ],
            if (lastUpdate != null)
              _buildInfoRow(Icons.access_time, 'Last Update', lastUpdate),
            if (latitude == null || longitude == null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location data not available',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            // Refresh Button
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loadLatestLocation,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh Location'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getLocationTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'gps':
        return Icons.gps_fixed;
      case 'network':
        return Icons.wifi;
      case 'ip':
        return Icons.public;
      default:
        return Icons.location_on;
    }
  }

  Color _getLocationTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'gps':
        return Colors.green;
      case 'network':
        return Colors.blue;
      case 'ip':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
  }
}