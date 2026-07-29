import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// Nordic UART Service UUIDs (standard)
final Guid NUS_SERVICE = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
final Guid NUS_RX = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E"); // write to device
final Guid NUS_TX = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E"); // notify from device

const String TARGET_NAME = "TMDrake_tail";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const DrakeApp());
}

class DrakeApp extends StatelessWidget {
  const DrakeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drake 2.0',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7B2CBF), // deep dragon purple
          brightness: Brightness.dark,
          primary: const Color(0xFF9D4EDD),
          secondary: const Color(0xFF00D4FF),
          surface: const Color(0xFF1A0B2E),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0618),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar; // write commands here
  BluetoothCharacteristic? _txChar; // receive status here
  StreamSubscription? _txSub;
  StreamSubscription? _connSub;

  bool _isScanning = false;
  bool _isConnected = false;
  String _status = "Tap Connect to find the tail";
  String _lastResponse = "";
  final List<String> _log = [];

  // UI state
  int _mode = 0;
  double _brightness = 80;
  double _sensitivity = 50;
  double _speed = 50;
  bool _soundOn = true;

  final List<Map<String, dynamic>> _modes = [
    {"id": 0, "name": "Sound Phase", "icon": Icons.graphic_eq},
    {"id": 1, "name": "Sound Distinct", "icon": Icons.equalizer},
    {"id": 2, "name": "VU Meter", "icon": Icons.bar_chart},
    {"id": 3, "name": "Rainbow", "icon": Icons.gradient},
    {"id": 4, "name": "Comet", "icon": Icons.rocket_launch},
    {"id": 5, "name": "Breathe", "icon": Icons.air},
    {"id": 6, "name": "Fire", "icon": Icons.local_fire_department},
    {"id": 7, "name": "Sparkle", "icon": Icons.auto_awesome},
    {"id": 8, "name": "Wave", "icon": Icons.waves},
    {"id": 9, "name": "Solid", "icon": Icons.circle},
    {"id": 10, "name": "Off", "icon": Icons.power_settings_new},
  ];

  @override
  void dispose() {
    _txSub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    if (await Permission.bluetoothScan.isDenied) {
      await Permission.bluetoothScan.request();
    }
    if (await Permission.bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    }
    // Location only needed on older Android for scan
    if (await Permission.locationWhenInUse.isDenied) {
      await Permission.locationWhenInUse.request();
    }
    return true;
  }

  Future<void> _startScanAndConnect() async {
    await _requestPermissions();

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      setState(() => _status = "Please turn on Bluetooth");
      return;
    }

    setState(() {
      _isScanning = true;
      _status = "Scanning for TMDrake_tail...";
    });

    try {
      // Stop any previous scan
      await FlutterBluePlus.stopScan();

      // Prefer devices advertising the NUS service
      await FlutterBluePlus.startScan(
        withServices: [NUS_SERVICE],
        timeout: const Duration(seconds: 12),
      );

      // Also listen for name match as fallback
      late StreamSubscription scanSub;
      scanSub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          final name = r.device.platformName;
          if (name == TARGET_NAME ||
              r.advertisementData.serviceUuids.contains(NUS_SERVICE)) {
            await FlutterBluePlus.stopScan();
            scanSub.cancel();
            await _connect(r.device);
            return;
          }
        }
      });

      // Timeout fallback message
      await Future.delayed(const Duration(seconds: 13));
      if (!_isConnected && mounted) {
        setState(() {
          _isScanning = false;
          _status = "No tail found. Is it powered and nearby?";
        });
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
        _status = "Scan error: $e";
      });
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _status = "Connecting to ${device.platformName}...");

    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;

      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _isConnected = false;
            _status = "Disconnected";
            _rxChar = null;
            _txChar = null;
          });
        }
      });

      final services = await device.discoverServices();
      BluetoothService? nus;
      for (final s in services) {
        if (s.uuid == NUS_SERVICE) {
          nus = s;
          break;
        }
      }

      if (nus == null) {
        setState(() => _status = "Connected but NUS service not found");
        return;
      }

      for (final c in nus.characteristics) {
        if (c.uuid == NUS_RX) _rxChar = c;
        if (c.uuid == NUS_TX) _txChar = c;
      }

      if (_txChar != null) {
        await _txChar!.setNotifyValue(true);
        _txSub = _txChar!.onValueReceived.listen((bytes) {
          final text = utf8.decode(bytes, allowMalformed: true).trim();
          if (text.isNotEmpty && mounted) {
            setState(() {
              _lastResponse = text;
              _log.insert(0, text);
              if (_log.length > 30) _log.removeLast();
            });
          }
        });
      }

      setState(() {
        _isConnected = true;
        _isScanning = false;
        _status = "Connected to TMDrake_tail 🐉";
      });

      // Ask for status on connect
      await _send("?");
    } catch (e) {
      setState(() {
        _isScanning = false;
        _status = "Connect failed: $e";
      });
    }
  }

  Future<void> _disconnect() async {
    await _txSub?.cancel();
    await _device?.disconnect();
    setState(() {
      _isConnected = false;
      _device = null;
      _rxChar = null;
      _txChar = null;
      _status = "Disconnected";
    });
  }

  Future<void> _send(String cmd) async {
    if (_rxChar == null) return;
    try {
      final bytes = utf8.encode(cmd);
      // Prefer writeWithoutResponse if supported for speed
      if (_rxChar!.properties.writeWithoutResponse) {
        await _rxChar!.write(bytes, withoutResponse: true);
      } else {
        await _rxChar!.write(bytes, withoutResponse: false);
      }
      setState(() {
        _log.insert(0, "→ $cmd");
        if (_log.length > 30) _log.removeLast();
      });
    } catch (e) {
      setState(() => _status = "Send error: $e");
    }
  }

  void _setMode(int id) {
    setState(() => _mode = id);
    _send("M$id");
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Drake 2.0 Tail", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: "Disconnect",
              onPressed: _disconnect,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Status + Connect
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isConnected ? cs.secondary : cs.onSurface.withOpacity(0.8),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isScanning
                          ? null
                          : (_isConnected ? null : _startScanAndConnect),
                      icon: _isScanning
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(_isConnected ? Icons.check_circle : Icons.bluetooth_searching),
                      label: Text(
                        _isConnected
                            ? "Connected"
                            : (_isScanning ? "Scanning..." : "Connect to Tail"),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _isConnected ? Colors.green.shade700 : cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Modes
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text("Modes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _modes.map((m) {
                        final selected = _mode == m["id"];
                        return SizedBox(
                          width: (MediaQuery.of(context).size.width - 40) / 3,
                          child: Material(
                            color: selected ? cs.primary.withOpacity(0.35) : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: _isConnected ? () => _setMode(m["id"] as int) : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                                child: Column(
                                  children: [
                                    Icon(m["icon"] as IconData,
                                        size: 28,
                                        color: selected ? cs.secondary : cs.onSurface.withOpacity(0.7)),
                                    const SizedBox(height: 6),
                                    Text(
                                      m["name"] as String,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                        color: selected ? Colors.white : cs.onSurface.withOpacity(0.85),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // Sliders
                    _sliderTile(
                      label: "Brightness",
                      value: _brightness,
                      icon: Icons.brightness_6,
                      onChanged: (v) => setState(() => _brightness = v),
                      onChangeEnd: (v) => _send("B${v.round()}"),
                    ),
                    _sliderTile(
                      label: "Sensitivity",
                      value: _sensitivity,
                      icon: Icons.mic,
                      onChanged: (v) => setState(() => _sensitivity = v),
                      onChangeEnd: (v) => _send("S${v.round()}"),
                    ),
                    _sliderTile(
                      label: "Speed",
                      value: _speed,
                      icon: Icons.speed,
                      onChanged: (v) => setState(() => _speed = v),
                      onChangeEnd: (v) => _send("V${v.round()}"),
                    ),

                    const SizedBox(height: 8),

                    // Quick actions
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            icon: _soundOn ? Icons.volume_up : Icons.volume_off,
                            label: _soundOn ? "Sound On" : "Sound Off",
                            color: _soundOn ? Colors.teal : Colors.grey,
                            onTap: _isConnected
                                ? () {
                                    setState(() => _soundOn = !_soundOn);
                                    _send(_soundOn ? "E1" : "E0");
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.flash_on,
                            label: "Flash",
                            color: Colors.amber.shade700,
                            onTap: _isConnected ? () => _send("L") : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            icon: Icons.save,
                            label: "Save",
                            color: cs.primary,
                            onTap: _isConnected ? () => _send("W") : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.refresh,
                            label: "Status",
                            color: cs.secondary,
                            onTap: _isConnected ? () => _send("?") : null,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Response log
                    if (_log.isNotEmpty) ...[
                      const Text("Log", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView.builder(
                          itemCount: _log.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            child: Text(
                              _log[i],
                              style: TextStyle(
                                fontFamily: "monospace",
                                fontSize: 12,
                                color: _log[i].startsWith("→") ? cs.secondary : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderTile({
    required String label,
    required double value,
    required IconData icon,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 8),
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 14))),
          Expanded(
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              divisions: 20,
              label: value.round().toString(),
              onChanged: _isConnected ? onChanged : null,
              onChangeEnd: _isConnected ? onChangeEnd : null,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text("${value.round()}", textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: color.withOpacity(0.25),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
