# Dropix — mDNS Device Discovery

Cross-platform AirDrop alternative built with Flutter.

## Project Structure

```
lib/
├── main.dart                        # App entry point
├── models/
│   └── discovered_device.dart       # Device data model
├── services/
│   └── discovery_service.dart       # Core mDNS logic (singleton)
├── providers/
│   └── discovery_provider.dart      # State management (ChangeNotifier)
└── screens/
    └── home_screen.dart             # UI wired to discovery
```

## How It Works

```
Your Device                          Other Device
    │                                     │
    ├─ register("uuid|DeviceName"         │
    │   _dropix._tcp port:49152)          │
    │                                     ├─ register(...)
    │                                     │
    ├─ startDiscovery(_dropix._tcp) ──────┤
    │         ← ServiceStatus.found ──────┤
    │                                     │
    ├─ resolve host + port                │
    ├─ add to devices list               │
    └─ notify UI                         │
```

## Setup

### 1. Install dependencies
```bash
flutter pub get
```

### 2. Android permissions
Already configured in `android/app/src/main/AndroidManifest.xml`:
- `INTERNET`
- `ACCESS_WIFI_STATE`
- `CHANGE_WIFI_MULTICAST_STATE` ← critical for mDNS multicast packets

### 3. iOS permissions
Already configured in `ios/Runner/Info.plist`:
- `NSLocalNetworkUsageDescription` ← triggers permission dialog on iOS 14+
- `NSBonjourServices: [_dropix._tcp]` ← required or iOS blocks mDNS

### 4. Run
```bash
flutter run
```

## Key Files Explained

### `discovery_service.dart`
The core singleton. Does two things simultaneously:
- **Registers** this device: `register(Service(name, type, port, txt))`
- **Discovers** others: `startDiscovery(_kServiceType)` and listens for `ServiceStatus.found` / `ServiceStatus.lost`

Service name format: `"<uuid>|<deviceName>"` — encodes both ID and display name into one field.

### `discovery_provider.dart`
Wraps `DiscoveryService` as a `ChangeNotifier`. The UI calls:
- `provider.startScanning()` — begin
- `provider.stopScanning()` — stop
- `provider.refresh()` — restart (pull-to-refresh)
- `provider.devices` — current list

### `home_screen.dart`
Consumes `DiscoveryProvider` via `Consumer<DiscoveryProvider>`. Rebuilds automatically as devices appear/disappear.

## mDNS Service Details

| Property | Value |
|---|---|
| Service type | `_dropix._tcp` |
| Port | `49152` |
| TXT: platform | `android` / `ios` |
| TXT: v | `1` (protocol version) |

## Next Steps
- [ ] File picker screen (send files to selected device)
- [ ] TCP socket server on port 49152 to receive files
- [ ] WebRTC data channel for large file transfers
- [ ] Transfer progress screen
