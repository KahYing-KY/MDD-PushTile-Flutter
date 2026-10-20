import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, playing, done }

class TwoHandPlayScreen extends StatefulWidget {
  const TwoHandPlayScreen({super.key});

  @override
  State<TwoHandPlayScreen> createState() => _TwoHandPlayScreenState();
}

class _TwoHandPlayScreenState extends State<TwoHandPlayScreen> {
  final PushController input = PushController();
  final Random _rng = Random();
  final Stopwatch _total = Stopwatch();
  final Stopwatch _idle = Stopwatch();
  final PressStats _stats = PressStats();
  Timer? _ticker;

  _Phase _phase = _Phase.setup;
  BoardMode _mode = BoardMode.row;
  Difficulty _difficulty = Difficulty.easy;
  int _gridAnchor = 4;

  int _anchor = 4;
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
    input.onUp = _onUp;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    input.dispose();
    super.dispose();
  }

  List<int> _makeTargets() {
    final out = <int>[];
    if (_mode == BoardMode.row) {
      var cur = _rng.nextBool() ? 3 : 5;
      for (var i = 0; i < _targetCount; i++) {
        out.add(cur);
        cur = cur == 3 ? 5 : 3;
      }
    } else {
      final others = [
        for (var i = 0; i < 9; i++)
          if (i != _anchor) i
      ];
      for (var i = 0; i < _targetCount; i++) {
        int c;
        do {
          c = others[_rng.nextInt(others.length)];
        } while (out.isNotEmpty && c == out.last);
        out.add(c);
      }
    }
    return out;
  }

  void _start() {
    trainingStarted = true;
    setState(() {
      _anchor = _mode == BoardMode.row ? 4 : _gridAnchor;
      input.allowed = _mode.cells;
      input.clear();
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
      _message =
          'Hold the anchor tile (${kKeyLabels[_anchor]}) until it reaches a full press.';
      _phase = _Phase.playing;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _phase != _Phase.playing) return;
    setState(() {
      if (!_armed) {
        if (input.isDown(_anchor) &&
            input.holdSeconds(_anchor) >= PushConfig.fullSec) {
          _armed = true;
          _stats.add(PressResult.full);
          _idle.start();
          _message = 'Anchor locked! Push the lit tile with your other hand.';
        }
      } else if (!input.isDown(_targets[_idx]) &&
          _idle.elapsedMilliseconds / 1000 >= PushConfig.tileTimeoutSec) {
        _timeouts++;
        _failed++;
        _advance('Time out - next tile.');
      }
    });
  }

  void _onUp(int cell, double sec) {
    if (_phase != _Phase.playing) return;

    // Anchor tile
    if (cell == _anchor) {
      setState(() {
        if (_armed) {
          _armed = false;
          _idle.stop();
          _drops++;
          _message =
              'Anchor released! Put your hand back and hold ${kKeyLabels[_anchor]} to full press.';
        } else {
          _stats.add(classifyHold(sec));
          _message =
              'Keep holding the anchor (${kKeyLabels[_anchor]}) until it turns full.';
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

  // inside setState
  void _advance(String msg) {
    _idx++;
    _tries = 0;
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

  // inside setState
  void _finish({bool early = false}) {
    _total.stop();
    _idle.stop();
    _ticker?.cancel();
    input.clear();
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
      notes: '${_mode.label} | anchor ${kKeyLabels[_anchor]} | '
          'anchor drops $_drops | timeouts $_timeouts | '
          'targets ${_done + _failed}/${_targets.length}',
    ));
  }

  // =========================================================================
  // UI
  // =========================================================================
  TileStyle _style(int cell) {
    if (_phase == _Phase.playing) {
      if (cell == _anchor) {
        return TileStyle(
          bg: _armed ? const Color(0xFFDDF4E8) : const Color(0xFFFFF3C4),
          border: _armed ? kFullColor : kHalfColor,
          borderWidth: 4,
          label: 'HOLD',
          labelColor: _armed ? kFullColor : const Color(0xFF8A5A00),
        );
      }
      if (_armed && _targets[_idx] == cell) {
        return const TileStyle(
          bg: Color(0xFFFFEBEE),
          border: Colors.redAccent,
          borderWidth: 4,
          label: 'PUSH',
          labelColor: Colors.redAccent,
        );
      }
    }
    return const TileStyle(
        bg: Color(0xFFECEFF1), border: Color(0xFFCFD8DC), borderWidth: 1.5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hold & Reach')),
      body: SafeArea(
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
        chipRow<BoardMode>(
          title: 'Board',
          values: BoardMode.values,
          selected: _mode,
          label: (m) => m == BoardMode.row ? '1 x 3 demo' : '3 x 3',
          onSelected: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: 12),
        if (_mode == BoardMode.row)
          const Text('Anchor: H (middle). Targets alternate between G and J.',
              style: TextStyle(fontWeight: FontWeight.w600, color: kTeal))
        else ...[
          const Text('Choose your anchor tile',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (var r = 0; r < 3; r++)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var c = 0; c < 3; c++)
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: ChoiceChip(
                      label: Text(kKeyLabels[r * 3 + c]),
                      selected: _gridAnchor == r * 3 + c,
                      onSelected: (_) =>
                          setState(() => _gridAnchor = r * 3 + c),
                    ),
                  ),
              ],
            ),
        ],
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
        Text(
            '${pressRulesText()}\nNote: holding two keys at once can fail on some keyboards. Test G+H and H+J early.',
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
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
                  fontSize: 28, fontWeight: FontWeight.bold, color: kTeal)),
          Text(
              'Target ${min(_idx + 1, _targets.length)} of ${_targets.length}'
              '   •   try ${_tries + 1}/${PushConfig.maxTries}'
              '   •   drops $_drops',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: kBlue)),
          const SizedBox(height: 8),
          Expanded(
              child: PushBoard(mode: _mode, input: input, styleOf: _style)),
          const SizedBox(height: 8),
          pressStatsBar(_stats),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End'),
          ),
        ],
      ),
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