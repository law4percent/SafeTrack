import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/quick_actions_data.dart'; 
import 'quick_action_tile.dart'; 
import '../screens/live_location_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/activity_log_screen.dart';
import '../screens/ask_ai_screen.dart'; 
import '../auth_service.dart';

class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;

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
            
            VoidCallback tileAction; 

            switch (label) {
              case 'Live Location':
                tileAction = () {
                  if (user == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Error: Walay user nga naka-login.')),
                    );
                    return;
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LiveLocationsScreen(),
                    ),
                  );
                };
                break;
                
              case 'Alerts':
                tileAction = () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AlertsScreen()),
                  );
                };
                break;
                
              case 'Ask AI':
                tileAction = () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AskAIScreen()),
                  );
                break;
                
              case 'Activity Log':
                tileAction = () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ActivityLogScreen()),
                  );
                break;
                
              default:
                tileAction = () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label: Action not yet implemented!')),
                  );
                };
            }

            return QuickActionTile(
              icon: action['icon'] as IconData,
              label: label,
              onTap: tileAction, 
            );
          }).toList(),
        ),
      ],
    );
  }
}