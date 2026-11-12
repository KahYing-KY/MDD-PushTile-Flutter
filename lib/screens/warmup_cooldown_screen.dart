import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, playing, done }

/// Lane colors matching the 1x4 rhythm game layout (Lane 0 to 3)
const List<Color> _laneColors = [
  Color(0xFFF0788C), // Lane 0 - Pink
  Color(0xFF7BD095), // Lane 1 - Green
  Color(0xFFFFC95C), // Lane 2 - Yellow
  Color(0xFF63A7EF), // Lane 3 - Blue
];

const List<String> _laneKeyLabels = ['D', 'F', 'J', 'K'];

class LightChaseScreen extends StatefulWidget {
  final bool coolDown;
  const LightChaseScreen({super.key, this.coolDown = false});

  @override
  State<LightChaseScreen> createState() => _LightChaseScreenState();
}

class _LightChaseScreenState extends State<LightChaseScreen> {
  final PushController input = PushController();
  final FocusNode _focusNode = FocusNode();
  final Random _rng = Random();
  final Stopwatch _total = Stopwatch();
  final Stopwatch _lit = Stopwatch();
  final Stopwatch _idle = Stopwatch();
  Timer? _ticker;

  _Phase _phase = _Phase.setup;
  final BoardMode _mode = BoardMode.row; // Fixed 1x4 mode

  /// Standard 1x4 lane cell indices [0, 1, 2, 3]
  List<int> get _laneCells => _mode.cells.length >= 4 
      ? _mode.cells.sublist(0, 4) 
      : const [0, 1, 2, 3];

  final Set<int> _touchDownLanes = {}; // Active touch, mouse, and keyboard button press indices
  final Map<int, DateTime> _lanePressStart = {}; // Tracks hold start for visual fill timing

  List<int> _seq = [];
  int _idx = 0;
  int _tries = 0;
  int _succeeded = 0;
  int _failed = 0;
  int _timeouts = 0;
  int _wrongTile = 0;
  bool _gotReaction = false;
  bool _early = false;
  final List<double> _reactions = [];
  final PressStats _stats = PressStats();
  String _message = '';
  WarmUpSummary? _summary;

  String get _name => widget.coolDown ? 'Cool-Down (1x4)' : 'Light Chase Warm-Up (1x4)';

  @override
  void initState() {
    super.initState();
    input.allowed = _laneCells;
    input.onDown = _onDown;
    input.onUp = _onUp;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    input.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<int> _makeSeq() {
    final out = <int>[];
    for (var i = 0; i < 6; i++) {
      int c;
      do {
        c = _laneCells[_rng.nextInt(_laneCells.length)];
      } while (out.isNotEmpty && c == out.last);
      out.add(c);
    }
    return out;
  }

  void _start() {
    setState(() {
      if (widget.coolDown) {
        _seq = List<int>.of(sessionSeq ?? _makeSeq());
      } else {
        _seq = _makeSeq();
      }
      input.allowed = _laneCells;
      input.clear();
      _touchDownLanes.clear();
      _lanePressStart.clear();

      _idx = 0;
      _tries = 0;
      _succeeded = 0;
      _failed = 0;
      _timeouts = 0;
      _wrongTile = 0;
      _gotReaction = false;
      _early = false;
      _reactions.clear();
      _stats.reset();
      _summary = null;
      _message = 'The lit tile needs a FULL press. Go!';
      _total
        ..reset()
        ..start();
      _lit
        ..reset()
        ..start();
      _idle
        ..reset()
        ..start();
      _phase = _Phase.playing;
    });

    // Request focus for hardware keyboard input when game starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!mounted || _phase != _Phase.playing) return;
      final idleSec = _idle.elapsedMilliseconds / 1000;
      if (!input.anyDown && _touchDownLanes.isEmpty && idleSec >= PushConfig.tileTimeoutSec) {
        setState(() {
          _timeouts++;
          _failed++;
          _advance('Time out - moving to the next tile.');
        });
      } else {
        setState(() {}); // Drives continuous vertical fill rendering
      }
    });
  }

  // =========================================================================
  // Keyboard Event Handler (D, F, J, K)
  // =========================================================================
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_phase != _Phase.playing) return KeyEventResult.ignored;

    final keyLabel = event.logicalKey.keyLabel.toUpperCase();
    int? laneIndex;
    if (keyLabel == 'D' || event.logicalKey == LogicalKeyboardKey.keyD) {
      laneIndex = 0;
    } else if (keyLabel == 'F' || event.logicalKey == LogicalKeyboardKey.keyF) {
      laneIndex = 1;
    } else if (keyLabel == 'J' || event.logicalKey == LogicalKeyboardKey.keyJ) {
      laneIndex = 2;
    } else if (keyLabel == 'K' || event.logicalKey == LogicalKeyboardKey.keyK) {
      laneIndex = 3;
    }

    if (laneIndex == null) return KeyEventResult.ignored;
    final cell = _laneCells[laneIndex];

    if (event is KeyDownEvent) {
      if (!_touchDownLanes.contains(laneIndex)) {
        setState(() {
          _touchDownLanes.add(laneIndex!);
          _lanePressStart[laneIndex] = DateTime.now();
        });
        _onDown(cell);
      }
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      if (_touchDownLanes.contains(laneIndex)) {
        final start = _lanePressStart.remove(laneIndex);
        final heldSec = start != null
            ? DateTime.now().difference(start).inMilliseconds / 1000.0
            : 0.0;
        setState(() {
          _touchDownLanes.remove(laneIndex!);
        });
        _onUp(cell, heldSec);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onDown(int cell) {
    if (_phase != _Phase.playing) return;
    final laneIndex = _laneCells.indexOf(cell);
    if (laneIndex >= 0 && !_lanePressStart.containsKey(laneIndex)) {
      _lanePressStart[laneIndex] = DateTime.now();
    }
    if (cell == _seq[_idx] && !_gotReaction) {
      _reactions.add(_lit.elapsedMilliseconds / 1000);
      _gotReaction = true;
    }
  }

  void _onUp(int cell, double sec) {
    if (_phase != _Phase.playing) return;

    final laneIndex = _laneCells.indexOf(cell);
    if (laneIndex >= 0) {
      _lanePressStart.remove(laneIndex);
    }

    if (cell != _seq[_idx]) {
      setState(() {
        _wrongTile++;
        _message = 'That is not the lit tile.';
      });
      return;
    }

    final r = classifyHold(sec);
    setState(() {
      _stats.add(r);
      if (r == PressResult.full) {
        _succeeded++;
        _advance('Full press! Next tile.');
        return;
      }
      _tries++;
      if (r == PressResult.half) {
        _idle
          ..reset()
          ..start();
      }
      if (_tries >= PushConfig.maxTries) {
        _failed++;
        _advance('Could not reach a full press on this tile - moving on.');
      } else {
        _message = r == PressResult.half
            ? 'Half press - try again for a full press ($_tries/${PushConfig.maxTries}).'
            : 'Too short - hold longer ($_tries/${PushConfig.maxTries}).';
      }
    });
  }

  void _advance(String msg) {
    _idx++;
    _tries = 0;
    _gotReaction = false;
    _lanePressStart.clear();
    if (_idx >= _seq.length) {
      _finish();
      return;
    }
    _lit
      ..reset()
      ..start();
    _idle
      ..reset()
      ..start();
    _message = msg;
  }

  void _finish({bool early = false}) {
    _total.stop();
    _lit.stop();
    _idle.stop();
    _ticker?.cancel();
    input.clear();
    _touchDownLanes.clear();
    _lanePressStart.clear();
    _early = early;
    _phase = _Phase.done;

    final avgReaction = _reactions.isEmpty
        ? 0.0
        : _reactions.reduce((a, b) => a + b) / _reactions.length;
    final secs = _total.elapsedMilliseconds / 1000;

    final summary = WarmUpSummary(
      avgReaction: avgReaction,
      totalSeconds: secs,
      full: _stats.full,
      half: _stats.half,
      none: _stats.none,
      done: _succeeded,
      failed: _failed,
      total: _seq.length,
    );
    _summary = summary;

    if (!early) {
      if (widget.coolDown) {
        coolDownSummary = summary;
      } else {
        warmUpSummary = summary;
        sessionSeq = List<int>.of(_seq);
        sessionMode = _mode;
        warmUpDone = true;
      }
    }

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: widget.coolDown ? 'Cool-Down' : 'Warm-Up',
      date: DateTime.now(),
      difficulty: '1x4 Mode',
      durationSeconds: secs.round(),
      correctAttempts: _succeeded,
      incorrectAttempts: _failed,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Light Chase 1x4 Mode | tiles $_succeeded/${_seq.length} '
          'full-pressed | avg reaction ${avgReaction.toStringAsFixed(1)} s | '
          'timeouts $_timeouts | wrong-tile presses $_wrongTile',
    ));
    _message = early ? '$_name stopped early.' : '$_name complete!';
  }

  // =========================================================================
  // UI
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: PushKeyboard(
            controller: input,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: switch (_phase) {
                  _Phase.setup => _buildSetup(),
                  _Phase.playing => _buildPlay(),
                  _Phase.done => _buildResult(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetup() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.touch_app_rounded, size: 72, color: kTeal),
        const SizedBox(height: 8),
        Text(widget.coolDown ? '1x4 Cool-Down' : '1x4 Light Chase',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          'A 1x4 pad lights up. Push and HOLD it until reaching 100% full press to score. '
          'A half or short press is recorded and you try again '
          '(3 tries per tile, 20 s limit).',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 16),
        const Text(
          'Controls: Use on-screen pads or keyboard keys D   F   J   K.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
        ),
        const SizedBox(height: 12),
        practiceSwitch(PushConfig.practice,
            (v) => setState(() => PushConfig.practice = v)),
        Text(pressRulesText(),
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _start,
          style: FilledButton.styleFrom(
              backgroundColor: kBlue, minimumSize: const Size.fromHeight(56)),
          child: Text('Start $_name',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }

  Widget _buildPlay() {
    return Container(
      color: const Color(0xFF05051A),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: Center(
              child: Text(
                _message,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                fmtSeconds(_total.elapsedMilliseconds / 1000),
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.bold, color: kTeal),
              ),
              Text(
                'Tile ${_idx + 1} of ${_seq.length}   •   Try ${_tries + 1}/${PushConfig.maxTries}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: _buildFourButtonRow(),
            ),
          ),
          const SizedBox(height: 16),
          pressStatsBar(_stats, dark: true),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End session', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  /// Builds 4 interactive lane buttons with vertical progress fill transitioning from
  /// Orange (0-50%) to Green (50-100%), matching the rhythm game style.
  Widget _buildFourButtonRow() {
    return AnimatedBuilder(
      animation: input,
      builder: (context, _) {
        final targetCell = _seq.isNotEmpty && _idx < _seq.length ? _seq[_idx] : -1;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            final cell = _laneCells[index];
            final isPressed = input.isDown(cell) || _touchDownLanes.contains(index);
            final isTarget = cell == targetCell;
            final color = _laneColors[index];

            double fillRatio = 0.0;
            if (isPressed && _lanePressStart.containsKey(index)) {
              final heldMs = DateTime.now().difference(_lanePressStart[index]!).inMilliseconds;
              final fullMs = (PushConfig.fullSec * 1000).round();
              fillRatio = fullMs > 0 ? (heldMs / fullMs).clamp(0.0, 1.0) : 0.0;
            }

            final pct = (fillRatio * 100).round();
            final reachedMid = fillRatio >= 0.50; // 50% threshold

            String labelText = _laneKeyLabels[index];
            Color labelColor = Colors.white;
            Color borderColor = color;
            double borderWidth = 3.0;
            Color fillColor = color.withValues(alpha: 0.45);

            if (isPressed) {
              labelText = '$pct%';
              labelColor = reachedMid ? Colors.greenAccent : Colors.amberAccent;
              borderColor = reachedMid ? kFullColor : kHalfColor;
              borderWidth = reachedMid ? 5.0 : 3.5;
              fillColor = reachedMid
                  ? Colors.greenAccent.withValues(alpha: 0.45)
                  : Colors.amberAccent.withValues(alpha: 0.45);
            } else if (isTarget) {
              borderColor = const Color(0xFFFFD740);
              borderWidth = 4.0;
              labelColor = Colors.white;
            }

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5.0),
                child: Listener(
                  onPointerDown: (_) {
                    setState(() {
                      _touchDownLanes.add(index);
                      _lanePressStart[index] = DateTime.now();
                    });
                    _onDown(cell);
                  },
                  onPointerUp: (_) {
                    final start = _lanePressStart.remove(index);
                    final heldSec = start != null
                        ? DateTime.now().difference(start).inMilliseconds / 1000.0
                        : 0.0;
                    setState(() {
                      _touchDownLanes.remove(index);
                    });
                    _onUp(cell, heldSec);
                  },
                  onPointerCancel: (_) {
                    final start = _lanePressStart.remove(index);
                    final heldSec = start != null
                        ? DateTime.now().difference(start).inMilliseconds / 1000.0
                        : 0.0;
                    setState(() {
                      _touchDownLanes.remove(index);
                    });
                    _onUp(cell, heldSec);
                  },
                  child: Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: isTarget ? const Color(0xFF1E1E48) : const Color(0xFF14143A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: borderColor,
                        width: borderWidth,
                      ),
                      boxShadow: isTarget || isPressed
                          ? [
                              BoxShadow(
                                color: borderColor.withValues(alpha: isPressed ? 0.8 : 0.65),
                                blurRadius: isPressed ? (reachedMid ? 16 : 12) : 14,
                                spreadRadius: isPressed ? (reachedMid ? 3 : 2) : 2,
                              )
                            ]
                          : [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          // Bottom-to-top dynamic fill: Orange (0-50%), Green (50-100%)
                          if (fillRatio > 0)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: fillRatio,
                                widthFactor: 1.0,
                                child: Container(color: fillColor),
                              ),
                            ),
                          // Lit target highlight banner showing PUSH
                          if (isTarget && !isPressed)
                            Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                color: const Color(0xFFFFD740).withValues(alpha: 0.85),
                                child: const Text(
                                  'PUSH',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          // Center Key Label (or percentage when pressing)
                          Center(
                            child: Text(
                              labelText,
                              style: TextStyle(
                                color: labelColor,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _line(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontSize: 16)),
      );

  Widget _buildResult() {
    final s = _summary!;
    final w = warmUpSummary;
    final compare = widget.coolDown && w != null && !_early;

    final rows = compare
        ? [
            _line('Reaction time: ${fmtSeconds(w.avgReaction)} to ${fmtSeconds(s.avgReaction)}'),
            _line('Tiles full-pressed: ${w.done}/${w.total} to ${s.done}/${s.total}'),
            _line('Full presses: ${w.full} to ${s.full}'),
            _line('Half presses: ${w.half} to ${s.half}'),
            _line('No presses: ${w.none} to ${s.none}'),
            _line('Total time: ${fmtSeconds(w.totalSeconds)} to ${fmtSeconds(s.totalSeconds)}'),
          ]
        : [
            _line('Tiles full-pressed: ${s.done}/${s.total}'),
            _line('Tiles failed: ${s.failed}'),
            _line('Average reaction time: ${fmtSeconds(s.avgReaction)}'),
            _line('Full presses: ${s.full}'),
            _line('Half presses: ${s.half}'),
            _line('No presses (too short): ${s.none}'),
            _line('Total time: ${fmtSeconds(s.totalSeconds)}'),
          ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(_early ? '$_name stopped' : '$_name complete!',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold, color: kInk)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kTeal, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(compare ? 'Compared with your warm-up' : 'Your results',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: kTeal)),
              const SizedBox(height: 12),
              ...rows,
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('Saved to My Progress',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(
              backgroundColor: kTeal, minimumSize: const Size.fromHeight(54)),
          child: Text(widget.coolDown ? 'Finish Session' : 'Continue',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        if (!widget.coolDown) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => setState(() => _phase = _Phase.setup),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Redo Warm-Up', style: TextStyle(fontSize: 16)),
          ),
        ],
      ],
    );
  }
}