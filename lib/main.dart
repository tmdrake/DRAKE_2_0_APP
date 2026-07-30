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
  static const int _logMax = 200;

  int _mode = 0;
  double _brightness = 80;
  double _speed = 50;
  Color _baseColor = const Color(0xFF9D4EDD);
  String _activeTheme = "purple";
  int _themeId = 0;

  bool _soundOn = true;
  double _sensitivity = 75;
  double _gate = 100;
  double _gain = 100;
  int _micLevel = 0;

  int _fanMode = 2;
  double _fanTemp = 85;
  double _cdsThreshold = 500;
  double _eyeDim = 40;
  double _headTemp = 0;
  int _headLight = 0;

  int _uptimeSec = 0;
  int _hbSeq = 0;

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
    {"id": 0, "key": "purple", "name": "Purple", "color": const Color.fromRGBO(157, 78, 221, 1), "rgb": "157,78,221"},
    {"id": 1, "key": "fire", "name": "Fire", "color": const Color.fromRGBO(255, 60, 0, 1), "rgb": "255,60,0"},
    {"id": 2, "key": "ice", "name": "Ice", "color": const Color.fromRGBO(80, 180, 255, 1), "rgb": "80,180,255"},
    {"id": 3, "key": "gold", "name": "Gold", "color": const Color.fromRGBO(255, 180, 40, 1), "rgb": "255,180,40"},
    {"id": 4, "key": "emerald", "name": "Emerald", "color": const Color.fromRGBO(20, 200, 100, 1), "rgb": "20,200,100"},
  ];

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

  /// Circular head portrait — AppBar / About. Falls back to pet icon if PNG missing.
  Widget _headCircle({double size = 36}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF9D4EDD).withOpacity(0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9D4EDD).withOpacity(0.25),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          "assets/tmdrake_head.png",
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF1A0B2E),
            alignment: Alignment.center,
            child: Icon(Icons.pets, size: size * 0.55, color: const Color(0xFF9D4EDD)),
          ),
        ),
      ),
    );
  }

  String _phoneStamp() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return "${n.year}-${two(n.month)}-${two(n.day)}T${two(n.hour)}:${two(n.minute)}:${two(n.second)}";
  }

  void _appendLog(String line) {
    final u = _uptimeSec > 0 ? " U:$_uptimeSec" : "";
    final entry = "${_phoneStamp()}$u  $line";
    setState(() {
      _log.insert(0, entry);
      if (_log.length > _logMax) _log.removeLast();
    });
  }

  Future<void> _exportLog() async {
    if (_log.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Log is empty")),
        );
      }
      return;
    }
    final buf = StringBuffer();
    buf.writeln("# Drake 2.0 companion log");
    buf.writeln("# exported ${_phoneStamp()}");
    buf.writeln("# last suit U:$_uptimeSec  Seq:$_hbSeq  mode:$_mode");
    buf.writeln("# format: phone_time [suit_U]  event");
    buf.writeln();
    for (final line in _log.reversed) {
      buf.writeln(line);
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Log copied (${_log.length} lines) — paste into notes / chat")),
      );
    }
  }

  String _fmtUptime(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return "${h}h ${m}m";
    if (m > 0) return "${m}m ${s}s";
    return "${s}s";
  }

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
    _appendLog("scan start");
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
        _appendLog("scan timeout — no device");
      }
    } catch (e) {
      setState(() {
        _isScanning = false;
        _statusMsg = "Scan error: $e";
      });
      _appendLog("scan error: $e");
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _statusMsg = "Connecting to ${device.platformName}...");
    _appendLog("connecting ${device.platformName}");
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
          _appendLog("disconnected");
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
        _appendLog("NUS service missing");
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
      _appendLog("connected + notify on");
      await _send("?");
    } catch (e) {
      setState(() {
        _isScanning = false;
        _statusMsg = "Connect failed: $e";
      });
      _appendLog("connect failed: $e");
    }
  }

  void _onBleData(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty || !mounted) return;

    if (text.startsWith("STAT")) {
      _parseStat(text);
      if (_log.isEmpty || !_log.first.contains("STAT")) {
        _appendLog(text);
      }
    } else if (text.startsWith("HBACK")) {
      _parseHback(text);
      _appendLog(text);
    } else {
      _appendLog(text);
    }
  }

  void _parseHback(String line) {
    final map = <String, String>{};
    for (final p in line.split(RegExp(r'\s+'))) {
      if (p.contains(':')) {
        final kv = p.split(':');
        if (kv.length >= 2) map[kv[0]] = kv.sublist(1).join(':');
      }
    }
    setState(() {
      if (map.containsKey('Seq')) _hbSeq = int.tryParse(map['Seq']!) ?? _hbSeq;
      if (map.containsKey('U')) _uptimeSec = int.tryParse(map['U']!) ?? _uptimeSec;
    });
  }

  void _parseStat(String line) {
    final map = <String, String>{};
    final parts = line.split(RegExp(r'\s+'));
    for (final p in parts) {
      if (p.contains(':')) {
        final kv = p.split(':');
        if (kv.length >= 2) map[kv[0]] = kv.sublist(1).join(':');
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
      if (map.containsKey('U')) _uptimeSec = int.tryParse(map['U']!) ?? _uptimeSec;
      if (map.containsKey('Seq')) _hbSeq = int.tryParse(map['Seq']!) ?? _hbSeq;

      if (map.containsKey('T')) {
        final t = int.tryParse(map['T']!);
        if (t != null) {
          _themeId = t;
          if (t >= 0 && t < _themes.length) {
            _activeTheme = _themes[t]["key"] as String;
            _baseColor = _themes[t]["color"] as Color;
          } else {
            _activeTheme = "custom";
            _themeId = -1;
          }
        }
      }
      if (map.containsKey('C') && _activeTheme == "custom") {
        final rgb = map['C']!.split(',');
        if (rgb.length == 3) {
          final r = int.tryParse(rgb[0]) ?? 157;
          final g = int.tryParse(rgb[1]) ?? 78;
          final b = int.tryParse(rgb[2]) ?? 221;
          _baseColor = Color.fromRGBO(r, g, b, 1);
        }
      }
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
    _appendLog("user disconnect");
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
      _appendLog("→ $cmd");
    } catch (e) {
      setState(() => _statusMsg = "Send error: $e");
      _appendLog("send error $cmd: $e");
    }
  }

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

  void _applyTheme(Map<String, dynamic> t) {
    setState(() {
      _activeTheme = t["key"] as String;
      _themeId = t["id"] as int;
      _baseColor = t["color"] as Color;
      _mode = 9;
    });
    _send("T${t["id"]}");
  }

  void _applyCustomColor(Color c) {
    setState(() {
      _baseColor = c;
      _activeTheme = "custom";
      _themeId = -1;
      _mode = 9;
    });
    _send("C${c.red},${c.green},${c.blue}");
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0B2E),
        title: Row(
          children: [
            _headCircle(size: 48),
            const SizedBox(width: 12),
            const Expanded(
              child: Text("Drake 2.0", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: const Text(
          "TMDrake companion · v0.2.3\n"
          "BLE NUS control for TMDrake_tail\n"
          "Contract APP_INTERFACE v1.6\n\n"
          "Head mark: circular portrait\n"
          "Full crest: assets/tmdrake_badge.png\n"
          "Art: marymouse",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _headCircle(size: 36),
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
                      child: Text(
                        _uptimeSec > 0
                            ? "Connected · U ${_fmtUptime(_uptimeSec)} · Seq $_hbSeq"
                            : "Connected",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.lightGreenAccent),
                      ),
                    ),
                ],
              ),
            ),
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
                    onTap: _isConnected
                        ? () {
                            setState(() => _mode = m["id"] as int);
                            _send("M${m["id"]}");
                          }
                        : null,
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
          const Text("Theme / Color (live)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text("Applies Solid mode + color across the suit", style: TextStyle(fontSize: 12, color: Colors.white54)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ..._themes.map((t) {
                  final selected = _activeTheme == t["key"];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: _isConnected ? () => _applyTheme(t) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: t["color"] as Color,
                          shape: BoxShape.circle,
                          border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1.5),
                          boxShadow: selected
                              ? [BoxShadow(color: (t["color"] as Color).withOpacity(0.55), blurRadius: 10, spreadRadius: 1)]
                              : null,
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _infoCard("Suit uptime", _fmtUptime(_uptimeSec), Icons.timer, cs.secondary)),
              const SizedBox(width: 10),
              Expanded(child: _infoCard("HB Seq", "$_hbSeq", Icons.sync, Colors.lightBlueAccent)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _infoCard(
                  "Theme",
                  _activeTheme == "custom" ? "Custom" : _activeTheme,
                  Icons.palette,
                  _baseColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _baseColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "${_baseColor.red},${_baseColor.green},${_baseColor.blue}",
                        style: const TextStyle(fontSize: 12, fontFamily: "monospace"),
                      ),
                      const Text("RGB", style: TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text("Field log", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text("${_log.length}/$_logMax", style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 160,
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
            child: ListView.builder(
              itemCount: _log.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Text(_log[i],
                    style: TextStyle(fontFamily: "monospace", fontSize: 11,
                        color: _log[i].contains("→") ? cs.secondary : Colors.white70)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isConnected ? () => _send("?") : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Refresh"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _log.isEmpty ? null : _exportLog,
                  icon: const Icon(Icons.copy_all),
                  label: const Text("Export log"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Export copies phone time + suit U into the clipboard for pasting into notes/chat.",
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          ListTile(
            leading: _headCircle(size: 32),
            title: const Text("About"),
            subtitle: const Text("Drake 2.0 · v0.2.3 · head portrait branding"),
            onTap: _showAbout,
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

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
                        _applyCustomColor(c);
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
