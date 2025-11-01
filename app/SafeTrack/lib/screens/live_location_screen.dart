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
          final deviceCodes = devicesData.keys.map((key) => key.toString()).toList();

          if (deviceCodes.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: deviceCodes.length,
            itemBuilder: (context, index) {
              return DeviceLocationCard(deviceCode: deviceCodes[index]);
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

class DeviceLocationCard extends StatelessWidget {
  final String deviceCode;

  const DeviceLocationCard({super.key, required this.deviceCode});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null) return const SizedBox();

    return StreamBuilder<DatabaseEvent>(
      stream: rtdbInstance.ref('linkedDevices').child(user.uid).child('devices').child(deviceCode).onValue,
      builder: (context, deviceSnapshot) {
        if (!deviceSnapshot.hasData || deviceSnapshot.data!.snapshot.value == null) {
          return const SizedBox();
        }

        final deviceData = deviceSnapshot.data!.snapshot.value as Map<dynamic, dynamic>;
        final childName = deviceData['childName']?.toString() ?? 'Unknown';

        return StreamBuilder<DatabaseEvent>(
          stream: rtdbInstance.ref('children/$deviceCode').onValue,
          builder: (context, locationSnapshot) {
            bool isOnline = false;
            double? latitude;
            double? longitude;
            int batteryLevel = 0;
            String? lastUpdate;

            if (locationSnapshot.hasData && locationSnapshot.data!.snapshot.value != null) {
              final data = locationSnapshot.data!.snapshot.value as Map<dynamic, dynamic>;
              isOnline = data['isOnline'] == true;
              latitude = (data['latitude'] as num?)?.toDouble();
              longitude = (data['longitude'] as num?)?.toDouble();
              batteryLevel = (data['batteryLevel'] as num?)?.toInt() ?? 0;
              
              if (data['lastUpdate'] != null) {
                final timestamp = data['lastUpdate'] as int;
                final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
                lastUpdate = _formatDateTime(date);
              }
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
                                childName,
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
                        if (batteryLevel > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: batteryLevel < 20 ? Colors.red.shade50 : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.battery_std,
                                  size: 16,
                                  color: batteryLevel < 20 ? Colors.red : Colors.green,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$batteryLevel%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: batteryLevel < 20 ? Colors.red : Colors.green,
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
                    ],
                    if (lastUpdate != null)
                      _buildInfoRow(Icons.access_time, 'Last Update', lastUpdate),
                    if (latitude == null || longitude == null)
                      Container(
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
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
