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

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

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

  static Future<void> showIncomingRequest({
    required String deviceName,
    required int fileCount,
  }) async {
    if (kIsWeb) return;

    final fileWord = fileCount == 1 ? '1 file' : '$fileCount files';
    final title = '$deviceName wants to send $fileWord';
    const body = 'Open Dropix to accept or decline.';

    if (Platform.isWindows || Platform.isLinux) {
      final notification = LocalNotification(title: title, body: body);
      await notification.show();
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'dropix_incoming',
      'Incoming Transfers',
      channelDescription: 'Notifications when a device wants to send files',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      id: 1,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
