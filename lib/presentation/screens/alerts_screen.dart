import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../widgets/alert_card.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, appProvider, _) {
        final alerts = appProvider.alerts;

        return CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.blue[600],
              title: Text(
                '🚨 Alerts (${alerts.length})',
                style: const TextStyle(color: Colors.white),
              ),
              actions: [
                if (alerts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Clear All Alerts?'),
                              content: const Text(
                                  'This action cannot be undone.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    appProvider.clearAlerts();
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (alerts.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 64,
                        color: Colors.green[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Alerts',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The forest is safe. Threats will appear here.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final alert = alerts[index];
                    return AlertCard(
                      alert: alert,
                      onTap: () {
                        appProvider.markAlertAsRead(alert);
                      },
                    );
                  },
                  childCount: alerts.length,
                ),
              ),
          ],
        );
      },
    );
  }
}
