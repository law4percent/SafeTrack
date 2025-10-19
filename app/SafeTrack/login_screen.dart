import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'signup_screen.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _isLoading = false;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (!mounted) return;
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => DashboardScreen()),
      );

    } catch (e) { 
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } 
    finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final isSmallScreen = screenSize.width < 350;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: _getHorizontalPadding(screenSize.width),
              vertical: _getVerticalPadding(screenSize.height),
            ),
            width: double.infinity,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: screenSize.height - MediaQuery.of(context).padding.vertical,
              ),
              child: IntrinsicHeight(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Logo Section
                      _buildLogoSection(screenSize),
                      
                      SizedBox(height: _getSpacing(screenSize.height)),
                      
                      // Form Section
                      _buildFormSection(screenSize, isSmallScreen),
                      
                      SizedBox(height: _getSpacing(screenSize.height)),
                      
                      // Login Button
                      _buildLoginButton(screenSize),
                      
                      SizedBox(height: _getSpacing(screenSize.height)),
                      
                      // Divider
                      _buildDivider(screenSize),
                      
                      SizedBox(height: _getSmallSpacing(screenSize.height)),
                      
                      // Sign Up Section
                      _buildSignUpSection(),
                      
                      // Add flexible space at the bottom for small screens
                      if (screenSize.height < 600) Expanded(child: Container()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection(Size screenSize) {
    return Column(
      children: [
        Text(
          'SafeTrack',
          style: TextStyle(
            fontSize: _getTitleSize(screenSize.width),
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        SizedBox(height: _getSmallSpacing(screenSize.height)),
        Text(
          'Student Safety',
          style: TextStyle(
            fontSize: _getSubtitleSize(screenSize.width),
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildFormSection(Size screenSize, bool isSmallScreen) {
    return Column(
      children: [
        // Email Field
        TextFormField(
          controller: _emailController,
          decoration: InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email),
            contentPadding: isSmallScreen 
                ? EdgeInsets.symmetric(vertical: 12, horizontal: 12)
                : null,
          ),
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your email';
            }
            if (!value.contains('@')) {
              return 'Please enter a valid email';
            }
            return null;
          },
        ),
        SizedBox(height: _getFieldSpacing(screenSize.height)),
        
        // Password Field
        TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
              onPressed: () {
                setState(() => _showPassword = !_showPassword);
              },
            ),
            contentPadding: isSmallScreen 
                ? EdgeInsets.symmetric(vertical: 12, horizontal: 12)
                : null,
          ),
          obscureText: !_showPassword,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your password';
            }
            if (value.length < 6) {
              return 'Password must be at least 6 characters';
            }
            return null;
          },
        ),
        SizedBox(height: _getFieldSpacing(screenSize.height)),
        
        // Show Password & Forgot Password Row
        _buildPasswordOptionsRow(screenSize),
      ],
    );
  }

  Widget _buildPasswordOptionsRow(Size screenSize) {
    return Row(
      children: [
        // Show Password Checkbox
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _showPassword,
                onChanged: (value) {
                  setState(() => _showPassword = value!);
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Flexible(
                child: Text(
                  'Show Password',
                  style: TextStyle(fontSize: _getSmallTextSize(screenSize.width)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        
        Spacer(),
        
        // Forgot Password
        TextButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Reset Password'),
                content: Text('Enter your email to reset password'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text('Send'),
                  ),
                ],
              ),
            );
          },
          child: Text(
            'Forgot Password?',
            style: TextStyle(fontSize: _getSmallTextSize(screenSize.width)),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton(Size screenSize) {
    return SizedBox(
      width: double.infinity,
      height: _getButtonHeight(screenSize.height),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        child: _isLoading 
            ? SizedBox(
                width: _getLoaderSize(screenSize.width),
                height: _getLoaderSize(screenSize.width),
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Text(
                'LOGIN',
                style: TextStyle(fontSize: _getButtonTextSize(screenSize.width)),
              ),
      ),
    );
  }

  Widget _buildDivider(Size screenSize) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            thickness: 1,
            color: Colors.grey.shade300,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _getSmallSpacing(screenSize.height)),
          child: Text(
            'or',
            style: TextStyle(
              color: Colors.grey,
              fontSize: _getSmallTextSize(screenSize.width),
            ),
          ),
        ),
        Expanded(
          child: Divider(
            thickness: 1,
            color: Colors.grey.shade300,
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account?",
          style: TextStyle(fontSize: _getSmallTextSize(MediaQuery.of(context).size.width)),
        ),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => SignUpScreen()),
            );
          },
          child: Text('Sign up'),
        ),
      ],
    );
  }

  // Responsive sizing methods
  double _getHorizontalPadding(double screenWidth) {
    if (screenWidth < 350) return 16;
    if (screenWidth < 600) return 24;
    if (screenWidth < 900) return 32;
    return 48;
  }

  double _getVerticalPadding(double screenHeight) {
    if (screenHeight < 600) return 16;
    if (screenHeight < 800) return 24;
    if (screenHeight < 1000) return 32;
    return 40;
  }

  double _getSpacing(double screenHeight) {
    if (screenHeight < 600) return 20;
    if (screenHeight < 800) return 24;
    return 30;
  }

  double _getSmallSpacing(double screenHeight) {
    if (screenHeight < 600) return 8;
    if (screenHeight < 800) return 10;
    return 12;
  }

  double _getFieldSpacing(double screenHeight) {
    if (screenHeight < 600) return 12;
    if (screenHeight < 800) return 16;
    return 20;
  }

  double _getTitleSize(double screenWidth) {
    if (screenWidth < 350) return 28;
    if (screenWidth < 600) return 32;
    return 36;
  }

  double _getSubtitleSize(double screenWidth) {
    if (screenWidth < 350) return 14;
    if (screenWidth < 600) return 16;
    return 18;
  }

  double _getButtonTextSize(double screenWidth) {
    if (screenWidth < 350) return 14;
    if (screenWidth < 600) return 16;
    return 18;
  }

  double _getSmallTextSize(double screenWidth) {
    if (screenWidth < 350) return 12;
    if (screenWidth < 600) return 14;
    return 16;
  }

  double _getButtonHeight(double screenHeight) {
    if (screenHeight < 600) return 45;
    if (screenHeight < 800) return 50;
    return 55;
  }

  double _getLoaderSize(double screenWidth) {
    if (screenWidth < 350) return 16;
    if (screenWidth < 600) return 18;
    return 20;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}