import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get userStream => _auth.authStateChanges();

  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User user = result.user!;

      // Store user data in Realtime Database
      await _database.child('users').child(user.uid).set({
        'name': name,
        'email': email,
        'phone': phone,
        'createdAt': ServerValue.timestamp,
      });

      // Initialize empty linked devices list
      await _database.child('linkedDevices').child(user.uid).set({
        'devices': {},
      });
      
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<User?> signInWithEmail(String email, String password) async {
    try {
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      notifyListeners();
      return result.user;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }

  Future<void> resetPassword(String email) async {
    try {
      // Validate email format before sending
      if (email.isEmpty || !email.contains('@')) {
        throw Exception('Invalid email format');
      }
      
      await _auth.sendPasswordResetEmail(email: email);
      debugPrint('✅ Password reset email sent successfully to: $email');
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      
      // Provide user-friendly error messages
      switch (e.code) {
        case 'user-not-found':
          throw Exception('No account found with this email address.');
        case 'invalid-email':
          throw Exception('Invalid email address format.');
        case 'too-many-requests':
          throw Exception('Too many requests. Please try again later.');
        default:
          throw Exception(e.message ?? 'Failed to send password reset email');
      }
    } catch (e) {
      debugPrint('❌ Unexpected error in resetPassword: $e');
      rethrow;
    }
  }

  // ADD THIS NEW METHOD:
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');
      
      if (user.email == null) throw Exception('User email not available');
      
      // Re-authenticate user with current password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      
      await user.reauthenticateWithCredential(credential);
      
      // Update to new password
      await user.updatePassword(newPassword);
      
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUserData() async {
    if (_auth.currentUser == null) return null;
    
    try {
      final snapshot = await _database.child('users').child(_auth.currentUser!.uid).get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting user data: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getLinkedDevices() async {
    if (_auth.currentUser == null) return [];
    
    try {
      final snapshot = await _database.child('linkedDevices').child(_auth.currentUser!.uid).child('devices').get();
      if (snapshot.exists) {
        final devicesMap = Map<String, dynamic>.from(snapshot.value as Map);
        return devicesMap.entries.map((entry) {
          return {
            'deviceId': entry.key,
            ...Map<String, dynamic>.from(entry.value as Map),
          };
        }).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error getting linked devices: $e');
      return [];
    }
  }

  Future<void> addLinkedDevice({
    required String deviceId,
    required String deviceName,
    String? childName,
  }) async {
    if (_auth.currentUser == null) throw Exception('User not logged in');
    
    try {
      await _database
          .child('linkedDevices')
          .child(_auth.currentUser!.uid)
          .child('devices')
          .child(deviceId)
          .set({
        'deviceName': deviceName,
        'childName': childName ?? 'Unknown',
        'addedAt': ServerValue.timestamp,
        'status': 'active',
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> removeLinkedDevice(String deviceId) async {
    if (_auth.currentUser == null) throw Exception('User not logged in');
    
    try {
      await _database
          .child('linkedDevices')
          .child(_auth.currentUser!.uid)
          .child('devices')
          .child(deviceId)
          .remove();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateUserProfile({
    String? name,
    String? phone,
  }) async {
    if (_auth.currentUser == null) throw Exception('User not logged in');
    
    try {
      Map<String, dynamic> updates = {};
      if (name != null) updates['name'] = name;
      if (phone != null) updates['phone'] = phone;
      
      if (updates.isNotEmpty) {
        await _database.child('users').child(_auth.currentUser!.uid).update(updates);
      }
    } catch (e) {
      rethrow;
    }
  }
}