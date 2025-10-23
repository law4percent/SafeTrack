import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../auth_service.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'package:image_picker/image_picker.dart'; 
import 'dart:io'; 
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

// ======================================================
// 🚨 RTDB SETUP
// ======================================================
const String firebaseRtdbUrl = 'https://protectid-f04a3-default-rtdb.asia-southeast1.firebasedatabase.app';

final FirebaseDatabase rtdbInstance = FirebaseDatabase.instanceFor(
  app: Firebase.app(),
  databaseURL: firebaseRtdbUrl,
);
// ======================================================

class LinkedDevice {
  final String deviceCode;
  final String nickname;
  final String? avatarPath;
  final String? grade;
  final String? section;
  final String? name;

  LinkedDevice({
    required this.deviceCode,
    required this.nickname,
    this.avatarPath,
    this.grade,
    this.section,
    this.name,
  });

  factory LinkedDevice.fromFirestore(String code, Map<String, dynamic> data) {
    return LinkedDevice(
      deviceCode: code,
      nickname: data['nickname']?.toString() ?? 'Device ${code.substring(0, 4)}',
      name: data['name']?.toString(),
      avatarPath: data['avatarUrl'],
      grade: data['grade']?.toString(),
      section: data['section']?.toString(),
    );
  }
}

class MyChildrenScreen extends StatelessWidget {
  const MyChildrenScreen({super.key});

  void _showAddDeviceDialog(BuildContext context) {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null) return;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AddDeviceDialog(parentId: user.uid);
      },
    );
  }

  void _updateDevice(BuildContext context, String deviceCode, Map<String, dynamic> updateData) async {
    try {
      await FirebaseFirestore.instance
          .collection('children')
          .doc(deviceCode)
          .update(updateData);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device information updated successfully!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update device: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Devices')),
        body: const Center(child: Text('Please log in first')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Devices', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blueAccent, Colors.lightBlueAccent],
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: const Column(
                children: [
                  Icon(Icons.devices, size: 60, color: Colors.white),
                  SizedBox(height: 10),
                  Text(
                    'Linked Devices',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Manage your connected safety devices',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('parents').doc(user.uid).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return _buildEmptyState();
                    }

                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    final deviceCodes = (data?['childDeviceCodes'] as List<dynamic>?)?.cast<String>() ?? [];

                    if (deviceCodes.isEmpty) {
                      return _buildEmptyState();
                    }
                    return _buildDeviceList(deviceCodes);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDeviceDialog(context),
        backgroundColor: Colors.white,
        foregroundColor: Colors.blueAccent,
        elevation: 4,
        icon: const Icon(Icons.add),
        label: const Text('LINK DEVICE', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 20),
            Text(
              'No Devices Linked',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tap the LINK DEVICE button below\nto connect your first safety device',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(List<String> deviceCodes) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.list, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text(
                'Connected Devices (${deviceCodes.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: deviceCodes.length,
            itemBuilder: (context, index) {
              return DeviceCard(
                deviceCode: deviceCodes[index],
                onUpdate: (data) => _updateDevice(context, deviceCodes[index], data),
              );
            },
          ),
        ),
      ],
    );
  }
}

class DeviceCard extends StatelessWidget {
  final String deviceCode;
  final Function(Map<String, dynamic> updateData) onUpdate;

  const DeviceCard({
    super.key, 
    required this.deviceCode,
    required this.onUpdate,
  });

  void _removeDevice(BuildContext context) async {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Device?'),
        content: const Text('Are you sure you want to remove this device? This will unlink it from your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('parents').doc(user.uid).update({
        'childDeviceCodes': FieldValue.arrayRemove([deviceCode]),
      });

      await FirebaseFirestore.instance.collection('children').doc(deviceCode).update({
        'parentId': FieldValue.delete(),
      });

      // ✅ FIXED: USE null INSTEAD OF FieldValue.delete() FOR RTDB
      try {
        await rtdbInstance.ref('children/$deviceCode').update({
          'parentId': null,
        });
        debugPrint('✅ RTDB parentId removed for $deviceCode');
      } catch (rtdbError) {
        debugPrint('⚠️ RTDB parentId removal warning: $rtdbError');
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device removed successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove device: $e')),
        );
      }
    }
  }

  void _showEditDialog(BuildContext context, LinkedDevice device) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return _EditDeviceDialog(
          device: device,
          onUpdate: onUpdate,
        );
      },
    );
  }

  void _showFullScreenImage(BuildContext context, LinkedDevice device) {
    final ImageProvider? imageProvider = _getImageProvider(device);
    
    if (imageProvider == null) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
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
                              return const Icon(Icons.error, color: Colors.white, size: 50);
                            },
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        device.nickname,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  ImageProvider? _getImageProvider(LinkedDevice device) {
    if (device.avatarPath != null && !device.avatarPath!.startsWith('http')) {
      final File localFile = File(device.avatarPath!);
      if (localFile.existsSync()) {
        return FileImage(localFile);
      }
    } else if (device.avatarPath != null && device.avatarPath!.startsWith('http')) {
      return NetworkImage(device.avatarPath!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('children').doc(deviceCode).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard(context);
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildOfflineCard(context);
        }

        final deviceData = snapshot.data!.data() as Map<String, dynamic>?;
        if (deviceData == null) {
          return _buildOfflineCard(context);
        }

        final device = LinkedDevice.fromFirestore(deviceCode, deviceData);
        return _buildDeviceCard(device, context);
      },
    );
  }

  Widget _buildLoadingCard(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey.shade200,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text(deviceCode, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Loading device information...'),
      ),
    );
  }

  Widget _buildOfflineCard(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.grey,
          child: Icon(Icons.device_unknown, color: Colors.white),
        ),
        title: Text(deviceCode, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Device not connected or offline'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _removeDevice(context),
        ),
      ),
    );
  }

  Widget _buildDeviceCard(LinkedDevice device, BuildContext context) {
    final ImageProvider? imageProvider = _getImageProvider(device);
    final avatarBgColor = Theme.of(context).primaryColor.withAlpha(50);

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: GestureDetector(
          onTap: () => _showFullScreenImage(context, device),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: avatarBgColor,
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? const Icon(Icons.person, size: 30, color: Colors.blueGrey)
                : null,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.nickname,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (device.name != null && device.name!.isNotEmpty)
              Text(
                device.name!,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (device.grade != null && device.grade!.isNotEmpty)
              Text(
                'Grade ${device.grade}${device.section != null ? ' - ${device.section}' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 2),
            Text(
              'ID: ${device.deviceCode}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
              tooltip: 'Edit Device Info',
              onPressed: () => _showEditDialog(context, device),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: () => _removeDevice(context),
              tooltip: 'Remove device',
            ),
          ],
        ),
      ),
    );
  }
}

class _EditDeviceDialog extends StatefulWidget {
  final LinkedDevice device;
  final Function(Map<String, dynamic> updateData) onUpdate;

  const _EditDeviceDialog({
    required this.device,
    required this.onUpdate,
  });

  @override
  _EditDeviceDialogState createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<_EditDeviceDialog> {
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _sectionController = TextEditingController();

  File? _pickedImageFile; 
  String? _currentAvatarPath; 

  @override
  void initState() {
    super.initState();
    _nicknameController.text = widget.device.nickname;
    _nameController.text = widget.device.name ?? '';
    _gradeController.text = widget.device.grade ?? '';
    _sectionController.text = widget.device.section ?? '';
    _currentAvatarPath = widget.device.avatarPath; 
  }

  Future<String?> _copyImageLocally() async {
    if (_pickedImageFile == null) {
      return null;
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = path.basename(_pickedImageFile!.path);
      final uniqueFileName = '${widget.device.deviceCode}_$fileName';
      final savedImage = File('${appDir.path}/$uniqueFileName');
      
      final File copiedFile = await _pickedImageFile!.copy(savedImage.path);
      
      return copiedFile.path;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save photo locally: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 600); 

    if (pickedFile != null) {
      setState(() {
        _pickedImageFile = File(pickedFile.path);
        _currentAvatarPath = null;
      });
      if(mounted) Navigator.of(context).pop(); 
    }
  }

  void _saveChanges() async {
    final newNickname = _nicknameController.text.trim();
    final newName = _nameController.text.trim();
    final newGrade = _gradeController.text.trim();
    final newSection = _sectionController.text.trim();
    
    if (newNickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a nickname')),
      );
      return;
    }

    String? finalAvatarPath;
    if (_pickedImageFile != null) {
      finalAvatarPath = await _copyImageLocally();
      if (finalAvatarPath == null) return;
    } else {
      finalAvatarPath = _currentAvatarPath;
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    final Map<String, dynamic> updates = {
      'nickname': newNickname,
      'name': newName.isNotEmpty ? newName : FieldValue.delete(),
      'grade': newGrade.isNotEmpty ? newGrade : FieldValue.delete(),
      'section': newSection.isNotEmpty ? newSection : FieldValue.delete(),
      'avatarUrl': finalAvatarPath?.isNotEmpty == true
        ? finalAvatarPath
        : FieldValue.delete(),
      'lastUpdated': FieldValue.serverTimestamp(), // ✅ ADDED FOR SYNC
    };
    
    widget.onUpdate(updates);
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    if (_pickedImageFile != null) {
      imageProvider = FileImage(_pickedImageFile!);
    } 
    else if (_currentAvatarPath != null && !_currentAvatarPath!.startsWith('http')) {
        final File existingFile = File(_currentAvatarPath!);
        if (existingFile.existsSync()) {
            imageProvider = FileImage(existingFile);
        }
    }
    else if (_currentAvatarPath != null && _currentAvatarPath!.startsWith('http')) {
        imageProvider = NetworkImage(_currentAvatarPath!);
    }
    
    return AlertDialog(
      title: const Text('Edit Device Info'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: imageProvider != null 
                        ? () => _showFullScreenImagePreview(context, imageProvider!)
                        : null,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Theme.of(context).primaryColor.withAlpha(50),
                      backgroundImage: imageProvider,
                      child: imageProvider == null
                          ? const Icon(Icons.person, size: 50, color: Colors.blueGrey)
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.camera_alt, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                      ),
                      onPressed: () => _showImageSourceSheet(context), 
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: 'Nickname *',
                hintText: 'e.g., "My Child\'s Device"',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name (Optional)',
                hintText: 'e.g., "Juan Dela Cruz"',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _gradeController,
              decoration: const InputDecoration(
                labelText: 'Grade Level (Optional)',
                hintText: 'e.g., "Grade 7"',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _sectionController,
              decoration: const InputDecoration(
                labelText: 'Section (Optional)',
                hintText: 'e.g., "Mabini"',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            if (_pickedImageFile != null || _currentAvatarPath != null)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _pickedImageFile = null; 
                    _currentAvatarPath = null;
                  });
                },
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('Remove Current Photo', style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          onPressed: _saveChanges, 
          child: const Text('Save Changes'),
        ),
      ],
    );
  }

  void _showFullScreenImagePreview(BuildContext context, ImageProvider imageProvider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              Container(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black87,
                ),
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 3.0,
                  child: Center(
                    child: Image(
                      image: imageProvider,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.error, color: Colors.white, size: 50);
                      },
                    ),
                  ),
                ),
              ),
              
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _showImageSourceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take a Photo'),
                onTap: () {
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class AddDeviceDialog extends StatefulWidget {
  final String parentId;
  const AddDeviceDialog({super.key, required this.parentId});

  @override
  AddDeviceDialogState createState() => AddDeviceDialogState();
}

class AddDeviceDialogState extends State<AddDeviceDialog> {
  final _codeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _linkDevice() async {
    final deviceCode = _codeController.text.trim().toUpperCase();

    if (deviceCode.isEmpty) {
      _showSnackBar('Please enter device code', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. CHECK IF DEVICE EXISTS IN FIRESTORE
      final deviceDoc = await FirebaseFirestore.instance
          .collection('children')
          .doc(deviceCode)
          .get();

      if (deviceDoc.exists) {
        final existingData = deviceDoc.data() ?? {};
        final existingParentId = existingData['parentId']?.toString() ?? '';
        
        if (existingParentId.isNotEmpty && existingParentId != widget.parentId) {
          throw Exception('Device "$deviceCode" is already linked to another parent account.');
        }

        if (existingParentId == widget.parentId) {
          throw Exception('Device "$deviceCode" is already linked to your account.');
        }
      }

      // 2. CHECK IF DEVICE EXISTS IN RTDB
      final rtdbSnapshot = await rtdbInstance.ref('children/$deviceCode').get();
      if (!rtdbSnapshot.exists) {
        throw Exception('Device "$deviceCode" not found in RTDB. Make sure device is active and sending data.');
      }

      final batch = FirebaseFirestore.instance.batch();
      final parentRef = FirebaseFirestore.instance.collection('parents').doc(widget.parentId);
      final childRef = FirebaseFirestore.instance.collection('children').doc(deviceCode);

      // 3. UPDATE FIRESTORE
      batch.update(parentRef, {
        'childDeviceCodes': FieldValue.arrayUnion([deviceCode]),
      });

      final childData = {
        'deviceCode': deviceCode,
        'parentId': widget.parentId,
        'nickname': 'Device ${deviceCode.substring(0, 4)}',
        'linkedAt': FieldValue.serverTimestamp(),
        'name': null,
        'grade': null,
        'section': null,
        'avatarUrl': null,
      };

      batch.set(childRef, childData, SetOptions(merge: true));
      await batch.commit();

      // 4. ✅ CRITICAL: UPDATE RTDB WITH SAME PARENTID
      try {
        await rtdbInstance.ref('children/$deviceCode').update({
          'parentId': widget.parentId
        });
        
        debugPrint('✅ RTDB PARENTID UPDATED: $deviceCode → ${widget.parentId}');
        
        // Verify the update
        final verifySnapshot = await rtdbInstance.ref('children/$deviceCode/parentId').get();
        debugPrint('✅ RTDB VERIFICATION: parentId = ${verifySnapshot.value}');
        
      } catch (rtdbError) {
        debugPrint('❌ RTDB UPDATE FAILED: $rtdbError');
        throw Exception('Device linked but RTDB update failed. Live tracking may not work.');
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnackBar('✅ Successfully linked device: $deviceCode', Colors.green);

    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showSnackBar('❌ Failed to link device: ${e.toString()}', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.qr_code_scanner, size: 40, color: Colors.blueAccent),
                  SizedBox(height: 10),
                  Text(
                    'Link New Device',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Enter the device code from your safety device',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: 'DEVICE CODE',
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blueAccent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                ),
                hintText: 'e.g., DEVICE001',
                prefixIcon: const Icon(Icons.security, color: Colors.blueAccent),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            
            const SizedBox(height: 10),
            
            const Text(
              'Find the device code on your safety device or its packaging',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            
            const SizedBox(height: 24),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Colors.grey),
                    ),
                    child: const Text(
                      'CANCEL',
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _linkDevice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'LINK DEVICE',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}