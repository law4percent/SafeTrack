// app/SafeTrack/lib/screens/route_registration_screen.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RouteRegistrationScreen extends StatefulWidget {
  final String deviceCode;
  final String childName;

  /// Pass an existing routeId to edit, null to create new
  final String? existingRouteId;

  const RouteRegistrationScreen({
    super.key,
    required this.deviceCode,
    required this.childName,
    this.existingRouteId,
  });

  @override
  State<RouteRegistrationScreen> createState() =>
      _RouteRegistrationScreenState();
}

class _RouteRegistrationScreenState extends State<RouteRegistrationScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _routeNameController = TextEditingController();

  final List<_Waypoint> _waypoints = [];
  double _thresholdMeters = 50;
  bool _isSaving = false;
  bool _isLoadingExisting = false;

  // Default center — Cebu City (adjust to your area)
  static const LatLng _defaultCenter = LatLng(10.3157, 123.8854);

  @override
  void initState() {
    super.initState();
    if (widget.existingRouteId != null) {
      _loadExistingRoute();
    }
  }

  @override
  void dispose() {
    _routeNameController.dispose();
    super.dispose();
  }

  // ── Load existing route for editing ──────────────────────────
  Future<void> _loadExistingRoute() async {
    setState(() => _isLoadingExisting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseDatabase.instance
          .ref('devicePaths')
          .child(user.uid)
          .child(widget.deviceCode)
          .child(widget.existingRouteId!)
          .get();

      if (!snapshot.exists) return;

      final data = snapshot.value as Map<dynamic, dynamic>;
      _routeNameController.text = data['pathName'] ?? '';
      _thresholdMeters =
          (data['deviationThresholdMeters'] as num?)?.toDouble() ?? 50;

      // ✅ Firebase returns sequential int keys as List — handle both
      final rawWaypoints = data['waypoints'];
      List<Map<dynamic, dynamic>> waypointList = [];

      if (rawWaypoints is Map) {
        // Map with wp_0, wp_1... keys — sort numerically
        final sorted = (rawWaypoints as Map<dynamic, dynamic>).entries.toList()
          ..sort((a, b) {
            final aIdx = int.tryParse(
                    a.key.toString().replaceAll('wp_', '')) ??
                0;
            final bIdx = int.tryParse(
                    b.key.toString().replaceAll('wp_', '')) ??
                0;
            return aIdx.compareTo(bIdx);
          });
        waypointList =
            sorted.map((e) => e.value as Map<dynamic, dynamic>).toList();
      } else if (rawWaypoints is List) {
        // Legacy: Firebase converted old sequential int keys to List
        waypointList = rawWaypoints
            .whereType<Map>()
            .map((e) => e as Map<dynamic, dynamic>)
            .toList();
      }

      if (waypointList.isNotEmpty) {
        for (final wp in waypointList) {
          _waypoints.add(_Waypoint(
            point: LatLng(
              (wp['latitude'] as num).toDouble(),
              (wp['longitude'] as num).toDouble(),
            ),
            label: wp['label']?.toString() ?? '',
          ));
        }

        if (_waypoints.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mapController.move(_waypoints.first.point, 15);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading existing route: $e');
    } finally {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  // ── Map tap → add waypoint ────────────────────────────────────
  void _onMapTap(TapPosition tapPos, LatLng point) {
    setState(() {
      _waypoints.add(_Waypoint(point: point, label: ''));
    });
  }

  // ── Remove a waypoint ─────────────────────────────────────────
  void _removeWaypoint(int index) {
    setState(() => _waypoints.removeAt(index));
  }

  // ── Edit waypoint label ───────────────────────────────────────
  Future<void> _editWaypointLabel(int index) async {
    if (index >= _waypoints.length) return;

    // Use a self-contained StatefulWidget for the dialog so the
    // TextEditingController lifecycle is fully owned inside it.
    // This prevents "controller used after disposed" and the
    // _dependents.isEmpty assertion that occur when the controller
    // is created/disposed by the parent and shared across an async gap.
    final result = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => _WaypointLabelDialog(
        initialLabel: _waypoints[index].label,
        waypointNumber: index + 1,
      ),
    );

    if (result != null && mounted && index < _waypoints.length) {
      setState(() => _waypoints[index] = _Waypoint(
            point: _waypoints[index].point,
            label: result.trim(),
          ));
    }
  }

  // ── Save route to Firebase ────────────────────────────────────
  Future<void> _saveRoute() async {
    if (_routeNameController.text.trim().isEmpty) {
      _showSnack('Please enter a route name', Colors.orange);
      return;
    }
    if (_waypoints.length < 2) {
      _showSnack('Please add at least 2 waypoints', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      final routeRef = FirebaseDatabase.instance
          .ref('devicePaths')
          .child(user.uid)
          .child(widget.deviceCode)
          .child(widget.existingRouteId ??
              FirebaseDatabase.instance
                  .ref()
                  .push()
                  .key!); // auto push key for new routes

      // Build waypoints map
      // ✅ Use "wp_0", "wp_1" prefix — prevents Firebase from
      //    auto-converting sequential int keys into a List
      final waypointsMap = <String, dynamic>{};
      for (int i = 0; i < _waypoints.length; i++) {
        waypointsMap['wp_$i'] = {
          'latitude': _waypoints[i].point.latitude,
          'longitude': _waypoints[i].point.longitude,
          'label': _waypoints[i].label,
        };
      }

      await routeRef.set({
        'pathName': _routeNameController.text.trim(),
        'deviationThresholdMeters': _thresholdMeters,
        'isActive': true,
        'createdAt': ServerValue.timestamp,
        'waypoints': waypointsMap,
      });

      if (!mounted) return;
      _showSnack(
        widget.existingRouteId != null
            ? '✅ Route updated successfully'
            : '✅ Route saved successfully',
        Colors.green,
      );
      Navigator.pop(context, true); // return true = saved
    } catch (e) {
      _showSnack('❌ Failed to save route: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ── Threshold slider dialog ───────────────────────────────────
  void _showThresholdDialog() {
    double tempThreshold = _thresholdMeters;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Deviation Threshold'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${tempThreshold.round()} meters',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Alert parent if child moves more than '
                '${tempThreshold.round()}m from route',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              Slider(
                value: tempThreshold,
                min: 20,
                max: 200,
                divisions: 18,
                label: '${tempThreshold.round()}m',
                onChanged: (v) =>
                    setDialogState(() => tempThreshold = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('20m (tight)',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500])),
                  Text('200m (loose)',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _thresholdMeters = tempThreshold);
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingExisting) {
      return Scaffold(
        appBar: AppBar(
          title: Text('${widget.childName}\'s Route'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingRouteId != null
              ? 'Edit Route — ${widget.childName}'
              : 'New Route — ${widget.childName}',
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_waypoints.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear all waypoints',
              onPressed: () => setState(() => _waypoints.clear()),
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Deviation threshold',
            onPressed: _showThresholdDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Route name input ──────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _routeNameController,
              decoration: InputDecoration(
                labelText: 'Route Name',
                hintText: 'e.g. Home to School',
                border: const OutlineInputBorder(),
                prefixIcon:
                    const Icon(Icons.route, color: Colors.blue),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.tune, color: Colors.blue),
                  tooltip:
                      'Threshold: ${_thresholdMeters.round()}m',
                  onPressed: _showThresholdDialog,
                ),
              ),
            ),
          ),

          // ── Info bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 6),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: Colors.blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tap on the map to drop waypoints. '
                    'Long-press a marker to remove it.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.blue[700]),
                  ),
                ),
                Text(
                  '${_waypoints.length} pt${_waypoints.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),

          // ── Map ───────────────────────────────────────────────
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _waypoints.isNotEmpty
                    ? _waypoints.first.point
                    : _defaultCenter,
                initialZoom: 15,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yourapp.safetrack',
                  maxZoom: 19,
                ),

                // Path polyline
                if (_waypoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _waypoints
                            .map((w) => w.point)
                            .toList(),
                        color: Colors.blue,
                        strokeWidth: 4,
                        pattern: const StrokePattern.dotted(),
                      ),
                    ],
                  ),

                // Waypoint markers
                MarkerLayer(
                  markers: List.generate(_waypoints.length, (i) {
                    final wp = _waypoints[i];
                    final isFirst = i == 0;
                    final isLast = i == _waypoints.length - 1;

                    return Marker(
                      point: wp.point,
                      width: 48,
                      height: 64,
                      child: GestureDetector(
                        onLongPress: () => _removeWaypoint(i),
                        onTap: () => _editWaypointLabel(i),
                        child: Column(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isFirst
                                    ? Colors.green
                                    : isLast
                                        ? Colors.red
                                        : Colors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  isFirst
                                      ? 'S'
                                      : isLast
                                          ? 'E'
                                          : '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            CustomPaint(
                              size: const Size(10, 6),
                              painter: _TrianglePainter(
                                color: isFirst
                                    ? Colors.green
                                    : isLast
                                        ? Colors.red
                                        : Colors.blue,
                              ),
                            ),
                            if (wp.label.isNotEmpty)
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(4),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  wp.label,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),

          // ── Waypoint list ─────────────────────────────────────
          if (_waypoints.isNotEmpty)
            Container(
              height: 80,
              color: Colors.grey[50],
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                itemCount: _waypoints.length,
                itemBuilder: (context, i) {
                  final wp = _waypoints[i];
                  final isFirst = i == 0;
                  final isLast = i == _waypoints.length - 1;
                  return GestureDetector(
                    onTap: () {
                      _mapController.move(wp.point, 16);
                      _editWaypointLabel(i);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isFirst
                            ? Colors.green.shade50
                            : isLast
                                ? Colors.red.shade50
                                : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isFirst
                              ? Colors.green
                              : isLast
                                  ? Colors.red
                                  : Colors.blue,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Text(
                            isFirst
                                ? 'START'
                                : isLast
                                    ? 'END'
                                    : 'WP ${i + 1}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isFirst
                                  ? Colors.green
                                  : isLast
                                      ? Colors.red
                                      : Colors.blue,
                            ),
                          ),
                          Text(
                            wp.label.isNotEmpty
                                ? wp.label
                                : '${wp.point.latitude.toStringAsFixed(4)},\n'
                                    '${wp.point.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 9),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // ── Save button ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveRoute,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _isSaving
                      ? 'Saving...'
                      : widget.existingRouteId != null
                          ? 'Update Route'
                          : 'Save Route',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
// ROUTE LIST SCREEN — view/manage all routes for a device
// =============================================================
class RouteListScreen extends StatelessWidget {
  final String deviceCode;
  final String childName;

  const RouteListScreen({
    super.key,
    required this.deviceCode,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return Scaffold(
      appBar: AppBar(
        title: Text('$childName\'s Routes'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance
            .ref('devicePaths')
            .child(user.uid)
            .child(deviceCode)
            .onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData ||
              snapshot.data!.snapshot.value == null) {
            return _buildEmptyState(context);
          }

          final routesData = snapshot.data!.snapshot.value
              as Map<dynamic, dynamic>;

          final routes = routesData.entries.map((e) {
            final data = e.value as Map<dynamic, dynamic>;
            // ✅ Handle both List and Map for waypoints
            final rawWp = data['waypoints'];
            final waypointCount = rawWp is Map
                ? rawWp.length
                : rawWp is List
                    ? rawWp.length
                    : 0;
            return _RouteItem(
              routeId: e.key.toString(),
              pathName: data['pathName']?.toString() ?? 'Unnamed',
              thresholdMeters:
                  (data['deviationThresholdMeters'] as num?)
                          ?.toDouble() ??
                      50,
              isActive: data['isActive'] as bool? ?? true,
              waypointCount: waypointCount,
            );
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...routes.map((route) => _buildRouteCard(
                    context,
                    route,
                    user.uid,
                  )),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RouteRegistrationScreen(
              deviceCode: deviceCode,
              childName: childName,
            ),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add Route'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.route, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 20),
          Text(
            'No Routes Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap "Add Route" to define\n$childName\'s safe travel path',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RouteRegistrationScreen(
                  deviceCode: deviceCode,
                  childName: childName,
                ),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add First Route'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(
    BuildContext context,
    _RouteItem route,
    String userId,
  ) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Active toggle header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: route.isActive
                  ? Colors.green.shade50
                  : Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  route.isActive
                      ? 'Monitoring Active'
                      : 'Monitoring Paused',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: route.isActive
                        ? Colors.green.shade700
                        : Colors.grey.shade600,
                  ),
                ),
                Switch(
                  value: route.isActive,
                  onChanged: (val) => _toggleRouteActive(
                      context, userId, route.routeId, val),
                  activeThumbColor: Colors.green,
                ),
              ],
            ),
          ),

          ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade50,
              child: const Icon(Icons.route, color: Colors.blue),
            ),
            title: Text(
              route.pathName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${route.waypointCount} waypoints  •  '
              '±${route.thresholdMeters.round()}m threshold',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: Colors.blue, size: 20),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RouteRegistrationScreen(
                        deviceCode: deviceCode,
                        childName: childName,
                        existingRouteId: route.routeId,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  onPressed: () => _deleteRoute(
                      context, userId, route.routeId, route.pathName),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRouteActive(
    BuildContext context,
    String userId,
    String routeId,
    bool value,
  ) async {
    try {
      await FirebaseDatabase.instance
          .ref('devicePaths')
          .child(userId)
          .child(deviceCode)
          .child(routeId)
          .update({'isActive': value});
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  Future<void> _deleteRoute(
    BuildContext context,
    String userId,
    String routeId,
    String routeName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Route?'),
        content: Text(
            'Are you sure you want to delete "$routeName"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseDatabase.instance
          .ref('devicePaths')
          .child(userId)
          .child(deviceCode)
          .child(routeId)
          .remove();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Route deleted'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }
}

// =============================================================
// DATA MODELS
// =============================================================
// =============================================================
// WAYPOINT LABEL DIALOG
// Self-contained StatefulWidget so the TextEditingController
// is created and disposed entirely within its own lifecycle.
// This avoids "controller used after disposed" and the
// _dependents.isEmpty assertion triggered by sharing a controller
// across an async gap between the parent and dialog context.
// =============================================================
class _WaypointLabelDialog extends StatefulWidget {
  final String initialLabel;
  final int waypointNumber;

  const _WaypointLabelDialog({
    required this.initialLabel,
    required this.waypointNumber,
  });

  @override
  State<_WaypointLabelDialog> createState() =>
      _WaypointLabelDialogState();
}

class _WaypointLabelDialogState extends State<_WaypointLabelDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLabel);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Label for Waypoint ${widget.waypointNumber}'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          hintText: 'e.g. Home, School, Gate...',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _Waypoint {
  final LatLng point;
  final String label;
  const _Waypoint({required this.point, required this.label});
}

class _RouteItem {
  final String routeId;
  final String pathName;
  final double thresholdMeters;
  final bool isActive;
  final int waypointCount;

  const _RouteItem({
    required this.routeId,
    required this.pathName,
    required this.thresholdMeters,
    required this.isActive,
    required this.waypointCount,
  });
}

// =============================================================
// TRIANGLE PAINTER (marker pointer)
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
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}