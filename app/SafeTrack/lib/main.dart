import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart'; // ADD THIS
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // 🔥 ADD REALTIME DATABASE CONFIGURATION
  _initializeRealtimeDatabase();
  
  runApp(MyApp());
}

// 🔥 NEW METHOD: Initialize Realtime Database
void _initializeRealtimeDatabase() {
  try {
    // Set your Realtime Database URL
    FirebaseDatabase database = FirebaseDatabase.instance;
    
    // Enable persistence for offline support
    database.setPersistenceEnabled(true);
    database.setPersistenceCacheSizeBytes(10000000); // 10MB
    
    debugPrint("✅ Realtime Database initialized successfully");
  } catch (e) {
    debugPrint("❌ Error initializing Realtime Database: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AuthService(),
      child: MaterialApp(
        title: 'ProtectID - Child Safety',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});
  
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    
    return StreamBuilder<User?>(
      stream: authService.userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (snapshot.hasData && snapshot.data != null) {
          return DashboardScreen();
        }
        
        return LoginScreen();
      },
    );
  }
}
