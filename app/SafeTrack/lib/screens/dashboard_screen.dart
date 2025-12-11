// app/SafeTrack/lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../services/auth_service.dart';
import '../widgets/quick_actions_grid.dart';
import 'live_location_screen.dart';
import 'my_children_screen.dart';
import 'settings_screen.dart';
import 'package:intl/intl.dart';
import 'activity_log_screen.dart';

// Firebase Realtime Database instance
final FirebaseDatabase rtdbInstance = FirebaseDatabase.instance;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  
  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const DashboardHome(),
      const LiveLocationsScreen(),
      const MyChildrenScreen(),
      const SettingsScreen(),
    ];
  }

  // Public method to change the current tab
  void setCurrentIndex(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Image.asset(
              'assets/images/my_app_logo.png',
              height: MediaQuery.of(context).size.width * 0.20,
              width: MediaQuery.of(context).size.width * 0.20,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.school, 
                  color: Colors.white, 
                  size: MediaQuery.of(context).size.width * 0.10
                );
              },
            ),
            SizedBox(width: MediaQuery.of(context).size.width * 0.02),
            Text(
              'SafeTrack - Student Safety',
              style: TextStyle(
                fontSize: MediaQuery.of(context).size.width * 0.038, 
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        centerTitle: false,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: Stack(
        children: [
          _screens[_currentIndex],
          if (_currentIndex == 0) // Only show on Dashboard Home
            const QuickActionsGrid(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index < _screens.length) {
            setState(() => _currentIndex = index);
          }
        },
        type: BottomNavigationBarType.fixed, 
        selectedItemColor: Colors.blue[700],
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'Live Location',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.child_care),
            label: 'My Children',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// --- MAIN DASHBOARD HOME WIDGET ---
class DashboardHome extends StatelessWidget {
  const DashboardHome({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    if (user == null) {
      return const Center(child: Text('User not logged in.'));
    }

    return StreamBuilder<DatabaseEvent>(
      stream: rtdbInstance.ref('linkedDevices').child(user.uid).child('devices').onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const DashboardContent(childDevices: []);
        }

        final devicesData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
        
        // Filter only enabled devices
        final List<Map<String, dynamic>> childDevices = [];
        devicesData.forEach((key, value) {
          final deviceData = value as Map<dynamic, dynamic>;
          final isEnabled = deviceData['deviceEnabled']?.toString() == 'true';
          
          if (isEnabled) {
            childDevices.add({
              'deviceCode': key.toString(),
              'data': deviceData,
            });
          }
        });

        return DashboardContent(childDevices: childDevices);
      },
    );
  }
}

// ---------------------------------------------
// --- DASHBOARD UI CONTENT ---
// ---------------------------------------------
class DashboardContent extends StatelessWidget {
  final List<Map<String, dynamic>> childDevices;
  const DashboardContent({super.key, required this.childDevices});

  @override
  Widget build(BuildContext context) {
      final screenWidth = MediaQuery.of(context).size.width;
      final isTablet = screenWidth > 600;
      final isDesktop = screenWidth > 1024;

      return SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(isDesktop ? 24.0 : isTablet ? 20.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section: Monitoring Status
              _buildMonitoringStatus(isTablet, isDesktop),
              
              SizedBox(height: isDesktop ? 40.0 : isTablet ? 30.0 : 20.0),
              
              // My Children Section
              _buildMyChildrenSection(context, isTablet, isDesktop),
              
              SizedBox(height: isDesktop ? 30.0 : isTablet ? 25.0 : 20.0),
              
              // Add some bottom padding so content isn't hidden behind the floating button
              SizedBox(height: 100),
            ],
          ),
        ),
      );
    }

  Widget _buildMonitoringStatus(bool isTablet, bool isDesktop) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getAllChildrenStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            elevation: 2,
            child: ListTile(
              leading: const CircularProgressIndicator(),
              title: Text(
                'Monitoring your children\'s safety at school',
                style: TextStyle(fontSize: isDesktop ? 18.0 : isTablet ? 16.0 : 14.0),
              ),
              subtitle: const Text('Checking status...'),
            ),
          );
        }

        final childrenStatus = snapshot.data ?? [];
        
        final bool hasEmergency = childrenStatus.any((child) => child['sosActive'] == true);
        final bool allChildrenOnline = childrenStatus.isNotEmpty && 
            childrenStatus.every((child) => child['isOnline'] == true);
        final bool someChildrenOffline = childrenStatus.isNotEmpty && 
            childrenStatus.any((child) => child['isOnline'] == false);
        final bool noDevices = childrenStatus.isEmpty;

        String statusText;
        Color statusColor;
        IconData statusIcon;

        if (hasEmergency) {
          statusText = 'EMERGENCY DETECTED!';
          statusColor = Colors.red;
          statusIcon = Icons.warning;
        } else if (noDevices) {
          statusText = 'No Devices Linked Yet';
          statusColor = Colors.orange;
          statusIcon = Icons.device_unknown;
        } else if (allChildrenOnline) {
          statusText = 'All Children Safe & Online';
          statusColor = Colors.green;
          statusIcon = Icons.security;
        } else if (someChildrenOffline) {
          statusText = 'Some Children Offline';
          statusColor = Colors.orange;
          statusIcon = Icons.signal_wifi_off;
        } else {
          statusText = 'Monitoring Status';
          statusColor = Colors.blue;
          statusIcon = Icons.monitor_heart;
        }

        return Card(
          elevation: hasEmergency ? 8 : 2,
          color: hasEmergency ? Colors.red.shade50 : null,
          child: ListTile(
            leading: Icon(
              statusIcon,
              color: hasEmergency ? Colors.red : statusColor,
              size: isDesktop ? 32.0 : isTablet ? 28.0 : 24.0,
            ),
            title: Text(
              'Monitoring your children\'s safety at school',
              style: TextStyle(
                fontSize: isDesktop ? 18.0 : isTablet ? 16.0 : 14.0,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              statusText,
              style: TextStyle(
                color: hasEmergency ? Colors.red : statusColor, 
                fontWeight: FontWeight.bold,
                fontSize: isDesktop ? 16.0 : isTablet ? 14.0 : 12.0,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMyChildrenSection(BuildContext context, bool isTablet, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'My Children',
          style: TextStyle(
            fontSize: isDesktop ? 24.0 : isTablet ? 22.0 : 20.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: isDesktop ? 16.0 : isTablet ? 12.0 : 8.0),

        if (childDevices.isEmpty)
          _buildEmptyState(isTablet, isDesktop)
        else
          _buildChildrenList(context, isTablet, isDesktop),
      ],
    );
  }

  Widget _buildEmptyState(bool isTablet, bool isDesktop) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: isDesktop ? 40.0 : isTablet ? 30.0 : 20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.devices_other,
              size: isDesktop ? 60.0 : isTablet ? 50.0 : 40.0,
              color: Colors.grey,
            ),
            SizedBox(height: isDesktop ? 16.0 : isTablet ? 12.0 : 8.0),
            Text(
              'No children linked yet.',
              style: TextStyle(
                fontSize: isDesktop ? 18.0 : isTablet ? 16.0 : 14.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: isDesktop ? 8.0 : isTablet ? 6.0 : 4.0),
            Text(
              'Go to My Children to link a device.',
              style: TextStyle(
                fontSize: isDesktop ? 14.0 : isTablet ? 13.0 : 12.0,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildrenList(BuildContext context, bool isTablet, bool isDesktop) {
    if (isDesktop) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
          childAspectRatio: 2.5,
        ),
        itemCount: childDevices.length,
        itemBuilder: (context, index) => ChildCard(
          deviceCode: childDevices[index]['deviceCode'],
          deviceData: childDevices[index]['data'],
          isTablet: isTablet,
          isDesktop: isDesktop,
        ),
      );
    } else if (isTablet) {
      final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
      
      if (isLandscape) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12.0,
            mainAxisSpacing: 12.0,
            childAspectRatio: 3.0,
          ),
          itemCount: childDevices.length,
          itemBuilder: (context, index) => ChildCard(
            deviceCode: childDevices[index]['deviceCode'],
            deviceData: childDevices[index]['data'],
            isTablet: isTablet,
            isDesktop: isDesktop,
          ),
        );
      } else {
        return Column(
          children: childDevices.map((device) => Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: ChildCard(
              deviceCode: device['deviceCode'],
              deviceData: device['data'],
              isTablet: isTablet,
              isDesktop: isDesktop,
            ),
          )).toList(),
        );
      }
    } else {
      return Column(
        children: childDevices.map((device) => Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: ChildCard(
            deviceCode: device['deviceCode'],
            deviceData: device['data'],
            isTablet: isTablet,
            isDesktop: isDesktop,
          ),
        )).toList(),
      );
    }
  }

  Stream<List<Map<String, dynamic>>> _getAllChildrenStatus() {
    return Stream.fromFuture(Future.wait(
      childDevices.map((device) async {
        final deviceCode = device['deviceCode'];
        final deviceData = device['data'];
        final deviceStatus = deviceData['deviceStatus'] as Map<dynamic, dynamic>?;
        
        final sosActive = deviceStatus?['sos']?.toString() == 'true';
        
        // Check if device is online (last update within 5 minutes)
        // final now = DateTime.now().millisecondsSinceEpoch;
        final lastUpdateStr = deviceStatus?['lastUpdate']?.toString() ?? '';
        final isOnline = _isDeviceOnline(lastUpdateStr);
        
        return {
          'deviceCode': deviceCode,
          'sosActive': sosActive,
          'isOnline': isOnline,
        };
      }),
    ));
  }

  bool _isDeviceOnline(String lastUpdateStr) {
    if (lastUpdateStr.isEmpty) return false;
    
    try {
      // Split date and time
      final parts = lastUpdateStr.trim().split(' ');
      if (parts.length != 2) return false;
      
      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');
      
      if (dateParts.length != 3 || timeParts.length != 3) return false;
      
      final lastUpdate = DateTime(
        int.parse(dateParts[0]), // year
        int.parse(dateParts[1]), // month
        int.parse(dateParts[2]), // day
        int.parse(timeParts[0]), // hour (works with or without leading zero)
        int.parse(timeParts[1]), // minute
        int.parse(timeParts[2]), // second
      );
      
      final now = DateTime.now();
      final difference = now.difference(lastUpdate).inMinutes;
      
      return difference < 5; // Online if updated within 5 minutes
    } catch (e) {
      debugPrint('Error parsing lastUpdate: $e - Value: $lastUpdateStr');
      return false;
    }
  }
}

// ---------------------------------------------
// --- CHILD CARD WIDGET ---
// ---------------------------------------------
class ChildCard extends StatelessWidget {
  final String deviceCode;
  final Map<dynamic, dynamic> deviceData;
  final bool isTablet;
  final bool isDesktop;

  const ChildCard({
    super.key, 
    required this.deviceCode,
    required this.deviceData,
    required this.isTablet,
    required this.isDesktop,
  });

  bool _isDeviceOnline(String lastUpdateStr) {
    if (lastUpdateStr.isEmpty) return false;
    
    try {
      // Split date and time
      final parts = lastUpdateStr.trim().split(' ');
      if (parts.length != 2) return false;
      
      final dateParts = parts[0].split('-');
      final timeParts = parts[1].split(':');
      
      if (dateParts.length != 3 || timeParts.length != 3) return false;
      
      final lastUpdate = DateTime(
        int.parse(dateParts[0]), // year
        int.parse(dateParts[1]), // month
        int.parse(dateParts[2]), // day
        int.parse(timeParts[0]), // hour (works with or without leading zero)
        int.parse(timeParts[1]), // minute
        int.parse(timeParts[2]), // second
      );
      
      final now = DateTime.now();
      final difference = now.difference(lastUpdate).inMinutes;
      
      return difference < 5; // Online if updated within 5 minutes
    } catch (e) {
      debugPrint('Error parsing lastUpdate: $e - Value: $lastUpdateStr');
      return false;
    }
  }

  void _showDeviceInfo(BuildContext context) {
    final addedAt = (deviceData['addedAt'] as num?)?.toInt();
    final addedDate = addedAt != null 
        ? DateFormat('MMM dd, yyyy - hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(addedAt))
        : 'Unknown';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('Device Information'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Device Code:', deviceCode),
              SizedBox(height: 8),
              _buildInfoRow('Added On:', addedDate),
              SizedBox(height: 8),
              _buildInfoRow('Status:', deviceData['deviceEnabled']?.toString() == 'true' ? 'Enabled' : 'Disabled'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  void _showFullScreenImage(BuildContext context, String childName, ImageProvider? imageProvider) {
    if (imageProvider == null) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.all(isDesktop ? 40.0 : isTablet ? 30.0 : 20.0),
          child: Stack(
            children: [
              Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black87,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 3.0,
                        child: Center(
                          child: Image(
                            image: imageProvider,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.error, 
                                color: Colors.white, 
                                size: isDesktop ? 60.0 : isTablet ? 50.0 : 40.0
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(isDesktop ? 20.0 : isTablet ? 16.0 : 12.0),
                      child: Text(
                        childName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isDesktop ? 20.0 : isTablet ? 18.0 : 16.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              Positioned(
                top: isDesktop ? 50.0 : isTablet ? 40.0 : 30.0,
                right: isDesktop ? 30.0 : isTablet ? 20.0 : 10.0,
                child: IconButton(
                  icon: Icon(
                    Icons.close, 
                    color: Colors.white, 
                    size: isDesktop ? 35.0 : isTablet ? 30.0 : 25.0
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ImageProvider? _getImageProvider(String? imageBase64) {
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(imageBase64);
        return MemoryImage(bytes);
      } catch (e) {
        debugPrint('Error decoding base64 image: $e');
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final childName = deviceData['childName']?.toString() ?? 'Unknown Child';
    final yearLevel = deviceData['yearLevel']?.toString() ?? '';
    final section = deviceData['section']?.toString() ?? '';
    final imageBase64 = deviceData['imageProfileBase64']?.toString();
    
    final deviceStatus = deviceData['deviceStatus'] as Map<dynamic, dynamic>?;
    final batteryLevel = (deviceStatus?['batteryLevel'] as num?)?.toInt() ?? 0;
    final sosActive = deviceStatus?['sos']?.toString() == 'true';
    final lastLocation = deviceStatus?['lastLocation'] as Map<dynamic, dynamic>?;
    
    final lastUpdateStr = deviceStatus?['lastUpdate']?.toString() ?? '';
    final isOnline = _isDeviceOnline(lastUpdateStr);
    
    // Build grade/section string
    String gradeSection = '';
    if (yearLevel.isNotEmpty) {
      gradeSection = 'Grade $yearLevel';
      if (section.isNotEmpty) {
        gradeSection += ' - $section';
      }
    } else if (section.isNotEmpty) {
      gradeSection = section;
    }
    
    final ImageProvider? imageProvider = _getImageProvider(imageBase64);
    final Color avatarBgColor = Theme.of(context).primaryColor.withValues(alpha: 0.2);

    return _buildChildCard(
      context,
      childName,
      gradeSection,
      sosActive,
      isOnline,
      batteryLevel,
      lastLocation,
      imageProvider,
      avatarBgColor,
    );
  }

  Widget _buildChildCard(
    BuildContext context,
    String childName,
    String gradeSection,
    bool sosActive,
    bool isOnline,
    int batteryLevel,
    Map<dynamic, dynamic>? lastLocation,
    ImageProvider? imageProvider,
    Color avatarBgColor,
  ) {
    final avatarSize = isDesktop ? 56.0 : isTablet ? 48.0 : 40.0;
    final iconSize = isDesktop ? 20.0 : isTablet ? 18.0 : 16.0;
    final fontSizeTitle = isDesktop ? 18.0 : isTablet ? 16.0 : 14.0;
    final fontSizeSubtitle = isDesktop ? 14.0 : isTablet ? 13.0 : 12.0;

    return Card(
      elevation: sosActive ? 8 : 2,
      margin: EdgeInsets.only(bottom: isDesktop ? 16.0 : isTablet ? 12.0 : 8.0),
      color: sosActive ? Colors.red.shade50 : null,
      child: InkWell(
        onTap: () {
          // Navigate to Activity Log for this specific device
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ActivityLogScreen(
                deviceCode: deviceCode,
                childName: childName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Container(
              decoration: sosActive ? BoxDecoration(
                border: Border.all(color: Colors.red, width: 3),
                borderRadius: BorderRadius.circular(12),
              ) : null,
              child: Padding(
                padding: EdgeInsets.all(isDesktop ? 16.0 : isTablet ? 12.0 : 10.0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _showFullScreenImage(context, childName, imageProvider),
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: avatarSize,
                            backgroundColor: sosActive ? Colors.red.withValues(alpha: 0.3) : avatarBgColor,
                            backgroundImage: imageProvider,
                            child: imageProvider == null 
                                ? Icon(
                                    sosActive ? Icons.warning : Icons.person, 
                                    size: avatarSize * 0.6,
                                    color: sosActive ? Colors.red : Colors.blueGrey,
                                  ) 
                                : null,
                          ),
                          if (sosActive && imageProvider != null)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.warning, 
                                  color: Colors.white, 
                                  size: avatarSize * 0.5
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    SizedBox(width: isDesktop ? 16.0 : isTablet ? 12.0 : 10.0),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  childName,
                                  style: TextStyle(
                                    fontSize: fontSizeTitle,
                                    fontWeight: sosActive ? FontWeight.bold : FontWeight.w600,
                                    color: sosActive ? Colors.red : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.info_outline, size: iconSize, color: Colors.blue),
                                onPressed: () => _showDeviceInfo(context),
                                padding: EdgeInsets.zero,
                                constraints: BoxConstraints(),
                              ),
                            ],
                          ),
                          
                          if (gradeSection.isNotEmpty) ...[
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.school, size: iconSize, color: Colors.grey[600]),
                                SizedBox(width: 4),
                                Text(
                                  gradeSection,
                                  style: TextStyle(
                                    fontSize: fontSizeSubtitle,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          
                          SizedBox(height: 6),
                          
                          // Status Row
                          Row(
                            children: [
                              Icon(
                                Icons.circle,
                                color: isOnline ? Colors.green : Colors.grey,
                                size: iconSize * 0.7,
                              ),
                              SizedBox(width: 4),
                              Text(
                                isOnline ? 'Active' : 'Offline',
                                style: TextStyle(
                                  color: isOnline ? Colors.green : Colors.grey,
                                  fontSize: fontSizeSubtitle,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          
                          SizedBox(height: 4),
                          
                          // Battery Level
                          if (batteryLevel > 0)
                            Row(
                              children: [
                                Icon(
                                  batteryLevel > 80 ? Icons.battery_full :
                                  batteryLevel > 50 ? Icons.battery_std :
                                  batteryLevel > 20 ? Icons.battery_charging_full :
                                  Icons.battery_alert,
                                  size: iconSize,
                                  color: batteryLevel < 20 ? Colors.red : Colors.grey[600],
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '$batteryLevel%',
                                  style: TextStyle(
                                    fontSize: fontSizeSubtitle,
                                    color: batteryLevel < 20 ? Colors.red : Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          
                          SizedBox(height: 4),
                          
                          // Location Info
                          if (lastLocation != null)
                            Row(
                              children: [
                                Icon(Icons.location_on, size: iconSize, color: Colors.blue),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Lat: ${lastLocation['latitude']?.toStringAsFixed(4) ?? '0.0000'}, '
                                    'Lon: ${lastLocation['longitude']?.toStringAsFixed(4) ?? '0.0000'}',
                                    style: TextStyle(
                                      fontSize: fontSizeSubtitle * 0.9,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          
                          // Tap hint
                          SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.touch_app, size: iconSize * 0.8, color: Colors.blue[300]),
                              SizedBox(width: 4),
                              Text(
                                'Tap to view activity log',
                                style: TextStyle(
                                  fontSize: fontSizeSubtitle * 0.85,
                                  color: Colors.blue[300],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Status Chip
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 16 : isTablet ? 12 : 10,
                            vertical: isDesktop ? 8 : isTablet ? 6 : 5,
                          ),
                          decoration: BoxDecoration(
                            color: sosActive ? Colors.red : Colors.green,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            sosActive ? 'SOS' : 'SAFE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: fontSizeSubtitle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}