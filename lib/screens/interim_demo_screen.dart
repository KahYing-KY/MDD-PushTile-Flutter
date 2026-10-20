import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

class InterimDemoScreen extends StatefulWidget {
  const InterimDemoScreen({super.key});

  @override
  State<InterimDemoScreen> createState() => _InterimDemoScreenState();
}

class _InterimDemoScreenState extends State<InterimDemoScreen> {
  final PushController input = PushController();
  final Random _rng = Random();
  final Stopwatch _total = Stopwatch();
  final Stopwatch _idle = Stopwatch();
  final PressStats _stats = PressStats();
  Timer? _ticker;
  Timer? _flashTimer;

  late List<int> _solution;
  late List<bool> _isClue;
  late List<int?> _board;
  List<int> _empties = [];
  final Set<int> _failedCells = {};

  int _pos = 0;
  int _tries = 0;
  int _mistakes = 0;
  int _correctFull = 0;
  int _timeouts = 0;
  int? _flashDigit;
  bool _finished = false;
  bool _saved = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    input.allowed = BoardMode.row.cells;
    input.onUp = _onUp;
    _newGame();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _finished) return;
      final idleSec = _idle.elapsedMilliseconds / 1000;
      if (!input.anyDown && idleSec >= PushConfig.tileTimeoutSec) {
        setState(() {
          _timeouts++;
          _failCell('Time out - moving on.');
        });
        if (_finished) _complete();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _flashTimer?.cancel();
    input.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Puzzle generation (exactly one answer, checked here)
  // ---------------------------------------------------------------------
  int _countSolutions(List<int?> start) {
    final g = List<int?>.from(start);
    int count = 0;

    bool fits(int i, int v) {
      final r = i ~/ 3, c = i % 3;
      for (var k = 0; k < 3; k++) {
        if (k != c && g[r * 3 + k] == v) return false;
        if (k != r && g[k * 3 + c] == v) return false;
      }
      return true;
    }

    void solve(int i) {
      if (count > 1) return;
      if (i == 9) {
        count++;
        return;
      }
      if (g[i] != null) {
        solve(i + 1);
        return;
      }
      for (var v = 1; v <= 3; v++) {
        if (fits(i, v)) {
          g[i] = v;
          solve(i + 1);
          g[i] = null;
        }
      }
    }

    solve(0);
    return count;
  }

  // Assigns fields directly (wrap in setState when called from UI).
  void _newGame() {
    final first = <int>[1, 2, 3]..shuffle(_rng);
    final shift = _rng.nextBool() ? 1 : 2;
    final sol = <int>[];
    for (var r = 0; r < 3; r++) {
      final s = r == 0 ? 0 : (r == 1 ? shift : 3 - shift);
      for (var c = 0; c < 3; c++) {
        sol.add(first[(c + s) % 3]);
      }
    }

    final order = List<int>.generate(9, (i) => i)..shuffle(_rng);
    var k = 4;
    late List<int?> puzzle;
    while (true) {
      puzzle = List<int?>.filled(9, null);
      for (var i = 0; i < k; i++) {
        puzzle[order[i]] = sol[order[i]];
      }
      if (_countSolutions(puzzle) == 1) break;
      k++;
    }

    _solution = sol;
    _board = puzzle;
    _isClue = List<bool>.generate(9, (i) => puzzle[i] != null);
    _empties = [
      for (var i = 0; i < 9; i++)
        if (puzzle[i] == null) i
    ];
    _failedCells.clear();
    _pos = 0;
    _tries = 0;
    _mistakes = 0;
    _correctFull = 0;
    _timeouts = 0;
    _flashDigit = null;
    _finished = false;
    _saved = false;
    _stats.reset();
    _message = 'Push the tile for the highlighted cell: G=1  H=2  J=3.';
    _total
      ..reset()
      ..start();
    _idle
      ..reset()
      ..start();
    input.clear();
  }

  // ---------------------------------------------------------------------
  // Game logic (runs on each release, never inside build)
  // ---------------------------------------------------------------------
  void _onUp(int cell, double sec) {
    if (_finished) return;
    final digit = cell - 2; // G=1, H=2, J=3
    final target = _empties[_pos];
    final right = digit == _solution[target];
    final r = classifyHold(sec);

    setState(() {
      _stats.add(r);

      if (r == PressResult.full) {
        if (right) {
          _board[target] = digit;
          _correctFull++;
          _advance('Correct! $digit entered.');
        } else {
          _wrong(digit);
        }
      } else if (r == PressResult.half) {
        if (right) {
          _idle
            ..reset()
            ..start();
          _tries++;
          if (_tries >= PushConfig.maxTries) {
            _failCell('3 attempts without a full press - moving on.');
          } else {
            _message =
                'Right number, but only a half press ($_tries/${PushConfig.maxTries}). Hold to full.';
          }
        } else {
          _wrong(digit);
        }
      } else {
        if (right) {
          _tries++;
          if (_tries >= PushConfig.maxTries) {
            _failCell('3 attempts without a full press - moving on.');
          } else {
            _message =
                'Too short ($_tries/${PushConfig.maxTries}). Hold longer.';
          }
        } else {
          _message = 'Too short - nothing entered.';
        }
      }
    });

    if (_finished) _complete();
  }

  // inside setState
  void _wrong(int digit) {
    _mistakes++;
    _flashDigit = digit;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _flashDigit = null);
    });
    _idle
      ..reset()
      ..start();
    _message = 'Wrong number ($digit) - mistake counted. Try again.';
  }

  // inside setState
  void _failCell(String msg) {
    final t = _empties[_pos];
    _board[t] = _solution[t];
    _failedCells.add(t);
    _advance(msg);
  }

  // inside setState
  void _advance(String msg) {
    _pos++;
    _tries = 0;
    _flashDigit = null;
    _idle
      ..reset()
      ..start();
    if (_pos >= _empties.length) {
      _finished = true;
      _total.stop();
      _idle.stop();
      _message = 'Board complete!';
    } else {
      _message = msg;
    }
  }

  void _complete({bool early = false}) {
    if (_saved) return;
    _saved = true;
    input.clear();
    _total.stop();
    final secs = _total.elapsedMilliseconds / 1000;

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Interim Demo',
      date: DateTime.now(),
      difficulty: '1 x 3 push tiles',
      durationSeconds: secs.round(),
      correctAttempts: _correctFull,
      incorrectAttempts: _mistakes + _failedCells.length,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Row-by-row 3x3 | mistakes $_mistakes | failed cells '
          '${_failedCells.length} | timeouts $_timeouts',
    ));

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(early ? 'Session ended' : 'Demo Completed!'),
        content: Text('Time ${fmtSeconds(secs)}\n'
            'Mistakes: $_mistakes   Failed cells: ${_failedCells.length}\n'
            'Full ${_stats.full} • Half ${_stats.half} • No press ${_stats.none}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(_newGame);
            },
            child: const Text('New Puzzle'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------
  TileStyle _padStyle(int cell) {
    final digit = cell - 2;
    return TileStyle(
      bg: const Color(0xFFE1F2F3),
      border: kTeal,
      borderWidth: 3,
      label: '$digit',
      labelColor: kTeal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cellNo = min(_pos + 1, _empties.length);
    return Scaffold(
      appBar: AppBar(title: const Text('Interim Demo')),
      body: SafeArea(
        child: PushKeyboard(
          controller: input,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDFF1F1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cell $cellNo of ${_empties.length}  •  '
                            'Mistakes $_mistakes  •  Try ${_tries + 1}/${PushConfig.maxTries}',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: kTeal),
                          ),
                          const SizedBox(height: 4),
                          Text(_message,
                              style:
                                  const TextStyle(fontSize: 14, color: kInk)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _boardArea()),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 110,
                      child: PushBoard(
                          mode: BoardMode.row,
                          input: input,
                          styleOf: _padStyle),
                    ),
                    const SizedBox(height: 8),
                    pressStatsBar(_stats),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: _finished
                              ? null
                              : () {
                                  setState(() => _finished = true);
                                  _complete(early: true);
                                },
                          child: const Text('End session'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: () => setState(_newGame),
                          child: const Text('New puzzle'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardArea() {
    return LayoutBuilder(builder: (context, c) {
      final side = min(c.maxWidth, c.maxHeight);
      return Center(
        child: Container(
          width: side,
          height: side,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kTeal.withValues(alpha: 0.3), width: 2),
          ),
          child: Column(
            children: [
              for (var r = 0; r < 3; r++)
                Expanded(
                  child: Row(
                    children: [
                      for (var col = 0; col < 3; col++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: _cell(r * 3 + col, side / 3),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _cell(int i, double size) {
    final active =
        !_finished && _pos < _empties.length && _empties[_pos] == i;
    final v = _board[i];

    Color bg = Colors.white;
    Color border = Colors.grey.shade300;
    Color text = kInk;
    double bw = 1.5;
    String t = v?.toString() ?? '';

    if (_isClue[i]) {
      bg = const Color(0xFFE1F2F3);
      border = kTeal;
      text = kTeal;
    } else if (_failedCells.contains(i)) {
      bg = Colors.amber.shade50;
      border = Colors.amber.shade700;
      text = Colors.amber.shade800;
    } else if (v != null) {
      bg = Colors.green.shade50;
      border = Colors.green;
      text = Colors.green.shade700;
    }

    if (active) {
      bg = const Color(0xFFFFF8E1);
      border = Colors.amber.shade700;
      bw = 4;
      text = Colors.amber.shade800;
      t = '?';
      if (_flashDigit != null) {
        bg = Colors.red.shade50;
        border = Colors.red;
        text = Colors.red;
        t = '$_flashDigit';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: bw),
      ),
      alignment: Alignment.center,
      child: Text(t,
          style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.bold,
              color: text)),
    );
  }
}