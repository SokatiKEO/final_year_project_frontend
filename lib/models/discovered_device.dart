// lib/models/discovered_device.dart

import 'package:flutter/material.dart';

/// Represents a Dropix device discovered on the local network via mDNS.
class DiscoveredDevice {
  final String id;         // Unique device ID (from mDNS service name)
  final String name;       // Human-readable device name e.g. "John's Pixel 8"
  final String platform;   // "android" | "ios" | "unknown"
  final String host;       // Hostname or IP address
  final int port;          // TCP port the device is listening on
  final DateTime discoveredAt;

  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.host,
    required this.port,
    required this.discoveredAt,
  });

  /// Material icon based on platform
  IconData get platformIcon {
    switch (platform.toLowerCase()) {
      case 'ios':
      case 'android':
        return Icons.smartphone;
      default:
        return Icons.laptop;
    }
  }

  /// How long ago this device was discovered
  String get timeAgo {
    final diff = DateTime.now().difference(discoveredAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoveredDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'DiscoveredDevice($name @ $host:$port)';
}
