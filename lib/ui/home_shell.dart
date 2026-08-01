import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ble/ble_link_service.dart';
import '../ble/nus_constants.dart';
import '../ble/suit_state.dart';
import 'gpu_ambient_bg.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.link});

  final BleLinkService link;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  BleLinkService get link => widget.link;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    link.addListener(_onLink);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    link.removeListener(_onLink);
    super.dispose();
  }

  void _onLink() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      link.onAppResumed();
    }
  }

  Widget _headCircle({double size = 36}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF9D4EDD).withValues(alpha: 0.7),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9D4EDD).withValues(alpha: 0.25),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/tmdrake_head.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF1A0B2E),
            alignment: Alignment.center,
            child: Icon(
              Icons.pets,
              size: size * 0.55,
              color: const Color(0xFF9D4EDD),
            ),
          ),
        ),
      ),
    );
  }

  String _fmtUptime(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Color _linkColor(LinkState s, ColorScheme cs) {
    switch (s) {
      case LinkState.linked:
        return Colors.lightGreenAccent;
      case LinkState.stale:
        return Colors.orangeAccent;
      case LinkState.scanning:
      case LinkState.connecting:
      case LinkState.retrying:
        return cs.secondary;
      case LinkState.off:
        return cs.onSurface.withValues(alpha: 0.7);
    }
  }

  Future<void> _exportLog() async {
    if (link.log.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log is empty')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: link.exportLogText()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Log copied (${link.log.length} lines) — paste into notes / chat',
          ),
        ),
      );
    }
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0B2E),
        title: Row(
          children: [
            _headCircle(size: 48),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Drake 2.0',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'TMDrake companion · v$appVersionLabel\n'
          'BLE NUS control for TMDrake_tail\n'
          'Contract $contractVersionLabel\n\n'
          'Link: HB every 3s · HBACK health · STAT sync\n'
          'Keep suit linked + autoConnect supported\n\n'
          'Art: marymouse',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = link.suit;
    final live = link.linkState == LinkState.linked;

    final accent = live
        ? Colors.lightGreenAccent
        : link.linkState == LinkState.stale
            ? Colors.orangeAccent
            : cs.secondary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _headCircle(size: 36),
            const SizedBox(width: 10),
            const Text(
              'Drake 2.0',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (link.isConnected ||
              link.isScanning ||
              link.linkState == LinkState.connecting ||
              (link.keepLinked && link.linkState != LinkState.off))
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Stop link',
              onPressed: () => link.stopLink(userInitiated: true),
            ),
        ],
      ),
      body: GpuAmbientBg(
        linkState: link.linkState,
        accent: accent,
        child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _linkColor(link.linkState, cs)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _linkColor(link.linkState, cs)
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          link.linkState.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: _linkColor(link.linkState, cs),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          link.statusMsg,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _linkColor(link.linkState, cs),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Busy / linked → status strip only. Purple Connect only when
                  // fully OFF and not auto-retrying (keepLinked).
                  if (link.linkState == LinkState.scanning ||
                      link.linkState == LinkState.retrying ||
                      link.linkState == LinkState.connecting)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: cs.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cs.secondary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.secondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              link.linkState == LinkState.retrying
                                  ? 'Auto-reconnecting to tail...'
                                  : link.linkState == LinkState.connecting
                                      ? 'Connecting to tail...'
                                      : 'Scanning for tail...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: cs.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (link.isConnected)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: live
                            ? Colors.green.shade900.withValues(alpha: 0.4)
                            : Colors.orange.shade900.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        s.uptimeSec > 0
                            ? '${live ? 'Connected' : 'Stale'} · U ${_fmtUptime(s.uptimeSec)} · Seq ${s.hbSeq}'
                            : (live ? 'Connected' : 'Stale'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: live
                              ? Colors.lightGreenAccent
                              : Colors.orangeAccent,
                        ),
                      ),
                    )
                  else if (link.keepLinked)
                    // Keep-linked ON: no Connect CTA — link will retry itself.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        link.savedRemoteId != null
                            ? 'Keep linked - waiting to reach tail...'
                            : 'Keep linked - use Settings to start a scan',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface.withValues(alpha: 0.75),
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: () => link.startLink(),
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text(
                          'Connect to Tail',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _buildControlTab(cs, s),
                  _buildStatusTab(cs, s),
                  _buildSettingsTab(cs, s),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: const Color(0xCC0D0618),
        surfaceTintColor: Colors.transparent,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.tune), label: 'Control'),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart),
            label: 'Status',
          ),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  /// Suit commands only when link is healthy enough to write.
  /// Controls stay visibly disabled offline so it's obvious nothing is live.
  bool get _canCmd =>
      link.linkState == LinkState.linked || link.linkState == LinkState.stale;

  Widget _buildControlTab(ColorScheme cs, SuitState s) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Surface can report width 0 during attach (lock→unlock). Old formula
        // (MediaQuery.width - 40) / 3 became -13.3 and red-screened Control.
        const hPad = 12.0;
        const spacing = 8.0;
        const cols = 3;
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        final innerW = (maxW - hPad * 2).clamp(0.0, double.infinity);
        final tileW = innerW <= 0
            ? 0.0
            : ((innerW - spacing * (cols - 1)) / cols).clamp(0.0, innerW);

        return AbsorbPointer(
          absorbing: !_canCmd,
          child: Opacity(
            opacity: _canCmd ? 1.0 : 0.42,
            child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: hPad, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Modes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (tileW > 0)
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: kModes.map((m) {
                    final selected = s.mode == m['id'];
                    return SizedBox(
                      width: tileW,
                      child: Material(
                        color: selected
                            ? cs.primary.withValues(alpha: 0.4)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _canCmd
                              ? () => link.setMode(m['id'] as int)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 4,
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  m['icon'] as IconData,
                                  size: 26,
                                  color: selected
                                      ? cs.secondary
                                      : cs.onSurface.withValues(alpha: 0.75),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  m['name'] as String,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
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
              const SizedBox(height: 18),
              const Text(
                'Theme / Color (live)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Applies Solid mode + color across the suit',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...kThemes.map((t) {
                      final selected = s.activeTheme == t['key'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: _canCmd ? () => link.applyTheme(t) : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: t['color'] as Color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? Colors.white
                                    : Colors.white24,
                                width: selected ? 3 : 1.5,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: (t['color'] as Color)
                                            .withValues(alpha: 0.55),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: selected
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 24,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }),
                    GestureDetector(
                      onTap: _canCmd ? _openColorPicker : null,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const SweepGradient(
                            colors: [
                              Colors.red,
                              Colors.yellow,
                              Colors.green,
                              Colors.cyan,
                              Colors.blue,
                              Colors.purple,
                              Colors.red,
                            ],
                          ),
                          border: Border.all(
                            color: s.activeTheme == 'custom'
                                ? Colors.white
                                : Colors.white24,
                            width: s.activeTheme == 'custom' ? 3 : 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.colorize,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _slider(
                'Brightness',
                s.brightness,
                0,
                100,
                Icons.brightness_6,
                (v) {
                  setState(() => s.brightness = v);
                  link.sendDebounced('B${v.round()}');
                },
              ),
              _slider(
                'Speed',
                s.speed,
                0,
                100,
                Icons.speed,
                (v) {
                  setState(() => s.speed = v);
                  link.sendDebounced('V${v.round()}');
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _actionBtn(
                      Icons.flash_on,
                      'Flash',
                      Colors.amber.shade700,
                      () => link.send('L'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _actionBtn(
                      Icons.refresh,
                      'Resync',
                      cs.secondary,
                      () => link.send('R'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
          ),
        );
      },
    );
  }

  Widget _buildStatusTab(ColorScheme cs, SuitState s) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live Telemetry',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _meterCard(
            'Mic Level (raw)',
            s.micLevel.toDouble(),
            0,
            2000,
            cs.secondary,
            Icons.mic,
          ),
          const SizedBox(height: 6),
          Text(
            'Gate G should sit above quiet Mic (now ${s.micLevel})',
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _infoCard(
                  'Head Temp',
                  '${s.headTemp.toStringAsFixed(1)} °F',
                  Icons.thermostat,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _infoCard(
                  'Ambient Light',
                  '${s.headLight}',
                  Icons.wb_sunny,
                  Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _infoCard(
                  'Mode',
                  '${s.mode}',
                  Icons.tune,
                  cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _infoCard(
                  'Sound',
                  s.soundOn ? 'ON' : 'OFF',
                  Icons.volume_up,
                  s.soundOn ? Colors.teal : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _infoCard(
                  'Suit uptime',
                  _fmtUptime(s.uptimeSec),
                  Icons.timer,
                  cs.secondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _infoCard(
                  'HB Seq',
                  '${s.hbSeq}',
                  Icons.sync,
                  Colors.lightBlueAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _infoCard(
                  'Theme',
                  s.activeTheme == 'custom' ? 'Custom' : s.activeTheme,
                  Icons.palette,
                  s.baseColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: s.baseColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(s.baseColor.r * 255).round()},'
                        '${(s.baseColor.g * 255).round()},'
                        '${(s.baseColor.b * 255).round()}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Text(
                        'RGB',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Field log',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${link.log.length}/200',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView.builder(
              itemCount: link.log.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                child: Text(
                  link.log[i],
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: link.log[i].contains('→')
                        ? cs.secondary
                        : Colors.white70,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _canCmd ? () => link.send('?') : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: link.log.isEmpty ? null : _exportLog,
                  icon: const Icon(Icons.copy_all),
                  label: const Text('Export log'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(ColorScheme cs, SuitState s) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Link', Icons.bluetooth_connected),
          SwitchListTile(
            title: const Text('Keep suit linked'),
            subtitle: const Text(
              'Auto-reconnect + heartbeat while ON. Leave on during con.',
            ),
            value: link.keepLinked,
            onChanged: (v) => link.setKeepLinked(v),
          ),
          if (link.savedRemoteId != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                'Saved device: ${link.savedRemoteId}',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),

          _sectionHeader('Sound', Icons.graphic_eq),
          SwitchListTile(
            title: const Text('Sound detect'),
            subtitle: const Text('Master wake for Phase / Pulse (E/e)'),
            value: s.soundOn,
            onChanged: _canCmd
                ? (v) {
                    setState(() => s.soundOn = v);
                    link.send(v ? 'E' : 'e');
                  }
                : null,
          ),
          const SizedBox(height: 4),
          const Text(
            'Presets',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Row(
            children: kSoundPresets.map((p) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: OutlinedButton(
                    onPressed:
                        _canCmd ? () => link.applySoundPreset(p) : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      p['name'] as String,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _slider(
            'Amp % (S)',
            s.amp,
            10,
            400,
            Icons.mic,
            (v) {
              setState(() => s.amp = v);
              link.sendDebounced('S${v.round()}');
            },
            subtitle: 'Post-envelope gain · firmware 10–400',
          ),
          _slider(
            'Preamp % (A)',
            s.preamp,
            50,
            300,
            Icons.tune,
            (v) {
              setState(() => s.preamp = v);
              link.sendDebounced('A${v.round()}');
            },
            subtitle: 'Mic preamp · firmware 50–300',
          ),
          _slider(
            'Gate (G)',
            s.gate,
            5,
            2000,
            Icons.door_front_door,
            (v) {
              setState(() => s.gate = v);
              link.sendDebounced('G${v.round()}');
            },
            subtitle:
                'Wake threshold vs raw Mic. Quiet Mic≈${s.micLevel} → set G higher',
          ),
          const SizedBox(height: 6),
          _meterCard(
            'Mic meter (live raw)',
            s.micLevel.toDouble(),
            0,
            2000,
            cs.secondary,
            Icons.graphic_eq,
          ),

          const SizedBox(height: 20),
          _sectionHeader('Fan (Head)', Icons.air),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Off'),
                icon: Icon(Icons.power_settings_new, size: 16),
              ),
              ButtonSegment(
                value: 1,
                label: Text('On'),
                icon: Icon(Icons.air, size: 16),
              ),
              ButtonSegment(
                value: 2,
                label: Text('Auto'),
                icon: Icon(Icons.thermostat, size: 16),
              ),
            ],
            selected: {s.fanMode.clamp(0, 2)},
            showSelectedIcon: false,
            onSelectionChanged: _canCmd
                ? (sel) {
                    final v = sel.first;
                    setState(() => s.fanMode = v);
                    link.send('F$v');
                  }
                : null,
          ),
          const SizedBox(height: 10),
          _slider(
            'Auto above °F',
            s.fanTemp,
            60,
            120,
            Icons.thermostat,
            (v) {
              setState(() => s.fanTemp = v);
              link.sendDebounced('FT${v.round()}');
            },
          ),
          Text(
            'Current Head Temp: ${s.headTemp.toStringAsFixed(1)} °F',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),

          const SizedBox(height: 20),
          _sectionHeader('Eyes / Ambient (Head)', Icons.visibility),
          _slider(
            'Dim when light ≥',
            s.cdsThreshold,
            0,
            1023,
            Icons.wb_sunny,
            (v) {
              setState(() => s.cdsThreshold = v);
              link.sendDebounced('I${v.round()}');
            },
          ),
          _slider(
            'Dimmed eye %',
            s.eyeDim,
            1,
            100,
            Icons.brightness_low,
            (v) {
              setState(() => s.eyeDim = v);
              link.sendDebounced('D${v.round()}');
            },
          ),
          Text(
            'Current light sensor: ${s.headLight}',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),

          const SizedBox(height: 20),
          _sectionHeader('System', Icons.settings_applications),
          ListTile(
            leading: const Icon(Icons.restart_alt, color: Colors.redAccent),
            title: const Text('Reboot Tail'),
            subtitle: const Text('Send Z command'),
            onTap: _canCmd
                ? () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Reboot Tail?'),
                        content: const Text(
                          'The tail will restart. Auto-reconnect will try if Keep suit linked is ON.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () {
                              link.send('Z');
                              Navigator.pop(ctx);
                            },
                            child: const Text('Reboot'),
                          ),
                        ],
                      ),
                    );
                  }
                : null,
          ),
          ListTile(
            leading: _headCircle(size: 32),
            title: const Text('About'),
            subtitle: Text(
              'Drake 2.0 · v$appVersionLabel · $contractVersionLabel',
            ),
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
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    IconData icon,
    ValueChanged<double> onChanged, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 14)),
              const Spacer(),
              Text(
                value.round().toString(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 2),
              child: Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions:
                ((max - min) / (max > 200 ? 10 : 5)).round().clamp(1, 100).toInt(),
            onChanged: _canCmd ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback? onTap,
  ) {
    return Material(
      color: color.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _canCmd ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meterCard(
    String label,
    double value,
    double min,
    double max,
    Color color,
    IconData icon,
  ) {
    final pct = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
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
              Text(
                value.round().toString(),
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
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
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  void _openColorPicker() {
    final s = link.suit;
    // HSV hue must stay in [0, 360) — 360 throws.
    double hue = HSVColor.fromColor(s.baseColor).hue % 360;
    double sat = HSVColor.fromColor(s.baseColor).saturation.clamp(0.0, 1.0);
    double val = HSVColor.fromColor(s.baseColor).value.clamp(0.0, 1.0);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A0B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final preview = HSVColor.fromAHSV(1, hue, sat, val).toColor();
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Custom Dragon Color',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 56,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: preview,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _hsvRow(
                    'Hue',
                    hue,
                    0,
                    359.99,
                    (v) => setModalState(() => hue = v),
                  ),
                  _hsvRow(
                    'Sat',
                    sat,
                    0,
                    1,
                    (v) => setModalState(() => sat = v),
                  ),
                  _hsvRow(
                    'Val',
                    val,
                    0,
                    1,
                    (v) => setModalState(() => val = v),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () {
                        final c = HSVColor.fromAHSV(1, hue, sat, val).toColor();
                        link.applyCustomColor(c);
                        Navigator.pop(ctx);
                      },
                      child: const Text('Apply Color'),
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

  Widget _hsvRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
