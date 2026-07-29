import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// Nordic UART Service UUIDs
final Guid NUS_SERVICE = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
final Guid NUS_RX = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E"); // write
final Guid NUS_TX = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E"); // notify

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
          seedColor: const Color(0xFF7B2CBF),
          brightness: Brightness.dark,
          primary: const Color(0xFF9D4EDD),
          secondary: const Color(0xFF00D4FF),
          surface: const Color(0xFF1A0B2E),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0618),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  // BLE
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar;
  BluetoothCharacteristic? _txChar;
  StreamSubscription? _txSub;
  StreamSubscription? _connSub;

  bool _isScanning = false;
  bool _isConnected = false;
  String _statusMsg = "Tap Connect to find the tail";
  final List<String> _log = [];

  // Control state
  int _mode = 0;
  double _brightness = 80;
  double _speed = 50;
  Color _baseColor = const Color(0xFF9D4EDD);
  String _activeTheme = "purple";

  // Sound / Settings state (from SETTINGS.md)
  bool _soundOn = true;
  double _sensitivity = 75; // default from firmware
  double _gate = 100;
  double _gain = 100; // 50–300
  int _micLevel = 0;

  // Head
  int _fanMode = 2; // 0 off, 1 on, 2 auto
  double _fanTemp = 85;
  double _cdsThreshold = 500;
  double _eyeDim = 40;
  double _headTemp = 0;
  int _headLight = 0;

  final List<Map<String, dynamic>> _modes = [
    {"id": 0, "name": "Sound Phase", "icon": Icons.graphic_eq},
    {"id": 1, "name": "Sound Pulse", "icon": Icons.equalizer},
    {"id": 2, "name": "VU Meter", "icon": Icons.bar_chart},
    {"id": 3, "name": "Rainbow", "icon": Icons.gradient},
    {"id": 4, "name": "Comet", "icon": Icons.rocket_launch},
    {"id": 5, "name": "Breathe", "icon": Icons.air},
    {"id": 6, "name": "Dragonfire", "icon": Icons.local_fire_department},
    {"id": 7, "name": "Sparkle", "icon": Icons.auto_awesome},
    {"id": 8, "name": "Wave", "icon": Icons.waves},
    {"id": 9, "name": "Solid", "icon": Icons.circle},
    {"id": 10, "name": "Blackout", "icon": Icons.power_settings_new},
  ];

  final List<Map<String, dynamic>> _themes = [
    {"id": "purple", "name": "Purple", "color": const Color(0xFF9D4EDD), "rgb": "157,78,221"},
    {"id": "fire", "name": "Fire", "color": const Color(0xFFFF6B35), "rgb": "255,107,53"},
    {"id": "ice", "name": "Ice", "color": const Color(0xFF00D4FF), "rgb": "0,212,255"},
    {"id": "gold", "name": "Gold", "color": const Color(0xFFFFB703), "rgb": "255,183,3"},
    {"id": "emerald", "name": "Emerald", "color": const Color(0xFF06D6A0), "rgb": "6,214,160"},
  ];

  // Mic presets from SETTINGS.md
  final List<Map<String, dynamic>> _presets = [
    {"name": "Quiet", "S": 100, "G": 60, "A": 120},
    {"name": "Normal", "S": 75, "G": 100, "A": 100},
    {"name": "Loud", "S": 40, "G": 180, "A": 80},
  ];

  @override
  void dispose() {
    _txSub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  // ───────── BLE helpers ─────────
  Future<bool> _requestPermissions() async {
    if (await Permission.bluetoothScan.isDenied) await Permission.bluetoothScan.request();
    if (await Permission.bluetoothConnect.isDenied) await Permission.bluetoothConnect.request();
    if (await Permission.locationWhenInUse.isDenied) await Permission.locationWhenInUse.request();
    return true;
  }

  Future<void> _startScanAndConnect() async {
    await _requestPermissions();
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      setState(() => _statusMsg = "Please turn on Bluetooth");
      return;
    }
    setState(() {
      _isScanning = true;
      _statusMsg = "Scanning for TMDrake_tail...";
    });
    try {
      await FlutterBluePlus.stopScan();
      await FlutterBluePlus.startScan(withServices: [NUS_SERVICE], timeout: const Duration(seconds: 12));
      late StreamSubscription scanSub;
      scanSub = FlutterBluePlus.scanResults.listen((results) async {
        for (final r in results) {
          final name = r.device.platformName;
          if (name == TARGET_NAME || r.advertisementData.serviceUuids.contains(NUS_SERVICE)) {
            await FlutterBluePlus.stopScan();
            scanSub.cancel();
            await _connect(r.device);
            return;
          }
        }
      });
      await Future.delayed(const Duration(seconds: 13));
      if (!_isConnected && mounted) {
        setState(() {
          _isScanning = false;
          _statusMsg = "No tail found. Is it powered and nearby?";
        });
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
        _statusMsg = "Scan error: $e";
      });
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _statusMsg = "Connecting to ${device.platformName}...");
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _isConnected = false;
            _statusMsg = "Disconnected";
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
        setState(() => _statusMsg = "Connected but NUS service not found");
        return;
      }
      for (final c in nus.characteristics) {
        if (c.uuid == NUS_RX) _rxChar = c;
        if (c.uuid == NUS_TX) _txChar = c;
      }
      if (_txChar != null) {
        await _txChar!.setNotifyValue(true);
        _txSub = _txChar!.onValueReceived.listen(_onBleData);
      }
      setState(() {
        _isConnected = true;
        _isScanning = false;
        _statusMsg = "Connected to TMDrake_tail 🐉";
      });
      await _send("?");
    } catch (e) {
      setState(() {
        _isScanning = false;
        _statusMsg = "Connect failed: $e";
      });
    }
  }

  void _onBleData(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty || !mounted) return;
    setState(() {
      _log.insert(0, text);
      if (_log.length > 40) _log.removeLast();
    });
    // Parse live STAT line
    if (text.startsWith("STAT")) {
      _parseStat(text);
    }
  }

  void _parseStat(String line) {
    // STAT M:3 B:80 V:50 S:75 G:100 A:100 E:1 Mic:1423 HeadB:512 HeadT:86.2
    final map = <String, String>{};
    final parts = line.split(RegExp(r'\s+'));
    for (final p in parts) {
      if (p.contains(':')) {
        final kv = p.split(':');
        if (kv.length == 2) map[kv[0]] = kv[1];
      }
    }
    setState(() {
      if (map.containsKey('M')) _mode = int.tryParse(map['M']!) ?? _mode;
      if (map.containsKey('B')) _brightness = double.tryParse(map['B']!) ?? _brightness;
      if (map.containsKey('V')) _speed = double.tryParse(map['V']!) ?? _speed;
      if (map.containsKey('S')) _sensitivity = double.tryParse(map['S']!) ?? _sensitivity;
      if (map.containsKey('G')) _gate = double.tryParse(map['G']!) ?? _gate;
      if (map.containsKey('A')) _gain = double.tryParse(map['A']!) ?? _gain;
      if (map.containsKey('E')) _soundOn = map['E'] == '1';
      if (map.containsKey('Mic')) _micLevel = int.tryParse(map['Mic']!) ?? _micLevel;
      if (map.containsKey('HeadB')) _headLight = int.tryParse(map['HeadB']!) ?? _headLight;
      if (map.containsKey('HeadT')) _headTemp = double.tryParse(map['HeadT']!) ?? _headTemp;
    });
  }

  Future<void> _disconnect() async {
    await _txSub?.cancel();
    await _device?.disconnect();
    setState(() {
      _isConnected = false;
      _device = null;
      _rxChar = null;
      _txChar = null;
      _statusMsg = "Disconnected";
    });
  }

  Future<void> _send(String cmd) async {
    if (_rxChar == null) return;
    try {
      final bytes = utf8.encode(cmd);
      if (_rxChar!.properties.writeWithoutResponse) {
        await _rxChar!.write(bytes, withoutResponse: true);
      } else {
        await _rxChar!.write(bytes, withoutResponse: false);
      }
      setState(() {
        _log.insert(0, "→ $cmd");
        if (_log.length > 40) _log.removeLast();
      });
    } catch (e) {
      setState(() => _statusMsg = "Send error: $e");
    }
  }

  // Debounced send for sliders
  Timer? _debounce;
  void _sendDebounced(String cmd) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () => _send(cmd));
  }

  void _applyPreset(Map<String, dynamic> p) {
    setState(() {
      _sensitivity = (p["S"] as num).toDouble();
      _gate = (p["G"] as num).toDouble();
      _gain = (p["A"] as num).toDouble();
    });
    _send("S${_sensitivity.round()}");
    _send("G${_gate.round()}");
    _send("A${_gain.round()}");
  }

  // ───────── UI ─────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                "assets/tmdrake_badge.png",
                height: 34,
                width: 34,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 28),
              ),
            ),
            const SizedBox(width: 10),
            const Text("Drake 2.0", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_isConnected)
            IconButton(icon: const Icon(Icons.link_off), tooltip: "Disconnect", onPressed: _disconnect),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Connection bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  Text(
                    _statusMsg,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isConnected ? cs.secondary : cs.onSurface.withOpacity(0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_isConnected)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _isScanning ? null : _startScanAndConnect,
                        icon: _isScanning
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.bluetooth_searching),
                        label: Text(_isScanning ? "Scanning..." : "Connect to Tail",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade900.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text("Connected", textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.lightGreenAccent)),
                    ),
                ],
              ),
            ),
            // Tab content
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _buildControlTab(cs),
                  _buildStatusTab(cs),
                  _buildSettingsTab(cs),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.tune), label: "Control"),
          NavigationDestination(icon: Icon(Icons.monitor_heart), label: "Status"),
          NavigationDestination(icon: Icon(Icons.settings), label: "Settings"),
        ],
      ),
    );
  }

  // ───── CONTROL TAB ─────
  Widget _buildControlTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Modes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _modes.map((m) {
              final selected = _mode == m["id"];
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 40) / 3,
                child: Material(
                  color: selected ? cs.primary.withOpacity(0.4) : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _isConnected ? () { setState(() => _mode = m["id"] as int); _send("M${m["id"]}"); } : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                      child: Column(
                        children: [
                          Icon(m["icon"] as IconData, size: 26,
                              color: selected ? cs.secondary : cs.onSurface.withOpacity(0.75)),
                          const SizedBox(height: 4),
                          Text(m["name"] as String, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          const Text("Theme / Color", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._themes.map((t) {
                  final selected = _activeTheme == t["id"];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _isConnected
                          ? () {
                              setState(() {
                                _activeTheme = t["id"] as String;
                                _baseColor = t["color"] as Color;
                              });
                              _send("C${t["rgb"]}");
                              _send("T${t["id"]}");
                            }
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: t["color"] as Color,
                          shape: BoxShape.circle,
                          border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1.5),
                        ),
                        child: selected ? const Icon(Icons.check, color: Colors.white, size: 24) : null,
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: _isConnected ? _openColorPicker : null,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red]),
                      border: Border.all(color: _activeTheme == "custom" ? Colors.white : Colors.white24, width: _activeTheme == "custom" ? 3 : 1.5),
                    ),
                    child: const Icon(Icons.colorize, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _slider("Brightness", _brightness, 0, 100, Icons.brightness_6, (v) {
            setState(() => _brightness = v);
            _sendDebounced("B${v.round()}");
          }),
          _slider("Speed", _speed, 0, 100, Icons.speed, (v) {
            setState(() => _speed = v);
            _sendDebounced("V${v.round()}");
          }),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _actionBtn(Icons.flash_on, "Flash", Colors.amber.shade700, () => _send("L"))),
              const SizedBox(width: 8),
              Expanded(child: _actionBtn(Icons.refresh, "Resync", cs.secondary, () => _send("R"))),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ───── STATUS TAB ─────
  Widget _buildStatusTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Live Telemetry", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _meterCard("Mic Level", _micLevel.toDouble(), 0, 2000, cs.secondary, Icons.mic),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _infoCard("Head Temp", "${_headTemp.toStringAsFixed(1)} °F", Icons.thermostat, Colors.orange)),
              const SizedBox(width: 10),
              Expanded(child: _infoCard("Ambient Light", "$_headLight", Icons.wb_sunny, Colors.amber)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _infoCard("Mode", "$_mode", Icons.tune, cs.primary)),
              const SizedBox(width: 10),
              Expanded(child: _infoCard("Sound", _soundOn ? "ON" : "OFF", Icons.volume_up, _soundOn ? Colors.teal : Colors.grey)),
            ],
          ),
          const SizedBox(height: 16),
          const Text("Recent Log", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            height: 160,
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Text(_log[i],
                    style: TextStyle(fontFamily: "monospace", fontSize: 12,
                        color: _log[i].startsWith("→") ? cs.secondary : Colors.white70)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isConnected ? () => _send("?") : null,
              icon: const Icon(Icons.refresh),
              label: const Text("Refresh Status"),
            ),
          ),
        ],
      ),
    );
  }

  // ───── SETTINGS TAB ─────
  Widget _buildSettingsTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SOUND SECTION
          _sectionHeader("Sound", Icons.graphic_eq),
          SwitchListTile(
            title: const Text("Sound reactive"),
            subtitle: const Text("Master enable for mic modes"),
            value: _soundOn,
            onChanged: _isConnected
                ? (v) {
                    setState(() => _soundOn = v);
                    _send(v ? "E" : "e");
                  }
                : null,
          ),
          const SizedBox(height: 4),
          // Presets
          const Text("Presets", style: TextStyle(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 6),
          Row(
            children: _presets.map((p) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: OutlinedButton(
                    onPressed: _isConnected ? () => _applyPreset(p) : null,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
                    child: Text(p["name"] as String, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _slider("Gain %", _gain, 50, 300, Icons.tune, (v) {
            setState(() => _gain = v);
            _sendDebounced("A${v.round()}");
          }, subtitle: "How hard the mic pushes"),
          _slider("Sensitivity", _sensitivity, 0, 500, Icons.mic, (v) {
            setState(() => _sensitivity = v);
            _sendDebounced("S${v.round()}");
          }, subtitle: "Additive boost after gain"),
          _slider("Gate", _gate, 20, 800, Icons.door_front_door, (v) {
            setState(() => _gate = v);
            _sendDebounced("G${v.round()}");
          }, subtitle: "How loud to wake the lights"),
          const SizedBox(height: 6),
          _meterCard("Mic meter (live)", _micLevel.toDouble(), 0, 2000, cs.secondary, Icons.graphic_eq),

          const SizedBox(height: 20),
          // FAN SECTION
          _sectionHeader("Fan (Head)", Icons.air),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text("Off"), icon: Icon(Icons.power_settings_new, size: 16)),
              ButtonSegment(value: 1, label: Text("On"), icon: Icon(Icons.air, size: 16)),
              ButtonSegment(value: 2, label: Text("Auto"), icon: Icon(Icons.thermostat, size: 16)),
            ],
            selected: {_fanMode},
            onSelectionChanged: _isConnected
                ? (s) {
                    final v = s.first;
                    setState(() => _fanMode = v);
                    _send("F$v");
                  }
                : null,
          ),
          const SizedBox(height: 10),
          _slider("Auto above °F", _fanTemp, 60, 120, Icons.thermostat, (v) {
            setState(() => _fanTemp = v);
            _sendDebounced("FT${v.round()}");
          }),
          Text("Current Head Temp: ${_headTemp.toStringAsFixed(1)} °F",
              style: const TextStyle(fontSize: 13, color: Colors.white70)),

          const SizedBox(height: 20),
          // EYES / CDS
          _sectionHeader("Eyes / Ambient (Head)", Icons.visibility),
          _slider("Dim when light ≥", _cdsThreshold, 0, 1023, Icons.wb_sunny, (v) {
            setState(() => _cdsThreshold = v);
            _sendDebounced("I${v.round()}");
          }),
          _slider("Dimmed eye %", _eyeDim, 1, 100, Icons.brightness_low, (v) {
            setState(() => _eyeDim = v);
            _sendDebounced("D${v.round()}");
          }),
          Text("Current light sensor: $_headLight",
              style: const TextStyle(fontSize: 13, color: Colors.white70)),

          const SizedBox(height: 20),
          // SYSTEM
          _sectionHeader("System", Icons.settings_applications),
          ListTile(
            leading: const Icon(Icons.restart_alt, color: Colors.redAccent),
            title: const Text("Reboot Tail"),
            subtitle: const Text("Send Z command"),
            onTap: _isConnected
                ? () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("Reboot Tail?"),
                        content: const Text("The tail will restart. You will need to reconnect."),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                          FilledButton(
                            onPressed: () {
                              _send("Z");
                              Navigator.pop(ctx);
                            },
                            child: const Text("Reboot"),
                          ),
                        ],
                      ),
                    );
                  }
                : null,
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text("About"),
            subtitle: Text("Drake 2.0 Companion · v0.2.0\nInterface contract v1.3"),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ───── Shared widgets ─────
  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max, IconData icon, ValueChanged<double> onChanged, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 14)),
              const Spacer(),
              Text(value.round().toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 2),
              child: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.white54)),
            ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / (max > 200 ? 10 : 5)).round().clamp(1, 50),
            onChanged: _isConnected ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback? onTap) {
    return Material(
      color: color.withOpacity(0.25),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isConnected ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meterCard(String label, double value, double min, double max, Color color, IconData icon) {
    final pct = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 13)),
              const Spacer(),
              Text(value.round().toString(), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: Colors.white12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }

  void _openColorPicker() {
    double hue = HSVColor.fromColor(_baseColor).hue;
    double sat = HSVColor.fromColor(_baseColor).saturation;
    double val = HSVColor.fromColor(_baseColor).value;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0B2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final preview = HSVColor.fromAHSV(1, hue, sat, val).toColor();
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Custom Dragon Color", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Container(
                    height: 56,
                    width: double.infinity,
                    decoration: BoxDecoration(color: preview, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
                  ),
                  const SizedBox(height: 12),
                  _hsvRow("Hue", hue, 0, 360, (v) => setModalState(() => hue = v)),
                  _hsvRow("Sat", sat, 0, 1, (v) => setModalState(() => sat = v)),
                  _hsvRow("Val", val, 0, 1, (v) => setModalState(() => val = v)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () {
                        final c = HSVColor.fromAHSV(1, hue, sat, val).toColor();
                        setState(() {
                          _baseColor = c;
                          _activeTheme = "custom";
                        });
                        _send("C${c.red},${c.green},${c.blue}");
                        Navigator.pop(ctx);
                      },
                      child: const Text("Apply Color"),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _hsvRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 36, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
      ],
    );
  }
}
