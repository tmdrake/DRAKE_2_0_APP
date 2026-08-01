import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Nordic UART Service UUIDs — matches TMDrake_tail firmware.
final Guid nusServiceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
final Guid nusRxUuid = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // app → tail (write)
final Guid nusTxUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // tail → app (notify)

const String targetDeviceName = 'TMDrake_tail';

/// Contract + app version strings (shown in About).
const String appVersionLabel = '0.3.1';
const String contractVersionLabel = 'APP_INTERFACE v2.0';

/// Heartbeat interval while linked (requirement: 2–5 s).
/// Slightly under 3s so we get multiple HB chances before STALE.
const Duration hbInterval = Duration(seconds: 2);

/// Soft STALE: no RX for this long → mark STALE, keep pipe, resend HB.
const Duration hbackStaleTimeout = Duration(seconds: 12);

/// Hard reconnect only after this much silence (avoids thrash on blips).
const Duration hbackHardReconnectTimeout = Duration(seconds: 22);

/// Scan timeout when actively searching.
const Duration scanTimeout = Duration(seconds: 14);

/// Pause after GATT connect before discoverServices (Android stack settle).
const Duration gattSettleDelay = Duration(milliseconds: 450);

/// Min gap between reconnect attempts (anti GATT-133 thrash).
const Duration reconnectMinGap = Duration(seconds: 2);
