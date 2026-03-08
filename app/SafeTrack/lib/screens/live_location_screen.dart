// app/SafeTrack/lib/screens/live_location_screen.dart
import 'dart:async';
import 'dart:ui' as ui; // alias to avoid Path conflict with flutter_map
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/auth_service.dart';

// =============================================================
// ROUTE DATA MODEL
// =============================================================
class _RouteData {
  final String routeId;
  final String pathName;
  final double thresholdMeters;
  final List<LatLng> waypoints;
  const _RouteData({
    required this.routeId,
    required this.pathName,
    required this.thresholdMeters,
    required this.waypoints,
  });
}

// =============================================================
// SHARED HELPERS
// =============================================================

List<LatLng> _parseWaypoints(dynamic raw) {
  final List<Map<dynamic, dynamic>> wpMaps = [];
  if (raw is Map) {
    final sorted = (raw as Map<dynamic, dynamic>).entries.toList()
      ..sort((a, b) {
        final ai =
            int.tryParse(a.key.toString().replaceAll('wp_', '')) ?? 0;
        final bi =
            int.tryParse(b.key.toString().replaceAll('wp_', '')) ?? 0;
        return ai.compareTo(bi);
      });
    wpMaps.addAll(sorted.map((e) => e.value as Map<dynamic, dynamic>));
  } else if (raw is List) {
    wpMaps.addAll(raw.whereType<Map<dynamic, dynamic>>());
  }
  return wpMaps
      .map((wp) {
        final lat = (wp['latitude'] as num?)?.toDouble();
        final lng = (wp['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) return null;
        return LatLng(lat, lng);
      })
      .whereType<LatLng>()
      .toList();
}

Future<List<_RouteData>> _loadRoutes(
    String userId, String deviceCode) async {
  try {
    final snap = await FirebaseDatabase.instance
        .ref('devicePaths')
        .child(userId)
        .child(deviceCode)
        .get();
    if (!snap.exists) return [];
    final data = snap.value as Map<dynamic, dynamic>;
    final routes = <_RouteData>[];
    for (final entry in data.entries) {
      final d = entry.value as Map<dynamic, dynamic>;
      if (!(d['isActive'] as bool? ?? true)) continue;
      final waypoints = _parseWaypoints(d['waypoints']);
      if (waypoints.length < 2) continue;
      routes.add(_RouteData(
        routeId: entry.key.toString(),
        pathName: d['pathName']?.toString() ?? 'Route',
        thresholdMeters:
            (d['deviationThresholdMeters'] as num?)?.toDouble() ?? 50,
        waypoints: waypoints,
      ));
    }
    return routes;
  } catch (e) {
    debugPrint('Error loading routes: $e');
    return [];
  }
}

// =============================================================
// LIVE LOCATIONS SCREEN
// =============================================================
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
        title: const Text(
          'Live Locations',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance
            .ref('linkedDevices')
            .child(user.uid)
            .child('devices')
            .onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData ||
              snapshot.data!.snapshot.value == null) {
            return _buildEmptyState();
          }
          final devicesData =
              snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
          final List<Map<String, String>> enabledDevices = [];
          devicesData.forEach((key, value) {
            final deviceData = value as Map<dynamic, dynamic>;
            final isEnabled =
                deviceData['deviceEnabled']?.toString() == 'true';
            if (isEnabled) {
              enabledDevices.add({
                'deviceCode': key.toString(),
                'childName':
                    deviceData['childName']?.toString() ?? 'Unknown',
              });
            }
          });
          if (enabledDevices.isEmpty) return _buildEmptyState();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: enabledDevices.length,
            itemBuilder: (context, index) {
              return DeviceLocationCard(
                deviceCode: enabledDevices[index]['deviceCode']!,
                childName: enabledDevices[index]['childName']!,
                userId: user.uid,
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
          Icon(Icons.location_off,
              size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 20),
          Text(
            'No Devices to Track',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Text(
            'Link a device in My Children to start tracking',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// DEVICE LOCATION CARD
// =============================================================
class DeviceLocationCard extends StatefulWidget {
  final String deviceCode;
  final String childName;
  final String userId;

  const DeviceLocationCard({
    super.key,
    required this.deviceCode,
    required this.childName,
    required this.userId,
  });

  @override
  State<DeviceLocationCard> createState() => _DeviceLocationCardState();
}

class _DeviceLocationCardState extends State<DeviceLocationCard> {
  Map<String, dynamic>? _latestLocation;
  bool _isLoading = true;
  bool _mapExpanded = true;
  StreamSubscription<DatabaseEvent>? _locationSub;
  final MapController _mapController = MapController();
  List<_RouteData> _routes = []; // ✅ NEW

  @override
  void initState() {
    super.initState();
    _subscribeToLocation();
    _loadDeviceRoutes(); // ✅ NEW
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  // ✅ NEW
  Future<void> _loadDeviceRoutes() async {
    final routes = await _loadRoutes(widget.userId, widget.deviceCode);
    if (mounted) setState(() => _routes = routes);
  }

  void _subscribeToLocation() {
    _locationSub = FirebaseDatabase.instance
        .ref('deviceLogs')
        .child(widget.userId)
        .child(widget.deviceCode)
        .onValue
        .listen((event) {
      if (!mounted) return;
      if (!event.snapshot.exists) {
        setState(() => _isLoading = false);
        return;
      }
      final locationData =
          event.snapshot.value as Map<dynamic, dynamic>;
      Map<String, dynamic>? latestEntry;
      int latestTimestamp = 0;

      locationData.forEach((key, value) {
        if (value is Map) {
          if (value.containsKey('timestamp')) {
            final timestamp = value['timestamp'] as int? ?? 0;
            if (timestamp > latestTimestamp) {
              latestTimestamp = timestamp;
              latestEntry = {
                'latitude':
                    (value['latitude'] as num?)?.toDouble(),
                'longitude':
                    (value['longitude'] as num?)?.toDouble(),
                'accuracy': value['accuracy'],
                'locationType': value['locationType'] ?? 'unknown',
                'timestamp': timestamp,
                'altitude':
                    (value['altitude'] as num?)?.toDouble(),
                'speed': (value['speed'] as num?)?.toDouble(),
              };
            }
          } else {
            value.forEach((timeKey, timeData) {
              if (timeData is Map) {
                try {
                  final dateParts = key.toString().split('-');
                  final timeParts = timeKey.toString().split(':');
                  if (dateParts.length == 3 &&
                      timeParts.length == 2) {
                    final dateTime = DateTime(
                      int.parse(dateParts[2]),
                      int.parse(dateParts[0]),
                      int.parse(dateParts[1]),
                      int.parse(timeParts[0]),
                      int.parse(timeParts[1]),
                    );
                    final timestamp =
                        dateTime.millisecondsSinceEpoch;
                    if (timestamp > latestTimestamp) {
                      latestTimestamp = timestamp;
                      latestEntry = {
                        'latitude':
                            (timeData['latitude'] as num?)
                                ?.toDouble(),
                        'longitude':
                            (timeData['longitude'] as num?)
                                ?.toDouble(),
                        'accuracy': 0,
                        'locationType': 'gps',
                        'timestamp': timestamp,
                        'altitude':
                            (timeData['altitude'] as num?)
                                ?.toDouble(),
                        'speed': (timeData['speed'] as num?)
                            ?.toDouble(),
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

      if (latestEntry != null) {
        final lat = latestEntry!['latitude'] as double?;
        final lng = latestEntry!['longitude'] as double?;
        if (lat != null && lng != null && _latestLocation != null) {
          try {
            _mapController.move(
                LatLng(lat, lng), _mapController.camera.zoom);
          } catch (_) {}
        }
      }
      setState(() {
        _latestLocation = latestEntry;
        _isLoading = false;
      });
    }, onError: (e) {
      debugPrint('Stream error for ${widget.deviceCode}: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  bool _isOnline() {
    if (_latestLocation == null) return false;
    final timestamp = _latestLocation!['timestamp'] as int? ?? 0;
    return DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(timestamp))
            .inMinutes <
        5;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        elevation: 4,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final isOnline = _isOnline();
    final latitude = _latestLocation?['latitude'] as double?;
    final longitude = _latestLocation?['longitude'] as double?;
    final accuracy = _latestLocation?['accuracy'];
    final locationType =
        _latestLocation?['locationType'] as String?;
    final altitude = _latestLocation?['altitude'] as double?;
    final speed = _latestLocation?['speed'] as double?;
    String? lastUpdate;
    if (_latestLocation != null) {
      final ts = _latestLocation!['timestamp'] as int? ?? 0;
      lastUpdate = _formatDateTime(
          DateTime.fromMillisecondsSinceEpoch(ts));
    }
    final hasLocation = latitude != null && longitude != null;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor:
                      isOnline ? Colors.green : Colors.grey,
                  child: Icon(
                    isOnline
                        ? Icons.location_on
                        : Icons.location_off,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.childName,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.circle,
                            size: 12,
                            color: isOnline
                                ? Colors.green
                                : Colors.red),
                        const SizedBox(width: 4),
                        Text(isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                                color: isOnline
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        if (isOnline)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius:
                                  BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.green),
                            ),
                            child: const Text('● LIVE',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green,
                                    fontWeight:
                                        FontWeight.bold)),
                          ),
                      ]),
                    ],
                  ),
                ),
                if (locationType != null)
                  _buildLocationTypeBadge(locationType),
              ],
            ),
          ),

          const Divider(height: 24, indent: 16, endIndent: 16),

          // ── Map section ───────────────────────────────────────
          if (hasLocation) ...[
            InkWell(
              onTap: () =>
                  setState(() => _mapExpanded = !_mapExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: Row(children: [
                  const Icon(Icons.map,
                      color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  const Text('Map View',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue)),
                  // ✅ Route count badge
                  if (_routes.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.green, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.route,
                              size: 12, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            '${_routes.length} route${_routes.length > 1 ? 's' : ''}',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _mapExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.blue,
                  ),
                ]),
              ),
            ),
            AnimatedCrossFade(
              firstChild:
                  _buildMap(latitude, longitude, _routes), // ✅
              secondChild: const SizedBox.shrink(),
              crossFadeState: _mapExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 250),
            ),
            const SizedBox(height: 12),
          ],

          // ── Location details ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              if (hasLocation) ...[
                _buildInfoRow(Icons.my_location, 'Latitude',
                    latitude.toStringAsFixed(6)),
                const SizedBox(height: 8),
                _buildInfoRow(Icons.explore, 'Longitude',
                    longitude.toStringAsFixed(6)),
                const SizedBox(height: 8),
              ],
              if (accuracy != null && (accuracy as num) > 0) ...[
                _buildInfoRow(
                    Icons.gps_fixed, 'Accuracy', '${accuracy}m'),
                const SizedBox(height: 8),
              ],
              if (altitude != null && altitude != 0) ...[
                _buildInfoRow(Icons.terrain, 'Altitude',
                    '${altitude.toStringAsFixed(2)}m'),
                const SizedBox(height: 8),
              ],
              if (speed != null && speed != 0) ...[
                _buildInfoRow(Icons.speed, 'Speed',
                    '${speed.toStringAsFixed(2)} m/s'),
                const SizedBox(height: 8),
              ],
              if (lastUpdate != null)
                _buildInfoRow(
                    Icons.access_time, 'Last Update', lastUpdate),
              if (!hasLocation)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location data not available yet. '
                        'Waiting for GPS fix...',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),

          if (hasLocation)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openFullScreenMap(
                      context, latitude, longitude),
                  icon: const Icon(Icons.open_in_full, size: 18),
                  label: const Text('Full Screen Map'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ✅ UPDATED: Embedded map with route polylines + legend
  Widget _buildMap(double latitude, double longitude,
      List<_RouteData> routes) {
    final point = LatLng(latitude, longitude);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 220,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 15,
                  interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.yourapp.safetrack',
                    maxZoom: 19,
                  ),
                  // ✅ Route polylines
                  if (routes.isNotEmpty)
                    PolylineLayer(
                      polylines: routes
                          .map((r) => Polyline(
                                points: r.waypoints,
                                color:
                                    Colors.green.withValues(alpha: 0.8),
                                strokeWidth: 4,
                                pattern:
                                    const StrokePattern.dotted(),
                              ))
                          .toList(),
                    ),
                  // ✅ Route start (🏠) / end (🏫) markers
                  if (routes.isNotEmpty)
                    MarkerLayer(
                      markers: routes
                          .expand((r) => [
                                Marker(
                                  point: r.waypoints.first,
                                  width: 24,
                                  height: 24,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white,
                                          width: 2),
                                    ),
                                    child: const Icon(Icons.home,
                                        color: Colors.white,
                                        size: 12),
                                  ),
                                ),
                                Marker(
                                  point: r.waypoints.last,
                                  width: 24,
                                  height: 24,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white,
                                          width: 2),
                                    ),
                                    child: const Icon(
                                        Icons.school,
                                        color: Colors.white,
                                        size: 12),
                                  ),
                                ),
                              ])
                          .toList(),
                    ),
                  // Child marker
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 48,
                        height: 48,
                        child: Column(children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2))
                              ],
                            ),
                            child: const Icon(Icons.child_care,
                                color: Colors.white, size: 20),
                          ),
                          CustomPaint(
                            size: const Size(10, 6),
                            painter:
                                _TrianglePainter(color: Colors.blue),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
              // ✅ Route legend chips overlay
              if (routes.isNotEmpty)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: routes
                        .map((r) => Container(
                              margin:
                                  const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white
                                    .withValues(alpha: 0.92),
                                borderRadius:
                                    BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.green, width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.route,
                                      size: 12,
                                      color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${r.pathName} ±${r.thresholdMeters.round()}m',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFullScreenMap(
      BuildContext context, double latitude, double longitude) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenMapPage(
          childName: widget.childName,
          latitude: latitude,
          longitude: longitude,
          userId: widget.userId,
          deviceCode: widget.deviceCode,
        ),
      ),
    );
  }

  Widget _buildLocationTypeBadge(String locationType) {
    final color = _getLocationTypeColor(locationType);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_getLocationTypeIcon(locationType),
            size: 14, color: color),
        const SizedBox(width: 4),
        Text(locationType.toUpperCase(),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 11)),
      ]),
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
    return Row(children: [
      Icon(icon, size: 20, color: Colors.blue),
      const SizedBox(width: 8),
      Text('$label: ',
          style: const TextStyle(
              fontWeight: FontWeight.w500, color: Colors.grey)),
      Expanded(
          child: Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold))),
    ]);
  }

  String _formatDateTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${date.day}/${date.month}/${date.year} '
        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// =============================================================
// FULL SCREEN MAP PAGE
// =============================================================
class _FullScreenMapPage extends StatefulWidget {
  final String childName;
  final double latitude;
  final double longitude;
  final String userId;
  final String deviceCode;

  const _FullScreenMapPage({
    required this.childName,
    required this.latitude,
    required this.longitude,
    required this.userId,
    required this.deviceCode,
  });

  @override
  State<_FullScreenMapPage> createState() =>
      _FullScreenMapPageState();
}

class _FullScreenMapPageState extends State<_FullScreenMapPage> {
  late double _latitude;
  late double _longitude;
  StreamSubscription<DatabaseEvent>? _sub;
  final MapController _mapController = MapController();
  String _lastUpdate = '';
  List<_RouteData> _routes = []; // ✅ NEW

  @override
  void initState() {
    super.initState();
    _latitude = widget.latitude;
    _longitude = widget.longitude;
    _subscribeToUpdates();
    _loadDeviceRoutes(); // ✅ NEW
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ✅ NEW
  Future<void> _loadDeviceRoutes() async {
    final routes =
        await _loadRoutes(widget.userId, widget.deviceCode);
    if (mounted) setState(() => _routes = routes);
  }

  void _subscribeToUpdates() {
    _sub = FirebaseDatabase.instance
        .ref('deviceLogs')
        .child(widget.userId)
        .child(widget.deviceCode)
        .onValue
        .listen((event) {
      if (!event.snapshot.exists || !mounted) return;
      final data =
          event.snapshot.value as Map<dynamic, dynamic>;
      int latestTs = 0;
      double? newLat, newLng;
      data.forEach((key, value) {
        if (value is Map && value.containsKey('timestamp')) {
          final ts = value['timestamp'] as int? ?? 0;
          if (ts > latestTs) {
            latestTs = ts;
            newLat = (value['latitude'] as num?)?.toDouble();
            newLng = (value['longitude'] as num?)?.toDouble();
          }
        }
      });
      if (newLat != null && newLng != null) {
        setState(() {
          _latitude = newLat!;
          _longitude = newLng!;
          _lastUpdate = _formatDateTime(
              DateTime.fromMillisecondsSinceEpoch(latestTs));
        });
        _mapController.move(
            LatLng(_latitude, _longitude),
            _mapController.camera.zoom);
      }
    });
  }

  String _formatDateTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(_latitude, _longitude);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.childName),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_lastUpdate.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(children: [
                  const Icon(Icons.circle,
                      color: Colors.greenAccent, size: 10),
                  const SizedBox(width: 4),
                  Text(_lastUpdate,
                      style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: point,
              initialZoom: 16,
              interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.yourapp.safetrack',
                maxZoom: 19,
              ),
              // ✅ Route polylines
              if (_routes.isNotEmpty)
                PolylineLayer(
                  polylines: _routes
                      .map((r) => Polyline(
                            points: r.waypoints,
                            color:
                                Colors.green.withValues(alpha:0.85),
                            strokeWidth: 5,
                            pattern:
                                const StrokePattern.dotted(),
                          ))
                      .toList(),
                ),
              // ✅ Route start / end markers
              if (_routes.isNotEmpty)
                MarkerLayer(
                  markers: _routes
                      .expand((r) => [
                            Marker(
                              point: r.waypoints.first,
                              width: 32,
                              height: 32,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white,
                                      width: 2),
                                ),
                                child: const Icon(Icons.home,
                                    color: Colors.white,
                                    size: 16),
                              ),
                            ),
                            Marker(
                              point: r.waypoints.last,
                              width: 32,
                              height: 32,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white,
                                      width: 2),
                                ),
                                child: const Icon(Icons.school,
                                    color: Colors.white,
                                    size: 16),
                              ),
                            ),
                          ])
                      .toList(),
                ),
              // Child marker
              MarkerLayer(
                markers: [
                  Marker(
                    point: point,
                    width: 56,
                    height: 56,
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white, width: 2.5),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black38,
                                blurRadius: 6,
                                offset: Offset(0, 3))
                          ],
                        ),
                        child: const Icon(Icons.child_care,
                            color: Colors.white, size: 24),
                      ),
                      CustomPaint(
                        size: const Size(12, 7),
                        painter:
                            _TrianglePainter(color: Colors.blue),
                      ),
                    ]),
                  ),
                ],
              ),
            ],
          ),

          // ✅ Bottom card with coordinates + route legend
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      const Icon(Icons.location_pin,
                          color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.childName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            Text(
                              'Lat: ${_latitude.toStringAsFixed(6)}  |  '
                              'Lng: ${_longitude.toStringAsFixed(6)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.my_location,
                            color: Colors.blue),
                        onPressed: () => _mapController.move(
                            LatLng(_latitude, _longitude), 16),
                        tooltip: 'Re-center',
                      ),
                    ]),
                    // ✅ Route legend
                    if (_routes.isNotEmpty) ...[
                      const Divider(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: _routes
                            .map((r) => Row(
                                  mainAxisSize:
                                      MainAxisSize.min,
                                  children: [
                                    Container(
                                        width: 16,
                                        height: 3,
                                        color: Colors.green),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${r.pathName} (±${r.thresholdMeters.round()}m)',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.green,
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// TRIANGLE PAINTER
// =============================================================
class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}