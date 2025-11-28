import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';

// Firebase Realtime Database instance
final FirebaseDatabase rtdbInstance = FirebaseDatabase.instance;

class LinkedDevice {
  final String deviceCode;
  final String childName;
  final String? imageProfileBase64;
  final String? yearLevel;
  final String? section;
  final bool deviceEnabled;

  LinkedDevice({
    required this.deviceCode,
    required this.childName,
    this.imageProfileBase64,
    this.yearLevel,
    this.section,
    this.deviceEnabled = true,
  });

  factory LinkedDevice.fromRTDB(String code, Map<dynamic, dynamic> data) {
    return LinkedDevice(
      deviceCode: code,
      childName: data['childName']?.toString() ?? 'Unknown',
      imageProfileBase64: data['imageProfileBase64']?.toString(),
      yearLevel: data['yearLevel']?.toString(),
      section: data['section']?.toString(),
      deviceEnabled: data['deviceEnabled']?.toString().toLowerCase() == 'true',
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
                child: StreamBuilder<DatabaseEvent>(
                  stream: rtdbInstance.ref('linkedDevices').child(user.uid).child('devices').onValue,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                      return _buildEmptyState();
                    }

                    final devicesData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                    final deviceCodes = devicesData.keys.map((key) => key.toString()).toList();

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
              const Icon(Icons.list, color: Colors.blueAccent),
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
              return DeviceCard(deviceCode: deviceCodes[index]);
            },
          ),
        ),
      ],
    );
  }
}

class DeviceCard extends StatelessWidget {
  final String deviceCode;

  const DeviceCard({
    super.key, 
    required this.deviceCode,
  });

  void _removeDevice(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Device?'),
        content: const Text('Are you sure you want to remove this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await authService.removeLinkedDevice(deviceCode);
      
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

  void _editDevice(BuildContext context, LinkedDevice device) async {
    final nameController = TextEditingController(text: device.childName);
    final yearLevelController = TextEditingController(text: device.yearLevel ?? '');
    final sectionController = TextEditingController(text: device.section ?? '');
    String? updatedImageBase64 = device.imageProfileBase64;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (statefulContext, setState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.edit, size: 40, color: Colors.blueAccent),
                  const SizedBox(height: 10),
                  const Text(
                    'Edit Device',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () async {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 512,
                        maxHeight: 512,
                        imageQuality: 85,
                      );
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        setState(() {
                          updatedImageBase64 = base64Encode(bytes);
                        });
                      }
                    },
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundImage: updatedImageBase64 != null && updatedImageBase64!.isNotEmpty
                              ? MemoryImage(base64Decode(updatedImageBase64!))
                              : null,
                          child: updatedImageBase64 == null || updatedImageBase64!.isEmpty
                              ? const Icon(Icons.person, size: 50)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap to change photo',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'CHILD NAME',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: yearLevelController,
                    decoration: const InputDecoration(
                      labelText: 'YEAR LEVEL',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., 8',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: sectionController,
                    decoration: const InputDecoration(
                      labelText: 'SECTION',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., Diamond',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(statefulContext, false),
                          child: const Text('CANCEL'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(statefulContext, true),
                          child: const Text('SAVE'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result != true) {
      nameController.dispose();
      yearLevelController.dispose();
      sectionController.dispose();
      return;
    }

    if (!context.mounted) {
      nameController.dispose();
      yearLevelController.dispose();
      sectionController.dispose();
      return;
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      
      if (user == null) {
        nameController.dispose();
        yearLevelController.dispose();
        sectionController.dispose();
        return;
      }

      await rtdbInstance
          .ref('linkedDevices')
          .child(user.uid)
          .child('devices')
          .child(deviceCode)
          .update({
        'childName': nameController.text.trim(),
        'yearLevel': yearLevelController.text.trim(),
        'section': sectionController.text.trim(),
        'imageProfileBase64': updatedImageBase64 ?? '',
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device updated successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update device: $e')),
        );
      }
    } finally {
      nameController.dispose();
      yearLevelController.dispose();
      sectionController.dispose();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null) return const SizedBox();

    return StreamBuilder<DatabaseEvent>(
      stream: rtdbInstance.ref('linkedDevices').child(user.uid).child('devices').child(deviceCode).onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard();
        }
        
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return _buildOfflineCard(context);
        }

        final deviceData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
        final device = LinkedDevice.fromRTDB(deviceCode, deviceData);
        return _buildDeviceCard(device, context);
      },
    );
  }

  Widget _buildLoadingCard() {
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
        subtitle: const Text('Device not connected'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _removeDevice(context),
        ),
      ),
    );
  }

  Widget _buildDeviceCard(LinkedDevice device, BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // Switch at the top
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: device.deviceEnabled ? Colors.green.shade50 : Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  device.deviceEnabled ? 'Device Enabled' : 'Device Disabled',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: device.deviceEnabled ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                ),
                Switch(
                  value: device.deviceEnabled,
                  onChanged: (value) => _toggleDeviceEnabled(context, value),
                  activeColor: Colors.green,
                ),
              ],
            ),
          ),
          // Device info
          ListTile(
            leading: CircleAvatar(
              radius: 28,
              backgroundImage: device.imageProfileBase64 != null && device.imageProfileBase64!.isNotEmpty
                  ? MemoryImage(base64Decode(device.imageProfileBase64!))
                  : null,
              child: device.imageProfileBase64 == null || device.imageProfileBase64!.isEmpty
                  ? const Icon(Icons.person, size: 30)
                  : null,
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.childName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (device.yearLevel != null && device.yearLevel!.isNotEmpty)
                  Text(
                    'Grade ${device.yearLevel}${device.section != null && device.section!.isNotEmpty ? " - ${device.section}" : ""}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
            subtitle: Text(
              'ID: ${device.deviceCode}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                  onPressed: () => _editDevice(context, device),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: () => _removeDevice(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _toggleDeviceEnabled(BuildContext context, bool value) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    
    if (user == null) return;

    try {
      await rtdbInstance
          .ref('linkedDevices')
          .child(user.uid)
          .child('devices')
          .child(deviceCode)
          .update({
        'deviceEnabled': value.toString(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'Device enabled' : 'Device disabled'),
            backgroundColor: value ? Colors.green : Colors.grey,
          ),
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
}

class AddDeviceDialog extends StatefulWidget {
  final String parentId;
  const AddDeviceDialog({super.key, required this.parentId});

  @override
  AddDeviceDialogState createState() => AddDeviceDialogState();
}

class AddDeviceDialogState extends State<AddDeviceDialog> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _yearLevelController = TextEditingController();
  final _sectionController = TextEditingController();
  bool _isLoading = false;
  String? _imageBase64;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _imageBase64 = base64Encode(bytes);
      });
    }
  }

  Future<void> _linkDevice() async {
    final deviceCode = _codeController.text.trim().toUpperCase();
    final childName = _nameController.text.trim();
    final yearLevel = _yearLevelController.text.trim();
    final section = _sectionController.text.trim();

    if (deviceCode.isEmpty) {
      _showSnackBar('Please enter device code', Colors.orange);
      return;
    }

    if (childName.isEmpty) {
      _showSnackBar('Please enter child name', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      
      if (user == null) throw Exception('User not logged in');

      // Check if device already exists
      final deviceSnapshot = await rtdbInstance
          .ref('linkedDevices')
          .child(user.uid)
          .child('devices')
          .child(deviceCode)
          .get();

      if (deviceSnapshot.exists) {
        if (mounted) setState(() => _isLoading = false);
        _showSnackBar('❌ Device already linked! This device code is already in use.', Colors.red);
        return;
      }

      // Save to Firebase with all fields including initialized deviceStatus
      await rtdbInstance
          .ref('linkedDevices')
          .child(user.uid)
          .child('devices')
          .child(deviceCode)
          .set({
        'childName': childName,
        'yearLevel': yearLevel,
        'section': section,
        'imageProfileBase64': _imageBase64 ?? '',
        'deviceEnabled': 'true',
        'addedAt': ServerValue.timestamp
      });

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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.qr_code_scanner, size: 40, color: Colors.blueAccent),
              const SizedBox(height: 10),
              const Text(
                'Link New Device',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: _imageBase64 != null
                          ? MemoryImage(base64Decode(_imageBase64!))
                          : null,
                      child: _imageBase64 == null
                          ? const Icon(Icons.person, size: 50)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap to add photo',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'DEVICE CODE',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., DEVICE001',
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'CHILD NAME',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Juan',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _yearLevelController,
                decoration: const InputDecoration(
                  labelText: 'YEAR LEVEL',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., 8',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sectionController,
                decoration: const InputDecoration(
                  labelText: 'SECTION',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Diamond',
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                      child: const Text('CANCEL'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _linkDevice,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('LINK DEVICE'),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _yearLevelController.dispose();
    _sectionController.dispose();
    super.dispose();
  }
}