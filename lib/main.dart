import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'ble/ble_link_service.dart';
import 'ble/suit_state.dart';
import 'ui/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Don't block startup if orientation fails on odd OEMs.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Edge-to-edge; Impeller composites under system bars.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  try {
    FlutterForegroundTask.initCommunicationPort();
  } catch (e, st) {
    debugPrint('FGS port init failed (non-fatal): $e\n$st');
  }

  runApp(const DrakeApp());
}

class DrakeApp extends StatefulWidget {
  const DrakeApp({super.key});

  @override
  State<DrakeApp> createState() => _DrakeAppState();
}

class _DrakeAppState extends State<DrakeApp> {
  final BleLinkService _link = BleLinkService();
  bool _ready = false;
  bool _fgsBusy = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _initForegroundTask();
    } catch (e, st) {
      debugPrint('FGS init failed (non-fatal): $e\n$st');
    }

    try {
      // Load prefs only — do NOT auto-connect before UI is up.
      await _link.init(autoStart: false);
    } catch (e, st) {
      debugPrint('BLE init failed (non-fatal): $e\n$st');
    }

    _link.addListener(_onLinkChanged);
    if (mounted) setState(() => _ready = true);

    // After first frame, optionally resume saved link.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_link.keepLinked &&
          _link.savedRemoteId != null &&
          _link.savedRemoteId!.isNotEmpty) {
        try {
          await _link.startLink(preferSaved: true);
        } catch (e, st) {
          debugPrint('auto startLink failed: $e\n$st');
        }
      }
    });
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'drake_suit_link',
        channelName: 'Suit link',
        channelDescription:
            'Keeps Drake 2.0 linked to TMDrake_tail in the background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<void> _onLinkChanged() async {
    if (_fgsBusy) return;
    _fgsBusy = true;
    try {
      final wantFgs = _link.keepLinked &&
          (_link.isConnected ||
              _link.isScanning ||
              _link.linkState == LinkState.retrying ||
              _link.linkState == LinkState.connecting ||
              _link.linkState == LinkState.stale);

      bool running = false;
      try {
        running = await FlutterForegroundTask.isRunningService;
      } catch (e) {
        debugPrint('isRunningService: $e');
        return;
      }

      if (wantFgs && !running) {
        await _startFgs();
      } else if (!wantFgs && running) {
        try {
          await FlutterForegroundTask.stopService();
        } catch (e) {
          debugPrint('stopService: $e');
        }
      } else if (wantFgs && running) {
        try {
          await FlutterForegroundTask.updateService(
            notificationTitle: 'Drake 2.0 · ${_link.linkState.label}',
            notificationText: _link.statusMsg,
          );
        } catch (e) {
          debugPrint('updateService: $e');
        }
      }
    } catch (e, st) {
      debugPrint('FGS link listener error: $e\n$st');
    } finally {
      _fgsBusy = false;
    }
  }

  Future<void> _startFgs() async {
    try {
      final notif = await FlutterForegroundTask.checkNotificationPermission();
      if (notif != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      final result = await FlutterForegroundTask.startService(
        serviceId: 2601,
        notificationTitle: 'Drake 2.0 · ${_link.linkState.label}',
        notificationText: _link.statusMsg,
        callback: startSuitLinkCallback,
      );
      debugPrint('startService result: $result');
    } catch (e, st) {
      // BLE still works without FGS; never let this kill the UI.
      debugPrint('startService failed (non-fatal): $e\n$st');
    }
  }

  @override
  void dispose() {
    _link.removeListener(_onLinkChanged);
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
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
          // Transparent so GpuAmbientBg shows through Scaffold.
          scaffoldBackgroundColor: Colors.transparent,
        ),
        home: _ready
            ? HomeShell(link: _link)
            : const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }
}

@pragma('vm:entry-point')
void startSuitLinkCallback() {
  FlutterForegroundTask.setTaskHandler(SuitLinkTaskHandler());
}

class SuitLinkTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
