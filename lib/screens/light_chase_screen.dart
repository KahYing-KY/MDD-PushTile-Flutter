import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, playing, done }

class LightChaseScreen extends StatefulWidget {
  final bool coolDown;
  const LightChaseScreen({super.key, this.coolDown = false});

  @override
  State<LightChaseScreen> createState() => _LightChaseScreenState();
}

class _LightChaseScreenState extends State<LightChaseScreen> {
  final PushController input = PushController();
  final Random _rng = Random();
  final Stopwatch _total = Stopwatch();
  final Stopwatch _lit = Stopwatch();
  final Stopwatch _idle = Stopwatch();
  Timer? _ticker;

  _Phase _phase = _Phase.setup;
  late BoardMode _mode = widget.coolDown ? sessionMode : BoardMode.grid;

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

  String get _name => widget.coolDown ? 'Cool-Down' : 'Light Chase Warm-Up';

  @override
  void initState() {
    super.initState();
    input.allowed = _mode.cells;
    input.onDown = _onDown;
    input.onUp = _onUp;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    input.dispose();
    super.dispose();
  }

  List<int> _makeSeq(BoardMode m) {
    final cells = m.cells;
    if (m == BoardMode.grid) return List<int>.of(cells)..shuffle(_rng);
    final out = <int>[];
    for (var i = 0; i < 6; i++) {
      int c;
      do {
        c = cells[_rng.nextInt(cells.length)];
      } while (out.isNotEmpty && c == out.last);
      out.add(c);
    }
    return out;
  }

  void _start() {
    setState(() {
      if (widget.coolDown) {
        _mode = sessionMode;
        _seq = List<int>.of(sessionSeq ?? _makeSeq(_mode));
      } else {
        _seq = _makeSeq(_mode);
      }
      input.allowed = _mode.cells;
      input.clear();
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

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _phase != _Phase.playing) return;
      final idleSec = _idle.elapsedMilliseconds / 1000;
      if (!input.anyDown && idleSec >= PushConfig.tileTimeoutSec) {
        setState(() {
          _timeouts++;
          _failed++;
          _advance('Time out - moving to the next tile.');
        });
      } else {
        setState(() {});
      }
    });
  }

  void _onDown(int cell) {
    if (_phase != _Phase.playing) return;
    if (cell == _seq[_idx] && !_gotReaction) {
      _reactions.add(_lit.elapsedMilliseconds / 1000);
      _gotReaction = true;
    }
  }

  void _onUp(int cell, double sec) {
    if (_phase != _Phase.playing) return;

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

  // Call inside setState
  void _advance(String msg) {
    _idx++;
    _tries = 0;
    _gotReaction = false;
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

  // Call inside setState
  void _finish({bool early = false}) {
    _total.stop();
    _lit.stop();
    _idle.stop();
    _ticker?.cancel();
    input.clear();
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
      difficulty: _mode.label,
      durationSeconds: secs.round(),
      correctAttempts: _succeeded,
      incorrectAttempts: _failed,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Light Chase ${_mode.label} | tiles $_succeeded/${_seq.length} '
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
        child: PushKeyboard(
          controller: input,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: switch (_phase) {
                _Phase.setup => _buildSetup(),
                _Phase.playing => _buildPlay(),
                _Phase.done => _buildResult(),
              },
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
        Text(widget.coolDown ? 'Cool-Down' : 'Light Chase',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          'A tile lights up. Push it with a FULL press to score. '
          'A half or short press is recorded and you try again '
          '(3 tries per tile, 20 s limit).',
          style: TextStyle(fontSize: 17),
        ),
        const SizedBox(height: 16),
        if (widget.coolDown)
          Text('Same board as your warm-up: ${_mode.label}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: kTeal))
        else
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
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _start,
          style: FilledButton.styleFrom(
              backgroundColor: kBlue, minimumSize: const Size.fromHeight(56)),
          child: Text('Start $_name',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  TileStyle _style(int cell) {
    final lit = _phase == _Phase.playing && _seq[_idx] == cell;
    if (lit) {
      return const TileStyle(
        bg: Color(0xFFFFF3C4),
        border: Color(0xFFF2A33A),
        borderWidth: 4,
        label: 'PUSH',
        labelColor: Color(0xFF8A5A00),
      );
    }
    return const TileStyle(
        bg: Color(0xFFECEFF1), border: Color(0xFFCFD8DC), borderWidth: 1.5);
  }

  Widget _buildPlay() {
    return Padding(
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
                      fontSize: 16, fontWeight: FontWeight.w600, color: kInk)),
            ),
          ),
          Text(fmtSeconds(_total.elapsedMilliseconds / 1000),
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.bold, color: kTeal)),
          Text(
              'Tile ${_idx + 1} of ${_seq.length}   •   try ${_tries + 1}/${PushConfig.maxTries}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: kBlue)),
          const SizedBox(height: 8),
          Expanded(
              child:
                  PushBoard(mode: _mode, input: input, styleOf: _style)),
          const SizedBox(height: 8),
          pressStatsBar(_stats),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End session'),
          ),
        ],
      ),
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
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        if (!widget.coolDown) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => setState(() => _phase = _Phase.setup),
            style:
                OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Redo Warm-Up', style: TextStyle(fontSize: 16)),
          ),
        ],
      ],
    );
  }
}