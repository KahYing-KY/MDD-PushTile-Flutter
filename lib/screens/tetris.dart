import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, playing, done }

enum GameSpeed {
  easy('Easy', Duration(milliseconds: 600)),
  medium('Medium', Duration(milliseconds: 400)),
  hard('Hard', Duration(milliseconds: 250));

  final String label;
  final Duration duration;
  const GameSpeed(this.label, this.duration);
}

const List<Color> _controlColors = [
  Color(0xFFF0788C), // D - Pink (Move Left / Wrap)
  Color(0xFF7BD095), // F - Green (Rotate Clockwise)
  Color(0xFFFFC95C), // J - Yellow (Save to Bank)
  Color(0xFF63A7EF), // K - Blue (Hard Drop)
];

const List<String> _controlKeys = ['D', 'F', 'J', 'K'];
const List<String> _controlActions = ['Move Left (Wrap)', 'Rotate CW', 'Save to Bank', 'Hard Drop'];

const int gridWidth = 10;
const int gridHeight = 20;

enum Tetromino { I, J, L, O, S, T, Z }

const Map<Tetromino, List<List<int>>> tetrominoShapes = {
  Tetromino.I: [
    [0, 0, 0, 0],
    [1, 1, 1, 1],
    [0, 0, 0, 0],
    [0, 0, 0, 0],
  ],
  Tetromino.J: [
    [1, 0, 0],
    [1, 1, 1],
    [0, 0, 0],
  ],
  Tetromino.L: [
    [0, 0, 1],
    [1, 1, 1],
    [0, 0, 0],
  ],
  Tetromino.O: [
    [1, 1],
    [1, 1],
  ],
  Tetromino.S: [
    [0, 1, 1],
    [1, 1, 0],
    [0, 0, 0],
  ],
  Tetromino.T: [
    [0, 1, 0],
    [1, 1, 1],
    [0, 0, 0],
  ],
  Tetromino.Z: [
    [1, 1, 0],
    [0, 1, 1],
    [0, 0, 0],
  ],
};

const Map<Tetromino, Color> tetrominoColors = {
  Tetromino.I: Colors.cyan,
  Tetromino.J: Colors.blue,
  Tetromino.L: Colors.orange,
  Tetromino.O: Colors.yellow,
  Tetromino.S: Colors.green,
  Tetromino.T: Colors.purple,
  Tetromino.Z: Colors.red,
};

class TetrisPlayScreen extends StatefulWidget {
  const TetrisPlayScreen({super.key});

  @override
  State<TetrisPlayScreen> createState() => _TetrisPlayScreenState();
}

class _TetrisPlayScreenState extends State<TetrisPlayScreen> {
  final FocusNode _focusNode = FocusNode();
  final Random _rng = Random();
  final Stopwatch _total = Stopwatch();
  Timer? _ticker;

  _Phase _phase = _Phase.setup;
  GameSpeed _speed = GameSpeed.easy;

  late List<List<Color?>> _grid;
  Tetromino? _currentPiece;
  int _currentX = 3;
  int _currentY = 0;
  List<List<int>> _currentShape = [];

  Tetromino? _bankedPiece;
  bool _canBank = true;

  int _score = 0;
  int _linesCleared = 0;
  bool _early = false;

  @override
  void initState() {
    super.initState();
    _resetGrid();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _resetGrid() {
    _grid = List.generate(gridHeight, (_) => List.filled(gridWidth, null));
  }

  void _spawnPiece({Tetromino? specificPiece}) {
    final piece = specificPiece ?? Tetromino.values[_rng.nextInt(Tetromino.values.length)];
    _currentPiece = piece;
    _currentShape = tetrominoShapes[piece]!;
    _currentX = (gridWidth - _currentShape[0].length) ~/ 2;
    _currentY = 0;
    _canBank = true;

    if (_checkCollision(_currentX, _currentY, _currentShape)) {
      _finish(early: false);
    }
  }

  bool _checkCollision(int x, int y, List<List<int>> shape) {
    for (int r = 0; r < shape.length; r++) {
      for (int c = 0; c < shape[r].length; c++) {
        if (shape[r][c] != 0) {
          int boardX = x + c;
          int boardY = y + r;
          if (boardX < 0 || boardX >= gridWidth || boardY >= gridHeight) {
            return true;
          }
          if (boardY >= 0 && _grid[boardY][boardX] != null) {
            return true;
          }
        }
      }
    }
    return false;
  }

  void _start() {
    trainingStarted = true;
    setState(() {
      _resetGrid();
      _score = 0;
      _linesCleared = 0;
      _bankedPiece = null;
      _early = false;
      _total
        ..reset()
        ..start();
      _phase = _Phase.playing;
      _spawnPiece();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });

    _ticker?.cancel();
    _ticker = Timer.periodic(_speed.duration, (_) => _gameTick());
  }

  void _gameTick() {
    if (!mounted || _phase != _Phase.playing) return;
    setState(() {
      if (!_checkCollision(_currentX, _currentY + 1, _currentShape)) {
        _currentY++;
      } else {
        _lockPiece();
      }
    });
  }

  void _lockPiece() {
    for (int r = 0; r < _currentShape.length; r++) {
      for (int c = 0; c < _currentShape[r].length; c++) {
        if (_currentShape[r][c] != 0) {
          int boardY = _currentY + r;
          int boardX = _currentX + c;
          if (boardY >= 0 && boardY < gridHeight && boardX >= 0 && boardX < gridWidth) {
            _grid[boardY][boardX] = tetrominoColors[_currentPiece!];
          }
        }
      }
    }
    _clearLines();
    _spawnPiece();
  }

  void _clearLines() {
    int cleared = 0;
    for (int r = gridHeight - 1; r >= 0; r--) {
      if (_grid[r].every((cell) => cell != null)) {
        _grid.removeAt(r);
        _grid.insert(0, List.filled(gridWidth, null));
        cleared++;
        r++;
      }
    }
    if (cleared > 0) {
      _linesCleared += cleared;
      _score += cleared * 100 * cleared;
    }
  }

  void _moveLeft() {
    if (_phase != _Phase.playing) return;
    setState(() {
      int targetX = _currentX - 1;
      if (!_checkCollision(targetX, _currentY, _currentShape)) {
        _currentX = targetX;
      } else {
        for (int x = gridWidth - 1; x > _currentX; x--) {
          if (!_checkCollision(x, _currentY, _currentShape)) {
            _currentX = x;
            break;
          }
        }
      }
    });
  }

  void _rotateClockwise() {
    if (_phase != _Phase.playing) return;
    setState(() {
      final rows = _currentShape.length;
      final cols = _currentShape[0].length;
      List<List<int>> rotated = List.generate(cols, (r) => List.generate(rows, (c) => _currentShape[rows - 1 - c][r]));
      if (!_checkCollision(_currentX, _currentY, rotated)) {
        _currentShape = rotated;
      }
    });
  }

  void _saveToBank() {
    if (_phase != _Phase.playing || !_canBank) return;
    setState(() {
      final previousPiece = _currentPiece;
      if (_bankedPiece == null) {
        _bankedPiece = previousPiece;
        _spawnPiece();
      } else {
        final temp = _bankedPiece;
        _bankedPiece = previousPiece;
        _spawnPiece(specificPiece: temp);
      }
      _canBank = false;
    });
  }

  void _hardDrop() {
    if (_phase != _Phase.playing) return;
    setState(() {
      while (!_checkCollision(_currentX, _currentY + 1, _currentShape)) {
        _currentY++;
      }
      _lockPiece();
    });
  }

  void _onButtonDown(int index) {
    if (_phase != _Phase.playing) return;
    switch (index) {
      case 0:
        _moveLeft();
        break;
      case 1:
        _rotateClockwise();
        break;
      case 2:
        _saveToBank();
        break;
      case 3:
        _hardDrop();
        break;
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_phase != _Phase.playing) return KeyEventResult.ignored;

    final keyLabel = event.logicalKey.keyLabel.toUpperCase();
    int? index;
    if (keyLabel == 'D' || event.logicalKey == LogicalKeyboardKey.keyD) {
      index = 0;
    } else if (keyLabel == 'F' || event.logicalKey == LogicalKeyboardKey.keyF) {
      index = 1;
    } else if (keyLabel == 'J' || event.logicalKey == LogicalKeyboardKey.keyJ) {
      index = 2;
    } else if (keyLabel == 'K' || event.logicalKey == LogicalKeyboardKey.keyK) {
      index = 3;
    }

    if (index == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _onButtonDown(index);
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _finish({bool early = false}) {
    _total.stop();
    _ticker?.cancel();
    _early = early;
    _phase = _Phase.done;

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Tetris 4-Key',
      date: DateTime.now(),
      difficulty: _speed.label,
      durationSeconds: (_total.elapsedMilliseconds / 1000).round(),
      correctAttempts: _linesCleared,
      incorrectAttempts: 0,
      fullPresses: _score,
      halfPresses: 0,
      noPresses: 0,
      completed: !early,
      notes: 'Score: $_score | Lines: $_linesCleared',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tetris (4-Key Control)')),
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
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
        const Text('Tetris 4-Key Mode',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          'Control the falling block using 4 keys (D, F, J, K):\n\n'
          '• D: Move Left (Wraps to the right boundary)\n'
          '• F: Rotate Clockwise\n'
          '• J: Save block to Bank\n'
          '• K: Instant Drop',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 20),
        const Text('Speed Level', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: GameSpeed.values.map((s) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: ChoiceChip(
                  label: Text(s.label),
                  selected: _speed == s,
                  onSelected: (_) => setState(() => _speed = s),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 30),
        FilledButton(
          onPressed: _start,
          style: FilledButton.styleFrom(
              backgroundColor: kBlue, minimumSize: const Size.fromHeight(56)),
          child: const Text('Start Game',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _play() {
    return Container(
      color: const Color(0xFF05051A),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Score: $_score',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Lines: $_linesCleared',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kTeal)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Bank: ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: _bankedPiece != null
                      ? Container(width: 16, height: 16, color: tetrominoColors[_bankedPiece])
                      : const Text('-', style: TextStyle(color: Colors.white54)),
                ),
              ),
              const Spacer(),
              Text(fmtSeconds(_total.elapsedMilliseconds / 1000),
                  style: const TextStyle(fontSize: 16, color: Colors.orangeAccent)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(color: Colors.indigoAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: gridWidth / gridHeight,
                  child: CustomPaint(
                    painter: TetrisBoardPainter(
                      grid: _grid,
                      currentPiece: _currentPiece,
                      currentShape: _currentShape,
                      currentX: _currentX,
                      currentY: _currentY,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            flex: 1,
            child: Row(
              children: List.generate(4, (index) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: GestureDetector(
                      onTapDown: (_) => _onButtonDown(index),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _controlColors[index].withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _controlColors[index], width: 2.5),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_controlKeys[index],
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _controlColors[index])),
                            const SizedBox(height: 2),
                            Text(_controlActions[index],
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 9, color: Colors.white70)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End Game', style: TextStyle(color: Colors.white70)),
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
        Text(_early ? 'Game Ended' : 'Game Over!',
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
              _line('Final Score: $_score'),
              _line('Lines Cleared: $_linesCleared'),
              _line('Total Time: ${fmtSeconds(_total.elapsedMilliseconds / 1000)}'),
            ],
          ),
        ),
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

class TetrisBoardPainter extends CustomPainter {
  final List<List<Color?>> grid;
  final Tetromino? currentPiece;
  final List<List<int>> currentShape;
  final int currentX;
  final int currentY;

  TetrisBoardPainter({
    required this.grid,
    required this.currentPiece,
    required this.currentShape,
    required this.currentX,
    required this.currentY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cellWidth = size.width / gridWidth;
    final double cellHeight = size.height / gridHeight;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int r = 0; r < gridHeight; r++) {
      for (int c = 0; c < gridWidth; c++) {
        final color = grid[r][c];
        if (color != null) {
          paint.color = color;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(c * cellWidth + 1, r * cellHeight + 1, cellWidth - 2, cellHeight - 2),
              const Radius.circular(3),
            ),
            paint,
          );
        }
      }
    }

    if (currentPiece != null) {
      paint.color = tetrominoColors[currentPiece]!;
      for (int r = 0; r < currentShape.length; r++) {
        for (int c = 0; c < currentShape[r].length; c++) {
          if (currentShape[r][c] != 0) {
            int boardX = currentX + c;
            int boardY = currentY + r;
            if (boardY >= 0 && boardY < gridHeight && boardX >= 0 && boardX < gridWidth) {
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromLTWH(boardX * cellWidth + 1, boardY * cellHeight + 1, cellWidth - 2, cellHeight - 2),
                  const Radius.circular(3),
                ),
                paint,
              );
            }
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}