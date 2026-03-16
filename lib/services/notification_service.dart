// lib/services/notification_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (kIsWeb) return;

    if (Platform.isWindows || Platform.isLinux) {
      await localNotifier.setup(appName: 'Dropix');
      return;
    }

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: initializationSettings);

    // Request permission — Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Request permission — iOS
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // Request permission — macOS
    await _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> showTransferComplete({
    required int fileCount,
    required String deviceName,
    required bool isSend,
  }) async {
    if (kIsWeb) return;

    final title = isSend ? 'Transfer Complete' : 'Files Received';
    final fileWord = '$fileCount file${fileCount == 1 ? '' : 's'}';
    final body = isSend
        ? '$fileWord sent to $deviceName'
        : '$fileWord received from $deviceName';

    if (Platform.isWindows || Platform.isLinux) {
      final notification = LocalNotification(title: title, body: body);
      await notification.show();
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'dropix_transfer',
      'File Transfers',
      channelDescription: 'Dropix file transfer notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      id: 0,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}