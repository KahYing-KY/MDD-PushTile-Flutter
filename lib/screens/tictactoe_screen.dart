import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, playing, done }

const List<List<int>> _lines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8],
  [0, 3, 6], [1, 4, 7], [2, 5, 8],
  [0, 4, 8], [2, 4, 6],
];

String? _winner(List<String?> b) {
  for (final l in _lines) {
    if (b[l[0]] != null && b[l[0]] == b[l[1]] && b[l[0]] == b[l[2]]) {
      return b[l[0]];
    }
  }
  return null;
}

bool _isFull(List<String?> b) => !b.contains(null);

int _minimax(List<String?> b, bool oTurn) {
  final w = _winner(b);
  if (w == 'O') return 1;
  if (w == 'X') return -1;
  if (_isFull(b)) return 0;
  var best = oTurn ? -2 : 2;
  for (var i = 0; i < 9; i++) {
    if (b[i] == null) {
      b[i] = oTurn ? 'O' : 'X';
      final s = _minimax(b, !oTurn);
      b[i] = null;
      best = oTurn ? max(best, s) : min(best, s);
    }
  }
  return best;
}

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen> {
  final PushController input = PushController();
  final Random _rng = Random();
  final Stopwatch _total = Stopwatch();
  final PressStats _stats = PressStats();

  _Phase _phase = _Phase.setup;
  Difficulty _difficulty = Difficulty.easy;
  List<String?> _board = List<String?>.filled(9, null);
  bool _thinking = false;
  int _placed = 0;
  int _notPlaced = 0;
  String _result = '';
  String _message = '';
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    input.onUp = _onUp;
  }

  @override
  void dispose() {
    _clock?.cancel();
    input.dispose();
    super.dispose();
  }

  void _start() {
    trainingStarted = true;
    input.allowed = BoardMode.grid.cells;
    input.clear();
    setState(() {
      _board = List<String?>.filled(9, null);
      _thinking = false;
      _placed = 0;
      _notPlaced = 0;
      _result = '';
      _stats.reset();
      _message = 'Your turn: FULL press a tile to place X.';
      _total
        ..reset()
        ..start();
      _phase = _Phase.playing;
    });
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _phase == _Phase.playing) setState(() {});
    });
  }

  void _onUp(int cell, double sec) {
    if (_phase != _Phase.playing || _thinking) return;
    final r = classifyHold(sec);

    setState(() {
      _stats.add(r);
      if (r != PressResult.full) {
        _notPlaced++;
        _message = r == PressResult.half
            ? 'Half press - hold to a full press to place X.'
            : 'Too short - hold longer.';
        return;
      }
      if (_board[cell] != null) {
        _notPlaced++;
        _message = 'That tile is taken. Choose an empty tile.';
        return;
      }
      _board[cell] = 'X';
      _placed++;
      final w = _winner(_board);
      if (w == 'X') {
        _end('You win!');
      } else if (_isFull(_board)) {
        _end('Draw!');
      } else {
        _thinking = true;
        _message = 'Computer is thinking...';
        Future.delayed(const Duration(milliseconds: 700), _computerMove);
      }
    });
  }

  int _pickMove() {
    final empty = [
      for (var i = 0; i < 9; i++)
        if (_board[i] == null) i
    ];

    int? findLine(String who) {
      for (final l in _lines) {
        final vals = l.map((i) => _board[i]).toList();
        if (vals.where((v) => v == who).length == 2 && vals.contains(null)) {
          return l[vals.indexOf(null)];
        }
      }
      return null;
    }

    switch (_difficulty) {
      case Difficulty.easy:
        return empty[_rng.nextInt(empty.length)];
      case Difficulty.medium:
        return findLine('O') ??
            findLine('X') ??
            empty[_rng.nextInt(empty.length)];
      case Difficulty.hard:
        var best = -2;
        var move = empty.first;
        for (final i in empty) {
          _board[i] = 'O';
          final s = _minimax(_board, false);
          _board[i] = null;
          if (s > best) {
            best = s;
            move = i;
          }
        }
        return move;
    }
  }

  void _computerMove() {
    if (!mounted || _phase != _Phase.playing) return;
    setState(() {
      _board[_pickMove()] = 'O';
      _thinking = false;
      final w = _winner(_board);
      if (w == 'O') {
        _end('Computer wins');
      } else if (_isFull(_board)) {
        _end('Draw!');
      } else {
        _message = 'Your turn: FULL press a tile to place X.';
      }
    });
  }

  // inside setState
  void _end(String result, {bool early = false}) {
    _total.stop();
    _clock?.cancel();
    input.clear();
    _result = result;
    _phase = _Phase.done;
    _message = result;

    if (early && _stats.total == 0) return;
    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Tic-Tac-Toe',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: (_total.elapsedMilliseconds / 1000).round(),
      correctAttempts: _placed,
      incorrectAttempts: _notPlaced,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Result: $result | marks placed $_placed',
    ));
  }

  TileStyle _style(int cell) {
    final v = _board[cell];
    if (v == 'X') {
      return TileStyle(
          bg: kTeal.withValues(alpha: 0.15),
          border: kTeal,
          borderWidth: 3,
          label: 'X',
          labelColor: kTeal);
    }
    if (v == 'O') {
      return TileStyle(
          bg: Colors.red.shade50,
          border: Colors.red,
          borderWidth: 3,
          label: 'O',
          labelColor: Colors.red);
    }
    return const TileStyle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tic-Tac-Toe')),
      body: SafeArea(
        child: PushKeyboard(
          controller: input,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child:
                  _phase == _Phase.setup ? _setup() : _game(),
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
        const Text('Tic-Tac-Toe',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          'You are X. Push a tile with a FULL press to place your mark. '
          'Half or short presses are recorded but do not place anything.',
          style: TextStyle(fontSize: 17),
        ),
        const SizedBox(height: 16),
        chipRow<Difficulty>(
          title: 'Computer level',
          values: Difficulty.values,
          selected: _difficulty,
          label: (d) => d.label,
          onSelected: (d) => setState(() => _difficulty = d),
        ),
        const SizedBox(height: 8),
        practiceSwitch(PushConfig.practice,
            (v) => setState(() => PushConfig.practice = v)),
        Text(pressRulesText(),
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _start,
          style: FilledButton.styleFrom(
              backgroundColor: kTeal, minimumSize: const Size.fromHeight(56)),
          child: const Text('Start',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _game() {
    final done = _phase == _Phase.done;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: done ? const Color(0xFFE4F3EB) : const Color(0xFFDFF1F1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(_message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: kTeal)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: PushBoard(
                mode: BoardMode.grid, input: input, styleOf: _style),
          ),
          const SizedBox(height: 8),
          pressStatsBar(_stats),
          const SizedBox(height: 8),
          if (!done)
            OutlinedButton(
              onPressed: () => setState(() => _end('Stopped early', early: true)),
              child: const Text('End session'),
            )
          else ...[
            Text('Result: $_result  •  saved to My Progress',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(
                  onPressed: () => setState(() => _phase = _Phase.setup),
                  style: FilledButton.styleFrom(backgroundColor: kTeal),
                  child: const Text('Play Again'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}