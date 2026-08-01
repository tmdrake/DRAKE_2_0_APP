import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nus_constants.dart';
import 'suit_state.dart';

/// BLE link + heartbeat service for TMDrake_tail (NUS).
///
/// Stability notes (Android GATT 133 thrash):
/// - Prefer direct connect + backoff over rapid autoConnect loops
/// - Treat any RX (HBACK/STAT) as link-alive, not only HBACK
/// - Soft STALE first; hard reconnect only after longer silence
/// - Settle delay before discoverServices; request HIGH connection priority
class BleLinkService extends ChangeNotifier {
  BleLinkService();

  // ── connection ──────────────────────────────────────────────
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar;
  BluetoothCharacteristic? _txChar;
  StreamSubscription<List<int>>? _txSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  LinkState _linkState = LinkState.off;
  String _statusMsg = 'Tap Connect to find the tail';
  bool _keepLinked = true;
  String? _savedRemoteId;

  // ── heartbeat / liveness ────────────────────────────────────
  Timer? _hbTimer;
  Timer? _staleTimer;
  DateTime? _lastRxAt;
  DateTime? _lastReconnectAt;
  bool _userDisconnect = false;
  bool _linkBusy = false;
  int _reconnectAttempt = 0;
  int _sessionGen = 0; // bump to cancel in-flight reconnects

  // ── suit mirror ─────────────────────────────────────────────
  final SuitState suit = SuitState();

  // ── log ─────────────────────────────────────────────────────
  final List<String> _log = [];
  static const int _logMax = 200;

  // ── debounced writes ────────────────────────────────────────
  Timer? _debounce;

  // ── getters ─────────────────────────────────────────────────
  LinkState get linkState => _linkState;
  String get statusMsg => _statusMsg;
  bool get keepLinked => _keepLinked;
  bool get isConnected =>
      _linkState == LinkState.linked || _linkState == LinkState.stale;
  bool get isScanning =>
      _linkState == LinkState.scanning || _linkState == LinkState.retrying;
  List<String> get log => List.unmodifiable(_log);
  String? get savedRemoteId => _savedRemoteId;
  BluetoothDevice? get device => _device;

  Future<void> init({bool autoStart = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _keepLinked = prefs.getBool('keep_linked') ?? true;
      _savedRemoteId = prefs.getString('tail_remote_id');
    } catch (e) {
      appendLog('prefs load error: $e');
    }
    notifyListeners();

    if (autoStart &&
        _keepLinked &&
        _savedRemoteId != null &&
        _savedRemoteId!.isNotEmpty) {
      unawaited(startLink(preferSaved: true));
    }
  }

  Future<void> setKeepLinked(bool value) async {
    _keepLinked = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('keep_linked', value);
    notifyListeners();
    if (!value) {
      await stopLink(userInitiated: true);
    } else {
      await startLink(preferSaved: true);
    }
  }

  Future<void> _persistRemoteId(String id) async {
    _savedRemoteId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tail_remote_id', id);
  }

  String _phoneStamp() {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}T${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  void appendLog(String line) {
    final u = suit.uptimeSec > 0 ? ' U:${suit.uptimeSec}' : '';
    final entry = '${_phoneStamp()}$u  $line';
    _log.insert(0, entry);
    if (_log.length > _logMax) _log.removeLast();
    notifyListeners();
  }

  String exportLogText() {
    final buf = StringBuffer();
    buf.writeln('# Drake 2.0 companion log');
    buf.writeln('# exported ${_phoneStamp()}');
    buf.writeln(
      '# last suit U:${suit.uptimeSec}  Seq:${suit.hbSeq}  mode:${suit.mode}',
    );
    buf.writeln('# format: phone_time [suit_U]  event');
    buf.writeln();
    for (final line in _log.reversed) {
      buf.writeln(line);
    }
    return buf.toString();
  }

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.notification,
    ].request();
    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? true;
    final connOk = statuses[Permission.bluetoothConnect]?.isGranted ?? true;
    return scanOk && connOk;
  }

  Future<void> startLink({bool preferSaved = false}) async {
    _userDisconnect = false;
    _reconnectAttempt = 0;
    try {
      final ok = await requestPermissions();
      if (!ok) {
        _setState(LinkState.off, 'Bluetooth permissions denied');
        return;
      }
      var adapter = FlutterBluePlus.adapterStateNow;
      if (adapter != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
        try {
          adapter = await FlutterBluePlus.adapterState
              .firstWhere((s) => s == BluetoothAdapterState.on)
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          adapter = FlutterBluePlus.adapterStateNow;
        }
      }
      if (adapter != BluetoothAdapterState.on) {
        _setState(LinkState.off, 'Please turn on Bluetooth');
        return;
      }

      if (preferSaved &&
          _savedRemoteId != null &&
          _savedRemoteId!.isNotEmpty) {
        // Direct first (more reliable than pure autoConnect on many Samsungs).
        await _connectById(_savedRemoteId!, preferDirect: true);
        return;
      }
      await _scanAndConnect();
    } catch (e) {
      _setState(LinkState.off, 'Link error: $e');
      appendLog('startLink error: $e');
    }
  }

  Future<void> stopLink({bool userInitiated = true}) async {
    _userDisconnect = userInitiated;
    _sessionGen++;
    _linkBusy = false;
    _reconnectAttempt = 0;
    _stopTimers();
    await _teardownGatt(disconnect: true);
    _setState(LinkState.off, userInitiated ? 'Disconnected' : 'Link stopped');
    if (userInitiated) appendLog('user disconnect');
  }

  void onAppResumed() {
    if (_linkState == LinkState.linked || _linkState == LinkState.stale) {
      unawaited(send('HB'));
      unawaited(send('?')); // resync STAT if firmware supports it
    } else if (_keepLinked && !_userDisconnect) {
      unawaited(startLink(preferSaved: true));
    }
  }

  Duration _backoffDelay() {
    // 1.5s, 3s, 5s, 8s, 12s… cap 15s
    final exp = math.min(_reconnectAttempt, 5);
    final sec = math.min(15.0, 1.5 * math.pow(1.7, exp));
    return Duration(milliseconds: (sec * 1000).round());
  }

  Future<void> _scheduleReconnect({String reason = 'retry'}) async {
    if (_userDisconnect || !_keepLinked) return;
    if (_linkBusy) {
      appendLog('reconnect skipped (busy) $reason');
      return;
    }

    final now = DateTime.now();
    if (_lastReconnectAt != null) {
      final since = now.difference(_lastReconnectAt!);
      if (since < reconnectMinGap) {
        await Future<void>.delayed(reconnectMinGap - since);
      }
    }

    final delay = _backoffDelay();
    _reconnectAttempt++;
    final gen = _sessionGen;
    _setState(LinkState.retrying, 'Reconnecting (try $_reconnectAttempt)...');
    appendLog('$reason — backoff ${delay.inMilliseconds}ms try=$_reconnectAttempt');
    await Future<void>.delayed(delay);
    if (gen != _sessionGen || _userDisconnect || !_keepLinked) return;

    _lastReconnectAt = DateTime.now();
    if (_savedRemoteId != null && _savedRemoteId!.isNotEmpty) {
      await _connectById(_savedRemoteId!, preferDirect: true);
    } else {
      await _scanAndConnect();
    }
  }

  Future<void> _scanAndConnect() async {
    if (_linkBusy) return;
    _linkBusy = true;
    final gen = _sessionGen;
    _setState(LinkState.scanning, 'Scanning for $targetDeviceName...');
    appendLog('scan start');
    try {
      // Bonded fast path
      try {
        final bonded = await FlutterBluePlus.bondedDevices;
        for (final d in bonded) {
          final n = d.platformName;
          if (n == targetDeviceName || n.contains('TMDrake_tail')) {
            appendLog('found bonded ${d.remoteId.str}');
            _linkBusy = false;
            await _connectDevice(d, useAutoConnect: false);
            return;
          }
        }
      } catch (e) {
        appendLog('bonded lookup: $e');
      }

      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();

      final completer = Completer<BluetoothDevice?>();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        // Prefer strongest RSSI match
        ScanResult? best;
        for (final r in results) {
          final name = r.device.platformName;
          final advName = r.advertisementData.advName;
          final hasNus =
              r.advertisementData.serviceUuids.contains(nusServiceUuid);
          final match = name == targetDeviceName ||
              advName == targetDeviceName ||
              name.contains('TMDrake') ||
              hasNus;
          if (!match) continue;
          if (best == null || r.rssi > best.rssi) best = r;
        }
        if (best != null && !completer.isCompleted) {
          completer.complete(best.device);
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [nusServiceUuid],
        timeout: const Duration(seconds: 8),
        androidUsesFineLocation: false,
      );
      var device = await completer.future.timeout(
        const Duration(seconds: 9),
        onTimeout: () => null,
      );

      if (device == null && gen == _sessionGen) {
        await FlutterBluePlus.stopScan();
        appendLog('NUS-filter scan empty — open scan');
        await FlutterBluePlus.startScan(
          timeout: scanTimeout,
          androidUsesFineLocation: false,
        );
        device = await completer.future.timeout(
          scanTimeout + const Duration(seconds: 1),
          onTimeout: () => null,
        );
      }

      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanSub = null;

      if (gen != _sessionGen) return;

      if (device == null) {
        _linkBusy = false;
        if (_keepLinked && !_userDisconnect) {
          unawaited(_scheduleReconnect(reason: 'scan timeout'));
        } else {
          _setState(
            LinkState.off,
            'No tail found. Power tail + stay nearby.',
          );
          appendLog('scan timeout — no device');
        }
        return;
      }
      _linkBusy = false;
      await _connectDevice(device, useAutoConnect: false);
    } catch (e) {
      _linkBusy = false;
      appendLog('scan error: $e');
      if (_keepLinked && !_userDisconnect) {
        unawaited(_scheduleReconnect(reason: 'scan error'));
      } else {
        _setState(LinkState.off, 'Scan error: $e');
      }
    }
  }

  Future<void> _connectById(
    String remoteId, {
    required bool preferDirect,
  }) async {
    _setState(LinkState.connecting, 'Connecting to suit...');
    appendLog('connect by id $remoteId direct=$preferDirect');
    try {
      final device = BluetoothDevice.fromId(remoteId);
      // Try direct first — fewer GATT 133s than long autoConnect waits.
      if (preferDirect) {
        try {
          await _connectDevice(device, useAutoConnect: false);
          return;
        } catch (e) {
          appendLog('direct connect failed, try autoConnect: $e');
        }
      }
      await _connectDevice(device, useAutoConnect: true);
    } catch (e) {
      appendLog('connect-by-id failed: $e');
      if (_keepLinked && !_userDisconnect) {
        unawaited(_scheduleReconnect(reason: 'connect-by-id fail'));
      } else {
        _setState(LinkState.off, 'Connect failed: $e');
      }
    }
  }

  Future<void> _connectDevice(
    BluetoothDevice device, {
    required bool useAutoConnect,
  }) async {
    if (_linkBusy && _device != null) {
      appendLog('connectDevice skipped busy');
      return;
    }
    _linkBusy = true;
    final gen = _sessionGen;
    _setState(
      LinkState.connecting,
      'Connecting to ${device.platformName.isEmpty ? targetDeviceName : device.platformName}...',
    );
    appendLog(
      'connecting ${device.remoteId.str} auto=$useAutoConnect',
    );

    try {
      // Clean previous handle without marking user disconnect.
      await _txSub?.cancel();
      _txSub = null;
      await _connSub?.cancel();
      _connSub = null;
      if (_device != null && _device!.remoteId != device.remoteId) {
        try {
          await _device!.disconnect();
        } catch (_) {}
      }

      // If already connected, skip connect().
      if (!device.isConnected) {
        await device.connect(
          autoConnect: useAutoConnect,
          // autoConnect requires mtu: null per flutter_blue_plus.
          mtu: useAutoConnect ? null : 247,
          timeout: useAutoConnect
              ? const Duration(seconds: 40)
              : const Duration(seconds: 15),
        );
      }

      if (gen != _sessionGen) {
        _linkBusy = false;
        return;
      }

      _device = device;
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          // Ignore spurts right after connect / during teardown.
          if (_linkState == LinkState.connecting) return;
          _onDisconnected();
        }
      });

      if (useAutoConnect) {
        await device.connectionState
            .firstWhere((s) => s == BluetoothConnectionState.connected)
            .timeout(const Duration(seconds: 25));
      }

      // Let Android GATT stack settle (reduces 133 / empty services).
      await Future<void>.delayed(gattSettleDelay);
      if (gen != _sessionGen) {
        _linkBusy = false;
        return;
      }

      // Discover first, then MTU — FBP warns requestMtu races discoverServices.
      final services = await device.discoverServices();
      BluetoothService? nus;
      for (final s in services) {
        if (s.uuid == nusServiceUuid) {
          nus = s;
          break;
        }
      }
      if (nus == null) {
        appendLog('NUS service missing — retry');
        _linkBusy = false;
        await _teardownGatt(disconnect: true);
        if (_keepLinked && !_userDisconnect) {
          unawaited(_scheduleReconnect(reason: 'NUS missing'));
        } else {
          _setState(LinkState.off, 'Connected but NUS service not found');
        }
        return;
      }

      _rxChar = null;
      _txChar = null;
      for (final c in nus.characteristics) {
        if (c.uuid == nusRxUuid) _rxChar = c;
        if (c.uuid == nusTxUuid) _txChar = c;
      }
      if (_txChar == null || _rxChar == null) {
        appendLog('NUS chars missing');
        _linkBusy = false;
        await _teardownGatt(disconnect: true);
        if (_keepLinked && !_userDisconnect) {
          unawaited(_scheduleReconnect(reason: 'NUS chars missing'));
        } else {
          _setState(LinkState.off, 'NUS RX/TX characteristics missing');
        }
        return;
      }

      // Prefer low latency while suit is linked (Android).
      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
      } catch (e) {
        appendLog('conn priority: $e');
      }

      try {
        await device.requestMtu(247);
      } catch (e) {
        appendLog('mtu: $e');
      }

      await _txSub?.cancel();
      await _txChar!.setNotifyValue(true);
      // Notifications only (not write echoes).
      _txSub = _txChar!.onValueReceived.listen(_onBleData);

      await _persistRemoteId(device.remoteId.str);

      _lastRxAt = DateTime.now();
      _reconnectAttempt = 0;
      _linkBusy = false;
      _setState(LinkState.linked, 'Linked to $targetDeviceName');
      appendLog('connected + notify on');

      await send('HB');
      // Optional full status pull
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await send('?', logTx: false);
      _startTimers();
    } catch (e) {
      _linkBusy = false;
      appendLog('connect failed: $e');
      try {
        await device.disconnect();
      } catch (_) {}
      if (_keepLinked && !_userDisconnect && gen == _sessionGen) {
        unawaited(_scheduleReconnect(reason: 'connect failed'));
      } else {
        _setState(LinkState.off, 'Connect failed: $e');
      }
    }
  }

  void _onDisconnected() {
    _stopTimers();
    _rxChar = null;
    _txChar = null;
    appendLog('disconnected');
    if (_userDisconnect || !_keepLinked) {
      _setState(LinkState.off, 'Disconnected');
      return;
    }
    if (_linkState == LinkState.retrying || _linkState == LinkState.scanning) {
      // Already recovering.
      return;
    }
    _setState(LinkState.retrying, 'Link lost — reconnecting...');
    unawaited(_scheduleReconnect(reason: 'link lost'));
  }

  Future<void> _teardownGatt({required bool disconnect}) async {
    await _txSub?.cancel();
    _txSub = null;
    await _connSub?.cancel();
    _connSub = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (disconnect && _device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _device = null;
    _rxChar = null;
    _txChar = null;
  }

  void _startTimers() {
    _stopTimers();
    _lastRxAt = DateTime.now();
    _hbTimer = Timer.periodic(hbInterval, (_) {
      if (_linkState == LinkState.linked || _linkState == LinkState.stale) {
        unawaited(send('HB', logTx: false));
      }
    });
    _staleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkStale();
    });
  }

  void _stopTimers() {
    _hbTimer?.cancel();
    _hbTimer = null;
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  void _checkStale() {
    if (_lastRxAt == null) return;
    if (_linkState != LinkState.linked && _linkState != LinkState.stale) {
      return;
    }
    final age = DateTime.now().difference(_lastRxAt!);

    // Soft STALE: keep GATT, poke HB harder.
    if (age > hbackStaleTimeout && age <= hbackHardReconnectTimeout) {
      if (_linkState != LinkState.stale) {
        _setState(LinkState.stale, 'Link soft-stale — waiting for RX...');
        appendLog('SOFT-STALE no RX ${age.inSeconds}s');
      }
      unawaited(send('HB', logTx: false));
      return;
    }

    // Hard reconnect only after prolonged silence.
    if (age > hbackHardReconnectTimeout) {
      appendLog('HARD-RECONNECT no RX ${age.inSeconds}s');
      if (_linkBusy) return;
      unawaited(() async {
        await _teardownGatt(disconnect: true);
        if (!_userDisconnect && _keepLinked) {
          await _scheduleReconnect(reason: 'hard stale');
        }
      }());
    }
  }

  void _noteRx() {
    _lastRxAt = DateTime.now();
  }

  void _onBleData(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty) return;
    _noteRx();

    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('STAT')) {
        _parseStat(t);
        if (_log.isEmpty || !_log.first.contains('STAT')) {
          appendLog(t);
        } else {
          notifyListeners();
        }
      } else if (t.startsWith('HBACK')) {
        _parseHback(t);
        if (_log.isEmpty || !_log.first.contains('HBACK')) {
          appendLog(t);
        } else {
          notifyListeners();
        }
      } else {
        appendLog(t);
      }
    }
  }

  void _parseHback(String line) {
    _noteRx();
    if (_linkState == LinkState.stale ||
        _linkState == LinkState.connecting ||
        _linkState == LinkState.retrying) {
      _linkState = LinkState.linked;
      _statusMsg = 'Linked to $targetDeviceName';
    } else if (_linkState != LinkState.linked) {
      _linkState = LinkState.linked;
    }
    final map = _tokenMap(line);
    if (map.containsKey('Seq')) {
      suit.hbSeq = int.tryParse(map['Seq']!) ?? suit.hbSeq;
    }
    if (map.containsKey('U')) {
      suit.uptimeSec = int.tryParse(map['U']!) ?? suit.uptimeSec;
    }
    notifyListeners();
  }

  void _parseStat(String line) {
    final map = _tokenMap(line);
    if (map.containsKey('M')) {
      suit.mode = int.tryParse(map['M']!) ?? suit.mode;
    }
    if (map.containsKey('B')) {
      suit.brightness = double.tryParse(map['B']!) ?? suit.brightness;
    }
    if (map.containsKey('V')) {
      suit.speed = double.tryParse(map['V']!) ?? suit.speed;
    }
    if (map.containsKey('S')) {
      suit.amp = double.tryParse(map['S']!) ?? suit.amp;
    }
    if (map.containsKey('G')) {
      suit.gate = double.tryParse(map['G']!) ?? suit.gate;
    }
    if (map.containsKey('A')) {
      suit.preamp = double.tryParse(map['A']!) ?? suit.preamp;
    }
    if (map.containsKey('E')) {
      suit.soundOn = map['E'] == '1';
    }
    if (map.containsKey('Mic')) {
      suit.micLevel = int.tryParse(map['Mic']!) ?? suit.micLevel;
    }
    if (map.containsKey('HeadB')) {
      suit.headLight = int.tryParse(map['HeadB']!) ?? suit.headLight;
    }
    if (map.containsKey('HeadT')) {
      suit.headTemp = double.tryParse(map['HeadT']!) ?? suit.headTemp;
    }
    if (map.containsKey('U')) {
      suit.uptimeSec = int.tryParse(map['U']!) ?? suit.uptimeSec;
    }
    if (map.containsKey('Seq')) {
      suit.hbSeq = int.tryParse(map['Seq']!) ?? suit.hbSeq;
    }
    if (map.containsKey('T')) {
      final t = int.tryParse(map['T']!);
      if (t != null) {
        suit.themeId = t;
        if (t >= 0 && t < kThemes.length) {
          suit.activeTheme = kThemes[t]['key'] as String;
          suit.baseColor = kThemes[t]['color'] as Color;
        } else {
          suit.activeTheme = 'custom';
          suit.themeId = -1;
        }
      }
    }
    if (map.containsKey('C')) {
      final rgb = map['C']!.split(',');
      if (rgb.length == 3) {
        final r = int.tryParse(rgb[0]) ?? 157;
        final g = int.tryParse(rgb[1]) ?? 78;
        final b = int.tryParse(rgb[2]) ?? 221;
        if (suit.activeTheme == 'custom' || suit.themeId < 0) {
          suit.baseColor = Color.fromRGBO(r, g, b, 1);
        }
      }
    }
    if (_linkState == LinkState.stale ||
        _linkState == LinkState.connecting ||
        _linkState == LinkState.retrying) {
      _linkState = LinkState.linked;
      _statusMsg = 'Linked to $targetDeviceName';
    }
    notifyListeners();
  }

  Map<String, String> _tokenMap(String line) {
    final map = <String, String>{};
    for (final p in line.split(RegExp(r'\s+'))) {
      if (p.contains(':')) {
        final kv = p.split(':');
        if (kv.length >= 2) map[kv[0]] = kv.sublist(1).join(':');
      }
    }
    return map;
  }

  Future<void> send(String cmd, {bool logTx = true}) async {
    if (_rxChar == null) return;
    try {
      final bytes = utf8.encode(cmd);
      // Prefer write-without-response when available (less ATT congestion).
      final noRsp = _rxChar!.properties.writeWithoutResponse;
      await _rxChar!.write(bytes, withoutResponse: noRsp);
      if (logTx) appendLog('→ $cmd');
    } catch (e) {
      appendLog('send error $cmd: $e');
      // Single failure is not a drop — HB soft-stale path handles silence.
      if (logTx) {
        _statusMsg = 'Send hiccup (still linked if badge says so)';
        notifyListeners();
      }
    }
  }

  void sendDebounced(String cmd) {
    _debounce?.cancel();
    // Slightly longer debounce = fewer ATT writes during slider drag.
    _debounce = Timer(const Duration(milliseconds: 160), () {
      unawaited(send(cmd));
    });
  }

  void setMode(int id) {
    suit.mode = id;
    notifyListeners();
    unawaited(send('M$id'));
  }

  void applyTheme(Map<String, dynamic> t) {
    suit.activeTheme = t['key'] as String;
    suit.themeId = t['id'] as int;
    suit.baseColor = t['color'] as Color;
    suit.mode = 9;
    notifyListeners();
    unawaited(send('T${t['id']}'));
  }

  void applyCustomColor(Color c) {
    suit.baseColor = c;
    suit.activeTheme = 'custom';
    suit.themeId = -1;
    suit.mode = 9;
    notifyListeners();
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);
    unawaited(send('C$r,$g,$b'));
  }

  void applySoundPreset(Map<String, dynamic> p) {
    suit.amp = (p['S'] as num).toDouble();
    suit.gate = (p['G'] as num).toDouble();
    suit.preamp = (p['A'] as num).toDouble();
    notifyListeners();
    unawaited(send('S${suit.amp.round()}'));
    unawaited(send('G${suit.gate.round()}'));
    unawaited(send('A${suit.preamp.round()}'));
  }

  void _setState(LinkState state, String msg) {
    _linkState = state;
    _statusMsg = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionGen++;
    _stopTimers();
    _debounce?.cancel();
    unawaited(_teardownGatt(disconnect: true));
    super.dispose();
  }
}
