import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  bool _isLoading = false;
  final List<Map<String, dynamic>> _sampleActivities = [
    {
      'type': 'arrival',
      'locationName': 'Home',
      'deviceNickname': 'Child 1',
      'timestamp': DateTime.now().subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
      'locationType': 'HOME',
    },
    {
      'type': 'arrival',
      'locationName': 'Elementary School',
      'deviceNickname': 'Child 2',
      'timestamp': DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
      'locationType': 'SCHOOL',
    },
    {
      'type': 'arrival', 
      'locationName': 'Home',
      'deviceNickname': 'Child 1',
      'timestamp': DateTime.now().subtract(const Duration(hours: 5)).millisecondsSinceEpoch,
      'locationType': 'HOME',
    },
  ];

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });

    // Simulate loading delay
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _isLoading = false;
    });
  }

  void _handleRefreshButton() {
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Log'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _handleRefreshButton,
            tooltip: 'Refresh Activities',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info Card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.family_restroom, color: Colors.blue[800], size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Sample Activities',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                '${_sampleActivities.length} sample activities',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Demo mode',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Activities List
                Expanded(
                  child: _sampleActivities.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No activities yet',
                                style: TextStyle(color: Colors.grey, fontSize: 16),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Activities will appear here automatically',
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refreshData,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _sampleActivities.length,
                            itemBuilder: (context, index) {
                              final activity = _sampleActivities[index];
                              return _buildActivityItem(activity, index);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> activity, int index) {
    final arrivalTime = DateTime.fromMillisecondsSinceEpoch(activity['timestamp']);
    final timeString = DateFormat('MMM dd, yyyy • h:mm a').format(arrivalTime);
    final isSchool = activity['locationType'] == 'SCHOOL';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSchool ? Colors.blue[100] : Colors.green[100],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            isSchool ? Icons.school : Icons.home,
            color: isSchool ? Colors.blue : Colors.green,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Arrived at ${activity['locationName']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              activity['deviceNickname'],
              style: TextStyle(
                color: Colors.blue[700],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        subtitle: Text(timeString),
        trailing: Text(
          isSchool ? '🏫' : '🏠',
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}