/// Mirrors the agent's `GET /api/device` payload (CP 4.5, extended by
/// PLAN V2.13.1 with `pinned_serial`/`default_serial`).
library;

class DeviceStatus {
  const DeviceStatus({
    required this.serial,
    required this.model,
    required this.bridgeReachable,
    required this.mirroring,
    this.pinnedSerial,
    this.defaultSerial,
  });

  final String? serial;
  final String? model;
  final bool bridgeReachable;
  final bool mirroring;

  /// Set only when Settings → Devices has pinned a specific serial —
  /// `null` means the agent is using the pipeline's own default.
  final String? pinnedSerial;

  /// The pipeline's own `ANDROID_SERIAL`, regardless of any pin — shown in
  /// Settings so "pin" always reads as an override, not the only truth.
  final String? defaultSerial;

  static DeviceStatus fromJson(Map<String, dynamic> json) => DeviceStatus(
    serial: json['serial'] as String?,
    model: json['model'] as String?,
    bridgeReachable: json['bridge_reachable'] as bool? ?? false,
    mirroring: json['mirroring'] as bool? ?? false,
    pinnedSerial: json['pinned_serial'] as String?,
    defaultSerial: json['default_serial'] as String?,
  );
}

/// A single `adb devices` entry (`GET /api/device/adb-devices`) — every
/// serial adb currently knows about, online or not.
class AdbDeviceInfo {
  const AdbDeviceInfo({required this.serial, required this.state});

  final String serial;
  final String state;

  static AdbDeviceInfo fromJson(Map<String, dynamic> json) =>
      AdbDeviceInfo(serial: json['serial'] as String? ?? '', state: json['state'] as String? ?? '');
}
