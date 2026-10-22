import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

class _Note {
  final int lane; // index into mode.cells
  double start; // time (s) the note must be pressed
  final double duration;
  final String kind; // half | full | endurance
  int state = 0; // 0 pending, 1 holding, 2 completed, 3 missed, 4 dropped
  double pressAt = 0;
  int timingPts = 0;
  _Note(this.lane, this.start, this.duration, this.kind);
}

enum _RPhase { setup, playing, done }

const Map<String, Color> _kindColors = {
  'half': Color(0xFF00E5FF),
  'full': Color(0xFFFF4081),
  'endurance': Color(0xFFFFD740),
};

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
  final Random _random = Random();
  final List<_Note> _notes = [];
  final PressStats _stats = PressStats();

  _RPhase _phase = _RPhase.setup;
  BoardMode _mode = BoardMode.row;
  Difficulty _difficulty = Difficulty.easy;
  double _t = 0;

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
    input.allowed = _mode.cells;
    input.onDown = _onDown;
    input.onUp = _onUp;
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    input.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Chart + start
  // ---------------------------------------------------------------------
  void _buildChart() {
    _notes.clear();
    double t = _lead + 1.0;
    int prev = -1;
    final lanes = _mode.cells.length;
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
    input.allowed = _mode.cells;
    input.clear();
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
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
  }

  void _flash(String text, Color c) {
    _judgment = text;
    _judgmentColor = c;
  }

  // ---------------------------------------------------------------------
  // Game loop
  // ---------------------------------------------------------------------
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
        } else if (n.state == 1 && _t >= n.start + n.duration) {
          n.state = 2;
          _stats.add(classifyHold(n.duration));
          _completed++;
          _combo++;
          _bestCombo = max(_bestCombo, _combo);
          _longest = max(_longest, n.duration);
          final mult = 1 + min(_combo, 10) * 0.1;
          _score += ((n.timingPts + n.duration * 20) * mult).round();
          _flash('HOLD COMPLETE', Colors.greenAccent);
        }
      }
      if (_notes.every((n) => n.state >= 2)) _finish();
    });
  }

  void _onDown(int cell) {
    if (_phase != _RPhase.playing) return;
    final lane = _mode.cells.indexOf(cell);
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
    final lane = _mode.cells.indexOf(cell);
    for (final n in _notes) {
      if (n.lane == lane && n.state == 1) {
        setState(() {
          final held = _t - n.pressAt;
          n.state = 4;
          final r = classifyHold(held);
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

  // inside setState
  void _finish({bool early = false}) {
    _ticker.stop();
    input.clear();
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
      notes: 'Score $_score | ${_mode.label} | holds $_completed/${_notes.length} | '
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
      appBar: AppBar(title: const Text('Rhythm Game')),
      body: SafeArea(
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
    );
  }

  Widget _setup() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.music_note_rounded, size: 72, color: kTeal),
        const SizedBox(height: 8),
        const Text('Rhythm Game',
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
        const SizedBox(height: 12),
        chipRow<BoardMode>(
          title: 'Board',
          values: BoardMode.values,
          selected: _mode,
          label: (m) => m.label,
          onSelected: (m) => setState(() {
            _mode = m;
            input.allowed = m.cells;
          }),
        ),
        const SizedBox(height: 8),
        practiceSwitch(PushConfig.practice,
            (v) => setState(() => PushConfig.practice = v)),
        Text(pressRulesText(),
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
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
            child: _mode == BoardMode.row
                ? ClipRRect(
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
                            for (var l = 0; l < 3; l++)
                              if (input.isDown(_mode.cells[l])) l
                          },
                        ),
                      ),
                    ),
                  )
                : PushBoard(mode: _mode, input: input, styleOf: _gridStyle),
          ),
          const SizedBox(height: 8),
          if (_mode == BoardMode.row)
            SizedBox(
              height: 100,
              child: PushBoard(
                  mode: BoardMode.row, input: input, styleOf: _padStyle),
            ),
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

  TileStyle _padStyle(int cell) {
    const colors = [Color(0xFF00E5FF), Color(0xFFFF4081), Color(0xFFFFD740)];
    final lane = _mode.cells.indexOf(cell);
    return TileStyle(
      bg: const Color(0xFF14143A),
      border: colors[lane % 3],
      borderWidth: 3,
      labelColor: Colors.white,
    );
  }

  TileStyle _gridStyle(int cell) {
    const dark = Color(0xFF14143A);
    _Note? up;
    _Note? hold;
    for (final n in _notes) {
      if (n.lane != cell) continue;
      if (n.state == 1) {
        hold = n;
      } else if (n.state == 0 &&
          n.start - _t <= _lead &&
          (up == null || n.start < up.start)) {
        up = n;
      }
    }

    if (hold != null) {
      final held = _t - hold.pressAt;
      return TileStyle(
        bg: dark,
        border: kFullColor,
        borderWidth: 4,
        label:
            '${held.toStringAsFixed(1)}/${hold.duration.toStringAsFixed(1)}s',
        labelColor: Colors.white,
      );
    }
    if (up != null) {
      final p = (1 - (up.start - _t) / _lead).clamp(0.0, 1.0);
      final color = _kindColors[up.kind]!;
      return TileStyle(
        bg: dark,
        border: color,
        borderWidth: 2 + 3 * p,
        label: '${up.duration.toStringAsFixed(1)}s',
        labelColor: Colors.white,
        overlay: Stack(
          children: [
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.45,
                heightFactor: 0.45,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                ),
              ),
            ),
            Center(
              child: FractionallySizedBox(
                widthFactor: 1 - 0.55 * p,
                heightFactor: 1 - 0.55 * p,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 4),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const TileStyle(
        bg: dark, border: Color(0xFF3A3A6A), labelColor: Colors.white);
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
// Perspective highway (1x3 mode)
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
    double cx(int lane, double y) =>
        s.width / 2 + (lane - 1) * (fullW / 3) * sc(y);
    double hw(double y) => (fullW / 3) * sc(y) / 2;

    const laneColors = [Color(0xFF00E5FF), Color(0xFFFF4081), Color(0xFFFFD740)];

    // lanes
    for (var l = 0; l < 3; l++) {
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
              ? laneColors[l].withValues(alpha: 0.28)
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

    // hit line
    canvas.drawLine(
      Offset(0, hitY),
      Offset(s.width, hitY),
      Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 3,
    );

    // notes
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