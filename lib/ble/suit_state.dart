import 'package:flutter/material.dart';

/// High-level BLE link state for UI indicators.
enum LinkState {
  off,
  scanning,
  connecting,
  linked,
  stale,
  retrying,
}

extension LinkStateX on LinkState {
  String get label {
    switch (this) {
      case LinkState.off:
        return 'OFF';
      case LinkState.scanning:
        return 'SCANNING';
      case LinkState.connecting:
        return 'CONNECTING';
      case LinkState.linked:
        return 'LINKED';
      case LinkState.stale:
        return 'STALE';
      case LinkState.retrying:
        return 'RETRY';
    }
  }

  bool get isLive => this == LinkState.linked;
}

/// Live telemetry + control mirrors driven by STAT / HBACK / user actions.
class SuitState {
  int mode = 0;
  double brightness = 80;
  double speed = 50;

  /// Mic amp % (S) — firmware 10–400.
  double amp = 100;

  /// Mic gate (G) — firmware 5–2000, wake threshold vs raw Mic.
  double gate = 40;

  /// Mic preamp % (A) — firmware 50–300.
  double preamp = 100;

  bool soundOn = true;
  int micLevel = 0;

  Color baseColor = const Color.fromRGBO(157, 78, 221, 1);
  String activeTheme = 'purple';
  int themeId = 0;

  int fanMode = 2;
  double fanTemp = 85;
  double cdsThreshold = 500;
  double eyeDim = 40;

  double headTemp = 0;
  int headLight = 0;
  int uptimeSec = 0;
  int hbSeq = 0;

  SuitState copy() {
    final s = SuitState();
    s.mode = mode;
    s.brightness = brightness;
    s.speed = speed;
    s.amp = amp;
    s.gate = gate;
    s.preamp = preamp;
    s.soundOn = soundOn;
    s.micLevel = micLevel;
    s.baseColor = baseColor;
    s.activeTheme = activeTheme;
    s.themeId = themeId;
    s.fanMode = fanMode;
    s.fanTemp = fanTemp;
    s.cdsThreshold = cdsThreshold;
    s.eyeDim = eyeDim;
    s.headTemp = headTemp;
    s.headLight = headLight;
    s.uptimeSec = uptimeSec;
    s.hbSeq = hbSeq;
    return s;
  }
}

/// Mode labels matching APP_TEAM / APP_INTERFACE v2.0.
const List<Map<String, dynamic>> kModes = [
  {'id': 0, 'name': 'Sound Phase', 'icon': Icons.graphic_eq},
  {'id': 1, 'name': 'Sound Pulse', 'icon': Icons.equalizer},
  {'id': 2, 'name': 'VU Meter', 'icon': Icons.bar_chart},
  {'id': 3, 'name': 'Rainbow', 'icon': Icons.gradient},
  {'id': 4, 'name': 'Comet', 'icon': Icons.rocket_launch},
  {'id': 5, 'name': 'Breathe', 'icon': Icons.air},
  {'id': 6, 'name': 'Dragonfire', 'icon': Icons.local_fire_department},
  {'id': 7, 'name': 'Sparkle', 'icon': Icons.auto_awesome},
  {'id': 8, 'name': 'Wave', 'icon': Icons.waves},
  {'id': 9, 'name': 'Solid', 'icon': Icons.circle},
  {'id': 10, 'name': 'Blackout', 'icon': Icons.power_settings_new},
];

const List<Map<String, dynamic>> kThemes = [
  {
    'id': 0,
    'key': 'purple',
    'name': 'Purple',
    'color': Color.fromRGBO(157, 78, 221, 1),
    'rgb': '157,78,221',
  },
  {
    'id': 1,
    'key': 'fire',
    'name': 'Fire',
    'color': Color.fromRGBO(255, 60, 0, 1),
    'rgb': '255,60,0',
  },
  {
    'id': 2,
    'key': 'ice',
    'name': 'Ice',
    'color': Color.fromRGBO(80, 180, 255, 1),
    'rgb': '80,180,255',
  },
  {
    'id': 3,
    'key': 'gold',
    'name': 'Gold',
    'color': Color.fromRGBO(255, 180, 40, 1),
    'rgb': '255,180,40',
  },
  {
    'id': 4,
    'key': 'emerald',
    'name': 'Emerald',
    'color': Color.fromRGBO(20, 200, 100, 1),
    'rgb': '20,200,100',
  },
];

/// Sound presets: S=amp, G=gate, A=preamp (contract ranges).
const List<Map<String, dynamic>> kSoundPresets = [
  {'name': 'Quiet', 'S': 100, 'G': 300, 'A': 120},
  {'name': 'Normal', 'S': 100, 'G': 40, 'A': 100},
  {'name': 'Loud', 'S': 80, 'G': 500, 'A': 80},
];
