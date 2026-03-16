// lib/services/notification_service.dart

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: initializationSettings);
  }

  static Future<void> showTransferComplete({
    required int fileCount,
    required String deviceName,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'dropix_transfer',
      'File Transfers',
      channelDescription: 'Dropix file transfer notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(
      id: 0,
      title: 'Transfer Complete',
      body: '$fileCount file${fileCount == 1 ? '' : 's'} sent to $deviceName',
      notificationDetails: details,
    );
  }
}
