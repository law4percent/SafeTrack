import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../auth_service.dart';
import 'dart:async';
import 'my_children_screen.dart';
// ======================================================
// 🚨 RTDB SETUP
// ======================================================
const String firebaseRtdbUrl = 'https://protectid-f04a3-default-rtdb.asia-southeast1.firebasedatabase.app';

final FirebaseDatabase rtdbInstance = FirebaseDatabase.instanceFor(
  app: Firebase.app(),
  databaseURL: firebaseRtdbUrl,
);
// ======================================================

// ✅ TRACKINGDEVICE CLASS
class TrackingDevice {
  final String deviceCode;
  final String nickname;
  final String? name;

  TrackingDevice({
    required this.deviceCode,
    required this.nickname,
    this.name,
  });

  @override
  String toString() => nickname;
}

// Location Type for School and Home
enum LocationType { school, home }

class SavedLocation {
  final String id;
  final String name;
  final LocationType type;
  final double latitude;
  final double longitude;
  final DateTime createdAt;

  SavedLocation({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.toString(),
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory SavedLocation.fromMap(Map<String, dynamic> map) {
    return SavedLocation(
      id: map['id'],
      name: map['name'],
      type: map['type'] == 'LocationType.school' ? LocationType.school : LocationType.home,
      latitude: map['latitude'],
      longitude: map['longitude'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
    );
  }
}

class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  final FirebaseDatabase _rtdb = rtdbInstance;
  late MapController _mapController;
  final List<LatLng> _locationHistory = [];
  final List<LatLng> _myLocationHistory = [];
  bool _isTracking = true;
  bool _isMapReady = false;
  bool _isLoading = true;
  bool _showMyLocation = true;
  Map<String, dynamic>? _lastData;
  StreamSubscription<DatabaseEvent>? _streamSubscription;
  StreamSubscription<Position>? _locationSubscription;
  
  // Device selection
  TrackingDevice? _selectedDevice;
  List<TrackingDevice> _availableDevices = [];
  bool _showDeviceSelector = false;

  // My Location
  LatLng? _myCurrentLocation;
  double? _myLocationAccuracy;
  DateTime? _lastLocationUpdate;

  // Saved Locations
  List<SavedLocation> _savedLocations = [];
  bool _isSelectingLocation = false;
  LatLng? _selectedLocation;

  // Auto-detection
  String _currentLocationStatus = '';
  final double _schoolHomeRadius = 100.0; // meters

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadUserDevices();
    
    // Delay location permission request
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestLocationPermission();
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }

  // Load saved locations from CHILD DEVICE
  void _loadSavedLocations() async {
    if (_selectedDevice == null) return;

    try {
      final locationsRef = _rtdb.ref('children/${_selectedDevice!.deviceCode}/savedLocations');
      final snapshot = await locationsRef.get();
      
      if (snapshot.exists) {
        final data = snapshot.value as Map?;
        final locations = <SavedLocation>[];
        
        if (data != null) {
          data.forEach((key, value) {
            final locationData = Map<String, dynamic>.from(value as Map);
            locations.add(SavedLocation.fromMap(locationData));
          });
        }
        
        setState(() {
          _savedLocations = locations;
        });
      } else {
        setState(() {
          _savedLocations = [];
        });
      }
    } catch (e) {
      debugPrint('❌ LOAD SAVED LOCATIONS ERROR: $e');
    }
  }

  // Save location to CHILD DEVICE
  void _saveLocation(String name, LocationType type, double lat, double lng) async {
    if (_selectedDevice == null) return;

    try {
      final locationId = DateTime.now().millisecondsSinceEpoch.toString();
      final newLocation = SavedLocation(
        id: locationId,
        name: name,
        type: type,
        latitude: lat,
        longitude: lng,
        createdAt: DateTime.now(),
      );

      final locationsRef = _rtdb.ref('children/${_selectedDevice!.deviceCode}/savedLocations/$locationId');
      await locationsRef.set(newLocation.toMap());

      if (mounted) {
        setState(() {
          _savedLocations.add(newLocation);
          _isSelectingLocation = false;
          _selectedLocation = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name location saved for ${_selectedDevice!.nickname}!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ SAVE LOCATION ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Delete saved location FROM CHILD DEVICE
  void _deleteLocation(String locationId) async {
    if (_selectedDevice == null) return;

    try {
      final locationRef = _rtdb.ref('children/${_selectedDevice!.deviceCode}/savedLocations/$locationId');
      await locationRef.remove();

      if (mounted) {
        setState(() {
          _savedLocations.removeWhere((location) => location.id == locationId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ DELETE LOCATION ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ SIMPLIFIED: CHILD PROXIMITY CHECK (WALANG ARRIVAL HISTORY SAVING)
  void _checkChildProximityOnly(Map<String, dynamic> childData) {
    // Clear status first
    setState(() {
      _currentLocationStatus = '';
    });
    
    final childLat = _getLatitude(childData);
    final childLng = _getLongitude(childData);
    
    if (childLat == null || childLng == null) {
      return;
    }
    
    final childLocation = LatLng(childLat, childLng);
    final childName = _selectedDevice?.nickname ?? 'Your child';
    final now = DateTime.now();
    
    // Check against CHILD'S saved locations only
    for (final savedLocation in _savedLocations) {
      final locationPoint = LatLng(savedLocation.latitude, savedLocation.longitude);
      final distance = _calculateDistance(childLocation, locationPoint);
      
      if (distance <= _schoolHomeRadius) {
        final locationType = savedLocation.type == LocationType.school ? 'SCHOOL' : 'HOME';
        final currentTime = DateFormat('h:mm a').format(now);
        
        final status = savedLocation.type == LocationType.school 
            ? '🏫 NASA SCHOOL NA! • Arrived: $currentTime'
            : '🏠 NASA BAHAY NA! • Arrived: $currentTime';
        
        setState(() {
          _currentLocationStatus = '$childName $status';
        });
        
        _showNotification('$childName $status');
        break;
      }
    }
  }

  void _showNotification(String message) {
    debugPrint('🔔 NOTIFICATION: $message');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // Show dialog for setting location
  void _showSetLocationDialog(LatLng location) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select location type for:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                '${location.latitude.toStringAsFixed(6)},\n${location.longitude.toStringAsFixed(6)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildLocationTypeButton(
                    LocationType.school,
                    Icons.school,
                    'School',
                    Colors.blue,
                  ),
                  _buildLocationTypeButton(
                    LocationType.home,
                    Icons.home,
                    'Home',
                    Colors.green,
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isSelectingLocation = false;
                _selectedLocation = null;
              });
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationTypeButton(LocationType type, IconData icon, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, size: 40, color: color),
          onPressed: () {
            Navigator.pop(context);
            _showNameLocationDialog(type, _selectedLocation!);
          },
        ),
        const SizedBox(height: 4),
        Text(
          label, 
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _showNameLocationDialog(LocationType type, LatLng location) {
    final defaultName = type == LocationType.school ? 'School' : 'Home';
    final TextEditingController nameController = TextEditingController(text: defaultName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set ${type.toString().split('.').last} Location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Coordinates:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${location.latitude.toStringAsFixed(6)},\n${location.longitude.toStringAsFixed(6)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Location Name',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => nameController.clear(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim().isEmpty ? defaultName : nameController.text.trim();
              _saveLocation(name, type, location.latitude, location.longitude);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Toggle location selection mode
  void _toggleLocationSelection() {
    setState(() {
      _isSelectingLocation = !_isSelectingLocation;
      _selectedLocation = null;
    });
  }

  // Handle map tap
  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_isSelectingLocation) {
      setState(() {
        _selectedLocation = point;
      });
      _showSetLocationDialog(point);
    }
  }

  // Request Location Permission
  void _requestLocationPermission() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showLocationErrorDialog('Location Services Disabled', 
              'Please enable location services on your device to see your current location on the map.');
        }
        return;
      }

      permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        
        if (permission == LocationPermission.denied) {
          if (mounted) {
            _showLocationErrorDialog('Location Permission Required',
                'Location permissions are required to show your current location on the map. Please grant location access in app settings.');
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showLocationErrorDialog('Location Permission Permanently Denied',
              'Location permissions are permanently denied. Please enable them in your device settings to see your location on the map.');
        }
        return;
      }

      if (permission == LocationPermission.whileInUse || 
          permission == LocationPermission.always) {
        _startLocationUpdates();
        _getCurrentLocation();
      }
      
    } catch (e) {
      debugPrint('Location permission error: $e');
    }
  }

  void _showLocationErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Start Location Updates with Better Accuracy - REAL TIME
  void _startLocationUpdates() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    _locationSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      debugPrint('📍 MY LOCATION UPDATE: ${position.latitude}, ${position.longitude} - Accuracy: ${position.accuracy}m');
      
      if (mounted) {
        setState(() {
          _myCurrentLocation = LatLng(position.latitude, position.longitude);
          _myLocationAccuracy = position.accuracy;
          _lastLocationUpdate = DateTime.now();
          
          _addToMyLocationHistory(position.latitude, position.longitude);
        });
      }
    }, onError: (error) {
      debugPrint('❌ LOCATION STREAM ERROR: $error');
    });
  }

  void _addToMyLocationHistory(double lat, double lng) {
    final newLocation = LatLng(lat, lng);
    
    if (_myLocationHistory.isEmpty || 
        _calculateDistance(_myLocationHistory.last, newLocation) > 2.0) {
      _myLocationHistory.add(newLocation);
      
      if (_myLocationHistory.length > 100) {
        _myLocationHistory.removeAt(0);
      }
    }
  }

  // Get Current Location Once
  void _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      debugPrint('📍 INITIAL MY LOCATION: ${position.latitude}, ${position.longitude}');
      
      if (mounted) {
        setState(() {
          _myCurrentLocation = LatLng(position.latitude, position.longitude);
          _myLocationAccuracy = position.accuracy;
          _lastLocationUpdate = DateTime.now();
        });
      }

    } catch (e) {
      debugPrint('❌ GET LOCATION ERROR: $e');
    }
  }

  // Load user's devices from Firestore
  void _loadUserDevices() async {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null) return;

    try {
      final parentDoc = await FirebaseFirestore.instance
          .collection('parents')
          .doc(user.uid)
          .get();

      if (parentDoc.exists) {
        final data = parentDoc.data();
        final deviceCodes = (data?['childDeviceCodes'] as List?)?.cast<String>() ?? [];

        if (deviceCodes.isNotEmpty) {
          final devices = <TrackingDevice>[];
          
          for (final code in deviceCodes) {
            final childDoc = await FirebaseFirestore.instance
                .collection('children')
                .doc(code)
                .get();
                
            if (childDoc.exists) {
              final childData = childDoc.data()!;
              devices.add(TrackingDevice(
                deviceCode: code,
                nickname: childData['nickname']?.toString() ?? 'Device ${code.substring(0, 4)}',
                name: childData['name']?.toString(),
              ));
            }
          }

          if (mounted) {
            setState(() {
              _availableDevices = devices;
              if (devices.isNotEmpty) {
                _selectedDevice = devices.first;
                _startTracking(devices.first.deviceCode);
                _loadSavedLocations(); // Load locations for this device
              }
              _isLoading = false;
            });
          }
          return;
        }
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ LOAD DEVICES ERROR: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startTracking(String deviceCode) {
    _streamSubscription?.cancel();
    
    debugPrint('🔍 START TRACKING DEVICE: $deviceCode');
    
    // Add debug check before starting
    _checkRTDBState(deviceCode);
    
    _streamSubscription = _rtdb.ref('children/$deviceCode').onValue.listen((event) {
      final data = event.snapshot.value as Map? ?? {};
      debugPrint('📡 DEVICE DATA RECEIVED: $data');
      
      final convertedData = <String, dynamic>{};
      data.forEach((key, value) {
        convertedData[key.toString()] = value;
      });
      
      if (mounted) {
        setState(() {
          _lastData = convertedData;
        });
        
        _checkChildProximityOnly(convertedData);
        
        if (_isTracking && _isMapReady) {
          final lat = _getLatitude(convertedData);
          final lng = _getLongitude(convertedData);
          if (lat != null && lng != null) {
            _mapController.move(LatLng(lat, lng), 16);
          }
        }
      }
    }, onError: (error) {
      debugPrint('❌ RTDB Error: $error');
    });
  }

  // Add debug function to check RTDB state
  void _checkRTDBState(String deviceCode) async {
    try {
      final snapshot = await _rtdb.ref('children/$deviceCode').get();
      debugPrint('🔍 RTDB STATE CHECK:');
      debugPrint('   - Device exists: ${snapshot.exists}');
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map? ?? {});
        debugPrint('   - parentId: ${data['parentId']}');
        debugPrint('   - Current User: ${Provider.of<AuthService>(context, listen: false).currentUser?.uid}');
        debugPrint('   - Match: ${data['parentId'] == Provider.of<AuthService>(context, listen: false).currentUser?.uid}');
        debugPrint('   - Available data keys: ${data.keys}');
      }
    } catch (e) {
      debugPrint('❌ RTDB STATE CHECK ERROR: $e');
    }
  }

  void _onDeviceChanged(TrackingDevice device) {
    setState(() {
      _selectedDevice = device;
      _lastData = null;
      _locationHistory.clear();
      _savedLocations.clear(); // Clear previous device's locations
      _currentLocationStatus = ''; // Reset status
      _showDeviceSelector = false;
    });
    
    _startTracking(device.deviceCode);
    _loadSavedLocations(); // Load locations for new device
  }

  void _toggleDeviceSelector() {
    setState(() {
      _showDeviceSelector = !_showDeviceSelector;
    });
  }

  void _toggleMyLocation() {
    setState(() {
      _showMyLocation = !_showMyLocation;
    });
  }

  double? _getLongitude(Map<String, dynamic> data) {
    return (data['lng'] as num?)?.toDouble() ?? 
           (data['longitude'] as num?)?.toDouble();
  }

  double? _getLatitude(Map<String, dynamic> data) {
    return (data['lat'] as num?)?.toDouble() ?? 
           (data['latitude'] as num?)?.toDouble();
  }

  void _addToHistory(double lat, double lng) {
    final newLocation = LatLng(lat, lng);
    
    if (_locationHistory.isEmpty || 
        _calculateDistance(_locationHistory.last, newLocation) > 5.0) {
      _locationHistory.add(newLocation);
      
      if (_locationHistory.length > 200) {
        _locationHistory.removeAt(0);
      }
    }
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const Distance distance = Distance();
    return distance(point1, point2);
  }

  void _centerOnLocation(double lat, double lng) {
    if (_isTracking && _isMapReady) {
      _mapController.move(LatLng(lat, lng), 16);
    }
  }

  void _centerOnMyLocation() {
    if (_myCurrentLocation != null && _isMapReady) {
      _mapController.move(_myCurrentLocation!, 16);
    }
  }

  void _centerOnBothLocations() {
    if (_myCurrentLocation != null && _lastData != null) {
      final deviceLat = _getLatitude(_lastData!);
      final deviceLng = _getLongitude(_lastData!);
      
      if (deviceLat != null && deviceLng != null) {
        final midLat = (_myCurrentLocation!.latitude + deviceLat) / 2;
        final midLng = (_myCurrentLocation!.longitude + deviceLng) / 2;
        
        final distance = _calculateDistance(_myCurrentLocation!, LatLng(deviceLat, deviceLng));
        double zoom = 16.0;
        if (distance > 1000) zoom = 12.0;
        else if (distance > 500) zoom = 13.0;
        else if (distance > 200) zoom = 14.0;
        else if (distance > 100) zoom = 15.0;
        
        _mapController.move(LatLng(midLat, midLng), zoom);
      }
    }
  }

  void _onMapReady() {
    setState(() {
      _isMapReady = true;
    });
  }

  void _refreshData() {
    if (_selectedDevice != null) {
      _startTracking(_selectedDevice!.deviceCode);
    }
    _getCurrentLocation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Location Selection Mode Toggle
          IconButton(
            icon: Icon(
              _isSelectingLocation ? Icons.location_on : Icons.add_location,
              color: _isSelectingLocation ? Colors.orange : Colors.white,
            ),
            onPressed: _toggleLocationSelection,
            tooltip: _isSelectingLocation ? 'Cancel location selection' : 'Set School/Home Location',
          ),
          IconButton(
            icon: Icon(_showMyLocation ? Icons.location_on : Icons.location_off,
                color: Colors.white),
            onPressed: _toggleMyLocation,
            tooltip: _showMyLocation ? 'Hide my location' : 'Show my location',
          ),
          IconButton(
            icon: Icon(_isTracking ? Icons.gps_fixed : Icons.gps_off,
                color: Colors.white),
            onPressed: () {
              setState(() {
                _isTracking = !_isTracking;
              });
            },
            tooltip: _isTracking ? 'Auto-tracking ON' : 'Auto-tracking OFF',
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_showDeviceSelector) _buildDeviceSelectorPopup(),
          if (_isSelectingLocation) _buildLocationSelectionOverlay(),
        ],
      ),
      floatingActionButton: _buildFloatingActions(),
    );
  }

  Widget _buildLocationSelectionOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.orange.withOpacity(0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.touch_app, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap on the map to set School or Home location',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'A dialog will appear to choose between School or Home',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_availableDevices.isEmpty) {
      return _buildNoDevicesState();
    }

    return Stack(
      children: [
        _buildMapSection(),
        _buildHeaderOverlay(),
        _buildBottomSheet(),
      ],
    );
  }

  Widget _buildHeaderOverlay() {
    return Positioned(
      top: _isSelectingLocation ? 70 : 16,
      left: 16,
      right: 16,
      child: Column(
        children: [
          // Device Selector Card
          _buildDeviceSelectorCard(),
          const SizedBox(height: 8),
          // Status Card
          if (_selectedDevice != null && _lastData != null) 
            _buildStatusCard(),
        ],
      ),
    );
  }

  Widget _buildDeviceSelectorCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blue[100],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.device_unknown, color: Colors.blue[800]),
        ),
        title: Text(
          _selectedDevice?.nickname ?? 'Select Device',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: _selectedDevice?.name != null ? Text(_selectedDevice!.name!) : null,
        trailing: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
        onTap: _toggleDeviceSelector,
      ),
    );
  }

  Widget _buildStatusCard() {
    final data = _lastData!;
    final isOnline = data['isOnline'] == true;
    final sosActive = data['sosActive'] == true;
    final batteryLevel = (data['batteryLevel'] as num?)?.toInt() ?? 0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ✅ UPDATED: CHILD-ONLY LOCATION STATUS WITH TIME
            if (_currentLocationStatus.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _currentLocationStatus.contains('SCHOOL') ? Colors.blue[100] : 
                         _currentLocationStatus.contains('BAHAY') ? Colors.green[100] : 
                         Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      _currentLocationStatus.split('•')[0].trim(), // Main status
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _currentLocationStatus.contains('SCHOOL') ? Colors.blue[800] : 
                               _currentLocationStatus.contains('BAHAY') ? Colors.green[800] : 
                               Colors.orange[800],
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentLocationStatus.split('•')[1].trim(), // Time
                      style: TextStyle(
                        color: _currentLocationStatus.contains('SCHOOL') ? Colors.blue[600] : 
                               _currentLocationStatus.contains('BAHAY') ? Colors.green[600] : 
                               Colors.orange[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            if (_currentLocationStatus.isNotEmpty) const SizedBox(height: 8),
            Row(
              children: [
                // Status Indicator
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                // Battery
                Row(
                  children: [
                    Icon(Icons.battery_std, size: 16, color: _getBatteryColor(batteryLevel)),
                    const SizedBox(width: 4),
                    Text('$batteryLevel%', style: TextStyle(
                      color: _getBatteryColor(batteryLevel),
                      fontWeight: FontWeight.bold,
                    )),
                  ],
                ),
                const SizedBox(width: 16),
                // SOS Indicator
                if (sosActive)
                  Row(
                    children: [
                      const Icon(Icons.warning, size: 16, color: Colors.red),
                      const SizedBox(width: 4),
                      const Text('SOS', style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      )),
                    ],
                  ),
                const Spacer(),
                // Last Update
                if (_lastLocationUpdate != null)
                  Text(
                    'Updated: ${_getTimeAgo(_lastLocationUpdate!)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getBatteryColor(int level) {
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }

  String _getTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  Widget _buildBottomSheet() {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_savedLocations.isNotEmpty) _buildSavedLocationsCard(),
          if (_showMyLocation && _myCurrentLocation != null) 
            _buildMyLocationCard(),
          const SizedBox(height: 8),
          if (_lastData != null)
            _buildDeviceLocationCard(),
        ],
      ),
    );
  }

  Widget _buildSavedLocationsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.purple[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bookmark, color: Colors.purple[800]),
                const SizedBox(width: 8),
                Text(
                  '${_selectedDevice?.nickname}\'s Locations',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${_savedLocations.length} locations',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _savedLocations.length,
                itemBuilder: (context, index) {
                  final location = _savedLocations[index];
                  return _buildSavedLocationChip(location);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedLocationChip(SavedLocation location) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Chip(
        backgroundColor: location.type == LocationType.school ? Colors.blue[100] : Colors.green[100],
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              location.type == LocationType.school ? Icons.school : Icons.home,
              size: 16,
              color: location.type == LocationType.school ? Colors.blue : Colors.green,
            ),
            const SizedBox(width: 4),
            Text(
              location.name,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        onDeleted: () => _showDeleteConfirmation(location),
        deleteIcon: const Icon(Icons.close, size: 16),
      ),
    );
  }

  void _showDeleteConfirmation(SavedLocation location) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Location'),
        content: Text('Are you sure you want to delete "${location.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteLocation(location.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildMyLocationCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.person_pin_circle, color: Colors.green[800]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Location',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  Text(
                    '${_myCurrentLocation!.latitude.toStringAsFixed(6)}, ${_myCurrentLocation!.longitude.toStringAsFixed(6)}',
                    style: TextStyle(color: Colors.green[700], fontSize: 12),
                  ),
                  if (_myLocationAccuracy != null)
                    Text(
                      'Accuracy: ±${_myLocationAccuracy!.toStringAsFixed(1)}m',
                      style: TextStyle(color: Colors.green[600], fontSize: 10),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceLocationCard() {
    final lat = _getLatitude(_lastData!);
    final lng = _getLongitude(_lastData!);
    
    if (lat == null || lng == null) return const SizedBox();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.device_hub, color: Colors.blue[800]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selectedDevice?.nickname ?? 'Device'} Location',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                  Text(
                    '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                    style: TextStyle(color: Colors.blue[700], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSelectorPopup() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // HEADER
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[800],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.devices, color: Colors.white),
                    const SizedBox(width: 12),
                    const Text(
                      'Select Device to Track',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _toggleDeviceSelector,
                    ),
                  ],
                ),
              ),
              
              // DEVICE LIST
              Expanded(
                child: _availableDevices.isEmpty
                    ? const Center(
                        child: Text('No devices available'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _availableDevices.length,
                        itemBuilder: (context, index) {
                          final device = _availableDevices[index];
                          final isSelected = _selectedDevice?.deviceCode == device.deviceCode;
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: isSelected ? Colors.blue.shade50 : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isSelected ? Colors.blue : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: ListTile(
                              leading: Icon(
                                Icons.device_unknown,
                                color: isSelected ? Colors.blue : Colors.grey,
                                size: 32,
                              ),
                              title: Text(
                                device.nickname,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.blue : Colors.black87,
                                ),
                              ),
                              subtitle: device.name != null && device.name!.isNotEmpty
                                  ? Text(device.name!)
                                  : null,
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: Colors.blue)
                                  : null,
                              onTap: () => _onDeviceChanged(device),
                            ),
                          );
                        },
                      ),
              ),
              
              // CLOSE BUTTON
              Container(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: _toggleDeviceSelector,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.black87,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading your devices...',
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  // ✅ FIXED: NO DEVICES STATE - CORRECTED NAVIGATION
  Widget _buildNoDevicesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.devices_other, size: 60, color: Colors.grey),
            const SizedBox(height: 20),
            const Text(
              'No Devices Available',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'You need to link devices first in the My Devices section',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // ✅ FIXED: Use Navigator to go to My Devices screen
                // Assuming your My Devices screen is named 'MyChildrenScreen'
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyChildrenScreen(), // Make sure to import MyChildrenScreen
                  ),
                );
              },
              child: const Text('Go to My Devices'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDeviceSelected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_searching, size: 60, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Select a Device to Track',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _toggleDeviceSelector,
            child: const Text('Choose Device'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.location_off, size: 60, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          if (_selectedDevice != null) ...[
            const SizedBox(height: 8),
            Text(
              'Device: ${_selectedDevice!.nickname}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _toggleDeviceSelector,
            child: const Text('Change Device'),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    if (_selectedDevice == null) {
      return _buildNoDeviceSelected();
    }

    if (_lastData == null || _lastData!.isEmpty) {
      return _buildNoDataState('Waiting for device data...');
    }

    final data = _lastData!;
    
    final lat = _getLatitude(data);
    final lng = _getLongitude(data);
    
    final isOnline = data['isOnline'] == true;
    final sosActive = data['sosActive'] == true;
    final batteryLevel = (data['batteryLevel'] as num?)?.toInt() ?? 0;

    if (lat == null || lng == null || lat == 0.0 || lng == 0.0) {
      return _buildNoDataState('No valid location data available');
    }

    _addToHistory(lat, lng);
    if (_isMapReady && _isTracking) {
      _centerOnLocation(lat, lng);
    }

    return _buildMapWithOverlay(
      lat: lat,
      lng: lng,
      isOnline: isOnline,
      sosActive: sosActive,
      batteryLevel: batteryLevel,
    );
  }

  Widget _buildMapWithOverlay({
    required double lat,
    required double lng,
    required bool isOnline,
    required bool sosActive,
    required int batteryLevel,
  }) {
    List<Marker> markers = [
      // DEVICE MARKER - BLUE
      Marker(
        width: 50.0,
        height: 50.0,
        point: LatLng(lat, lng),
        child: Container(
          decoration: BoxDecoration(
            color: sosActive ? Colors.red : Colors.blue,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            sosActive ? Icons.warning : Icons.person_pin_circle,
            color: Colors.white,
            size: 25,
          ),
        ),
      ),
    ];

    // ADD MY LOCATION MARKER - GREEN
    if (_showMyLocation && _myCurrentLocation != null) {
      markers.add(
        Marker(
          width: 40.0,
          height: 40.0,
          point: _myCurrentLocation!,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    }

    // ADD SAVED LOCATIONS MARKERS
    for (final location in _savedLocations) {
      markers.add(
        Marker(
          width: 35.0,
          height: 35.0,
          point: LatLng(location.latitude, location.longitude),
          child: Container(
            decoration: BoxDecoration(
              color: location.type == LocationType.school ? Colors.blue : Colors.green,
              borderRadius: BorderRadius.circular(17.5),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              location.type == LocationType.school ? Icons.school : Icons.home,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }

    List<Polyline> polylines = [];

    // DEVICE ROUTE - BLUE
    if (_locationHistory.length > 1) {
      polylines.add(
        Polyline(
          points: _locationHistory,
          color: Colors.blue.withOpacity(0.7),
          strokeWidth: 4.0,
        ),
      );
    }

    // MY LOCATION ROUTE - GREEN
    if (_showMyLocation && _myLocationHistory.length > 1) {
      polylines.add(
        Polyline(
          points: _myLocationHistory,
          color: Colors.green.withOpacity(0.7),
          strokeWidth: 3.0,
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(lat, lng),
        initialZoom: 16,
        onMapReady: _onMapReady,
        onTap: _onMapTap,
      ),
      children: [
        TileLayer(
          urlTemplate: "https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=pk.eyJ1IjoiYXNocmVkIiwiYSI6ImNtZ2dndWNhODBrcGwyam9ybXhodzN0YXUifQ.nFtZjuv0AvGEIv3v4TxmXg",
          userAgentPackageName: 'com.example.protectid',
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildFloatingActions() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          onPressed: _centerOnBothLocations,
          heroTag: 'center_both',
          mini: true,
          backgroundColor: Colors.purple,
          child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 10),
        
        if (_showMyLocation && _myCurrentLocation != null)
          Column(
            children: [
              FloatingActionButton(
                onPressed: _centerOnMyLocation,
                heroTag: 'center_my_location',
                mini: true,
                backgroundColor: Colors.green,
                child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 10),
            ],
          ),
        
        FloatingActionButton(
          onPressed: () {
            if (_isMapReady && _lastData != null) {
              final lat = _getLatitude(_lastData!);
              final lng = _getLongitude(_lastData!);
              if (lat != null && lng != null) {
                _mapController.move(LatLng(lat, lng), 16);
              }
            }
          },
          heroTag: 'center_device_location',
          mini: true,
          backgroundColor: Colors.blue,
          child: const Icon(Icons.device_hub, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 10),
        
        FloatingActionButton(
          onPressed: _refreshData,
          heroTag: 'refresh',
          mini: true,
          backgroundColor: Colors.orange,
          child: const Icon(Icons.refresh, color: Colors.white, size: 20),
        ),
      ],
    );
  }
}