// app/SafeTrack/lib/widgets/quick_actions_grid.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/quick_actions_data.dart';
import '../screens/alerts_screen.dart';
import '../screens/activity_log_screen.dart';
import '../screens/ask_ai_screen.dart';
import '../services/auth_service.dart';
import '../screens/dashboard_screen.dart';

class QuickActionsGrid extends StatefulWidget {
  const QuickActionsGrid({super.key});

  @override
  State<QuickActionsGrid> createState() => _QuickActionsGridState();
}

class _QuickActionsGridState extends State<QuickActionsGrid> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  VoidCallback _getActionHandler(BuildContext context, String label) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;

    switch (label) {
      case 'Live Location':
        return () {
          _toggleExpanded();
          if (user == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please log in first')),
            );
            return;
          }

          final dashboardState = context.findAncestorStateOfType<DashboardScreenState>();
          dashboardState?.setCurrentIndex(1);
        };

      case 'Alerts':
        return () {
          _toggleExpanded();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AlertsScreen()),
          );
        };

      case 'Ask AI':
        return () {
          _toggleExpanded();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AskAIScreen()),
          );
        };

      case 'Activity Log':
        return () {
          _toggleExpanded();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
          );
        };

      default:
        return () {
          _toggleExpanded();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label: Action not yet implemented!')),
          );
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Backdrop overlay when expanded
        if (_isExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleExpanded,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  color: Colors.black26,
                ),
              ),
            ),
          ),

        // Floating button and expanded grid
        Positioned(
          bottom: 16,
          right: 16,
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return _isExpanded
                  ? _buildExpandedGrid(context)
                  : _buildCollapsedButton(context);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedButton(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _toggleExpanded,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade600, Colors.blue.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.dashboard, color: Colors.white, size: 28),
              SizedBox(height: 2),
              Text(
                'Quick',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedGrid(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final gridWidth = screenWidth > 600 ? 400.0 : screenWidth * 0.85;
    
    return ScaleTransition(
      scale: _scaleAnimation,
      alignment: Alignment.bottomRight,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: gridWidth,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _toggleExpanded,
                      splashRadius: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.1,
                  children: quickActionsData.map((action) {
                    final label = action['label'] as String;
                    final icon = action['icon'] as IconData;

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: _getActionHandler(context, label),
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 36, color: Colors.blueAccent),
                            const SizedBox(height: 8),
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}