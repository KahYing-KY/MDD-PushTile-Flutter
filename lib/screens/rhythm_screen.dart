import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

class _Note {
  final int lane; // index 0..3 for 1x4
  double start; // time (s) the note must be pressed
  final double duration;
  final String kind; // half | full | endurance
  int state = 0; // 0 pending, 1 holding, 2 completed, 3 missed, 4 dropped
  double pressAt = 0;
  int timingPts = 0;
  bool midReached = false; // Tracks if the 50% midpoint mark was hit during hold
  _Note(this.lane, this.start, this.duration, this.kind);
}

enum _RPhase { setup, playing, done }

const Map<String, Color> _kindColors = {
  'half': Color(0xFF00E5FF),
  'full': Color(0xFFFF4081),
  'endurance': Color(0xFFFFD740),
};

/// Customised to match the diagram layout (Left -> Bottom-Left -> Bottom-Right -> Right)
const List<Color> _laneColors = [
  Color(0xFFF0788C), // Lane 0 - Pink (Push tile left)
  Color(0xFF7BD095), // Lane 1 - Green (Push tile bottom left)
  Color(0xFFFFC95C), // Lane 2 - Yellow (Push tile bottom right)
  Color(0xFF63A7EF), // Lane 3 - Blue (Push tile right)
];

const List<String> _laneKeyLabels = ['D', 'F', 'J', 'K'];

/// Classifies a hold result scaled relative to a specific note's target duration.
PressResult classifyNoteHold(double heldSeconds, double targetDuration) {
  if (targetDuration <= 0) return PressResult.none;
  final ratio = heldSeconds / targetDuration;
  if (ratio >= 0.90) return PressResult.full;
  if (ratio >= 0.45) return PressResult.half;
  return PressResult.none;
}

class RhythmGameScreen extends StatefulWidget {
  const RhythmGameScreen({super.key});

  @override
  State<RhythmGameScreen> createState() => _RhythmGameScreenState();
}

class _RhythmGameScreenState extends State<RhythmGameScreen>
    with SingleTickerProviderStateMixin {
  static const double _window = 0.45; // seconds either side of note start

  late final Ticker _ticker;
  final PushController input = PushController();
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  final List<_Note> _notes = [];
  final PressStats _stats = PressStats();
  final Set<int> _touchDownLanes = {}; // Tracks active touch/mouse/keyboard button presses

  _RPhase _phase = _RPhase.setup;
  final BoardMode _mode = BoardMode.row;
  Difficulty _difficulty = Difficulty.easy;
  double _t = 0;

  /// Retrieves 4 lane cells [0, 1, 2, 3] for 1x4 mode
  List<int> get _laneCells => _mode.cells.length >= 4 
      ? _mode.cells.sublist(0, 4) 
      : const [0, 1, 2, 3];

  int _score = 0, _combo = 0, _bestCombo = 0;
  int _completed = 0, _missed = 0, _dropped = 0, _perfect = 0, _good = 0;
  double _longest = 0;
  bool _early = false;
  String _judgment = '';
  Color _judgmentColor = Colors.white;

  double get _lead => switch (_difficulty) {
        Difficulty.easy => 3.6,
        Difficulty.medium => 3.0,
        Difficulty.hard => 2.6,
      };

  double get _gap => switch (_difficulty) {
        Difficulty.easy => 1.6,
        Difficulty.medium => 1.3,
        Difficulty.hard => 1.1,
      };

  double get _enduranceSec => switch (_difficulty) {
        Difficulty.easy => 8.0,
        Difficulty.medium => 12.0,
        Difficulty.hard => 15.0,
      };

  List<String> get _pattern => switch (_difficulty) {
        Difficulty.easy => [
            'half', 'half', 'full', 'half', 'full', 'half', 'endurance', 'half'
          ],
        Difficulty.medium => [
            'half', 'full', 'half', 'full', 'full', 'endurance', 'half',
            'full', 'half', 'endurance'
          ],
        Difficulty.hard => [
            'full', 'half', 'full', 'full', 'endurance', 'full', 'half',
            'full', 'endurance', 'full', 'full', 'half'
          ],
      };

  @override
  void initState() {
    super.initState();
    input.allowed = _laneCells;
    input.onDown = _onDown;
    input.onUp = _onUp;
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    input.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Chart + start
  // ---------------------------------------------------------------------
  void _buildChart() {
    _notes.clear();
    double t = _lead + 1.0;
    int prev = -1;
    final lanes = _laneCells.length; // 4 lanes
    for (final k in _pattern) {
      int lane;
      do {
        lane = _random.nextInt(lanes);
      } while (lane == prev && lanes > 1);
      prev = lane;
      final d = switch (k) {
        'half' => PushConfig.halfSec,
        'full' => PushConfig.fullSec,
        _ => _enduranceSec * PushConfig.scale,
      };
      _notes.add(_Note(lane, t, d, k));
      t += d + _gap;
    }
  }

  void _startGame() {
    trainingStarted = true;
    input.allowed = _laneCells;
    input.clear();
    _touchDownLanes.clear();
    setState(() {
      _buildChart();
      _stats.reset();
      _score = 0;
      _combo = 0;
      _bestCombo = 0;
      _completed = 0;
      _missed = 0;
      _dropped = 0;
      _perfect = 0;
      _good = 0;
      _longest = 0;
      _early = false;
      _judgment = '';
      _t = 0;
      _phase = _RPhase.playing;
    });
    
    // Request focus for keyboard input when game starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });

    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
  }

  void _flash(String text, Color c) {
    _judgment = text;
    _judgmentColor = c;
  }

  // ---------------------------------------------------------------------
  // Game loop & Keyboard handler mapping (D, F, J, K)
  // ---------------------------------------------------------------------
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_phase != _RPhase.playing) return KeyEventResult.ignored;

    // Map keys D, F, J, K to lane indices 0, 1, 2, 3
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
      // Prevent duplicate trigger on key repeat
      if (!_touchDownLanes.contains(laneIndex)) {
        setState(() {
          _touchDownLanes.add(laneIndex!);
        });
        _onDown(cell);
      }
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      if (_touchDownLanes.contains(laneIndex)) {
        setState(() {
          _touchDownLanes.remove(laneIndex!);
        });
        _onUp(cell, 0);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onTick(Duration e) {
    _t = e.inMicroseconds / 1e6;
    if (_phase != _RPhase.playing) return;

    setState(() {
      for (final n in _notes) {
        if (n.state == 0 && _t > n.start + _window) {
          n.state = 3;
          _missed++;
          _combo = 0;
          _flash('MISS', Colors.redAccent);
        } else if (n.state == 1) {
          final held = _t - n.pressAt;

          // Visual feedback trigger upon reaching 50% midpoint
          if (!n.midReached && held >= n.duration * 0.5) {
            n.midReached = true;
            _flash('HALF WAY! (50%)', kHalfColor);
          }

          if (_t >= n.start + n.duration) {
            n.state = 2;
            _stats.add(classifyNoteHold(n.duration, n.duration));
            _completed++;
            _combo++;
            _bestCombo = max(_bestCombo, _combo);
            _longest = max(_longest, n.duration);
            final mult = 1 + min(_combo, 10) * 0.1;
            _score += ((n.timingPts + n.duration * 20) * mult).round();
            _flash('HOLD COMPLETE', Colors.greenAccent);
          }
        }
      }
      if (_notes.every((n) => n.state >= 2)) _finish();
    });
  }

  void _onDown(int cell) {
    if (_phase != _RPhase.playing) return;
    final lane = _laneCells.indexOf(cell);
    if (lane < 0) return;
    _Note? best;
    double bd = 99;
    for (final n in _notes) {
      if (n.lane == lane && n.state == 0) {
        final d = (_t - n.start).abs();
        if (d <= _window && d < bd) {
          best = n;
          bd = d;
        }
      }
    }
    if (best == null) return;
    final note = best;
    setState(() {
      if (bd <= 0.2) {
        note.timingPts = 100;
        _perfect++;
        _flash('PERFECT', Colors.greenAccent);
      } else {
        note.timingPts = 50;
        _good++;
        _flash('GOOD', Colors.lightBlueAccent);
      }
      note.state = 1;
      note.pressAt = _t;
      note.start = _t; // snap so hold length is measured from the press
    });
  }

  void _onUp(int cell, double sec) {
    if (_phase != _RPhase.playing) return;
    final lane = _laneCells.indexOf(cell);
    if (lane < 0) return;
    for (final n in _notes) {
      if (n.lane == lane && n.state == 1) {
        setState(() {
          final held = _t - n.pressAt;
          n.state = 4;
          final r = classifyNoteHold(held, n.duration);
          _stats.add(r);
          _dropped++;
          _combo = 0;
          _longest = max(_longest, held);
          _score += (held * 10).round();
          _flash(
              r == PressResult.none
                  ? 'TOO SHORT'
                  : (r == PressResult.half ? 'RELEASED (HALF)' : 'RELEASED (FULL)'),
              Colors.orangeAccent);
        });
        break;
      }
    }
  }

  void _finish({bool early = false}) {
    _ticker.stop();
    input.clear();
    _touchDownLanes.clear();
    _early = early;
    _phase = _RPhase.done;

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Rhythm Game',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: _t.round(),
      correctAttempts: _completed,
      incorrectAttempts: _notes.length - _completed,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Score $_score | 1x4 Mode | holds $_completed/${_notes.length} | '
          'missed $_missed, released early $_dropped | perfect $_perfect, good $_good | '
          'longest hold ${_longest.toStringAsFixed(1)} s | best combo $_bestCombo',
    ));
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rhythm Game (1x4)')),
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
                  _RPhase.setup => _setup(),
                  _RPhase.playing => _play(),
                  _RPhase.done => _summary(),
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
        const Icon(Icons.music_note_rounded, size: 72, color: kTeal),
        const SizedBox(height: 8),
        const Text('1x4 Rhythm Game',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          'Press and HOLD a tile when its note reaches the line, and keep holding until the note ends.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            _legendDot(_kindColors['half']!,
                'Half hold ${PushConfig.halfSec.toStringAsFixed(1)} s'),
            _legendDot(_kindColors['full']!,
                'Full hold ${PushConfig.fullSec.toStringAsFixed(1)} s'),
            _legendDot(_kindColors['endurance']!,
                'Endurance ${(_enduranceSec * PushConfig.scale).toStringAsFixed(0)} s'),
          ],
        ),
        const SizedBox(height: 16),
        chipRow<Difficulty>(
          title: 'Level',
          values: Difficulty.values,
          selected: _difficulty,
          label: (d) => d.label,
          onSelected: (d) => setState(() => _difficulty = d),
        ),
        const SizedBox(height: 8),
        practiceSwitch(PushConfig.practice,
            (v) => setState(() => PushConfig.practice = v)),
        const Text(
          'Press evaluation scaled to note length:\n'
          'Under 45% = no press   •   45% to 90% = half press   •   90%+ = full press.\n'
          'Controls: Use on-screen pads or keyboard keys D  F  J  K.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _startGame,
          style: FilledButton.styleFrom(
              backgroundColor: kTeal, minimumSize: const Size.fromHeight(56)),
          child: const Text('Start',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }

  Widget _legendDot(Color c, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _play() {
    final done = _notes.where((n) => n.state >= 2).length;
    const white = TextStyle(
        color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold);

    return Container(
      color: const Color(0xFF05051A),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Score $_score', style: white),
              Text('Note ${min(done + 1, _notes.length)}/${_notes.length}',
                  style: white.copyWith(color: Colors.white70)),
              Text('Combo x$_combo',
                  style: white.copyWith(color: Colors.orangeAccent)),
            ],
          ),
          SizedBox(
            height: 38,
            child: Center(
              child: Text(_judgment,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: _judgmentColor)),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AnimatedBuilder(
                animation: input,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _HighwayPainter(
                    _notes,
                    _t,
                    _lead,
                    {
                      for (var l = 0; l < 4; l++)
                        if (input.isDown(_laneCells[l]) ||
                            _touchDownLanes.contains(l))
                          l
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Interactive 4-Button Row with percentage fill animation
          _buildFourButtonRow(),
          const SizedBox(height: 8),
          pressStatsBar(_stats, dark: true),
          TextButton(
            onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End session',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  /// Builds 4 interactive lane buttons with vertical progress fill based on hold percentage
  Widget _buildFourButtonRow() {
    return AnimatedBuilder(
      animation: input,
      builder: (context, _) {
        return Row(
          children: List.generate(4, (index) {
            final cell = _laneCells[index];
            final isPressed =
                input.isDown(cell) || _touchDownLanes.contains(index);
            final color = _laneColors[index];

            // Check if there is an active hold note in this lane
            _Note? holdNote;
            for (final n in _notes) {
              if (n.lane == index && n.state == 1) {
                holdNote = n;
                break;
              }
            }

            double fillRatio = 0.0;
            String labelText = _laneKeyLabels[index];
            Color labelColor = Colors.white;
            Color borderColor = color;
            double borderWidth = 3.0;
            Color fillColor = color.withValues(alpha: 0.45);

            if (holdNote != null) {
              final held = _t - holdNote.pressAt;
              fillRatio = (holdNote.duration > 0 ? held / holdNote.duration : 0.0)
                  .clamp(0.0, 1.0);
              final pct = (fillRatio * 100).round();
              final reachedMid = held >= holdNote.duration * 0.5;

              labelText = '$pct%';
              labelColor = reachedMid ? Colors.greenAccent : Colors.amberAccent;
              borderColor = reachedMid ? kFullColor : kHalfColor;
              borderWidth = reachedMid ? 5.0 : 3.0;
              fillColor = reachedMid
                  ? Colors.greenAccent.withValues(alpha: 0.4)
                  : Colors.amberAccent.withValues(alpha: 0.4);
            } else if (isPressed) {
              fillRatio = 1.0;
            }

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Listener(
                  onPointerDown: (_) {
                    setState(() {
                      _touchDownLanes.add(index);
                    });
                    _onDown(cell);
                  },
                  onPointerUp: (_) {
                    setState(() {
                      _touchDownLanes.remove(index);
                    });
                    _onUp(cell, 0);
                  },
                  onPointerCancel: (_) {
                    setState(() {
                      _touchDownLanes.remove(index);
                    });
                    _onUp(cell, 0);
                  },
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF14143A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: borderColor,
                        width: borderWidth,
                      ),
                      boxShadow: isPressed || holdNote != null
                          ? [
                              BoxShadow(
                                color: borderColor.withValues(alpha: 0.65),
                                blurRadius: 14,
                                spreadRadius: 2,
                              )
                            ]
                          : [],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          // Bottom-to-top visual fill based on hold percentage
                          if (fillRatio > 0)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: fillRatio,
                                widthFactor: 1.0,
                                child: Container(color: fillColor),
                              ),
                            ),
                          // Center label text
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

  Widget _summary() {
    final accuracy =
        _notes.isEmpty ? 0.0 : _completed / _notes.length * 100;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
        const SizedBox(height: 8),
        Text(_early ? 'Session stopped' : 'Performance Summary',
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              _row('Final score', '$_score'),
              const Divider(height: 18),
              _row('Holds completed', '$_completed / ${_notes.length}'),
              const Divider(height: 18),
              _row('Completion', '${accuracy.toStringAsFixed(1)}%'),
              const Divider(height: 18),
              _row('Longest hold', '${_longest.toStringAsFixed(1)} s'),
              const Divider(height: 18),
              _row('Perfect / Good', '$_perfect / $_good'),
              const Divider(height: 18),
              _row('Released early', '$_dropped'),
              const Divider(height: 18),
              _row('Missed', '$_missed'),
              const Divider(height: 18),
              _row('Full / Half / No press',
                  '${_stats.full} / ${_stats.half} / ${_stats.none}'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('Saved to My Progress',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => setState(() => _phase = _RPhase.setup),
          icon: const Icon(Icons.replay),
          label: const Text('Play Again',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          style: FilledButton.styleFrom(
              backgroundColor: kTeal,
              padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 15,
                color: Colors.black54,
                fontWeight: FontWeight.w500)),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ===========================================================================
// Perspective highway (1x4 mode)
// ===========================================================================
class _HighwayPainter extends CustomPainter {
  final List<_Note> notes;
  final double t;
  final double lead;
  final Set<int> down;

  _HighwayPainter(this.notes, this.t, this.lead, this.down);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF05051A), Color(0xFF241046)],
        ).createShader(rect),
    );

    final hitY = s.height * 0.88;
    final horizon = s.height * 0.03;
    final span = hitY - horizon;
    final fullW = s.width * 0.96;

    double yAt(double p) => horizon + span * pow(p, 1.6).toDouble();
    double sc(double y) => 0.30 + 0.70 * ((y - horizon) / span);

    // 1x4 Perspective center calculations
    double cx(int lane, double y) =>
        s.width / 2 + (lane - 1.5) * (fullW / 4) * sc(y);
    double hw(double y) => (fullW / 4) * sc(y) / 2;

    // Render 4 Lanes
    for (var l = 0; l < 4; l++) {
      final path = Path()
        ..moveTo(cx(l, horizon) - hw(horizon), horizon)
        ..lineTo(cx(l, horizon) + hw(horizon), horizon)
        ..lineTo(cx(l, s.height) + hw(s.height), s.height)
        ..lineTo(cx(l, s.height) - hw(s.height), s.height)
        ..close();
      final isDown = down.contains(l);
      canvas.drawPath(
        path,
        Paint()
          ..color = isDown
              ? _laneColors[l].withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: l.isEven ? 0.04 : 0.08),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.15),
      );
    }

    // Hit line
    canvas.drawLine(
      Offset(0, hitY),
      Offset(s.width, hitY),
      Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 3,
    );

    // Render Notes
    for (final n in notes) {
      if (n.state != 0 && n.state != 1) continue;
      final pHead = n.state == 1 ? 1.0 : (t - (n.start - lead)) / lead;
      if (pHead <= 0 || pHead > 1.25) continue;
      var pTail = (t - (n.start + n.duration - lead)) / lead;
      if (pTail < 0) pTail = 0;

      final yH = yAt(pHead);
      final yT = yAt(pTail);
      final color = _kindColors[n.kind]!;
      const bw = 0.55;

      final body = Path()
        ..moveTo(cx(n.lane, yT) - hw(yT) * bw, yT)
        ..lineTo(cx(n.lane, yT) + hw(yT) * bw, yT)
        ..lineTo(cx(n.lane, yH) + hw(yH) * bw, yH)
        ..lineTo(cx(n.lane, yH) - hw(yH) * bw, yH)
        ..close();
      canvas.drawPath(
          body, Paint()..color = color.withValues(alpha: n.state == 1 ? 0.75 : 0.45));

      // -----------------------------------------------------------------
      // Midpoint bar with active glowing visual feedback when hold >= 50%
      // -----------------------------------------------------------------
      final pMid = (t - (n.start + n.duration / 2 - lead)) / lead;
      if (pMid > pTail && pMid < pHead) {
        final yM = yAt(pMid);
        final hwM = hw(yM) * bw;
        final bool isHeldPastMid =
            n.state == 1 && (t - n.pressAt >= n.duration * 0.5);

        if (isHeldPastMid) {
          // Glowing aura behind the 50% midpoint line
          canvas.drawLine(
            Offset(cx(n.lane, yM) - hwM * 1.2, yM),
            Offset(cx(n.lane, yM) + hwM * 1.2, yM),
            Paint()
              ..color = kHalfColor.withValues(alpha: 0.85)
              ..strokeWidth = 7.0
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
          );
        }

        // Midpoint bar line
        canvas.drawLine(
          Offset(cx(n.lane, yM) - hwM, yM),
          Offset(cx(n.lane, yM) + hwM, yM),
          Paint()
            ..color =
                isHeldPastMid ? Colors.amberAccent : Colors.white.withValues(alpha: 0.85)
            ..strokeWidth = isHeldPastMid ? 3.5 : 2.0,
        );
      }

      final cap = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx(n.lane, yH), yH),
          width: hw(yH) * 2 * 0.9,
          height: 16 * sc(yH),
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(
          cap, Paint()..color = color.withValues(alpha: pHead > 1 ? 0.4 : 1.0));
    }
  }

  @override
  bool shouldRepaint(covariant _HighwayPainter old) => true;
}