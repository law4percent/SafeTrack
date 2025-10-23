import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  SignUpScreenState createState() => SignUpScreenState();
}

class SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // TINANGGAL: final _deviceCodeController = TextEditingController(); 
  bool _showPassword = false;
  bool _isLoading = false;

  Future<void> _signUp() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => _isLoading = true); // Start loading
  
  try {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.signUpWithEmail(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      // TINANGGAL ANG PARAMETER NA CHILDDEVICECODE DITO (Dahil optional na sa AuthService)
    );
        
    // RUN ON SUCCESS: 
    if (!mounted) return;
        
    // 1. Ipakita ang SUCCESS NOTIFICATION
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Sign up successful! You can now log in.'), 
        backgroundColor: Colors.green,
      ),
    );

    // ⭐ ITO ANG FIX: Agad na i-sign out ang user para hindi mag-redirect sa Dashboard.
    await authService.signOut(); 
    // --------------------------------------------------------------------------
        
    // 2. Ibalik sa login screen pagkatapos ng successful sign-up
    // Ngayon, babalik ito sa Login Screen dahil naka-sign out na ang user.
    if (mounted) Navigator.pop(context);

  } catch (e) { 
    // RUN ON FAILURE:
    if (!mounted) return;
    
    // Hinto ang loading state
    setState(() => _isLoading = false); 

    // Magpakita ng ERROR NOTIFICATION
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sign up failed: ${e.toString()}'),
        backgroundColor: Colors.red, 
      ),
    );
  }
  // Kailangan na lang i-set ang _isLoading = false kung sa 'finally' block mo ilalagay
  // Pero okay na rin ang current setup mo dahil nasa catch block na ang pag-set ng false.
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create Account')),
      body: Padding(
        padding: EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                'Sign Up',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 30),
              
              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              
              // Email Field
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
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
              SizedBox(height: 16),
              
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
              SizedBox(height: 16),
              
              // TINANGGAL ANG DEVICE CODE FIELD DITO
              
              // Show Password Checkbox
              Row(
                children: [
                  Checkbox(
                    value: _showPassword,
                    onChanged: (value) {
                      setState(() => _showPassword = value!);
                    },
                  ),
                  Text('Show Password'),
                ],
              ),
              
              SizedBox(height: 24),
              
              // Sign Up Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  child: _isLoading 
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text('SIGN UP'),
                ),
              ),
              
              SizedBox(height: 20),
              
              // Back to Login
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text('Already have an account? Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    // TINANGGAL: _deviceCodeController.dispose();
    super.dispose();
  }
}