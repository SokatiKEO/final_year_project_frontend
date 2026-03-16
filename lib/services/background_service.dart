// lib/services/background_service.dart
//
// Keeps the transfer alive when the app is backgrounded.
//
// Android : Uses flutter_foreground_task to run a real foreground service
//           with a sticky notification showing live progress.
// iOS     : Uses flutter_background_fetch to periodically refresh and prevent
//           the OS from suspending the process mid-transfer.
// Desktop : No-op — desktop OSes don't kill background processes.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ── Top-level entry point required by flutter_foreground_task ─────────────────
// Must be a top-level function (not a method) so the plugin can call it from
// a separate isolate on Android.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_DropixTaskHandler());
}

class _DropixTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

// ── BackgroundService ─────────────────────────────────────────────────────────

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _isIOS => !kIsWeb && Platform.isIOS;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isAndroid) {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'dropix_transfer',
          channelName: 'Dropix Transfers',
          channelDescription: 'Shown while a file transfer is in progress',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          allowWifiLock: true,
        ),
      );
    }
  }

  // ── Start ─────────────────────────────────────────────────────────────────

  Future<void> startTransfer(String message) async {
    if (_isAndroid) {
      await FlutterForegroundTask.startService(
        serviceId: 1001,
        notificationTitle: 'Dropix',
        notificationText: message,
        callback: startCallback,
      );
    }
    // iOS: the TCP socket keeps the network task alive as long as
    // the app holds an active URLSessionTask / CFSocket. No extra
    // setup is needed beyond declaring the background mode in Info.plist.
  }

  // ── Update notification text ──────────────────────────────────────────────

  Future<void> updateProgress(String message) async {
    if (_isAndroid) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Dropix',
        notificationText: message,
      );
    }
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  Future<void> stopTransfer() async {
    if (_isAndroid) {
      await FlutterForegroundTask.stopService();
    }
  }

  // ── Permissions (Android 13+ requires POST_NOTIFICATIONS) ─────────────────

  Future<void> requestPermissions() async {
    if (_isAndroid) {
      final notifPerm =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notifPerm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    }
  }
}
