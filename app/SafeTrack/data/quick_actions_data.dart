import 'package:flutter/material.dart';

// Ito ang central source ng data para sa Quick Actions
const List<Map<String, dynamic>> quickActionsData = [
  {
    'icon': Icons.location_on,
    'label': 'Live Location',
    'route': '/liveLocation', // Gagamitin ang route name na ito
  },
  {
    'icon': Icons.notifications_active,
    'label': 'Alerts',
    'route': '/alerts',
  },
  {
    'icon': Icons.question_answer,
    'label': 'Ask AI',
    'route': '/askAi',
  },
  {
    'icon': Icons.history,
    'label': 'Activity Log',
    'route': '/activityLog',
  },
];