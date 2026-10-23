import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, cutting, done }

class _IngredientTask {
  final int lane; // 0 = Left Tile (Hold to Slice), 1 = Right Tile (Tap & Hold per cut)
  final String name;
  final double requiredDuration; 
  double progress = 0; // 0.0 to 1.0
  int state = 0; // 0: pending, 1: active/cutting, 2: completed
  double activeTime = 0;
  
  _IngredientTask(this.lane, this.name, this.requiredDuration);
}

const _ingredientColors = <String, Color>{
  'Carrot': Color(0xFFFF6D00),
  'Cucumber': Color(0xFF00E676),
  'Steak': Color(0xFFFF5252),
  'Cheese': Color(0xFFFFEA00),
};

class TwoTileKitchenCutterScreen extends StatefulWidget {
  const TwoTileKitchenCutterScreen({super.key});

  @override
  State<TwoTileKitchenCutterScreen> createState() =>
      _TwoTileKitchenCutterScreenState();
}

class _TwoTileKitchenCutterScreenState extends State<TwoTileKitchenCutterScreen>
    with SingleTickerProviderStateMixin {
  static const _cells = <int>[3, 5]; // G (Left) and J (Right)
  final PushController input = PushController();
  final Random _random = Random();
  final PressStats _stats = PressStats();
  
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

  List<String> get _ingredientList => switch (_difficulty) {
        Difficulty.easy => ['Carrot', 'Cucumber', 'Carrot', 'Cucumber'],
        Difficulty.medium => ['Carrot', 'Cucumber', 'Steak', 'Cheese', 'Carrot'],
        Difficulty.hard => ['Steak', 'Cheese', 'Carrot', 'Cucumber', 'Steak', 'Cheese'],
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

  void _makeTasks() {
    _tasks.clear();
    for (final name in _ingredientList) {
      final lane = _random.nextInt(2);
      final duration = switch (_difficulty) {
        Difficulty.easy => 3.0,
        Difficulty.medium => 4.5,
        Difficulty.hard => 6.0,
      };
      _tasks.add(_IngredientTask(lane, name, duration));
    }
    _currentTaskIndex = 0;
  }

  void _start() {
    trainingStarted = true;
    input.allowed = _cells;
    input.clear();
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
    _ticker.start();
  }

  void _flash(String text, Color color) {
    _feedback = text;
    _feedbackColor = color;
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
      
      // Left Tile (Lane 0) continuous hold slice
      if (current.lane == 0 && current.state == 1) {
        if (input.isDown(_cells[0])) {
          current.activeTime += 0.016;
          current.progress = min(1.0, current.activeTime / current.requiredDuration);
          
          if (current.progress >= 1.0) {
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
    _score += (100 * (1 + _combo * 0.1)).round();
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

      // Right Tile (Lane 1) tap & hold per individual cut slice step
      if (lane == 1) {
        current.activeTime += 0.8;
        current.progress = min(1.0, current.activeTime / current.requiredDuration);
        _flash('CHOP!', Colors.cyanAccent);
        
        if (current.progress >= 1.0) {
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
    if (lane == 0 && current.lane == 0 && current.state == 1 && current.progress < 1.0) {
      setState(() {
        _flash('RELEASED EARLY!', Colors.orangeAccent);
      });
    }
  }

  void _finish({bool early = false}) {
    if (_phase != _Phase.cutting) return;
    _ticker.stop();
    input.clear();
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
        appBar: AppBar(title: const Text('Kitchen Cutter Challenge')),
        body: SafeArea(
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
      );

  Widget _setup() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.kitchen_rounded, size: 72, color: Colors.orangeAccent),
          const SizedBox(height: 8),
          const Text('Two-Tile Kitchen Cutter',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text(
            'Cut ingredients into equal parts!\n\n'
            '• Left Tile (G): Press and HOLD continuously to slice steady ingredients.\n'
            '• Right Tile (J): Tap and hold repeatedly for rhythmic chops.',
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
    final isDown = currentTask != null && input.isDown(_cells[currentTask.lane]);

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
              currentTask.lane == 0 
                  ? 'Target: Hold Left Tile (G) Continuously' 
                  : 'Target: Press & Hold Right Tile (J) Repeatedly',
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.w600),
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
          // Controller Tiles UI matching G and J
          SizedBox(
            height: 100,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: PushTile(
                      cell: _cells[0],
                      input: input,
                      style: TileStyle(
                        bg: const Color(0xFF14143A),
                        border: Colors.cyanAccent,
                        borderWidth: 3,
                        labelColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: PushTile(
                      cell: _cells[1],
                      input: input,
                      style: TileStyle(
                        bg: const Color(0xFF14143A),
                        border: Colors.pinkAccent,
                        borderWidth: 3,
                        labelColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End Session', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.done_all, size: 64, color: Colors.greenAccent),
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

    // Wood Grain
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
    final progress = currentTask!.progress;

    // Task Label
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${currentTask!.name} - ${(progress * 100).toStringAsFixed(0)}%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(blurRadius: 4, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - 95));

    const totalWidth = 240.0;
    const totalSegments = 6;
    final pieceWidth = totalWidth / totalSegments;

    // Number of segments fully cut so far (0 to totalSegments)
    final cutCount = (progress * totalSegments).floor();

    // 2. Render Separated Cut Slices (Left side sliding outwards)
    for (int i = 0; i < cutCount; i++) {
      final distanceFromCenter = (i - (totalSegments / 2.0) + 0.5);
      final pieceX = center.dx + (distanceFromCenter * pieceWidth) + (distanceFromCenter.sign * 16.0);

      final pieceRect = Rect.fromCenter(
        center: Offset(pieceX, center.dy),
        width: pieceWidth - 4,
        height: 60,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(pieceRect, const Radius.circular(8)),
        Paint()..color = ingColor,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: pieceRect.center.translate(0, -10), width: pieceWidth - 12, height: 10),
          const Radius.circular(5),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.3),
      );

      // Dark edge cut line
      final edgeX = pieceX + (pieceWidth / 2) - 2;
      canvas.drawLine(
        Offset(edgeX, center.dy - 30),
        Offset(edgeX, center.dy + 30),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.6)
          ..strokeWidth = 2.5,
      );
    }

    // 3. Render Remaining Uncut Whole Block (Right side remaining)
    if (cutCount < totalSegments) {
      final uncutLeftX = center.dx - (totalWidth / 2) + (cutCount * pieceWidth);
      final uncutWidth = totalWidth - (cutCount * pieceWidth);
      final uncutCenter = Offset(uncutLeftX + (uncutWidth / 2), center.dy);

      final uncutRect = Rect.fromCenter(
        center: uncutCenter,
        width: uncutWidth,
        height: 60,
      );

      // Draw as one solid whole block (only rounding the outer right edge if part is cut)
      final rRect = cutCount == 0
          ? RRect.fromRectAndRadius(uncutRect, const Radius.circular(12))
          : RRect.fromRectAndRadius(uncutRect, const Radius.circular(8));

      canvas.drawRRect(rRect, Paint()..color = ingColor);

      // Glossy highlight spanning across the uncut block
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: uncutRect.center.translate(0, -10), width: uncutWidth - 16, height: 10),
          const Radius.circular(5),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.3),
      );
    }

    // 4. Kitchen Knife Animation (positioned at the current cutting edge)
    final knifeTargetX = center.dx - (totalWidth / 2) + (min(cutCount, totalSegments - 1) * pieceWidth);
    double knifeYOffset = isHolding ? 10.0 : -45.0;
    if (!isHolding && currentTask!.lane == 1) {
      knifeYOffset = -25.0 + sin(animationTime * 20) * 12;
    }

    final knifeCenter = Offset(knifeTargetX, center.dy - 75 + knifeYOffset);

    // Knife Blade
    final bladePath = Path()
      ..moveTo(knifeCenter.dx - 5, knifeCenter.dy)
      ..lineTo(knifeCenter.dx + 6, knifeCenter.dy)
      ..lineTo(knifeCenter.dx + 3, knifeCenter.dy + 90)
      ..lineTo(knifeCenter.dx - 5, knifeCenter.dy + 90)
      ..close();

    canvas.drawPath(bladePath, Paint()..color = Colors.blueGrey.shade100);

    // Blade Edge
    canvas.drawLine(
      Offset(knifeCenter.dx - 5, knifeCenter.dy),
      Offset(knifeCenter.dx - 5, knifeCenter.dy + 90),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );

    // Handle
    final handleRect = Rect.fromCenter(center: knifeCenter.translate(0, -35), width: 16, height: 45);
    canvas.drawRRect(
      RRect.fromRectAndRadius(handleRect, const Radius.circular(6)),
      Paint()..color = const Color(0xFF263238),
    );
  }

  @override
  bool shouldRepaint(covariant _KitchenCuttingPainter oldDelegate) => true;
}