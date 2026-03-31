// app/SafeTrack/lib/screens/activity_plot_screen.dart
//
// Plotting feature — renders a child's GPS history on a FlutterMap.
// Accessible as Tab 2 inside ActivityLogScreen.
//
// Features:
//   • Date/time range picker → filtered GPS point trail
//   • Blue-grey solid polyline connecting actual GPS points (chronological)
//   • Green dashed polyline overlay for the selected registered route
//   • Route start 🏠 / end 🏫 markers from registered route
//   • Blue→red time-gradient markers per actual GPS point
//   • Eye icon badge on every marker — tap to open detail bottom sheet
//   • Warning badge (⚠️) on markers that exceed the route's deviation threshold
//   • Route dropdown selector (active routes only, single-device view)
//   • Fit-to-bounds FAB + map legend
//
// Dependencies (already in pubspec):
//   flutter_map, latlong2, intl, firebase_database, firebase_auth
//   ../services/haversine_service.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/haversine_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// INTERNAL DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// ROUTE LOADER  (mirrors _loadRoutes in live_location_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────

List<LatLng> _parseWaypoints(dynamic raw) {
  final List<Map<dynamic, dynamic>> wpMaps = [];
  if (raw is Map) {
    final sorted = (raw as Map<dynamic, dynamic>).entries.toList()
      ..sort((a, b) {
        final ai = int.tryParse(a.key.toString().replaceAll('wp_', '')) ?? 0;
        final bi = int.tryParse(b.key.toString().replaceAll('wp_', '')) ?? 0;
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

Future<List<_RouteData>> _loadRoutes(String userId, String deviceCode) async {
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
    debugPrint('[ActivityPlot] Error loading routes: $e');
    return [];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

/// Drop this widget into Tab 2 of ActivityLogScreen.
/// Receives the already-loaded [activities] list — no extra Firebase reads
/// for the GPS trail. Routes are fetched independently from devicePaths.
class ActivityPlotTab extends StatefulWidget {
  final List<Map<String, dynamic>> activities;
  final String? childName;
  final String? deviceCode; // null → multi-device view, route overlay disabled

  const ActivityPlotTab({
    super.key,
    required this.activities,
    this.childName,
    this.deviceCode,
  });

  @override
  State<ActivityPlotTab> createState() => _ActivityPlotTabState();
}

// ─────────────────────────────────────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────────────────────────────────────

class _ActivityPlotTabState extends State<ActivityPlotTab> {
  // Date range — defaults to today 00:00 → now
  DateTime _fromDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime _toDate = DateTime.now();

  List<Map<String, dynamic>> _plotPoints = [];
  bool _rangeSelected = false;

  // Registered routes
  List<_RouteData> _routes = [];
  _RouteData? _selectedRoute;
  bool _routesLoading = false;

  final MapController _mapController = MapController();

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _applyFilter();
    if (widget.deviceCode != null) _fetchRoutes();
  }

  @override
  void didUpdateWidget(ActivityPlotTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activities != widget.activities) _applyFilter();
    if (oldWidget.deviceCode != widget.deviceCode &&
        widget.deviceCode != null) {
      _fetchRoutes();
    }
  }

  // ── Route fetching ─────────────────────────────────────────────────────────

  Future<void> _fetchRoutes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.deviceCode == null) return;

    setState(() => _routesLoading = true);
    final routes = await _loadRoutes(user.uid, widget.deviceCode!);
    if (!mounted) return;
    setState(() {
      _routes = routes;
      // Auto-select if only one route exists
      _selectedRoute = routes.length == 1 ? routes.first : null;
      _routesLoading = false;
    });
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  void _applyFilter() {
    final fromMs = _fromDate.millisecondsSinceEpoch;
    final toMs   = _toDate.millisecondsSinceEpoch;

    final filtered = widget.activities.where((a) {
      final ts  = a['lastUpdate'] as int;
      final loc = a['location']  as Map<String, dynamic>?;
      return ts >= fromMs && ts <= toMs && loc != null;
    }).toList();

    // Sort oldest → newest so the trail flows chronologically
    filtered.sort(
        (a, b) => (a['lastUpdate'] as int).compareTo(b['lastUpdate'] as int));

    setState(() {
      _plotPoints    = filtered;
      _rangeSelected = true;
    });

    if (filtered.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    }
  }

  // ── Distance helpers ───────────────────────────────────────────────────────

  double? _distanceToRoute(LatLng point, _RouteData? route) {
    if (route == null || route.waypoints.length < 2) return null;
    return HaversineService.distanceToPath(point, route.waypoints);
  }

  bool _isDeviation(double? distanceMeters, _RouteData? route) {
    if (distanceMeters == null || route == null) return false;
    return distanceMeters > route.thresholdMeters;
  }

  // ── Date/time range dialog ─────────────────────────────────────────────────

  Future<void> _showRangeDialog() async {
    DateTime tmpFrom = _fromDate;
    DateTime tmpTo   = _toDate;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Select Date & Time Range'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Only points with coordinates in this range will be plotted.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _dateTimeTile(
                ctx: ctx,
                icon: Icons.calendar_today,
                iconColor: Colors.blue[800]!,
                label: 'From',
                value: tmpFrom,
                firstDate: DateTime(2025),
                lastDate: DateTime.now(),
                onPicked: (dt) => setS(() => tmpFrom = dt),
              ),
              _dateTimeTile(
                ctx: ctx,
                icon: Icons.calendar_today,
                iconColor: Colors.green,
                label: 'To',
                value: tmpTo,
                firstDate: DateTime(2025),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                onPicked: (dt) => setS(() => tmpTo = dt),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.map),
              label: const Text('Plot'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      setState(() {
        _fromDate = tmpFrom;
        _toDate   = tmpTo;
      });
      _applyFilter();
    }
  }

  Widget _dateTimeTile({
    required BuildContext ctx,
    required IconData icon,
    required Color iconColor,
    required String label,
    required DateTime value,
    required DateTime firstDate,
    required DateTime lastDate,
    required ValueChanged<DateTime> onPicked,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(label),
      subtitle: Text(DateFormat('MMM dd, yyyy  h:mm a').format(value)),
      onTap: () async {
        final d = await showDatePicker(
          context: ctx,
          initialDate: value,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (d == null) return;
        final t = await showTimePicker(
          context: ctx,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        if (t == null) return;
        onPicked(DateTime(d.year, d.month, d.day, t.hour, t.minute));
      },
    );
  }

  // ── Camera helpers ─────────────────────────────────────────────────────────

  void _fitBounds() {
    final allPoints = <LatLng>[
      ..._plotPoints.map((p) {
        final loc = p['location'] as Map<String, dynamic>;
        return LatLng(loc['latitude'] as double, loc['longitude'] as double);
      }),
      if (_selectedRoute != null) ..._selectedRoute!.waypoints,
    ];

    if (allPoints.isEmpty) return;

    final lats = allPoints.map((p) => p.latitude).toList();
    final lngs = allPoints.map((p) => p.longitude).toList();

    final sw = LatLng(lats.reduce(math.min) - 0.001, lngs.reduce(math.min) - 0.001);
    final ne = LatLng(lats.reduce(math.max) + 0.001, lngs.reduce(math.max) + 0.001);

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(sw, ne),
          padding: const EdgeInsets.all(48),
        ),
      );
    } catch (_) {}
  }

  // ── Color gradient (blue → red by time) ───────────────────────────────────

  Color _pointColor(int index, int total) {
    if (total <= 1) return Colors.blue;
    final t = index / (total - 1);
    return Color.lerp(Colors.blue, Colors.red, t)!;
  }

  // ── Marker tap ─────────────────────────────────────────────────────────────

  void _onMarkerTap(Map<String, dynamic> point, Color color, int index) {
    final loc      = point['location'] as Map<String, dynamic>;
    final lat      = loc['latitude']   as double;
    final lng      = loc['longitude']  as double;
    final ts       = point['lastUpdate'] as int;
    final isCached = point['isCached']   as bool? ?? false;
    final locType  = point['locationType'] as String? ?? 'unknown';
    final battery  = (point['batteryLevel'] as num?)?.toDouble() ?? 0.0;

    final distMeters = _distanceToRoute(LatLng(lat, lng), _selectedRoute);
    final deviation  = _isDeviation(distMeters, _selectedRoute);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => _MarkerDetailSheet(
        dateTime:        DateTime.fromMillisecondsSinceEpoch(ts),
        latitude:        lat,
        longitude:       lng,
        battery:         battery,
        locationType:    locType,
        isCached:        isCached,
        markerColor:     color,
        distanceMeters:  distMeters,
        isDeviation:     deviation,
        thresholdMeters: _selectedRoute?.thresholdMeters,
        routeName:       _selectedRoute?.pathName,
        pointIndex:      index + 1,
        totalPoints:     _plotPoints.length,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildTopBar(),
      Expanded(child: _buildBody()),
    ]);
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: date range + point count chip + Range button
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMM dd, yyyy  h:mm a').format(_fromDate),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  Row(children: [
                    const Icon(Icons.arrow_downward, size: 11, color: Colors.grey),
                    const SizedBox(width: 2),
                    Text(
                      DateFormat('MMM dd, yyyy  h:mm a').format(_toDate),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ],
              ),
            ),
            if (_plotPoints.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue[300]!),
                ),
                child: Text(
                  '${_plotPoints.length} pt${_plotPoints.length != 1 ? 's' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue[800],
                      fontWeight: FontWeight.bold),
                ),
              ),
            ElevatedButton.icon(
              onPressed: _showRangeDialog,
              icon: const Icon(Icons.tune, size: 15),
              label: const Text('Range', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]),

          // Row 2: route dropdown (single-device view only)
          if (widget.deviceCode != null) ...[
            const SizedBox(height: 8),
            _buildRouteDropdown(),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteDropdown() {
    if (_routesLoading) {
      return const Row(children: [
        SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 8),
        Text('Loading routes…', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ]);
    }

    if (_routes.isEmpty) {
      return Row(children: [
        Icon(Icons.route, size: 14, color: Colors.grey[400]),
        const SizedBox(width: 6),
        Text('No registered routes for this device',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ]);
    }

    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('— No route overlay —',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ),
      ..._routes.map((r) => DropdownMenuItem<String?>(
            value: r.routeId,
            child: Row(children: [
              const Icon(Icons.route, size: 14, color: Colors.green),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${r.pathName}  ±${r.thresholdMeters.round()}m',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          )),
    ];

    return Row(children: [
      const Icon(Icons.route, size: 15, color: Colors.green),
      const SizedBox(width: 6),
      const Text('Route:',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green)),
      const SizedBox(width: 8),
      Expanded(
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: _selectedRoute?.routeId,
            isDense: true,
            isExpanded: true,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            items: items,
            onChanged: (value) {
              setState(() {
                _selectedRoute = value == null
                    ? null
                    : _routes.firstWhere((r) => r.routeId == value);
              });
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _fitBounds());
            },
          ),
        ),
      ),
    ]);
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (!_rangeSelected) return const Center(child: CircularProgressIndicator());
    if (_plotPoints.isEmpty) return _buildEmptyState();
    return Stack(children: [
      _buildMap(),
      _buildLegend(),
      _buildFitButton(),
    ]);
  }

  Widget _buildEmptyState() {
    final hasAnyInRange = widget.activities.any((a) {
      final ts = a['lastUpdate'] as int;
      return ts >= _fromDate.millisecondsSinceEpoch &&
          ts <= _toDate.millisecondsSinceEpoch;
    });

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 72, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              hasAnyInRange
                  ? 'No GPS coordinates in this range'
                  : 'No activity in this range',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasAnyInRange
                  ? 'Log entries exist but none have location coordinates.\nTry a different range.'
                  : 'No log entries found between the selected dates.',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _showRangeDialog,
              icon: const Icon(Icons.tune),
              label: const Text('Change Range'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Map ────────────────────────────────────────────────────────────────────

  Widget _buildMap() {
    final total = _plotPoints.length;

    // Actual GPS trail polyline
    final trailPoints = _plotPoints.map((p) {
      final loc = p['location'] as Map<String, dynamic>;
      return LatLng(loc['latitude'] as double, loc['longitude'] as double);
    }).toList();

    // GPS point markers
    final gpsMarkers = <Marker>[];
    for (int i = 0; i < total; i++) {
      final p        = _plotPoints[i];
      final loc      = p['location'] as Map<String, dynamic>;
      final pt       = LatLng(loc['latitude'] as double, loc['longitude'] as double);
      final color    = _pointColor(i, total);
      final isCached = p['isCached'] as bool? ?? false;
      final isFirst  = i == 0;
      final isLast   = i == total - 1;

      final distMeters = _distanceToRoute(pt, _selectedRoute);
      final deviation  = _isDeviation(distMeters, _selectedRoute) &&
          !isFirst && !isLast; // exempt start/end

      gpsMarkers.add(Marker(
        point:  pt,
        width:  isFirst || isLast ? 44 : 30,
        height: isFirst || isLast ? 44 : 30,
        child: GestureDetector(
          onTap: () => _onMarkerTap(p, color, i),
          child: _buildMarkerWidget(
            color:    color,
            isCached: isCached,
            isFirst:  isFirst,
            isLast:   isLast,
            deviation: deviation,
          ),
        ),
      ));
    }

    // Registered route endpoint markers
    final routeEndMarkers = <Marker>[];
    if (_selectedRoute != null) {
      final wps = _selectedRoute!.waypoints;
      routeEndMarkers.addAll([
        Marker(
          point: wps.first,
          width: 28, height: 28,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: const Icon(Icons.home, color: Colors.white, size: 14),
          ),
        ),
        Marker(
          point: wps.last,
          width: 28, height: 28,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.teal,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: const Icon(Icons.school, color: Colors.white, size: 14),
          ),
        ),
      ]);
    }

    // Camera initial center = midpoint of first and last actual point
    final firstLoc = _plotPoints.first['location'] as Map<String, dynamic>;
    final lastLoc  = _plotPoints.last['location']  as Map<String, dynamic>;
    final centerLat =
        ((firstLoc['latitude'] as double) + (lastLoc['latitude'] as double)) / 2;
    final centerLng =
        ((firstLoc['longitude'] as double) + (lastLoc['longitude'] as double)) / 2;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(centerLat, centerLng),
        initialZoom: 14,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        // Base tiles
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.yourapp.safetrack',
          maxZoom: 19,
        ),

        // Registered route — green dashed polyline
        if (_selectedRoute != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points:      _selectedRoute!.waypoints,
                color:       Colors.green.withValues(alpha: 0.85),
                strokeWidth: 3.5,
                pattern:     const StrokePattern.dotted(),
              ),
            ],
          ),

        // Actual GPS trail — blue-grey solid polyline
        PolylineLayer(
          polylines: [
            Polyline(
              points:      trailPoints,
              color:       Colors.blueGrey.withValues(alpha: 0.75),
              strokeWidth: 3,
            ),
          ],
        ),

        // Registered route start / end markers
        if (routeEndMarkers.isNotEmpty)
          MarkerLayer(markers: routeEndMarkers),

        // GPS point markers (rendered last = on top)
        MarkerLayer(markers: gpsMarkers),
      ],
    );
  }

  // ── Individual marker widget ───────────────────────────────────────────────

  Widget _buildMarkerWidget({
    required Color color,
    required bool isCached,
    required bool isFirst,
    required bool isLast,
    required bool deviation,
  }) {
    // ── Start marker (home icon, blue) ─────────────────────────
    if (isFirst) {
      return Stack(clipBehavior: Clip.none, children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(Icons.home, color: Colors.white, size: 22),
        ),
        Positioned(right: -2, bottom: -2, child: _eyeBadge()),
      ]);
    }

    // ── End marker (flag icon, red) ────────────────────────────
    if (isLast) {
      return Stack(clipBehavior: Clip.none, children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(Icons.flag, color: Colors.white, size: 22),
        ),
        Positioned(right: -2, bottom: -2, child: _eyeBadge()),
      ]);
    }

    // ── Mid-point: cached (hollow) or live GPS (solid) ─────────
    final Widget dot = isCached
        ? Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border:
                  Border.all(color: color.withValues(alpha: 0.8), width: 2.5),
            ),
            child: Center(
              child: Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          )
        : Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                )
              ],
            ),
          );

    return Stack(clipBehavior: Clip.none, children: [
      dot,
      // Eye badge — bottom-right
      Positioned(right: -3, bottom: -3, child: _eyeBadge()),
      // Warning badge — top-right (only when deviating from registered route)
      if (deviation)
        Positioned(right: -3, top: -3, child: _warningBadge()),
    ]);
  }

  Widget _eyeBadge() => Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.6), width: 0.5),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
        ),
        child: const Icon(Icons.remove_red_eye, size: 8, color: Colors.blueGrey),
      );

  Widget _warningBadge() => Container(
        width: 14, height: 14,
        decoration: BoxDecoration(
          color: Colors.orange,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 0.5),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
        ),
        child: const Icon(Icons.warning_amber_rounded, size: 9, color: Colors.white),
      );

  // ── Map overlays ───────────────────────────────────────────────────────────

  Widget _buildLegend() {
    return Positioned(
      top: 12, left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Time gradient bar
            Row(children: [
              _gradientBar(),
              const SizedBox(width: 6),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Early', style: TextStyle(fontSize: 9, color: Colors.blue)),
                  SizedBox(height: 10),
                  Text('Late',  style: TextStyle(fontSize: 9, color: Colors.red)),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            _legendRow(
              child: Container(
                width: 12, height: 12,
                decoration: const BoxDecoration(
                    color: Colors.purple, shape: BoxShape.circle),
              ),
              label: 'GPS point',
            ),
            const SizedBox(height: 4),
            _legendRow(
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.purple, width: 2),
                ),
              ),
              label: 'Cached',
            ),
            const SizedBox(height: 4),
            _legendRow(
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.2),
                    shape: BoxShape.circle),
                child: const Icon(Icons.home, size: 8, color: Colors.blue),
              ),
              label: 'Start',
            ),
            const SizedBox(height: 4),
            _legendRow(
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    shape: BoxShape.circle),
                child: const Icon(Icons.flag, size: 8, color: Colors.red),
              ),
              label: 'End',
            ),
            if (_selectedRoute != null) ...[
              const SizedBox(height: 4),
              _legendRow(
                child: SizedBox(
                  width: 20, height: 3,
                  child: CustomPaint(
                      painter: _DashedLinePainter(Colors.green)),
                ),
                label: 'Reg. route',
              ),
              const SizedBox(height: 4),
              _legendRow(
                child: Container(
                  width: 12, height: 12,
                  decoration: const BoxDecoration(
                      color: Colors.green, shape: BoxShape.circle),
                  child: const Icon(Icons.home, size: 7, color: Colors.white),
                ),
                label: 'Route start',
              ),
              const SizedBox(height: 4),
              _legendRow(
                child: Container(
                  width: 12, height: 12,
                  decoration: const BoxDecoration(
                      color: Colors.teal, shape: BoxShape.circle),
                  child: const Icon(Icons.school, size: 7, color: Colors.white),
                ),
                label: 'Route end',
              ),
              const SizedBox(height: 4),
              _legendRow(
                child: Container(
                  width: 12, height: 12,
                  decoration: const BoxDecoration(
                      color: Colors.orange, shape: BoxShape.circle),
                  child: const Icon(Icons.warning_amber_rounded,
                      size: 8, color: Colors.white),
                ),
                label: 'Off route',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendRow({required Widget child, required String label}) =>
      Row(children: [
        child,
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10)),
      ]);

  Widget _gradientBar() => Container(
        width: 10, height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue, Colors.red],
          ),
        ),
      );

  Widget _buildFitButton() => Positioned(
        bottom: 24, right: 16,
        child: FloatingActionButton.small(
          heroTag: 'plotFitBounds',
          backgroundColor: Colors.white,
          foregroundColor: Colors.blue[800],
          tooltip: 'Fit all points',
          onPressed: _fitBounds,
          child: const Icon(Icons.fit_screen),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MARKER DETAIL BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _MarkerDetailSheet extends StatelessWidget {
  final DateTime  dateTime;
  final double    latitude;
  final double    longitude;
  final double    battery;
  final String    locationType;
  final bool      isCached;
  final Color     markerColor;
  final double?   distanceMeters;
  final bool      isDeviation;
  final double?   thresholdMeters;
  final String?   routeName;
  final int       pointIndex;
  final int       totalPoints;

  const _MarkerDetailSheet({
    required this.dateTime,
    required this.latitude,
    required this.longitude,
    required this.battery,
    required this.locationType,
    required this.isCached,
    required this.markerColor,
    required this.distanceMeters,
    required this.isDeviation,
    required this.thresholdMeters,
    required this.routeName,
    required this.pointIndex,
    required this.totalPoints,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Handle ────────────────────────────────────────────
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Title row ─────────────────────────────────────────
            Row(children: [
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Point $pointIndex of $totalPoints',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (isDeviation)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 13),
                      SizedBox(width: 4),
                      Text('Off Route',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ]),

            const Divider(height: 20),

            // ── Detail fields ─────────────────────────────────────
            _detailRow(
              icon: Icons.access_time,
              color: Colors.blue[700]!,
              label: 'Date & Time',
              value: DateFormat('MMM dd, yyyy  •  h:mm:ss a').format(dateTime),
            ),
            _detailRow(
              icon: Icons.place,
              color: Colors.red,
              label: 'Coordinates',
              value:
                  '${latitude.toStringAsFixed(6)},  ${longitude.toStringAsFixed(6)}',
            ),
            _detailRow(
              icon: isCached ? Icons.cached : Icons.satellite_alt,
              color: isCached ? Colors.orange : Colors.green,
              label: 'Location Type',
              value:
                  '${locationType.toUpperCase()}${isCached ? '  (no live fix)' : ''}',
            ),
            _detailRow(
              icon: _batteryIcon(battery),
              color: _batteryColor(battery),
              label: 'Battery',
              value:
                  battery > 0 ? '${battery.toStringAsFixed(0)}%' : 'Unknown',
            ),
            _buildDistanceRow(),

            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Distance row (rich layout) ─────────────────────────────────────────────

  Widget _buildDistanceRow() {
    if (distanceMeters == null) {
      return _detailRow(
        icon: Icons.route,
        color: Colors.grey,
        label: 'Dist. from Route',
        value: 'No route selected',
      );
    }

    final dist   = distanceMeters!;
    final thresh = thresholdMeters ?? 50;
    final rName  = routeName ?? 'Route';
    final within = dist <= thresh;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.social_distance,
              size: 18, color: within ? Colors.green : Colors.orange),
          const SizedBox(width: 10),
          const SizedBox(
            width: 110,
            child: Text('Dist. from Route',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black87)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${dist.toStringAsFixed(0)} m  •  "$rName"',
                  style: TextStyle(
                    fontSize: 13,
                    color: within ? Colors.black54 : Colors.orange[800],
                    fontWeight:
                        within ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(
                    within ? Icons.check_circle_outline : Icons.warning_amber,
                    size: 13,
                    color: within ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      within
                          ? 'Within ±${thresh.round()} m threshold'
                          : '${(dist - thresh).toStringAsFixed(0)} m outside threshold',
                      style: TextStyle(
                        fontSize: 11,
                        color: within ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Generic detail row ─────────────────────────────────────────────────────

  Widget _detailRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black87)),
          ),
          Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 13, color: Colors.black54)),
          ),
        ],
      ),
    );
  }

  IconData _batteryIcon(double level) {
    if (level > 80) return Icons.battery_full;
    if (level > 50) return Icons.battery_std;
    if (level > 20) return Icons.battery_charging_full;
    return Icons.battery_alert;
  }

  Color _batteryColor(double level) {
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHED LINE PAINTER  (used in the legend only)
// ─────────────────────────────────────────────────────────────────────────────

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dashW = 4.0;
    const gapW  = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + dashW, size.width), size.height / 2),
        paint,
      );
      x += dashW + gapW;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}