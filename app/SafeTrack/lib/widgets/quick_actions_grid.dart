import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/quick_actions_data.dart';
import '../screens/alerts_screen.dart';
import '../screens/activity_log_screen.dart';
import '../screens/ask_ai_screen.dart';
import '../services/auth_service.dart';
import '../screens/dashboard_screen.dart';

class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  VoidCallback _getActionHandler(BuildContext context, String label) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;

    switch (label) {
      case 'Live Location':
        return () {
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
        return () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlertsScreen()),
            );

      case 'Ask AI':
        return () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AskAIScreen()),
            );

      case 'Activity Log':
        return () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
            );

      default:
        return () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label: Action not yet implemented!')),
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10.0),
          child: Text(
            'Quick Actions',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          physics: const NeverScrollableScrollPhysics(),
          children: quickActionsData.map((action) {
            final label = action['label'] as String;
            final icon = action['icon'] as IconData;

            return Card(
              elevation: 2,
              child: InkWell(
                onTap: _getActionHandler(context, label),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 40, color: Colors.blueAccent),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
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
    );
  }
}