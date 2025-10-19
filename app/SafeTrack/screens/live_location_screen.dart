import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import '../auth_service.dart';
import 'live_tracking_screen.dart';

// ✅ Same RTDB configuration gaya ng LiveTrackingScreen
const String firebaseRtdbUrl = 'https://protectid-f04a3-default-rtdb.asia-southeast1.firebasedatabase.app';

final FirebaseDatabase rtdbInstance = FirebaseDatabase.instanceFor(
  app: Firebase.app(),
  databaseURL: firebaseRtdbUrl,
);

class ChildLocationData {
  final double lat;
  final double lng;
  final String deviceCode;
  final String nickname;
  final bool isOnline;
  final bool sosActive;
  final int batteryLevel;
  final DateTime? lastUpdated;

  const ChildLocationData({
    required this.lat,
    required this.lng,
    required this.deviceCode,
    required this.nickname,
    required this.isOnline,
    required this.sosActive,
    required this.batteryLevel,
    this.lastUpdated,
  });

  // ✅ Helper function to get longitude from multiple field names
  static double? _getLongitudeFromRTDB(Map<dynamic, dynamic> data) {
    return (data['Ing'] as num?)?.toDouble() ?? 
           (data['ing'] as num?)?.toDouble() ?? 
           (data['lng'] as num?)?.toDouble();
  }

  // ✅ Helper function to parse timestamp
  static DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    if (timestamp is String) {
      return DateTime.tryParse(timestamp);
    }
    return null;
  }

  // ✅ Gumamit ng Firestore nickname kung available
  factory ChildLocationData.fromRTDB(
    String code, 
    Map<dynamic, dynamic> data, 
    Map<String, String>? firestoreNicknames,
  ) {
    final lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
    final lng = _getLongitudeFromRTDB(data) ?? 0.0;
    
    // ✅ PRIORITIZE: Firestore nickname from 'children' collection
    String nickname;
    if (firestoreNicknames != null && firestoreNicknames.containsKey(code)) {
      nickname = firestoreNicknames[code]!;
    } else {
      // Fallback to RTDB nickname or default
      nickname = data['nickname']?.toString() ?? 'Device ${code.length > 4 ? code.substring(0, 4) : code}';
    }
    
    return ChildLocationData(
      lat: lat,
      lng: lng,
      deviceCode: code,
      nickname: nickname,
      isOnline: data['isOnline'] == true,
      sosActive: data['sosActive'] == true,
      batteryLevel: (data['batteryLevel'] as num?)?.toInt() ?? 0,
      lastUpdated: _parseTimestamp(data['timestamp']),
    );
  }
}

class LiveLocationsScreen extends StatefulWidget {
  const LiveLocationsScreen({super.key});

  @override
  State<LiveLocationsScreen> createState() => _LiveLocationsScreenState();
}

class _LiveLocationsScreenState extends State<LiveLocationsScreen> {
  // ✅ Gamitin ang configured instance hindi default
  final FirebaseDatabase _rtdb = rtdbInstance;
  final MapController _mapController = MapController();
  final GlobalKey _refreshIndicatorKey = GlobalKey();
  bool _isLoading = false;

  Future<List<String>> _fetchDeviceCodes(String parentId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('parents')
          .doc(parentId)
          .get();

      final deviceCodes = (doc.data()?['childDeviceCodes'] as List<dynamic>?)?.cast<String>() ?? [];
      debugPrint('📱 Found ${deviceCodes.length} device codes for parent $parentId');
      return deviceCodes;
    } catch (e) {
      debugPrint('❌ Error fetching device codes: $e');
      return [];
    }
  }

  // ✅ FIXED: Correct Firestore nickname fetching from 'children' collection
  Future<Map<String, String>> _fetchFirestoreNicknames(List<String> deviceCodes) async {
    try {
      if (deviceCodes.isEmpty) return {};
      
      final Map<String, String> nicknames = {};
      
      // ✅ Query the 'children' collection for each device code
      for (String deviceCode in deviceCodes) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('children')
              .doc(deviceCode) // ✅ Use deviceCode as document ID
              .get();

          if (doc.exists) {
            final data = doc.data();
            // ✅ Get nickname from the document fields directly
            final nickname = data?['nickname']?.toString();
            
            if (nickname != null && nickname.isNotEmpty) {
              nicknames[deviceCode] = nickname;
              debugPrint('✅ Found Firestore nickname for $deviceCode: $nickname');
            } else {
              debugPrint('⚠️ No nickname found in Firestore for $deviceCode');
            }
          } else {
            debugPrint('❌ No Firestore document found for device: $deviceCode');
          }
        } catch (e) {
          debugPrint('❌ Error fetching nickname for $deviceCode: $e');
        }
      }
      
      debugPrint('✅ Final Firestore nicknames: $nicknames');
      return nicknames;
    } catch (e) {
      debugPrint('❌ Error in _fetchFirestoreNicknames: $e');
      return {};
    }
  }

  // ✅ FIXED: Stream para sa real-time location updates
  Stream<List<ChildLocationData>> _getLiveLocations(List<String> deviceCodes) {
    if (deviceCodes.isEmpty) {
      return Stream.value([]);
    }

    return _rtdb.ref('children').onValue.asyncMap((event) async {
      final Map<dynamic, dynamic>? devicesData = event.snapshot.value as Map<dynamic, dynamic>?;
      final List<ChildLocationData> locations = [];

      // ✅ Fetch Firestore nicknames from 'children' collection
      final firestoreNicknames = await _fetchFirestoreNicknames(deviceCodes);

      if (devicesData != null) {
        devicesData.forEach((deviceId, data) {
          final deviceIdStr = deviceId.toString();
          
          // ✅ FIXED: Check if device exists in our device codes list
          if (deviceCodes.contains(deviceIdStr) && data is Map) {
            try {
              final location = ChildLocationData.fromRTDB(deviceIdStr, data, firestoreNicknames);
              
              // ✅ FIXED: Only add if location is valid (not 0,0)
              if (location.lat != 0.0 && location.lng != 0.0) {
                locations.add(location);
                debugPrint('📍 Added marker for $deviceIdStr at ${location.lat}, ${location.lng}');
              } else {
                debugPrint('⚠️ Invalid location for $deviceIdStr: ${location.lat}, ${location.lng}');
              }
            } catch (e) {
              debugPrint('❌ Error creating location for $deviceIdStr: $e');
            }
          }
        });
      }
      
      debugPrint('🎯 Total markers to display: ${locations.length}');
      return locations;
    });
  }

  // ✅ FIXED: Navigation to LiveTrackingScreen - use default constructor
  void _navigateToLiveTracking(BuildContext context, ChildLocationData data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LiveTrackingScreen(), // ✅ USE DEFAULT CONSTRUCTOR
      ),
    );
  }

  Widget _buildBatteryIcon(int batteryLevel) {
    IconData icon;
    Color color;
    
    if (batteryLevel >= 70) {
      icon = Icons.battery_full;
      color = Colors.green;
    } else if (batteryLevel >= 30) {
      icon = Icons.battery_std;
      color = Colors.orange;
    } else {
      icon = Icons.battery_alert;
      color = Colors.red;
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 2),
        Text('$batteryLevel%', style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }

  Marker _buildMarker(ChildLocationData data) {
    final Color color = data.sosActive ? Colors.red : (data.isOnline ? Colors.green : Colors.grey);
    final IconData icon = data.sosActive ? Icons.warning : (data.isOnline ? Icons.location_on : Icons.location_off);

    return Marker(
      width: 80.0,
      height: 80.0,
      point: LatLng(data.lat, data.lng),
      child: GestureDetector(
        onTap: () {
          _showDeviceInfo(context, data);
        },
        onLongPress: () {
          _navigateToLiveTracking(context, data);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: data.sosActive 
                    ? Border.all(color: Colors.yellow, width: 3) 
                    : Border.all(color: color, width: 2),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                border: data.sosActive 
                    ? Border.all(color: Colors.yellow, width: 2) 
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                data.nickname,
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 11, 
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 3,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeviceInfo(BuildContext context, ChildLocationData data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              data.sosActive ? Icons.warning : Icons.location_on,
              color: data.sosActive ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                data.nickname,
                style: TextStyle(
                  color: data.sosActive ? Colors.red : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Device Code', data.deviceCode),
              _buildInfoRow('Status', 
                data.isOnline ? 'Online' : 'Offline', 
                color: data.isOnline ? Colors.green : Colors.grey
              ),
              _buildInfoRow('Battery Level', '${data.batteryLevel}%'),
              _buildInfoRow('SOS Status', 
                data.sosActive ? 'ACTIVE - NEEDS HELP!' : 'Inactive',
                color: data.sosActive ? Colors.red : Colors.grey
              ),
              _buildInfoRow('Location', 
                '${data.lat.toStringAsFixed(6)}, ${data.lng.toStringAsFixed(6)}'
              ),
              if (data.lastUpdated != null)
                _buildInfoRow('Last Updated', 
                  _formatDateTime(data.lastUpdated!)
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToLiveTracking(context, data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.track_changes, size: 16),
                SizedBox(width: 4),
                Text('Track Live'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: color == Colors.red ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} ${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  void _zoomToAllMarkers(List<ChildLocationData> locations) {
    if (locations.isEmpty) return;

    final validLocations = locations.where((loc) => loc.lat != 0.0).toList();
    if (validLocations.isEmpty) return;

    if (validLocations.length == 1) {
      _mapController.move(LatLng(validLocations.first.lat, validLocations.first.lng), 15);
    } else {
      double minLat = validLocations.first.lat;
      double maxLat = validLocations.first.lat;
      double minLng = validLocations.first.lng;
      double maxLng = validLocations.first.lng;

      for (final location in validLocations) {
        if (location.lat < minLat) minLat = location.lat;
        if (location.lat > maxLat) maxLat = location.lat;
        if (location.lng < minLng) minLng = location.lng;
        if (location.lng > maxLng) maxLng = location.lng;
      }

      final center = LatLng(
        (minLat + maxLat) / 2,
        (minLng + maxLng) / 2,
      );
      
      final latDiff = maxLat - minLat;
      final lngDiff = maxLng - minLng;
      final zoom = 12 - (latDiff + lngDiff) * 5;
      
      _mapController.move(center, zoom.clamp(10.0, 16.0));
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });
    
    // Simulate refresh delay
    await Future.delayed(const Duration(milliseconds: 1000));
    
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Locations')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('Please log in first', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<List<String>>(
      future: _fetchDeviceCodes(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading your devices...'),
                ],
              ),
            ),
          );
        }

        final deviceCodes = snapshot.data ?? [];

        if (deviceCodes.isEmpty) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Live Locations'),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refreshData,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.devices_other, size: 80, color: Colors.grey),
                    const SizedBox(height: 20),
                    const Text(
                      'No Linked Devices',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Add devices in My Children section to see them here',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _refreshData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return StreamBuilder<List<ChildLocationData>>(
          stream: _getLiveLocations(deviceCodes),
          builder: (context, locationSnapshot) {
            final locations = locationSnapshot.data ?? [];
            final markers = locations.map(_buildMarker).toList();

            // ✅ FIXED: Default center and zoom calculation
            LatLng center = const LatLng(10.3157, 123.8854); // Default Cebu
            double zoom = 12.0;

            if (locations.isNotEmpty) {
              final validLocations = locations.where((loc) => loc.lat != 0.0).toList();
              if (validLocations.isNotEmpty) {
                double totalLat = 0;
                double totalLng = 0;
                
                for (final location in validLocations) {
                  totalLat += location.lat;
                  totalLng += location.lng;
                }
                
                center = LatLng(totalLat / validLocations.length, totalLng / validLocations.length);
                zoom = validLocations.length > 1 ? 10.0 : 14.0;
              }
            }

            debugPrint('🗺️ Map Center: $center, Zoom: $zoom');
            debugPrint('📍 Markers count: ${markers.length}');

            return Scaffold(
              appBar: AppBar(
                title: const Text('Live Locations - Overview'),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                actions: [
                  if (markers.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.zoom_out_map),
                      onPressed: () => _zoomToAllMarkers(locations),
                      tooltip: 'Zoom to all markers',
                    ),
                  IconButton(
                    icon: _isLoading 
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    onPressed: _isLoading ? null : _refreshData,
                    tooltip: 'Refresh locations',
                  ),
                ],
              ),
              body: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center, 
                        initialZoom: zoom,
                        onMapReady: () {
                          debugPrint('🗺️ Map is ready!');
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: "https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=pk.eyJ1IjoiYXNocmVkIiwiYSI6ImNtZ2dndWNhODBrcGwyam9ybXhodzN0YXUifQ.nFtZjuv0AvGEIv3v4TxmXg",
                          userAgentPackageName: 'com.example.protectid',
                        ),
                        MarkerLayer(markers: markers),
                      ],
                    ),
                    
                    // ✅ Quick Status Overview
                    if (locations.isNotEmpty)
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(240),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '📍 Quick Overview',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.green,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _buildStatusIndicator(
                                    'Total',
                                    locations.length.toString(),
                                    Icons.devices,
                                    Colors.blue,
                                  ),
                                  _buildStatusIndicator(
                                    'Online',
                                    locations.where((loc) => loc.isOnline).length.toString(),
                                    Icons.circle,
                                    Colors.green,
                                  ),
                                  _buildStatusIndicator(
                                    'SOS',
                                    locations.where((loc) => loc.sosActive).length.toString(),
                                    Icons.warning,
                                    Colors.red,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ✅ Loading Indicator
                    if (locationSnapshot.connectionState == ConnectionState.waiting)
                      const Center(
                        child: CircularProgressIndicator(),
                      ),

                    // ✅ No Markers Found Message
                    if (locationSnapshot.connectionState == ConnectionState.active && 
                        locations.isEmpty)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(200),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_off, size: 50, color: Colors.grey),
                              const SizedBox(height: 10),
                              const Text(
                                'No Location Data',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${deviceCodes.length} devices found but no location data available',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ✅ Bottom buttons
              bottomNavigationBar: _buildBottomButtons(context, locations.isNotEmpty ? locations : null),
            );
          },
        );
      },
    );
  }

  // ✅ Bottom buttons
  Widget _buildBottomButtons(BuildContext context, List<ChildLocationData>? locations) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Refresh Button
          ElevatedButton.icon(
            onPressed: _refreshData,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),

          // Devices List Button (kung may markers)
          if (locations != null && locations.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => _showDevicesList(context, locations),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              icon: const Icon(Icons.list),
              label: const Text('Devices'),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _showDevicesList(BuildContext context, List<ChildLocationData> locations) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'All Linked Devices',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: locations.length,
                itemBuilder: (context, index) {
                  final device = locations[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    elevation: 2,
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: device.sosActive ? Colors.red : 
                                device.isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          device.sosActive ? Icons.warning : 
                          device.isOnline ? Icons.location_on : Icons.location_off,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        device.nickname,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${device.lat.toStringAsFixed(4)}, ${device.lng.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _buildBatteryIcon(device.batteryLevel),
                              const SizedBox(width: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: device.sosActive ? Colors.red : 
                                        device.isOnline ? Colors.green : Colors.grey,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  device.sosActive ? 'SOS!' : 
                                  device.isOnline ? 'Online' : 'Offline',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.pop(context);
                        _navigateToLiveTracking(context, device);
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Close List'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
