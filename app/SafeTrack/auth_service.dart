import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get userStream => _auth.authStateChanges();

  Future<void> signUpWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User user = result.user!;

      await _firestore.collection('parents').doc(user.uid).set({
        'name': name,
        'email': email,
        'childDeviceCodes': FieldValue.arrayUnion([]),
        'createdAt': FieldValue.serverTimestamp(),
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
    await _auth.sendPasswordResetEmail(email: email);
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

  Future<Map<String, dynamic>?> getParentData() async {
    if (_auth.currentUser == null) return null;
    
    try {
      final doc = await _firestore.collection('parents').doc(_auth.currentUser!.uid).get();
      return doc.data();
    } catch (e) {
      debugPrint('Error getting parent data: $e');
      return null;
    }
  }
}