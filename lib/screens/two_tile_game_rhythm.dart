import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, playing, done }

class _RhythmNote {
  final int lane;
  double start;
  final double duration;
  final String kind;
  int state = 0;
  double pressedAt = 0;
  int timingPoints = 0;
  _RhythmNote(this.lane, this.start, this.duration, this.kind);
}

const _noteColors = <String, Color>{
  'half': Color(0xFF00E5FF),
  'full': Color(0xFFFF4081),
  'endurance': Color(0xFFFFD740),
};

class TwoTileGameRhythmScreen extends StatefulWidget {
  const TwoTileGameRhythmScreen({super.key});

  @override
  State<TwoTileGameRhythmScreen> createState() =>
      _TwoTileGameRhythmScreenState();
}

class _TwoTileGameRhythmScreenState extends State<TwoTileGameRhythmScreen>
    with SingleTickerProviderStateMixin {
  static const _cells = <int>[3, 5];
  static const double _window = 0.45;
  final PushController input = PushController();
  final Random _random = Random();
  final PressStats _stats = PressStats();
  final List<_RhythmNote> _notes = [];
  late final Ticker _ticker;

  _Phase _phase = _Phase.setup;
  Difficulty _difficulty = Difficulty.easy;
  double _time = 0;
  int _score = 0, _combo = 0, _bestCombo = 0;
  int _completed = 0, _missed = 0, _dropped = 0;
  int _perfect = 0, _good = 0;
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
  double get _endurance => switch (_difficulty) {
        Difficulty.easy => 8,
        Difficulty.medium => 12,
        Difficulty.hard => 15,
      };
  List<String> get _pattern => switch (_difficulty) {
        Difficulty.easy => [
            'half', 'half', 'full', 'half', 'full', 'half', 'endurance', 'half'
          ],
        Difficulty.medium => [
            'half', 'full', 'half', 'full', 'full', 'endurance',
            'half', 'full', 'half', 'endurance'
          ],
        Difficulty.hard => [
            'full', 'half', 'full', 'full', 'endurance', 'full',
            'half', 'full', 'endurance', 'full', 'full', 'half'
          ],
      };

  @override
  void initState() {
    super.initState();
    input.allowed = _cells;
    input.onDown = _onDown;
    input.onUp = _onUp;
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    input.dispose();
    super.dispose();
  }

  void _makeNotes() {
    _notes.clear();
    double at = _lead + 1;
    int previous = _random.nextInt(2);
    for (final kind in _pattern) {
      final lane = previous;
      previous = 1 - previous;
      final duration = switch (kind) {
        'half' => PushConfig.halfSec,
        'full' => PushConfig.fullSec,
        _ => _endurance * PushConfig.scale,
      };
      _notes.add(_RhythmNote(lane, at, duration, kind));
      at += duration + _gap;
    }
  }

  void _start() {
    trainingStarted = true;
    input.allowed = _cells;
    input.clear();
    if (_ticker.isActive) _ticker.stop();
    setState(() {
      _makeNotes();
      _stats.reset();
      _score = _combo = _bestCombo = 0;
      _completed = _missed = _dropped = _perfect = _good = 0;
      _longest = _time = 0;
      _early = false;
      _judgment = '';
      _phase = _Phase.playing;
    });
    _ticker.start();
  }

  void _flash(String text, Color color) {
    _judgment = text;
    _judgmentColor = color;
  }

  void _tick(Duration elapsed) {
    if (_phase != _Phase.playing || !mounted) return;
    _time = elapsed.inMicroseconds / 1000000;
    setState(() {
      for (final note in _notes) {
        if (note.state == 0 && _time > note.start + _window) {
          note.state = 3;
          _missed++;
          _combo = 0;
          _flash('MISS', Colors.redAccent);
        } else if (note.state == 1 &&
            _time >= note.pressedAt + note.duration &&
            input.isDown(_cells[note.lane])) {
          note.state = 2;
          _stats.add(classifyHold(note.duration));
          _completed++;
          _combo++;
          _bestCombo = max(_bestCombo, _combo);
          _longest = max(_longest, note.duration);
          final multiplier = 1 + min(_combo, 10) * 0.1;
          _score += ((note.timingPoints + note.duration * 20) * multiplier).round();
          _flash('HOLD COMPLETE', Colors.greenAccent);
        }
      }
      if (_notes.isNotEmpty && _notes.every((n) => n.state >= 2)) {
        _finish();
      }
    });
  }

  void _onDown(int cell) {
    if (_phase != _Phase.playing) return;
    final lane = _cells.indexOf(cell);
    if (lane < 0) return;
    _RhythmNote? best;
    double distance = double.infinity;
    for (final note in _notes) {
      final delta = (_time - note.start).abs();
      if (note.lane == lane && note.state == 0 && delta <= _window && delta < distance) {
        best = note;
        distance = delta;
      }
    }
    if (best == null) return;
    final note = best;
    setState(() {
      if (distance <= 0.2) {
        note.timingPoints = 100;
        _perfect++;
        _flash('PERFECT', Colors.greenAccent);
      } else {
        note.timingPoints = 50;
        _good++;
        _flash('GOOD', Colors.lightBlueAccent);
      }
      note.state = 1;
      note.pressedAt = _time;
    });
  }

  void _onUp(int cell, double seconds) {
    if (_phase != _Phase.playing) return;
    final lane = _cells.indexOf(cell);
    if (lane < 0) return;
    for (final note in _notes) {
      if (note.lane == lane && note.state == 1) {
        setState(() {
          final held = max(0.0, _time - note.pressedAt);
          note.state = 4;
          final result = classifyHold(held);
          _stats.add(result);
          _dropped++;
          _combo = 0;
          _longest = max(_longest, held);
          _score += (held * 10).round();
          _flash(
            result == PressResult.none
                ? 'TOO SHORT'
                : result == PressResult.half
                    ? 'RELEASED (HALF)'
                    : 'RELEASED (FULL)',
            Colors.orangeAccent,
          );
        });
        break;
      }
    }
  }

  void _finish({bool early = false}) {
    if (_phase != _Phase.playing) return;
    _ticker.stop();
    input.clear();
    _early = early;
    _phase = _Phase.done;
    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Rhythm Game',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: _time.round(),
      correctAttempts: _completed,
      incorrectAttempts: _notes.length - _completed,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Two tiles (G/J) | Score $_score | '
          'holds $_completed/${_notes.length} | missed $_missed | '
          'released early $_dropped | perfect $_perfect | good $_good | '
          'longest hold ${_longest.toStringAsFixed(1)} s | '
          'best combo $_bestCombo',
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Two-Tile Rhythm Game')),
        body: SafeArea(
          child: PushKeyboard(
            controller: input,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: switch (_phase) {
                  _Phase.setup => _setup(),
                  _Phase.playing => _play(),
                  _Phase.done => _summary(),
                },
              ),
            ),
          ),
        ),
      );

  Widget _setup() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.music_note_rounded, size: 72, color: kTeal),
          const SizedBox(height: 8),
          const Text('Two-Tile Rhythm Game',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text(
            'Press and HOLD the left or right tile when its note '
            'reaches the line. Keep holding until the note ends.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 8,
            children: [
              _legend(_noteColors['half']!, 'Half ${PushConfig.halfSec.toStringAsFixed(1)} s'),
              _legend(_noteColors['full']!, 'Full ${PushConfig.fullSec.toStringAsFixed(1)} s'),
              _legend(_noteColors['endurance']!, 'Endurance ${(_endurance * PushConfig.scale).toStringAsFixed(0)} s'),
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
          const Text('Board: 1 x 2 (left = G, right = J)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          practiceSwitch(PushConfig.practice,
              (value) => setState(() => PushConfig.practice = value)),
          const Text(
            'Hold G or J on the keyboard, or press and hold '
            'either on-screen tile. Use therapist-approved settings.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(
                backgroundColor: kTeal,
                minimumSize: const Size.fromHeight(56)),
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

  Widget _legend(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      );

  Widget _play() {
    final done = _notes.where((n) => n.state >= 2).length;
    const white = TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold);

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
              Text('Combo x$_combo', style: white.copyWith(color: Colors.orangeAccent)),
            ],
          ),
          SizedBox(
            height: 38,
            child: Center(
              child: Text(_judgment,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: _judgmentColor,
                  )),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AnimatedBuilder(
                animation: input,
                builder: (context, _) => CustomPaint(
                  painter: _TwoLaneHighwayPainter(
                    _notes,
                    _time,
                    _lead,
                    {for (var lane = 0; lane < 2; lane++)
                      if (input.isDown(_cells[lane])) lane},
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: Row(
              children: [
                for (var lane = 0; lane < 2; lane++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: PushTile(
                        cell: _cells[lane],
                        input: input,
                        style: TileStyle(
                          bg: const Color(0xFF14143A),
                          border: lane == 0
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFFFF4081),
                          borderWidth: 3,
                          labelColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          pressStatsBar(_stats, dark: true),
          TextButton(
            onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End session', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    final accuracy = _notes.isEmpty ? 0.0 : _completed / _notes.length * 100;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
        const SizedBox(height: 8),
        Text(_early ? 'Session stopped' : 'Performance Summary',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row('Final score', '$_score'),
                const Divider(),
                _row('Holds completed', '$_completed / ${_notes.length}'),
                const Divider(),
                _row('Completion', '${accuracy.toStringAsFixed(1)}%'),
                const Divider(),
                _row('Longest hold', '${_longest.toStringAsFixed(1)} s'),
                const Divider(),
                _row('Perfect / Good', '$_perfect / $_good'),
                const Divider(),
                _row('Released early', '$_dropped'),
                const Divider(),
                _row('Missed', '$_missed'),
                const Divider(),
                _row('Full / Half / No press', '${_stats.full} / ${_stats.half} / ${_stats.none}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Saved to My Progress',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => setState(() => _phase = _Phase.setup),
          icon: const Icon(Icons.replay),
          label: const Text('Play Again'),
          style: FilledButton.styleFrom(
              backgroundColor: kTeal, padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label)),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      );
}

class _TwoLaneHighwayPainter extends CustomPainter {
  final List<_RhythmNote> notes;
  final double time;
  final double lead;
  final Set<int> down;

  _TwoLaneHighwayPainter(this.notes, this.time, this.lead, this.down);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF05051A), Color(0xFF241046)],
        ).createShader(rect),
    );

    final hitY = size.height * 0.88;
    final horizon = size.height * 0.03;
    final span = hitY - horizon;
    final fullWidth = size.width * 0.96;

    double yAt(double p) => horizon + span * pow(p, 1.6).toDouble();
    double scale(double y) => 0.30 + 0.70 * ((y - horizon) / span);
    double centerX(int lane, double y) => size.width / 2 + (lane - 0.5) * (fullWidth / 2) * scale(y);
    double halfWidth(double y) => (fullWidth / 2) * scale(y) / 2;

    const laneColors = [Color(0xFF00E5FF), Color(0xFFFF4081)];

    for (var lane = 0; lane < 2; lane++) {
      final path = Path()
        ..moveTo(centerX(lane, horizon) - halfWidth(horizon), horizon)
        ..lineTo(centerX(lane, horizon) + halfWidth(horizon), horizon)
        ..lineTo(centerX(lane, size.height) + halfWidth(size.height), size.height)
        ..lineTo(centerX(lane, size.height) - halfWidth(size.height), size.height)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = down.contains(lane)
              ? laneColors[lane].withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: lane.isEven ? 0.04 : 0.08),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.15),
      );
    }

    canvas.drawLine(
      Offset(0, hitY),
      Offset(size.width, hitY),
      Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 3,
    );

    for (final note in notes) {
      if (note.state != 0 && note.state != 1) continue;
      final head = note.state == 1 ? 1.0 : (time - (note.start - lead)) / lead;
      if (head <= 0 || head > 1.25) continue;
      var tail = (time - (note.start + note.duration - lead)) / lead;
      if (tail < 0) tail = 0;

      final yHead = yAt(head);
      final yTail = yAt(tail);
      final color = _noteColors[note.kind]!;
      const bodyWidth = 0.55;

      final body = Path()
        ..moveTo(centerX(note.lane, yTail) - halfWidth(yTail) * bodyWidth, yTail)
        ..lineTo(centerX(note.lane, yTail) + halfWidth(yTail) * bodyWidth, yTail)
        ..lineTo(centerX(note.lane, yHead) + halfWidth(yHead) * bodyWidth, yHead)
        ..lineTo(centerX(note.lane, yHead) - halfWidth(yHead) * bodyWidth, yHead)
        ..close();

      canvas.drawPath(
        body,
        Paint()..color = color.withValues(alpha: note.state == 1 ? 0.75 : 0.45),
      );

      final cap = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX(note.lane, yHead), yHead),
          width: halfWidth(yHead) * 2 * 0.9,
          height: 16 * scale(yHead),
        ),
        const Radius.circular(8),
      );

      canvas.drawRRect(
        cap,
        Paint()..color = color.withValues(alpha: head > 1 ? 0.4 : 1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TwoLaneHighwayPainter old) => true;
}