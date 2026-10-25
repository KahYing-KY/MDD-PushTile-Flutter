import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, playing, collapsing, done }
enum _DropStep { selectX, selectY, dropping }

class _BurgerLayer {
  final String name;
  final Color color;
  final double x; // Width offset (-1.0 to 1.0)
  final double y; // Depth/Length offset (-1.0 to 1.0)
  final double sizeScale; // Scale multiplier for hard difficulty
  _BurgerLayer(this.name, this.color, this.x, this.y, {this.sizeScale = 1.0});
}

const Map<String, Color> _ingredientColors = {
  'Bottom Bun': Color(0xFFD7CCC8),
  'Patty': Color(0xFF4E342E),
  'Cheese': Color(0xFFFFD54F),
  'Tomato': Color(0xFFEF5350),
  'Lettuce': Color(0xFF66BB6A),
  'Pickle': Color(0xFF81C784),
  'Top Bun': Color(0xFFD7CCC8),
};

const List<String> _ingredientPool = [
  'Patty', 'Cheese', 'Tomato', 'Lettuce', 'Pickle'
];

class SkyBurger2DScreen extends StatefulWidget {
  const SkyBurger2DScreen({super.key});

  @override
  State<SkyBurger2DScreen> createState() => _SkyBurger2DScreenState();
}

class _SkyBurger2DScreenState extends State<SkyBurger2DScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final PushController input = PushController();
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  final Set<int> _touchDownLanes = {};

  _Phase _phase = _Phase.setup;
  Difficulty _difficulty = Difficulty.easy;
  double _t = 0;
  double _stepT = 0.0;
  double _collapseProgress = 0.0;
  double _currentOscillationSpeed = 1.5;
  double _currentSizeScale = 1.0;

  // 2x2 grid cell indices [0, 1, 2, 3]
  final List<int> _cells = const [0, 1, 2, 3];

  int _score = 0;
  int _combo = 1;
  int _bestCombo = 1;
  int _layersStacked = 0;
  bool _collapsed = false;
  String _message = '';
  Color _messageColor = Colors.white;
  double _lastAlignmentAccuracy = 100.0;

  // Current falling ingredient state in 2.5D space
  String _currentIngredient = 'Bottom Bun';
  _DropStep _dropStep = _DropStep.selectX;
  double _currentX = 0.0;
  double _currentY = 0.0;
  double _lockedX = 0.0;
  double _lockedY = 0.0;
  double _dropAnimProgress = 1.0;

  final List<_BurgerLayer> _burgerStack = [];

  @override
  void initState() {
    super.initState();
    input.allowed = _cells;
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

  void _startGame() {
    trainingStarted = true;
    input.allowed = _cells;
    input.clear();
    _touchDownLanes.clear();

    setState(() {
      _burgerStack.clear();
      _burgerStack.add(_BurgerLayer('Bottom Bun', _ingredientColors['Bottom Bun']!, 0.0, 0.0, sizeScale: 1.0));
      _spawnNextIngredient();
      _score = 0;
      _combo = 1;
      _bestCombo = 1;
      _layersStacked = 0;
      _collapsed = false;
      _collapseProgress = 0.0;
      _lastAlignmentAccuracy = 100.0;
      _t = 0;
      _phase = _Phase.playing;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });

    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
  }

  void _spawnNextIngredient() {
    _currentIngredient = _ingredientPool[_random.nextInt(_ingredientPool.length)];
    _dropStep = _DropStep.selectX;
    _stepT = 0.0;
    _currentX = 0.0;
    _currentY = 0.0;
    _dropAnimProgress = 1.0;

    // Vary speed based on difficulty
    if (_difficulty == Difficulty.easy) {
      _currentOscillationSpeed = 1.5;
    } else if (_difficulty == Difficulty.medium) {
      _currentOscillationSpeed = 1.8 + _random.nextDouble() * 1.5; // 1.8 to 3.3
    } else {
      // Hard: Faster speed variation
      _currentOscillationSpeed = 2.4 + _random.nextDouble() * 2.2; // 2.4 to 4.6
    }

    // Vary ingredient size for Hard difficulty
    if (_difficulty == Difficulty.hard) {
      _currentSizeScale = 0.7 + _random.nextDouble() * 0.6; // 0.7 to 1.3 scale
    } else {
      _currentSizeScale = 1.0;
    }

    _message = 'Step 1: Lock X-Axis (Speed: ${_currentOscillationSpeed.toStringAsFixed(1)}x)';
    _messageColor = Colors.cyanAccent;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_phase != _Phase.playing) return KeyEventResult.ignored;

    int? cellIndex;
    final keyLabel = event.logicalKey.keyLabel.toUpperCase();
    if (keyLabel == 'D' || event.logicalKey == LogicalKeyboardKey.keyD) {
      cellIndex = 0;
    } else if (keyLabel == 'F' || event.logicalKey == LogicalKeyboardKey.keyF) {
      cellIndex = 1;
    } else if (keyLabel == 'J' || event.logicalKey == LogicalKeyboardKey.keyJ) {
      cellIndex = 2;
    } else if (keyLabel == 'K' || event.logicalKey == LogicalKeyboardKey.keyK) {
      cellIndex = 3;
    }

    if (cellIndex == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      if (!_touchDownLanes.contains(cellIndex)) {
        setState(() {
          _touchDownLanes.add(cellIndex!);
        });
        _handleCellAction(cellIndex);
      }
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      if (_touchDownLanes.contains(cellIndex)) {
        _touchDownLanes.remove(cellIndex);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _handleCellAction(int cell) {
    if (_phase != _Phase.playing || _dropStep == _DropStep.dropping) return;

    if (_dropStep == _DropStep.selectX) {
      _lockedX = _currentX;
      _dropStep = _DropStep.selectY;
      _stepT = 0.0;
      _currentY = 0.0;
      _message = 'Step 2: Lock Y-Axis (Depth) & Drop!';
      _messageColor = Colors.pinkAccent;
    } else if (_dropStep == _DropStep.selectY) {
      _lockedY = _currentY;
      _dropStep = _DropStep.dropping;
      _dropAnimProgress = 0.0;
    }
  }

  void _onDown(int cell) {
    _handleCellAction(cell);
  }

  void _onUp(int cell, double sec) {}

  void _onTick(Duration e) {
    final double newT = e.inMicroseconds / 1e6;
    final double dt = newT - _t;
    _t = newT;

    if (_phase == _Phase.playing) {
      _stepT += dt;
      if (_dropStep == _DropStep.selectX) {
        _currentX = 1.4 * sin(_stepT * _currentOscillationSpeed * pi);
      } else if (_dropStep == _DropStep.selectY) {
        _currentY = 1.4 * sin(_stepT * _currentOscillationSpeed * pi);
      } else if (_dropStep == _DropStep.dropping) {
        _dropAnimProgress += 0.08;
        if (_dropAnimProgress >= 1.0) {
          _dropAnimProgress = 1.0;
          _evaluatePlacement();
        }
      }
      setState(() {});
    } else if (_phase == _Phase.collapsing) {
      _collapseProgress += 0.04;
      if (_collapseProgress >= 1.0) {
        _collapseProgress = 1.0;
        _phase = _Phase.done;
        _finishSession();
      }
      setState(() {});
    }
  }

  void _evaluatePlacement() {
    final prevLayer = _burgerStack.last;
    final deltaX = _lockedX - prevLayer.x;
    final deltaY = _lockedY - prevLayer.y;
    final distanceToPrev = sqrt(deltaX * deltaX + deltaY * deltaY);

    const maxStableOffset = 1.1;
    _lastAlignmentAccuracy = ((1.0 - (distanceToPrev / maxStableOffset)).clamp(0.0, 1.0)) * 100;

    if (distanceToPrev > maxStableOffset) {
      _collapsed = true;
      _phase = _Phase.collapsing;
      _collapseProgress = 0.0;
      _message = 'TOWER COLLAPSED! Too imbalanced!';
      _messageColor = Colors.redAccent;
      input.clear();
      _touchDownLanes.clear();
      return;
    }

    int pointsEarned = 0;
    if (distanceToPrev < 0.25) {
      pointsEarned = 350 + (_combo * 60);
      _message = 'PERFECT ALIGNMENT! (+${pointsEarned} pts)';
      _messageColor = Colors.greenAccent;
      _combo++;
    } else if (distanceToPrev < 0.6) {
      pointsEarned = 180 + (_combo * 25);
      _message = 'GOOD STACK! (+${pointsEarned} pts)';
      _messageColor = Colors.lightBlueAccent;
      _combo++;
    } else {
      _combo = 1;
      pointsEarned = 60;
      _message = 'UNSTABLE STACK! (+${pointsEarned} pts)';
      _messageColor = Colors.orangeAccent;
    }

    _score += pointsEarned;
    _bestCombo = max(_bestCombo, _combo);
    _layersStacked++;

    _burgerStack.add(_BurgerLayer(
      _currentIngredient,
      _ingredientColors[_currentIngredient] ?? Colors.brown,
      _lockedX,
      _lockedY,
      sizeScale: _currentSizeScale,
    ));

    _spawnNextIngredient();
  }

  void _finishSession() {
    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Sky Burger 2.5D Infinite',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: _t.round(),
      correctAttempts: _layersStacked,
      incorrectAttempts: _collapsed ? 1 : 0,
      fullPresses: _score,
      halfPresses: 0,
      noPresses: 0,
      completed: !_collapsed,
      notes: 'Score $_score | Ingredients Stacked $_layersStacked | Best Combo $_bestCombo ${_collapsed ? "[Collapsed]" : ""}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sky Burger (Endless 2.5D Stacker)')),
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
                  _Phase.setup => _setupView(),
                  _Phase.playing || _Phase.collapsing => _playView(),
                  _Phase.done => _summaryView(),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _setupView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.fastfood_rounded, size: 72, color: Colors.orangeAccent),
        const SizedBox(height: 8),
        const Text('Sky Burger Endless 2.5D',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          'Endless 3D isometric stacking with variable speed & size physics!\n\n'
          '• Medium/Hard: Movement speeds vary per ingredient.\n'
          '• Hard: Ingredient sizes vary randomly.\n'
          '• Watch out for tower balance and precise alignment!',
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
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _startGame,
          style: FilledButton.styleFrom(
              backgroundColor: Colors.orange, minimumSize: const Size.fromHeight(56)),
          child: const Text('Start Endless Grilling',
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

  Widget _playView() {
    return Container(
      color: const Color(0xFF0F0F23),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Score: $_score',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _lastAlignmentAccuracy > 80 ? Colors.green.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _lastAlignmentAccuracy > 80 ? Colors.greenAccent : Colors.orangeAccent),
                ),
                child: Text('Alignment: ${_lastAlignmentAccuracy.toStringAsFixed(0)}%',
                    style: TextStyle(color: _lastAlignmentAccuracy > 80 ? Colors.greenAccent : Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Text('Ingredients: $_layersStacked',
                  style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Combo: x$_combo', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              Text('Best: x$_bestCombo', style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 32,
            child: Center(
              child: Text(_message,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: _messageColor)),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(
                painter: _Burger25DPainter(
                  burgerStack: _burgerStack,
                  currentIngredient: _currentIngredient,
                  currentSizeScale: _currentSizeScale,
                  dropStep: _dropStep,
                  currentX: _currentX,
                  currentY: _currentY,
                  lockedX: _lockedX,
                  dropAnimProgress: _dropAnimProgress,
                  phase: _phase,
                  collapseProgress: _collapseProgress,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildHorizontalButtonGrid(),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _ticker.stop();
              setState(() => _phase = _Phase.done);
              _finishSession();
            },
            child: const Text('End Session', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalButtonGrid() {
    return AnimatedBuilder(
      animation: input,
      builder: (context, _) {
        return Row(
          children: [
            _buildGridButton(0, 'Left 1 [D]', Colors.cyan),
            const SizedBox(width: 6),
            _buildGridButton(1, 'Right 1 [F]', Colors.cyan),
            const SizedBox(width: 6),
            _buildGridButton(2, 'Left 2 [J]', Colors.pinkAccent),
            const SizedBox(width: 6),
            _buildGridButton(3, 'Right 2 [K]', Colors.pinkAccent),
          ],
        );
      },
    );
  }

  Widget _buildGridButton(int index, String label, Color accentColor) {
    final cell = _cells[index];
    final isPressed = input.isDown(cell) || _touchDownLanes.contains(index);

    return Expanded(
      child: Listener(
        onPointerDown: (_) {
          setState(() {
            _touchDownLanes.add(index);
          });
          _handleCellAction(index);
        },
        onPointerUp: (_) {
          setState(() {
            _touchDownLanes.remove(index);
          });
        },
        onPointerCancel: (_) {
          setState(() {
            _touchDownLanes.remove(index);
          });
        },
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF14143A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accentColor,
              width: 2.0,
            ),
            boxShadow: isPressed
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.6),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(_collapsed ? Icons.warning_rounded : Icons.emoji_events, size: 64, color: _collapsed ? Colors.redAccent : Colors.amber),
        const SizedBox(height: 8),
        Text(_collapsed ? 'Tower Collapsed!' : 'Stack Session Complete!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _summaryRow('Final Score', '$_score'),
                const Divider(),
                _summaryRow('Ingredients Stacked', '$_layersStacked'),
                const Divider(),
                _summaryRow('Best Combo', 'x$_bestCombo'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => setState(() => _phase = _Phase.setup),
          icon: const Icon(Icons.replay),
          label: const Text('Try Again'),
          style: FilledButton.styleFrom(
              backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16, color: Colors.black87)),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      );
}

class _Burger25DPainter extends CustomPainter {
  final List<_BurgerLayer> burgerStack;
  final String currentIngredient;
  final double currentSizeScale;
  final _DropStep dropStep;
  final double currentX;
  final double currentY;
  final double lockedX;
  final double dropAnimProgress;
  final _Phase phase;
  final double collapseProgress;

  _Burger25DPainter({
    required this.burgerStack,
    required this.currentIngredient,
    required this.currentSizeScale,
    required this.dropStep,
    required this.currentX,
    required this.currentY,
    required this.lockedX,
    required this.dropAnimProgress,
    required this.phase,
    required this.collapseProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // --- STYLIZED DINER KITCHEN BACKGROUND ---
    final wallRect = Offset.zero & size;
    canvas.drawRect(
      wallRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B143F), Color(0xFF0C091E)],
        ).createShader(wallRect),
    );

    final tilePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1.0;
    for (double x = 0; x < size.width; x += 45) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height * 0.7), tilePaint);
    }
    for (double y = 0; y < size.height * 0.7; y += 45) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), tilePaint);
    }

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.8),
        radius: 0.8,
        colors: [
          Colors.pinkAccent.withValues(alpha: 0.12),
          Colors.cyanAccent.withValues(alpha: 0.04),
          Colors.transparent,
        ],
      ).createShader(wallRect);
    canvas.drawRect(wallRect, glowPaint);

    final counterRect = Rect.fromLTWH(0, size.height * 0.65, size.width, size.height * 0.35);
    canvas.drawRect(
      counterRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A244E), Color(0xFF120E26)],
        ).createShader(counterRect),
    );
    canvas.drawLine(
      Offset(0, size.height * 0.65),
      Offset(size.width, size.height * 0.65),
      Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.4)
        ..strokeWidth = 3.0,
    );

    // --- GAME SCENE & ISOMETRIC PROJECTION ---
    const double layerHeight = 22.0;
    final double stackHeightZ = burgerStack.length * layerHeight;
    final double cameraPanY = max(0.0, stackHeightZ - 120.0);

    final center = Offset(size.width / 2, size.height * 0.68 + cameraPanY);

    Offset isoToScreen(double x, double y, double zHeight) {
      final double screenX = center.dx + (x - y) * 55.0;
      final double screenY = center.dy - zHeight + (x + y) * 20.0;
      return Offset(screenX, screenY);
    }

    final platePaint = Paint()..color = Colors.white.withValues(alpha: 0.15);
    final plateCenter = isoToScreen(0, 0, -15.0);
    canvas.drawOval(
      Rect.fromCenter(center: plateCenter, width: 220, height: 110),
      platePaint,
    );

    final bullseyePaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawOval(
      Rect.fromCenter(center: plateCenter, width: 50, height: 25),
      bullseyePaint,
    );
    canvas.drawLine(
      isoToScreen(-0.3, 0, -15.0),
      isoToScreen(0.3, 0, -15.0),
      bullseyePaint,
    );
    canvas.drawLine(
      isoToScreen(0, -0.3, -15.0),
      isoToScreen(0, 0.3, -15.0),
      bullseyePaint,
    );

    // 1. Draw Burger Stack (with individual size scaling)
    for (int i = 0; i < burgerStack.length; i++) {
      final layer = burgerStack[i];
      double x = layer.x;
      double y = layer.y;
      double zH = i * layerHeight;

      if (phase == _Phase.collapsing) {
        final scatterFactor = (i + 1) * 0.25;
        final dir = (i % 2 == 0 ? 1.0 : -1.0);
        x += collapseProgress * scatterFactor * dir * 1.8;
        y += collapseProgress * scatterFactor * (i % 3 == 0 ? 1.0 : -0.8) * 1.5;
        zH = max(-10.0, zH - (collapseProgress * collapseProgress) * (200.0 + i * 15.0));
      }

      final Offset layerCenter = isoToScreen(x, y, zH);
      _drawIsometricLayer(canvas, layerCenter, layer.name, layer.color, scale: layer.sizeScale);
    }

    if (phase == _Phase.playing) {
      double targetX = currentX;
      double targetY = 0.0;
      if (dropStep == _DropStep.selectY || dropStep == _DropStep.dropping) {
        targetX = lockedX;
        targetY = currentY;
      }

      // Aim Marker & Drop Target Ring scaled to current ingredient size
      final Offset ghostCenter = isoToScreen(targetX, targetY, stackHeightZ);
      final ghostPaint = Paint()
        ..color = (dropStep == _DropStep.selectX ? Colors.cyanAccent : Colors.pinkAccent)
            .withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawOval(
        Rect.fromCenter(center: ghostCenter, width: 140 * currentSizeScale, height: 64 * currentSizeScale),
        ghostPaint,
      );

      final prevLayer = burgerStack.last;
      final Offset immediatePrevCenter = isoToScreen(prevLayer.x, prevLayer.y, stackHeightZ - layerHeight);
      canvas.drawLine(
        immediatePrevCenter,
        ghostCenter,
        Paint()
          ..color = Colors.greenAccent.withValues(alpha: 0.4)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );

      // 2. Draw Falling / Hovering Ingredient with Shadow aligned precisely to Drop Marker
      if (dropStep != _DropStep.dropping || dropAnimProgress < 1.0) {
        double renderX = currentX;
        double renderY = currentY;
        double startZ = stackHeightZ + 160.0;

        if (dropStep == _DropStep.selectY) {
          renderX = lockedX;
        } else if (dropStep == _DropStep.dropping) {
          renderX = lockedX;
          renderY = currentY;
          startZ = uiLerp(startZ, stackHeightZ, dropAnimProgress);
        }

        final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
        canvas.drawOval(
          Rect.fromCenter(center: ghostCenter, width: 120 * currentSizeScale, height: 50 * currentSizeScale),
          shadowPaint,
        );

        final Offset fallingCenter = isoToScreen(renderX, renderY, startZ);
        _drawIsometricLayer(
          canvas,
          fallingCenter,
          currentIngredient,
          _ingredientColors[currentIngredient] ?? Colors.brown,
          scale: currentSizeScale,
          isFalling: false,
        );
      }
    }
  }

  void _drawIsometricLayer(Canvas canvas, Offset center, String name, Color color, {double scale = 1.0, bool isFalling = false}) {
    const double baseThickness = 18.0;
    final double thickness = baseThickness * scale;
    final double baseWidth = 140.0 * scale;
    final double baseHeight = 64.0 * scale;

    final bottomCenter = center.translate(0, thickness);

    final sideColor = Color.lerp(color, Colors.black, 0.35)!;
    final sidePaint = Paint()..color = sideColor;

    final cylinderSide = Path()
      ..moveTo(center.dx - (baseWidth / 2), center.dy)
      ..lineTo(bottomCenter.dx - (baseWidth / 2), bottomCenter.dy)
      ..arcTo(Rect.fromCenter(center: bottomCenter, width: baseWidth, height: baseHeight), pi, pi, false)
      ..lineTo(center.dx + (baseWidth / 2), center.dy)
      ..arcTo(Rect.fromCenter(center: center, width: baseWidth, height: baseHeight), 0, -pi, false)
      ..close();

    canvas.drawPath(cylinderSide, sidePaint);
    canvas.drawOval(
      Rect.fromCenter(center: bottomCenter, width: baseWidth, height: baseHeight),
      sidePaint,
    );

    final topRect = Rect.fromCenter(center: center, width: baseWidth, height: baseHeight);
    final topPaint = Paint()..color = color;
    canvas.drawOval(topRect, topPaint);

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: center.translate(-22 * scale, -8 * scale), width: 85 * scale, height: 30 * scale),
      highlightPaint,
    );

    if (name == 'Tomato') {
      final seedPaint = Paint()..color = Colors.white70;
      canvas.drawCircle(center.translate(-22 * scale, -6 * scale), 3.5 * scale, seedPaint);
      canvas.drawCircle(center.translate(22 * scale, 4 * scale), 3.5 * scale, seedPaint);
    } else if (name == 'Cheese') {
      final dripPath = Path()
        ..moveTo(center.dx + (50 * scale), center.dy + (12 * scale))
        ..quadraticBezierTo(center.dx + (75 * scale), center.dy + (30 * scale), center.dx + (65 * scale), center.dy + (40 * scale))
        ..quadraticBezierTo(center.dx + (55 * scale), center.dy + (30 * scale), center.dx + (40 * scale), center.dy + (22 * scale))
        ..close();
      canvas.drawPath(dripPath, topPaint);
    } else if (name == 'Lettuce') {
      final leafBorder = Paint()
        ..color = Colors.green.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * scale;
      canvas.drawOval(Rect.fromCenter(center: center, width: (baseWidth + 6), height: (baseHeight + 4)), leafBorder);
    }
  }

  double uiLerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(covariant _Burger25DPainter oldDelegate) => true;
}