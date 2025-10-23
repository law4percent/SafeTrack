import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../auth_service.dart';
import '../widgets/quick_actions_grid.dart'; 

// ======================================================
// 🚨 RTDB REGION FIX: Gamitin ang parehong RTDB instance
// ======================================================
const String firebaseRtdbUrl = 'https://protectid-f04a3-default-rtdb.asia-southeast1.firebasedatabase.app';

final FirebaseDatabase rtdbInstance = FirebaseDatabase.instanceFor(
  app: Firebase.app(),
  databaseURL: firebaseRtdbUrl,
);
// ======================================================

// --- MAIN DASHBOARD WIDGET ---
class DashboardHome extends StatelessWidget {
  const DashboardHome({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    if (user == null) {
      return const Center(child: Text('User not logged in.'));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('parents').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || !snapshot.data!.exists || snapshot.data!.data() == null) {
          return const Center(child: Text('Error: Parent data not found.'));
        }

        final parentData = snapshot.data!.data() as Map<String, dynamic>;

        final List<String> childDeviceCodes = (parentData['childDeviceCodes'] as List<dynamic>?)
            ?.map((item) => item.toString())
            .toList() ??
            [];

        return DashboardContent(childDeviceCodes: childDeviceCodes);
      },
    );
  }
}

// ---------------------------------------------
// --- DASHBOARD UI CONTENT ---
// ---------------------------------------------
class DashboardContent extends StatelessWidget {
  final List<String> childDeviceCodes;
  const DashboardContent({super.key, required this.childDeviceCodes});

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
            // Header Section: Monitoring Status - FIXED LOGIC
            _buildMonitoringStatus(isTablet, isDesktop),
            
            SizedBox(height: isDesktop ? 40.0 : isTablet ? 30.0 : 20.0),
            
            // My Children Section
            _buildMyChildrenSection(context, isTablet, isDesktop),
            
            SizedBox(height: isDesktop ? 30.0 : isTablet ? 25.0 : 20.0),
            
            // AI Behavioral Insights
            _buildAIBsection(isTablet, isDesktop),
            
            SizedBox(height: isDesktop ? 40.0 : isTablet ? 30.0 : 25.0),
            
            // Quick Actions Section
            const QuickActionsGrid(), 
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
        
        // 🔥 FIXED LOGIC: Proper safety status checking
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

        if (childDeviceCodes.isEmpty)
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
          childAspectRatio: 3.0,
        ),
        itemCount: childDeviceCodes.length,
        itemBuilder: (context, index) => ChildCard(
          deviceCode: childDeviceCodes[index],
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
            childAspectRatio: 3.5,
          ),
          itemCount: childDeviceCodes.length,
          itemBuilder: (context, index) => ChildCard(
            deviceCode: childDeviceCodes[index],
            isTablet: isTablet,
            isDesktop: isDesktop,
          ),
        );
      } else {
        return Column(
          children: childDeviceCodes.map((code) => Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: ChildCard(
              deviceCode: code,
              isTablet: isTablet,
              isDesktop: isDesktop,
            ),
          )).toList(),
        );
      }
    } else {
      return Column(
        children: childDeviceCodes.map((code) => Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: ChildCard(
            deviceCode: code,
            isTablet: isTablet,
            isDesktop: isDesktop,
          ),
        )).toList(),
      );
    }
  }

  Widget _buildAIBsection(bool isTablet, bool isDesktop) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getAllChildrenStatus(),
      builder: (context, snapshot) {
        final childrenStatus = snapshot.data ?? [];
        final bool hasEmergency = childrenStatus.any((child) => child['sosActive'] == true);
        final bool allOnline = childrenStatus.isNotEmpty && 
            childrenStatus.every((child) => child['isOnline'] == true);

        String insightText;
        
        if (hasEmergency) {
          insightText = '🚨 EMERGENCY ALERT! Immediate attention required.';
        } else if (childrenStatus.isEmpty) {
          insightText = 'Link a device to enable insights.';
        } else if (allOnline) {
          insightText = 'All Patterns Normal. Your children are following their usual routines.';
        } else {
          insightText = 'Some devices offline. Monitoring limited connectivity.';
        }

        return Card(
          elevation: 2,
          child: ListTile(
            leading: Icon(
              Icons.insights,
              color: hasEmergency ? Colors.red : Colors.blue,
              size: isDesktop ? 32.0 : isTablet ? 28.0 : 24.0,
            ),
            title: Text(
              'AI Behavioral Insights',
              style: TextStyle(
                fontSize: isDesktop ? 18.0 : isTablet ? 16.0 : 14.0,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              insightText,
              style: TextStyle(
                fontSize: isDesktop ? 14.0 : isTablet ? 13.0 : 12.0,
                color: hasEmergency ? Colors.red : null,
                fontWeight: hasEmergency ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }

  Stream<List<Map<String, dynamic>>> _getAllChildrenStatus() {
    return Stream.fromFuture(Future.wait(
      childDeviceCodes.map((deviceCode) async {
        try {
          final rtdbSnapshot = await rtdbInstance.ref('children/$deviceCode').get();
          if (rtdbSnapshot.exists) {
            final data = rtdbSnapshot.value as Map<dynamic, dynamic>?;
            return {
              'deviceCode': deviceCode,
              'sosActive': data?['sosActive'] == true,
              'isOnline': data?['isOnline'] == true,
            };
          }
        } catch (e) {
          debugPrint('Error fetching status for $deviceCode: $e');
        }
        return {
          'deviceCode': deviceCode,
          'sosActive': false,
          'isOnline': false,
        };
      }),
    ));
  }
}

// ---------------------------------------------
// --- WIDGET PARA SA BAWAT BATA (Child Card) ---
// ---------------------------------------------
class ChildCard extends StatelessWidget {
  final String deviceCode;
  final bool isTablet;
  final bool isDesktop;

  const ChildCard({
    super.key, 
    required this.deviceCode,
    required this.isTablet,
    required this.isDesktop,
  });

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
              // Full screen image content
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
              
              // Close button
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

  ImageProvider? _getImageProvider(String? avatarPath) {
    if (avatarPath != null && !avatarPath.startsWith('http')) {
      final File localFile = File(avatarPath);
      if (localFile.existsSync()) {
        return FileImage(localFile);
      }
    } else if (avatarPath != null && avatarPath.startsWith('http')) {
      return NetworkImage(avatarPath);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('children').doc(deviceCode).snapshots(), // ✅ ADDED FIRESTORE STREAM
      builder: (context, firestoreSnapshot) {
        if (firestoreSnapshot.connectionState == ConnectionState.waiting) {
          return LinearProgressIndicator(
            minHeight: isDesktop ? 8.0 : isTablet ? 6.0 : 4.0,
          );
        }
        
        if (!firestoreSnapshot.hasData || !firestoreSnapshot.data!.exists) {
          return _buildErrorCard();
        }
        
        final childData = firestoreSnapshot.data!.data() as Map<String, dynamic>?;
        if (childData == null) {
          return _buildErrorCard();
        }
        
        final childName = childData['name'] ?? 'Unknown Child (${deviceCode.substring(0, 4)}...)';
        final avatarPath = childData['avatarUrl']?.toString(); 
        final childGrade = childData['grade']?.toString().trim();
        final childSection = childData['section']?.toString().trim();
        
        String roomInfo = '';
        if (childGrade?.isNotEmpty == true) {
          roomInfo += childGrade!;
        }
        if (childSection?.isNotEmpty == true) {
          roomInfo += (roomInfo.isNotEmpty ? ' - ' : '') + childSection!;
        }
        if (roomInfo.isEmpty) {
          roomInfo = 'Room Info N/A';
        }

        return StreamBuilder<DatabaseEvent>(
          stream: rtdbInstance.ref('children/$deviceCode').onValue,
          builder: (context, rtdbSnapshot) {
            bool sosActive = false;
            bool isOnline = false;
            int batteryLevel = 0;

            if (rtdbSnapshot.hasData && rtdbSnapshot.data!.snapshot.value != null) {
              final rtdbData = rtdbSnapshot.data!.snapshot.value as Map<dynamic, dynamic>;
              sosActive = rtdbData['sosActive'] == true;
              isOnline = rtdbData['isOnline'] == true;
              batteryLevel = (rtdbData['batteryLevel'] as num?)?.toInt() ?? 0;
            }
            
            final ImageProvider? imageProvider = _getImageProvider(avatarPath);
            final Color avatarBgColor = Theme.of(context).primaryColor.withAlpha(50);

            return _buildChildCard(
              context,
              childName,
              roomInfo,
              sosActive,
              isOnline,
              batteryLevel,
              imageProvider,
              avatarBgColor,
            );
          },
        );
      },
    );
  }

  Widget _buildErrorCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            Icons.person_off,
            size: isDesktop ? 28.0 : isTablet ? 24.0 : 20.0,
          ),
        ),
        title: Text(
          'Device ${deviceCode.substring(0, 4)}...',
          style: TextStyle(
            fontSize: isDesktop ? 16.0 : isTablet ? 15.0 : 14.0,
          ),
        ),
        subtitle: Text(
          'Device data not found.',
          style: TextStyle(
            fontSize: isDesktop ? 14.0 : isTablet ? 13.0 : 12.0,
          ),
        ),
      ),
    );
  }

  Widget _buildChildCard(
    BuildContext context,
    String childName,
    String roomInfo,
    bool sosActive,
    bool isOnline,
    int batteryLevel,
    ImageProvider? imageProvider,
    Color avatarBgColor,
  ) {
    final avatarSize = isDesktop ? 56.0 : isTablet ? 48.0 : 40.0;
    final iconSize = isDesktop ? 24.0 : isTablet ? 20.0 : 16.0;
    final fontSizeTitle = isDesktop ? 18.0 : isTablet ? 16.0 : 14.0;
    final fontSizeSubtitle = isDesktop ? 14.0 : isTablet ? 13.0 : 12.0;

    return Card(
      elevation: sosActive ? 8 : 2,
      margin: EdgeInsets.only(bottom: isDesktop ? 16.0 : isTablet ? 12.0 : 8.0),
      color: sosActive ? Colors.red.shade50 : null,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(isDesktop ? 16.0 : isTablet ? 12.0 : 8.0),
            child: Row(
              children: [
                // Avatar Section
                GestureDetector(
                  onTap: () => _showFullScreenImage(context, childName, imageProvider),
                  child: CircleAvatar(
                    radius: avatarSize,
                    backgroundColor: sosActive ? const Color.fromRGBO(255, 0, 0, 0.4) : avatarBgColor,
                    backgroundImage: imageProvider, 
                    child: imageProvider == null 
                        ? Icon(
                            sosActive ? Icons.warning : Icons.person, 
                            size: avatarSize * 0.6,
                            color: sosActive ? Colors.white : Colors.blueGrey,
                          ) 
                        : sosActive 
                            ? Container(
                                decoration: const BoxDecoration(
                                  color: Color.fromRGBO(255, 0, 0, 0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.warning, color: Colors.white, size: iconSize),
                              )
                            : null,
                  ),
                ),
                
                SizedBox(width: isDesktop ? 16.0 : isTablet ? 12.0 : 8.0),
                
                // Info Section
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        childName,
                        style: TextStyle(
                          fontSize: fontSizeTitle,
                          fontWeight: sosActive ? FontWeight.bold : FontWeight.normal,
                          color: sosActive ? Colors.red : Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: isDesktop ? 8.0 : isTablet ? 6.0 : 4.0),
                      Text(
                        roomInfo,
                        style: TextStyle(
                          fontSize: fontSizeSubtitle,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: isDesktop ? 8.0 : isTablet ? 6.0 : 4.0),
                      _buildStatusInfo(sosActive, isOnline, batteryLevel, fontSizeSubtitle),
                    ],
                  ),
                ),
                
                // Status Chip Section
                _buildStatusChip(sosActive, batteryLevel, fontSizeSubtitle),
              ],
            ),
          ),
          
          // Emergency Border
          if (sosActive)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusInfo(bool sosActive, bool isOnline, int batteryLevel, double fontSize) {
    if (sosActive) {
      return Row(
        children: [
          Icon(Icons.warning, color: Colors.red, size: fontSize),
          SizedBox(width: 4),
          Text(
            'SOS EMERGENCY!',
            style: TextStyle(
              color: Colors.red,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    } else {
      return Row(
        children: [
          Icon(
            Icons.circle,
            color: isOnline ? Colors.green : Colors.red,
            size: fontSize * 0.8,
          ),
          SizedBox(width: 4),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              color: isOnline ? Colors.green : Colors.red,
              fontSize: fontSize,
            ),
          ),
          if (batteryLevel > 0) ...[
            SizedBox(width: 12),
            Icon(Icons.battery_std, color: Colors.grey, size: fontSize),
            SizedBox(width: 2),
            Text(
              '$batteryLevel%',
              style: TextStyle(
                fontSize: fontSize,
                color: batteryLevel < 20 ? Colors.red : Colors.grey,
              ),
            ),
          ],
        ],
      );
    }
  }

  Widget _buildStatusChip(bool sosActive, int batteryLevel, double fontSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Chip(
          label: Text(
            sosActive ? 'EMERGENCY' : 'Safe',
            style: TextStyle(
              color: Colors.white, 
              fontWeight: FontWeight.bold,
              fontSize: fontSize * 0.9,
            ),
          ),
          backgroundColor: sosActive ? Colors.red : Colors.green,
        ),
        if (!sosActive && batteryLevel > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              '$batteryLevel%',
              style: TextStyle(
                fontSize: fontSize * 0.8,
                color: batteryLevel < 20 ? Colors.red : Colors.grey,
              ),
            ),
          ),
      ],
    );
  }
}
