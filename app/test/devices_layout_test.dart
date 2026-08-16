import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/device_models.dart';
import 'package:ia_control_center/core/pairing_models.dart';
import 'package:ia_control_center/features/live/device_bar.dart';
import 'package:ia_control_center/features/settings/devices_controller.dart';
import 'package:ia_control_center/features/settings/devices_tab.dart';

/// Overflow is a paint-time error `flutter analyze` is blind to (D19's
/// precedent). The real risks here: a long phone display name in the paired
/// devices list (the phone, not this app, chooses that string — CP 6.1's
/// `claim()` only trims it), and the QR/code split row at the app's 1024px
/// minimum window.
class _FakeDevicesController extends DevicesController {
  _FakeDevicesController(this._devices, {this.code});
  final List<PairedDevice> _devices;
  final PairingCode? code;

  @override
  Future<List<PairedDevice>> build() async => _devices;

  @override
  Future<PairingCode> startPairing() async => code!;
}

/// PLAN V2.13.1's device-identity card (`_DeviceIdentityCard`) — a real
/// `DeviceController` override so pinning actually mutates the state the
/// card reads, the same way `live_layout_test.dart`'s own fake does, rather
/// than a real dio call hitting nothing in a test environment.
class _FakeDeviceController extends DeviceController {
  _FakeDeviceController(this._status);
  DeviceStatus _status;
  String? lastPinned;
  int pinCalls = 0;

  @override
  Future<DeviceStatus> build() async => _status;

  @override
  Future<void> setPinnedSerial(String? serial) async {
    lastPinned = serial;
    pinCalls++;
    _status = DeviceStatus(
      serial: serial ?? _status.defaultSerial,
      model: serial == null ? _status.model : null,
      bridgeReachable: _status.bridgeReachable,
      mirroring: _status.mirroring,
      pinnedSerial: serial,
      defaultSerial: _status.defaultSerial,
    );
    state = AsyncData(_status);
  }
}

void main() {
  testWidgets('DevicesTab lays out without overflow: a 60-char device name and several devices', (tester) async {
    final longName = 'a_very_long_phone_display_name_that_keeps_going_60c';
    final devices = [
      PairedDevice(id: '1', name: longName, createdAt: DateTime(2026, 7, 1), lastSeen: DateTime.now()),
      PairedDevice(id: '2', name: 'Pixel 7', createdAt: DateTime(2026, 6, 1), lastSeen: DateTime(2026, 1, 1)),
    ];

    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          devicesControllerProvider.overrideWith(() => _FakeDevicesController(devices)),
          adbDevicesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const Scaffold(body: DevicesTab()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Pair a phone'), findsOneWidget);
    expect(find.text('Paired devices'), findsOneWidget);
    expect(find.text('ADB device'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DevicesTab: the QR code panel lays out without overflow at the minimum window width', (tester) async {
    final code = PairingCode(
      code: '123456',
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
      host: '192.168.1.50',
      port: 8787,
    );

    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          devicesControllerProvider.overrideWith(() => _FakeDevicesController(const [], code: code)),
          adbDevicesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const Scaffold(body: DevicesTab()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Generate QR code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('123456'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DevicesTab: device identity card lists adb devices, pins one by tapping it, then clears the pin — no overflow at 1024px',
      (tester) async {
    const status = DeviceStatus(
      serial: '159555486700071',
      model: 'Pixel 7',
      bridgeReachable: true,
      mirroring: false,
      pinnedSerial: null,
      defaultSerial: '159555486700071',
    );
    final fakeController = _FakeDeviceController(status);

    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          devicesControllerProvider.overrideWith(() => _FakeDevicesController(const [])),
          deviceControllerProvider.overrideWith(() => fakeController),
          adbDevicesProvider.overrideWith(
            (ref) async => const [
              AdbDeviceInfo(serial: '159555486700071', state: 'device'),
              AdbDeviceInfo(serial: 'emulator-5554-a-rather-long-simulated-serial-0123456789', state: 'offline'),
            ],
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const Scaffold(body: DevicesTab()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Using the default device'), findsOneWidget);
    expect(find.text('Use default'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('159555486700071 · device'));
    await tester.pump();
    await tester.tap(find.text('159555486700071 · device'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fakeController.lastPinned, '159555486700071');
    expect(find.textContaining('Pinned to'), findsOneWidget);
    expect(find.text('Use default'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Use default'));
    await tester.pump();
    await tester.tap(find.text('Use default'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fakeController.lastPinned, isNull);
    expect(fakeController.pinCalls, 2);
    expect(find.text('Use default'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
