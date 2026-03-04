// app/SafeTrack/lib/services/haversine_service.dart
import 'dart:math';
import 'package:latlong2/latlong.dart';

class HaversineService {
  static const double _earthRadiusMeters = 6371000.0;

  // ── Degrees to radians ────────────────────────────────────────
  static double _toRad(double deg) => deg * pi / 180.0;

  /// Haversine distance between two GPS points in meters.
  static double distanceBetween(LatLng a, LatLng b) {
    final dLat = _toRad(b.latitude - a.latitude);
    final dLon = _toRad(b.longitude - a.longitude);

    final sinDLat = sin(dLat / 2);
    final sinDLon = sin(dLon / 2);

    final h = sinDLat * sinDLat +
        cos(_toRad(a.latitude)) *
            cos(_toRad(b.latitude)) *
            sinDLon *
            sinDLon;

    return 2 * _earthRadiusMeters * asin(sqrt(h));
  }

  /// Minimum distance from point [p] to the line segment [a]→[b] in meters.
  ///
  /// Projects [p] onto the segment using a parameter t ∈ [0, 1].
  /// If t < 0 → nearest point is [a].
  /// If t > 1 → nearest point is [b].
  /// Otherwise  → nearest point is the projection on the segment.
  static double distanceToSegment(LatLng p, LatLng a, LatLng b) {
    // Work in a flat local coordinate system (meters) centred on [a].
    // Valid for short distances (< ~50 km) — more than enough for school routes.
    final ax = 0.0;
    final ay = 0.0;
    final bx = _toMetersEast(a, b);
    final by = _toMetersNorth(a, b);
    final px = _toMetersEast(a, p);
    final py = _toMetersNorth(a, p);

    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;

    if (lenSq == 0) {
      // Segment is a single point
      return distanceBetween(p, a);
    }

    // Projection parameter t
    final t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
    final tClamped = t.clamp(0.0, 1.0);

    final nearestX = ax + tClamped * dx;
    final nearestY = ay + tClamped * dy;

    final diffX = px - nearestX;
    final diffY = py - nearestY;
    return sqrt(diffX * diffX + diffY * diffY);
  }

  /// Minimum distance from point [p] to any segment in the [waypoints] path.
  ///
  /// Returns 0 if fewer than 2 waypoints (no segments to check).
  static double distanceToPath(LatLng p, List<LatLng> waypoints) {
    if (waypoints.length < 2) return 0;

    double minDistance = double.infinity;
    for (int i = 0; i < waypoints.length - 1; i++) {
      final d = distanceToSegment(p, waypoints[i], waypoints[i + 1]);
      if (d < minDistance) minDistance = d;
    }
    return minDistance;
  }

  // ── Local flat projection helpers ─────────────────────────────

  /// Approximate eastward distance in meters from [origin] to [target].
  static double _toMetersEast(LatLng origin, LatLng target) {
    final dLon = _toRad(target.longitude - origin.longitude);
    return _earthRadiusMeters *
        dLon *
        cos(_toRad((origin.latitude + target.latitude) / 2));
  }

  /// Approximate northward distance in meters from [origin] to [target].
  static double _toMetersNorth(LatLng origin, LatLng target) {
    final dLat = _toRad(target.latitude - origin.latitude);
    return _earthRadiusMeters * dLat;
  }
}