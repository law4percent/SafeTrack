# SafeTrack/server/utils/haversine.py
#
# Direct port of haversine_service.dart
# All math, edge cases, and function signatures are identical.
#
# Functions:
#   distance_between(a, b)          → float (meters)
#   distance_to_segment(p, a, b)    → float (meters)
#   distance_to_path(p, waypoints)  → float (meters)

import math

# ── Constants ─────────────────────────────────────────────────────────────────

EARTH_RADIUS_METERS = 6371000.0


# ── Helpers ───────────────────────────────────────────────────────────────────

def _to_rad(deg: float) -> float:
    """Convert degrees to radians."""
    return deg * math.pi / 180.0


def _to_meters_east(origin: tuple, target: tuple) -> float:
    """
    Approximate eastward distance in meters from origin to target.
    Port of HaversineService._toMetersEast()
    """
    d_lon   = _to_rad(target[1] - origin[1])
    mid_lat = _to_rad((origin[0] + target[0]) / 2)
    return EARTH_RADIUS_METERS * d_lon * math.cos(mid_lat)


def _to_meters_north(origin: tuple, target: tuple) -> float:
    """
    Approximate northward distance in meters from origin to target.
    Port of HaversineService._toMetersNorth()
    """
    d_lat = _to_rad(target[0] - origin[0])
    return EARTH_RADIUS_METERS * d_lat


# ── Public API ────────────────────────────────────────────────────────────────

def distance_between(a: tuple, b: tuple) -> float:
    """
    Haversine distance between two GPS points in meters.
    Port of HaversineService.distanceBetween()

    Args:
        a: (latitude, longitude) in decimal degrees
        b: (latitude, longitude) in decimal degrees

    Returns:
        Distance in meters as float.
    """
    d_lat = _to_rad(b[0] - a[0])
    d_lon = _to_rad(b[1] - a[1])

    sin_d_lat = math.sin(d_lat / 2)
    sin_d_lon = math.sin(d_lon / 2)

    h = (
        sin_d_lat * sin_d_lat
        + math.cos(_to_rad(a[0]))
        * math.cos(_to_rad(b[0]))
        * sin_d_lon
        * sin_d_lon
    )

    return 2 * EARTH_RADIUS_METERS * math.asin(math.sqrt(h))


def distance_to_segment(p: tuple, a: tuple, b: tuple) -> float:
    """
    Minimum distance from point p to the line segment a→b in meters.
    Port of HaversineService.distanceToSegment()

    Uses flat local coordinate system centred on a.
    Valid for short distances (< ~50 km) — sufficient for school routes.

    Projects p onto segment using parameter t ∈ [0, 1]:
      t < 0 → nearest point is a
      t > 1 → nearest point is b
      else  → nearest point is projection on segment

    Args:
        p: (latitude, longitude) point to measure from
        a: (latitude, longitude) segment start
        b: (latitude, longitude) segment end

    Returns:
        Distance in meters as float.
    """
    # Work in flat local coordinates (meters) centred on a
    ax, ay = 0.0, 0.0
    bx = _to_meters_east(a, b)
    by = _to_meters_north(a, b)
    px = _to_meters_east(a, p)
    py = _to_meters_north(a, p)

    dx = bx - ax
    dy = by - ay
    len_sq = dx * dx + dy * dy

    # Segment is a single point
    if len_sq == 0:
        return distance_between(p, a)

    # Projection parameter t, clamped to [0, 1]
    t = ((px - ax) * dx + (py - ay) * dy) / len_sq
    t_clamped = max(0.0, min(1.0, t))

    nearest_x = ax + t_clamped * dx
    nearest_y = ay + t_clamped * dy

    diff_x = px - nearest_x
    diff_y = py - nearest_y
    return math.sqrt(diff_x * diff_x + diff_y * diff_y)


def distance_to_path(p: tuple, waypoints: list) -> float:
    """
    Minimum distance from point p to any segment in the waypoints path.
    Port of HaversineService.distanceToPath()

    Returns 0.0 if fewer than 2 waypoints (no segments to check).

    Args:
        p:          (latitude, longitude) point to measure from
        waypoints:  list of (latitude, longitude) tuples

    Returns:
        Minimum distance in meters as float.
    """
    if len(waypoints) < 2:
        return 0.0

    min_distance = float('inf')
    for i in range(len(waypoints) - 1):
        d = distance_to_segment(p, waypoints[i], waypoints[i + 1])
        if d < min_distance:
            min_distance = d

    return min_distance


# ── Waypoint parser ───────────────────────────────────────────────────────────

def parse_waypoints(raw: dict | list) -> list:
    """
    Parse RTDB waypoints into a list of (lat, lng) tuples.
    Handles both Map format (wp_0, wp_1, ...) and legacy List format.
    Port of PathMonitorService._parseWaypoints()

    Args:
        raw: dict (Map format from RTDB) or list (legacy format)

    Returns:
        List of (latitude, longitude) tuples, sorted by index for Map format.
    """
    wp_maps = []

    if isinstance(raw, dict):
        # Sort by numeric index extracted from key (e.g. 'wp_0', 'wp_1')
        def sort_key(entry):
            key = entry[0]
            index_str = key.replace('wp_', '')
            return int(index_str) if index_str.isdigit() else 0

        sorted_entries = sorted(raw.items(), key=sort_key)
        wp_maps = [v for _, v in sorted_entries if isinstance(v, dict)]

    elif isinstance(raw, list):
        wp_maps = [wp for wp in raw if isinstance(wp, dict)]

    waypoints = []
    for wp in wp_maps:
        lat = wp.get('latitude')
        lng = wp.get('longitude')
        if lat is None or lng is None:
            continue
        try:
            waypoints.append((float(lat), float(lng)))
        except (TypeError, ValueError):
            continue

    return waypoints