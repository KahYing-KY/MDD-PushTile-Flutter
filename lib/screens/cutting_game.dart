import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, cutting, done }

class _IngredientTask {
  final int lane; // 0: Pink (D), 1: Green (F), 2: Yellow (J), 3: Blue (K)
  final bool isHold; // true = Hold continuously, false = Press per cut
  final String name;
  final int totalPieces; // Total pieces desired
  final int slicesPerCut; // Hits or hold multiplier per cut line

  int get totalCuts => max(1, totalPieces - 1);
  int get totalHitsNeeded => totalCuts * slicesPerCut;

  int completedHits = 0;
  double holdProgress = 0.0;
  int state = 0; // 0: pending, 1: active, 2: completed

  _IngredientTask(
    this.lane,
    this.name,
    this.totalPieces, {
    required this.isHold,
    this.slicesPerCut = 1,
  });

  double get progress => isHold
      ? holdProgress
      : (completedHits / totalHitsNeeded).clamp(0.0, 1.0);

  int get completedCuts => isHold
      ? (holdProgress * totalCuts).floor().clamp(0, totalCuts)
      : (completedHits / slicesPerCut).floor().clamp(0, totalCuts);
}

const _ingredientColors = <String, Color>{
  'Carrot': Color(0xFFFF6D00),
  'Cucumber': Color(0xFF00E676),
  'Steak': Color(0xFFFF5252),
  'Cheese': Color(0xFFFFEA00),
  'Pumpkin': Color(0xFFFF9800),
  'Frozen Meat': Color(0xFF80DEEA),
  'Pineapple': Color(0xFFFFD54F),
  'Coconut': Color(0xFF8D6E63),
};

const List<Color> _laneColors = [
  Color(0xFFF0788C), // Pink (D)
  Color(0xFF7BD095), // Green (F)
  Color(0xFFFFC95C), // Yellow (J)
  Color(0xFF63A7EF), // Blue (K)
];

const List<String> _laneKeyLabels = ['D', 'F', 'J', 'K'];
const List<String> _laneNames = ['Pink (D)', 'Green (F)', 'Yellow (J)', 'Blue (K)'];

// Ingredient pools by difficulty
const _easyPool = ['Carrot', 'Cucumber', 'Cheese', 'Pumpkin'];
const _mediumPool = ['Carrot', 'Cucumber', 'Steak', 'Cheese', 'Pumpkin', 'Pineapple', 'Frozen Meat'];
const _hardPool = ['Carrot', 'Steak', 'Pumpkin', 'Pineapple', 'Frozen Meat', 'Coconut'];

int _getSlicesPerCut(String name) => switch (name) {
      'Pumpkin' || 'Pineapple' || 'Frozen Meat' => 2,
      'Coconut' => 3,
      _ => 1,
    };

class FourTileKitchenCutterScreen extends StatefulWidget {
  const FourTileKitchenCutterScreen({super.key});

  @override
  State<FourTileKitchenCutterScreen> createState() =>
      _FourTileKitchenCutterScreenState();
}

class _FourTileKitchenCutterScreenState
    extends State<FourTileKitchenCutterScreen>
    with SingleTickerProviderStateMixin {
  final List<int> _cells = const [0, 1, 2, 3];
  final PushController input = PushController();
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  final PressStats _stats = PressStats();
  final Set<int> _touchDownLanes = {}; // Tracks active touch, mouse, and keyboard button presses

  final List<_IngredientTask> _tasks = [];
  late final Ticker _ticker;

  _Phase _phase = _Phase.setup;
  Difficulty _difficulty = Difficulty.easy;
  double _time = 0;
  int _score = 0, _combo = 0, _bestCombo = 0;
  int _completed = 0;
  int _currentTaskIndex = 0;

  String _feedback = '';
  Color _feedbackColor = Colors.white;

  List<String> _generateRandomTaskPool() {
    final pool = switch (_difficulty) {
      Difficulty.easy => _easyPool,
      Difficulty.medium => _mediumPool,
      Difficulty.hard => _hardPool,
    };

    final itemCount = switch (_difficulty) {
      Difficulty.easy => 4,
      Difficulty.medium => 5,
      Difficulty.hard => 6,
    };

    return List.generate(itemCount, (_) => pool[_random.nextInt(pool.length)]);
  }

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
    _focusNode.dispose();
    super.dispose();
  }

  void _makeTasks() {
    _tasks.clear();
    final ingredients = _generateRandomTaskPool();

    for (final name in ingredients) {
      final lane = _random.nextInt(4); // 4 Lanes
      final isHold = _random.nextBool(); // Alternate hold vs tap per cut
      final pieces = switch (_difficulty) {
        Difficulty.easy => 4,
        Difficulty.medium => 5,
        Difficulty.hard => 6,
      };
      final slices = _getSlicesPerCut(name);
      _tasks.add(_IngredientTask(lane, name, pieces, isHold: isHold, slicesPerCut: slices));
    }
    _currentTaskIndex = 0;
  }

  void _start() {
    trainingStarted = true;
    input.allowed = _cells;
    input.clear();
    _touchDownLanes.clear();
    if (_ticker.isActive) _ticker.stop();
    setState(() {
      _makeTasks();
      _stats.reset();
      _score = _combo = _bestCombo = 0;
      _completed = 0;
      _time = 0;
      _feedback = 'Start Cutting!';
      _feedbackColor = Colors.greenAccent;
      _phase = _Phase.cutting;
    });

    // Request focus for keyboard input when game starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });

    _ticker.start();
  }

  void _flash(String text, Color color) {
    _feedback = text;
    _feedbackColor = color;
  }

  // ---------------------------------------------------------------------
  // Keyboard Event Handler (D, F, J, K)
  // ---------------------------------------------------------------------
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_phase != _Phase.cutting) return KeyEventResult.ignored;

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
    final cell = _cells[laneIndex];

    if (event is KeyDownEvent) {
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

  void _tick(Duration elapsed) {
    if (_phase != _Phase.cutting || !mounted) return;
    _time = elapsed.inMicroseconds / 1000000;

    setState(() {
      if (_currentTaskIndex >= _tasks.length) {
        _finish();
        return;
      }

      final current = _tasks[_currentTaskIndex];

      // Continuous hold mechanism for hold tasks
      if (current.isHold && current.state == 1) {
        final cell = _cells[current.lane];
        final isInputActive = input.isDown(cell) || _touchDownLanes.contains(current.lane);

        if (isInputActive) {
          current.holdProgress += 0.012 / current.slicesPerCut;
          if (current.holdProgress >= 1.0) {
            current.holdProgress = 1.0;
            current.state = 2;
            _completeTask(current);
          }
        }
      }
    });
  }

  void _completeTask(_IngredientTask task) {
    _completed++;
    _combo++;
    _bestCombo = max(_bestCombo, _combo);
    _score += (150 * (1 + _combo * 0.1)).round();
    _stats.add(PressResult.full);
    _flash('SLICE COMPLETE!', Colors.amberAccent);
    _currentTaskIndex++;
  }

  void _onDown(int cell) {
    if (_phase != _Phase.cutting) return;
    final lane = _cells.indexOf(cell);
    if (lane < 0 || _currentTaskIndex >= _tasks.length) return;

    final current = _tasks[_currentTaskIndex];
    if (current.lane != lane) {
      _flash('WRONG TILE!', Colors.redAccent);
      return;
    }

    setState(() {
      if (current.state == 0) {
        current.state = 1;
      }

      // Tap per chop impact
      if (!current.isHold) {
        current.completedHits++;
        
        final hitInCurrentCut = ((current.completedHits - 1) % current.slicesPerCut) + 1;
        if (current.slicesPerCut > 1 && hitInCurrentCut < current.slicesPerCut) {
          _flash('HACK! ($hitInCurrentCut/${current.slicesPerCut})', Colors.orangeAccent);
        } else {
          _flash('CHOP!', Colors.cyanAccent);
        }

        if (current.completedHits >= current.totalHitsNeeded) {
          current.state = 2;
          _completeTask(current);
        }
      }
    });
  }

  void _onUp(int cell, double seconds) {
    if (_phase != _Phase.cutting) return;
    final lane = _cells.indexOf(cell);
    if (lane < 0 || _currentTaskIndex >= _tasks.length) return;

    final current = _tasks[_currentTaskIndex];
    if (current.isHold && current.lane == lane && current.state == 1 && current.holdProgress < 1.0) {
      setState(() {
        _flash('RELEASED EARLY!', Colors.orangeAccent);
      });
    }
  }

  void _finish({bool early = false}) {
    if (_phase != _Phase.cutting) return;
    _ticker.stop();
    input.clear();
    _touchDownLanes.clear();
    _phase = _Phase.done;

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Kitchen Cutter',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: _time.round(),
      correctAttempts: _completed,
      incorrectAttempts: _tasks.length - _completed,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Kitchen Cutter | Score $_score | Completed $_completed/${_tasks.length} | Best Combo $_bestCombo',
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Kitchen Cutter Challenge (4-Tile)')),
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
                    _Phase.setup => _setup(),
                    _Phase.cutting => _play(),
                    _Phase.done => _summary(),
                  },
                ),
              ),
            ),
          ),
        ),
      );

  Widget _setup() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.kitchen_rounded, size: 72, color: Colors.orangeAccent),
          const SizedBox(height: 8),
          const Text('4-Tile Kitchen Cutter',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text(
            'Cut ingredients into equal parts using 4 colored tiles!\n\n'
            '• Pink (D) • Green (F) • Yellow (J) • Blue (K)\n\n'
            '• HOLD tasks: Press and hold the target colored tile continuously.\n'
            '• CHOP tasks: Tap the target tile rhythmic times per cut.\n'
            '• Tough items require multiple chops/holds per cut seam!\n'
            '• Controls: Use on-screen pads or keyboard keys D  F  J  K.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 20),
          chipRow<Difficulty>(
            title: 'Level',
            values: Difficulty.values,
            selected: _difficulty,
            label: (d) => d.label,
            onSelected: (d) => setState(() => _difficulty = d),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                minimumSize: const Size.fromHeight(56)),
            child: const Text('Start Cooking',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to Home'),
          ),
        ],
      );

  Widget _play() {
    final currentTask = _currentTaskIndex < _tasks.length ? _tasks[_currentTaskIndex] : null;
    final isDown = currentTask != null &&
        (input.isDown(_cells[currentTask.lane]) || _touchDownLanes.contains(currentTask.lane));

    return Container(
      color: const Color(0xFF1E1E2C),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Score: $_score', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text('Item: ${_currentTaskIndex + 1}/${_tasks.length}', style: const TextStyle(color: Colors.white70)),
              Text('Combo: x$_combo', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: Center(
              child: Text(_feedback,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _feedbackColor)),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AnimatedBuilder(
                animation: input,
                builder: (_, __) => CustomPaint(
                  painter: _KitchenCuttingPainter(
                    currentTask: currentTask,
                    isHolding: isDown,
                    animationTime: _time,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (currentTask != null) ...[
            Text(
              currentTask.isHold
                  ? 'Target: Hold ${_laneNames[currentTask.lane]} Continuously ${currentTask.slicesPerCut > 1 ? "(${currentTask.slicesPerCut}x Toughness)" : ""}'
                  : 'Target: Tap ${_laneNames[currentTask.lane]} (${currentTask.slicesPerCut}x per cut) [${currentTask.completedHits}/${currentTask.totalHitsNeeded}]',
              style: TextStyle(
                color: _laneColors[currentTask.lane],
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: currentTask.progress,
              minHeight: 10,
              backgroundColor: Colors.black26,
              color: _ingredientColors[currentTask.name] ?? Colors.orange,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
          const SizedBox(height: 12),
          // Interactive 4-Button Input Row
          _buildFourButtonRow(),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End Session', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  /// Builds 4 interactive lane buttons matching Pink, Green, Yellow, and Blue color scheme
  Widget _buildFourButtonRow() {
    return AnimatedBuilder(
      animation: input,
      builder: (context, _) {
        return Row(
          children: List.generate(4, (index) {
            final cell = _cells[index];
            final isPressed = input.isDown(cell) || _touchDownLanes.contains(index);
            final color = _laneColors[index];

            final currentTask = _currentTaskIndex < _tasks.length ? _tasks[_currentTaskIndex] : null;
            final isTargetLane = currentTask != null && currentTask.lane == index;

            double fillRatio = 0.0;
            String labelText = _laneKeyLabels[index];
            Color labelColor = Colors.white;
            Color borderColor = color;
            double borderWidth = isTargetLane ? 5.0 : 3.0;

            if (isTargetLane && currentTask.isHold && currentTask.state == 1) {
              fillRatio = currentTask.holdProgress;
              final pct = (fillRatio * 100).round();
              labelText = '$pct%';
              labelColor = Colors.amberAccent;
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
                      boxShadow: isPressed || isTargetLane
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.65),
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
                          if (fillRatio > 0)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: fillRatio,
                                widthFactor: 1.0,
                                child: Container(color: color.withValues(alpha: 0.45)),
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
            );
          }),
        );
      },
    );
  }

  Widget _summary() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
        const SizedBox(height: 8),
        const Text('Cooking Session Complete!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row('Final Score', '$_score'),
                const Divider(),
                _row('Items Cut', '$_completed / ${_tasks.length}'),
                const Divider(),
                _row('Best Combo', '$_bestCombo'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => setState(() => _phase = _Phase.setup),
          icon: const Icon(Icons.replay),
          label: const Text('Play Again'),
          style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
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

  Widget _row(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      );
}

class _KitchenCuttingPainter extends CustomPainter {
  final _IngredientTask? currentTask;
  final bool isHolding;
  final double animationTime;

  _KitchenCuttingPainter({
    required this.currentTask,
    required this.isHolding,
    required this.animationTime,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Wood Cutting Board Background
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3E2723), Color(0xFF5D4037)],
        ).createShader(rect),
    );

    final boardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(16, 16, size.width - 32, size.height - 32),
      const Radius.circular(16),
    );
    canvas.drawRRect(boardRect, Paint()..color = const Color(0xFF8D6E63));

    // Wood Grain Lines
    final grainPaint = Paint()
      ..color = const Color(0xFF795548).withValues(alpha: 0.4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (double i = 30; i < size.width; i += 50) {
      canvas.drawLine(Offset(i, 20), Offset(i + 15, size.height - 20), grainPaint);
    }

    if (currentTask == null) return;

    final center = Offset(size.width / 2, size.height * 0.60);
    final ingColor = _ingredientColors[currentTask!.name] ?? Colors.orange;
    final progress = currentTask!.progress.clamp(0.0, 1.0);

    // 2. Ingredient Name & Percentage Display
    final toughnessBadge = currentTask!.slicesPerCut > 1 ? ' [${currentTask!.slicesPerCut}x Tough]' : '';
    final percentText = '${(progress * 100).toStringAsFixed(0)}%';
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${currentTask!.name}$toughnessBadge\n$percentText',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(blurRadius: 4, color: Colors.black)],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - 105));

    const totalWidth = 240.0;
    final totalPieces = currentTask!.totalPieces;
    final totalCuts = currentTask!.totalCuts;
    final pieceWidth = totalWidth / totalPieces;
    final leftX = center.dx - (totalWidth / 2);

    final completedCutsCount = currentTask!.completedCuts;
    final isFullyDone = progress >= 1.0 || completedCutsCount >= totalCuts;

    final numSeparatedSlices = isFullyDone ? totalPieces : completedCutsCount;

    // 3. Render Cut Slices (Sliding cleanly leftwards away from remaining block)
    for (int i = 0; i < numSeparatedSlices; i++) {
      final origX = leftX + (i + 0.5) * pieceWidth;
      final shiftLeft = 12.0 + (numSeparatedSlices - 1 - i) * 3.0;
      final pieceX = origX - shiftLeft;

      final pieceRect = Rect.fromCenter(
        center: Offset(pieceX, center.dy),
        width: max(1.0, pieceWidth - 3),
        height: 60,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(pieceRect, const Radius.circular(8)),
        Paint()..color = ingColor,
      );

      // Top specular highlight
      if (pieceWidth > 10) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: pieceRect.center.translate(0, -10),
              width: max(1.0, pieceWidth - 8),
              height: 10,
            ),
            const Radius.circular(5),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.3),
        );
      }

      // Seam line on right edge of slice
      final edgeX = pieceRect.right - 1;
      canvas.drawLine(
        Offset(edgeX, center.dy - 28),
        Offset(edgeX, center.dy + 28),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.5)
          ..strokeWidth = 2.0,
      );
    }

    // 4. Render Remaining Uncut Block
    if (!isFullyDone && numSeparatedSlices < totalPieces) {
      final uncutLeftX = leftX + (numSeparatedSlices * pieceWidth);
      final uncutWidth = totalWidth - (numSeparatedSlices * pieceWidth);
      final uncutCenter = Offset(uncutLeftX + (uncutWidth / 2), center.dy);

      final uncutRect = Rect.fromCenter(
        center: uncutCenter,
        width: uncutWidth,
        height: 60,
      );

      final rRect = numSeparatedSlices == 0
          ? RRect.fromRectAndRadius(uncutRect, const Radius.circular(12))
          : RRect.fromRectAndRadius(uncutRect, const Radius.circular(8));

      canvas.drawRRect(rRect, Paint()..color = ingColor);

      if (uncutWidth > 12) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: uncutRect.center.translate(0, -10),
              width: max(1.0, uncutWidth - 10),
              height: 10,
            ),
            const Radius.circular(5),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.3),
        );
      }
    }

    // 5. Knife Target Position (Positioned strictly along cut lines 1 through totalCuts)
    final double knifeTargetX;
    if (currentTask!.isHold) {
      final startCutX = leftX + pieceWidth;
      final endCutX = leftX + totalCuts * pieceWidth;
      knifeTargetX = startCutX + progress * (endCutX - startCutX);
    } else {
      final currentCutMark = min(completedCutsCount + 1, totalCuts);
      knifeTargetX = leftX + currentCutMark * pieceWidth;
    }

    double knifeYOffset = -45.0;
    if (currentTask!.isHold) {
      knifeYOffset = isHolding
          ? 5.0 + (sin(animationTime * 30) * 4.0)
          : -45.0;
    } else {
      if (isHolding) {
        knifeYOffset = 12.0;
      } else {
        knifeYOffset = -35.0 + (sin(animationTime * 12) * 4.0);
      }
    }

    final knifeCenter = Offset(knifeTargetX, center.dy - 65 + knifeYOffset);

    // Blade Path
    final bladePath = Path()
      ..moveTo(knifeCenter.dx - 6, knifeCenter.dy)
      ..lineTo(knifeCenter.dx + 6, knifeCenter.dy)
      ..lineTo(knifeCenter.dx + 4, knifeCenter.dy + 85)
      ..lineTo(knifeCenter.dx - 6, knifeCenter.dy + 85)
      ..close();

    canvas.drawPath(bladePath, Paint()..color = Colors.blueGrey.shade100);

    // Blade Edge Highlight
    canvas.drawLine(
      Offset(knifeCenter.dx - 6, knifeCenter.dy),
      Offset(knifeCenter.dx - 6, knifeCenter.dy + 85),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );

    // Knife Handle
    final handleRect = Rect.fromCenter(
      center: knifeCenter.translate(0, -32),
      width: 14,
      height: 42,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(handleRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFF263238),
    );
  }

  @override
  bool shouldRepaint(covariant _KitchenCuttingPainter oldDelegate) => true;
}