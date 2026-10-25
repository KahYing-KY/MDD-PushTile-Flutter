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

class TwoHandPlayScreen extends StatefulWidget {
  const TwoHandPlayScreen({super.key});

  @override
  State<TwoHandPlayScreen> createState() => _TwoHandPlayScreenState();
}

class _TwoHandPlayScreenState extends State<TwoHandPlayScreen> {
  final PushController input = PushController();
  final FocusNode _focusNode = FocusNode();
  final Random _rng = Random();
  final Stopwatch _total = Stopwatch();
  final Stopwatch _idle = Stopwatch();
  final PressStats _stats = PressStats();
  Timer? _ticker;

  _Phase _phase = _Phase.setup;
  Difficulty _difficulty = Difficulty.easy;

  /// Standard 1x4 lane cell indices [0, 1, 2, 3]
  final List<int> _laneCells = const [0, 1, 2, 3];

  final Set<int> _touchDownLanes = {}; // Active touch, mouse, and keyboard button press indices
  final Map<int, DateTime> _lanePressStart = {}; // Tracks hold start for visual fill timing

  // 1x4 row uses index 1 as default anchor (F key)
  final int _anchor = 1;
  List<int> _targets = [];
  int _idx = 0;
  int _tries = 0;
  int _done = 0;
  int _failed = 0;
  int _timeouts = 0;
  int _drops = 0;
  bool _armed = false;
  bool _early = false;
  String _message = '';

  int get _targetCount => switch (_difficulty) {
        Difficulty.easy => 6,
        Difficulty.medium => 10,
        Difficulty.hard => 14,
      };

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

  List<int> _makeTargets() {
    final out = <int>[];
    final others = [
      for (var i = 0; i < 4; i++)
        if (i != _anchor) i
    ];
    for (var i = 0; i < _targetCount; i++) {
      int c;
      do {
        c = others[_rng.nextInt(others.length)];
      } while (out.isNotEmpty && c == out.last);
      out.add(c);
    }
    return out;
  }

  void _start() {
    trainingStarted = true;
    setState(() {
      input.allowed = _laneCells;
      input.clear();
      _touchDownLanes.clear();
      _lanePressStart.clear();
      _targets = _makeTargets();
      _idx = 0;
      _tries = 0;
      _done = 0;
      _failed = 0;
      _timeouts = 0;
      _drops = 0;
      _armed = false;
      _early = false;
      _stats.reset();
      _idle
        ..stop()
        ..reset();
      _total
        ..reset()
        ..start();
      _message = 'Hold the anchor tile (${_laneKeyLabels[_anchor]}) until it reaches a full press.';
      _phase = _Phase.playing;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _phase != _Phase.playing) return;
    setState(() {
      if (!_armed) {
        final anchorLaneIndex = _anchor;
        final isAnchorDown = anchorLaneIndex >= 0 && (_touchDownLanes.contains(anchorLaneIndex) || input.isDown(_anchor));
        
        if (isAnchorDown) {
          final start = _lanePressStart[anchorLaneIndex];
          final heldSec = start != null 
              ? DateTime.now().difference(start).inMilliseconds / 1000.0 
              : input.holdSeconds(_anchor);
          
          if (heldSec >= PushConfig.fullSec) {
            _armed = true;
            _stats.add(PressResult.full);
            _idle.start();
            _message = 'Anchor locked! Push the lit tile with your other hand.';
            
            // Reset hold start for any non-anchor keys currently down so progress starts fresh from 0%
            for (var i = 0; i < 4; i++) {
              if (i != _anchor) {
                final cell = _laneCells[i];
                if (_touchDownLanes.contains(i) || input.isDown(cell)) {
                  _lanePressStart[i] = DateTime.now();
                }
              }
            }
          }
        }
      } else {
        final targetCell = _targets[_idx];
        final targetLaneIndex = targetCell;
        final isTargetDown = targetLaneIndex >= 0 && (_touchDownLanes.contains(targetLaneIndex) || input.isDown(targetCell));

        if (!isTargetDown && _idle.elapsedMilliseconds / 1000 >= PushConfig.tileTimeoutSec) {
          _timeouts++;
          _failed++;
          _advance('Time out - next tile.');
        }
      }
    });
  }

  // =========================================================================
  // Keyboard Event Handler (D, F, J, K for 1x4 mode)
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

    // Lock non-anchor keys if the anchor is not armed/held down
    if (cell != _anchor && !_armed) {
      return KeyEventResult.handled;
    }

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
    if (cell != _anchor && !_armed) return;

    final laneIndex = cell;
    if (laneIndex >= 0 && !_lanePressStart.containsKey(laneIndex)) {
      _lanePressStart[laneIndex] = DateTime.now();
    }
  }

  void _onUp(int cell, double sec) {
    if (_phase != _Phase.playing) return;

    final laneIndex = cell;
    if (laneIndex >= 0) {
      _lanePressStart.remove(laneIndex);
    }

    // Anchor tile
    if (cell == _anchor) {
      setState(() {
        if (_armed) {
          _armed = false;
          _idle.stop();
          _drops++;
          final anchorLabel = _laneKeyLabels[_anchor];
          _message = 'Anchor released! Put your hand back and hold $anchorLabel to full press.';
        } else {
          _stats.add(classifyHold(sec));
          final anchorLabel = _laneKeyLabels[_anchor];
          _message = 'Keep holding the anchor ($anchorLabel) until it turns full.';
        }
      });
      return;
    }

    // Target presses only count while the anchor is locked
    if (!_armed) return;
    if (cell != _targets[_idx]) {
      setState(() => _message = 'That is not the lit tile.');
      return;
    }

    final r = classifyHold(sec);
    setState(() {
      _stats.add(r);
      if (r == PressResult.full) {
        _done++;
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
        _advance('Could not full-press this tile - moving on.');
      } else {
        _message = r == PressResult.half
            ? 'Half press - try again ($_tries/${PushConfig.maxTries}).'
            : 'Too short - hold longer ($_tries/${PushConfig.maxTries}).';
      }
    });
  }

  void _advance(String msg) {
    _idx++;
    _tries = 0;
    _lanePressStart.clear();
    if (_idx >= _targets.length) {
      _finish();
      return;
    }
    _idle
      ..stop()
      ..reset();
    if (_armed) _idle.start();
    _message = msg;
  }

  void _finish({bool early = false}) {
    _total.stop();
    _idle.stop();
    _ticker?.cancel();
    input.clear();
    _touchDownLanes.clear();
    _lanePressStart.clear();
    _early = early;
    _phase = _Phase.done;

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Hold & Reach',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: (_total.elapsedMilliseconds / 1000).round(),
      correctAttempts: _done,
      incorrectAttempts: _failed,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: '1x4 Mode | anchor ${_laneKeyLabels[_anchor]} | '
          'anchor drops $_drops | timeouts $_timeouts | '
          'targets ${_done + _failed}/${_targets.length}',
    ));
  }

  // =========================================================================
  // UI
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hold & Reach')),
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: PushKeyboard(
            controller: input,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: switch (_phase) {
                  _Phase.setup => _setup(),
                  _Phase.playing => _play(),
                  _Phase.done => _result(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _setup() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Hold & Reach',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          'One hand HOLDS the anchor tile at full press for the whole round. '
          'The other hand pushes the lit tile. If the anchor is released, '
          'the round pauses until you hold it again. Tap End if you need to stop.',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 16),
        const Text('Anchor: F (Lane 1). Targets alternate among D, J, K.',
            style: TextStyle(fontWeight: FontWeight.w600, color: kTeal)),
        const SizedBox(height: 12),
        chipRow<Difficulty>(
          title: 'Level (targets per round)',
          values: Difficulty.values,
          selected: _difficulty,
          label: (d) => '${d.label} (${switch (d) {
                Difficulty.easy => 6,
                Difficulty.medium => 10,
                Difficulty.hard => 14,
              }})',
          onSelected: (d) => setState(() => _difficulty = d),
        ),
        const SizedBox(height: 8),
        practiceSwitch(PushConfig.practice,
            (v) => setState(() => PushConfig.practice = v)),
        const Text(
            'Controls: Use on-screen pads or keyboard keys D   F   J   K.',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _start,
          style: FilledButton.styleFrom(
              backgroundColor: kBlue, minimumSize: const Size.fromHeight(56)),
          child: const Text('Start',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _play() {
    return Container(
      color: const Color(0xFF05051A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Center(
              child: Text(_message,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.w600, 
                      color: Colors.white)),
            ),
          ),
          Text(fmtSeconds(_total.elapsedMilliseconds / 1000),
              style: const TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: kTeal)),
          Text(
              'Target ${min(_idx + 1, _targets.length)} of ${_targets.length}'
              '   •   try ${_tries + 1}/${PushConfig.maxTries}'
              '   •   drops $_drops',
              style: const TextStyle(
                  fontSize: 15, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.orangeAccent)),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: _buildFourButtonRow(),
            ),
          ),
          const SizedBox(height: 8),
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

  /// Builds the 1x4 horizontal rhythm-game lane layout
  Widget _buildFourButtonRow() {
    return AnimatedBuilder(
      animation: input,
      builder: (context, _) {
        final targetCell = _targets.isNotEmpty && _idx < _targets.length ? _targets[_idx] : -1;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (index) {
            final cell = _laneCells[index];
            final isAnchor = cell == _anchor;
            final isLocked = !isAnchor && !_armed;
            final isPressed = !isLocked && (input.isDown(cell) || _touchDownLanes.contains(index));
            final isTarget = cell == targetCell;
            final color = _laneColors[index];

            double fillRatio = 0.0;
            if (!isLocked) {
              if (isPressed && _lanePressStart.containsKey(index)) {
                final heldMs = DateTime.now().difference(_lanePressStart[index]!).inMilliseconds;
                final fullMs = (PushConfig.fullSec * 1000).round();
                fillRatio = fullMs > 0 ? (heldMs / fullMs).clamp(0.0, 1.0) : 0.0;
              } else if (input.isDown(cell)) {
                fillRatio = (input.holdSeconds(cell) / PushConfig.fullSec).clamp(0.0, 1.0);
              }
            }

            final pct = (fillRatio * 100).round();
            final reachedMid = fillRatio >= 0.50;

            String labelText = _laneKeyLabels[index];
            Color labelColor = Colors.white;
            Color borderColor = color;
            double borderWidth = 3.0;
            Color fillColor = color.withValues(alpha: 0.45);

            if (isAnchor) {
              borderColor = _armed ? kFullColor : kHalfColor;
              borderWidth = _armed ? 5.0 : 4.0;
              fillColor = _armed ? const Color(0xFFDDF4E8) : const Color(0xFFFFF3C4);
            } else if (isLocked) {
              borderColor = color.withValues(alpha: 0.25);
              borderWidth = 2.0;
              fillColor = Colors.transparent;
              labelColor = Colors.white38;
            } else if (_armed && isTarget) {
              borderColor = Colors.redAccent;
              borderWidth = 5.0;
            }

            if (isPressed && !isAnchor) {
              labelText = '$pct%';
              labelColor = reachedMid ? Colors.greenAccent : Colors.amberAccent;
              borderColor = reachedMid ? kFullColor : kHalfColor;
              borderWidth = reachedMid ? 5.0 : 3.5;
              fillColor = reachedMid
                  ? Colors.greenAccent.withValues(alpha: 0.45)
                  : Colors.amberAccent.withValues(alpha: 0.45);
            }

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5.0),
                child: Opacity(
                  opacity: isLocked ? 0.4 : 1.0,
                  child: Listener(
                    onPointerDown: (_) {
                      if (isLocked) return;
                      setState(() {
                        _touchDownLanes.add(index);
                        _lanePressStart[index] = DateTime.now();
                      });
                      _onDown(cell);
                    },
                    onPointerUp: (_) {
                      if (isLocked) return;
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
                      if (isLocked) return;
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
                        color: isLocked 
                            ? const Color(0xFF0A0A18) 
                            : (isTarget && _armed ? const Color(0xFF1E1E48) : const Color(0xFF14143A)),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: borderColor,
                          width: borderWidth,
                        ),
                        boxShadow: (isTarget || isPressed || isAnchor) && !isLocked
                            ? [
                                BoxShadow(
                                  color: borderColor.withValues(alpha: isPressed ? 0.8 : 0.65),
                                  blurRadius: isPressed ? 16 : 14,
                                  spreadRadius: 2,
                                )
                              ]
                            : [],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            if (fillRatio > 0 && !isLocked)
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: fillRatio,
                                  widthFactor: 1.0,
                                  child: Container(color: fillColor),
                                ),
                              ),
                            if (isAnchor)
                              Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  color: (_armed ? kFullColor : const Color(0xFF8A5A00)).withValues(alpha: 0.85),
                                  child: Text(
                                    _armed ? 'HOLD ✓' : 'HOLD',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            if (_armed && isTarget && !isPressed)
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
              ),
            );
          }),
        );
      },
    );
  }

  Widget _line(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 16)),
      );

  Widget _result() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(_early ? 'Session ended' : 'Round complete!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
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
              _line('Targets full-pressed: $_done / ${_targets.length}'),
              _line('Targets failed: $_failed'),
              _line('Anchor drops: $_drops'),
              _line('Full presses: ${_stats.full}'),
              _line('Half presses: ${_stats.half}'),
              _line('No presses (too short): ${_stats.none}'),
              _line('Total time: ${fmtSeconds(_total.elapsedMilliseconds / 1000)}'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('Saved to My Progress',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => setState(() => _phase = _Phase.setup),
          style: FilledButton.styleFrom(
              backgroundColor: kBlue, minimumSize: const Size.fromHeight(50)),
          child: const Text('Play Again'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }
}