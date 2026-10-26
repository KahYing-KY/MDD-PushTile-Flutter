import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, playing, collapsing, done }

class _BurgerLayer {
  final String name;
  final Color color;
  final double relX;
  final double relY;
  final double sizeScale;
  _BurgerLayer(this.name, this.color, this.relX, this.relY, {this.sizeScale = 1.0});
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

const List<Color> _laneColors = [
  Color(0xFFF0788C), // Left (D / F)
  Color(0xFF63A7EF), // Right (J / K)
];

const List<String> _laneKeyLabels = ['D / F', 'J / K'];
const List<String> _laneDirLabels = ['MOVE LEFT', 'MOVE RIGHT'];

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
  final PressStats _stats = PressStats();

  _Phase _phase = _Phase.setup;
  Difficulty _difficulty = Difficulty.easy;
  double _t = 0;
  double _collapseProgress = 0.0;

  final List<int> _cells = const [0, 1];

  int _score = 0;
  int _combo = 1;
  int _bestCombo = 1;
  int _layersStacked = 0;
  bool _collapsed = false;
  String _message = '';
  Color _messageColor = Colors.white;
  double _instability = 0.0;
  bool _lastCatchWasFirmGrip = false;

  double _bunX = 0.0;
  final double _bunY = 0.0;

  String _currentIngredient = 'Patty';
  double _ingX = 0.0;
  final double _ingY = 0.0;
  double _ingZ = 300.0;
  double _fallSpeed = 180.0;
  double _currentSizeScale = 1.0;

  // Track initial bun position and active press duration per ingredient fall
  double _startTopAbsX = 0.0;
  double _pressDurationThisTurn = 0.0;

  final List<_BurgerLayer> _burgerStack = [];

  @override
  void initState() {
    super.initState();
    input.allowed = _cells;
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
      _bunX = 0.0;
      _burgerStack.clear();
      _burgerStack.add(_BurgerLayer('Bottom Bun', _ingredientColors['Bottom Bun']!, 0.0, 0.0, sizeScale: 1.0));
      _stats.reset();
      _score = 0;
      _combo = 1;
      _bestCombo = 1;
      _layersStacked = 0;
      _collapsed = false;
      _collapseProgress = 0.0;
      _instability = 0.0;
      _lastCatchWasFirmGrip = false;
      _t = 0;
      _phase = _Phase.playing;
      _spawnNextIngredient();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });

    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
  }

  void _spawnNextIngredient() {
    _currentIngredient = _ingredientPool[_random.nextInt(_ingredientPool.length)];
    _ingX = (_random.nextDouble() * 2.8) - 1.4;
    _ingZ = 320.0;

    double baseSpeed = 160.0;
    if (_difficulty == Difficulty.medium) baseSpeed = 220.0;
    if (_difficulty == Difficulty.hard) baseSpeed = 290.0;

    _fallSpeed = baseSpeed + (_layersStacked * 4.0);
    _currentSizeScale = _difficulty == Difficulty.hard ? (0.7 + _random.nextDouble() * 0.5) : 1.0;

    // Calculate top of stack X position at spawn
    double cumulativeRelX = 0.0;
    for (final layer in _burgerStack) {
      cumulativeRelX += layer.relX;
    }
    _startTopAbsX = _bunX + cumulativeRelX;
    _pressDurationThisTurn = 0.0;

    _message = 'Catch the falling $_currentIngredient!';
    _messageColor = Colors.white;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_phase != _Phase.playing) return KeyEventResult.ignored;

    int? laneIndex;
    final keyLabel = event.logicalKey.keyLabel.toUpperCase();
    if (keyLabel == 'D' || keyLabel == 'F' || event.logicalKey == LogicalKeyboardKey.keyD || event.logicalKey == LogicalKeyboardKey.keyF) {
      laneIndex = 0;
    } else if (keyLabel == 'J' || keyLabel == 'K' || event.logicalKey == LogicalKeyboardKey.keyJ || event.logicalKey == LogicalKeyboardKey.keyK) {
      laneIndex = 1;
    }

    if (laneIndex == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      if (!_touchDownLanes.contains(laneIndex)) {
        setState(() => _touchDownLanes.add(laneIndex!));
      }
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      if (_touchDownLanes.contains(laneIndex)) {
        setState(() => _touchDownLanes.remove(laneIndex!));
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _isLanePressed(int laneIndex) {
    return input.isDown(_cells[laneIndex]) || _touchDownLanes.contains(laneIndex);
  }

  void _onTick(Duration e) {
    final double newT = e.inMicroseconds / 1e6;
    final double dt = newT - _t;
    _t = newT;

    if (_phase == _Phase.playing) {
      double moveX = 0.0;
      if (_isLanePressed(0)) moveX -= 1.0;
      if (_isLanePressed(1)) moveX += 1.0;

      const double moveSpeed = 2.8;
      _bunX = (_bunX + moveX * moveSpeed * dt).clamp(-1.8, 1.8);

      // Accumulate press duration while moving
      if (moveX != 0.0) {
        _pressDurationThisTurn += dt;
      }

      _ingZ -= _fallSpeed * dt;
      if (_ingZ <= 0.0) {
        _ingZ = 0.0;
        _evaluateCatch();
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

  void _evaluateCatch() {
    double cumulativeRelX = 0.0;
    for (final layer in _burgerStack) {
      cumulativeRelX += layer.relX;
    }

    final double topAbsX = _bunX + cumulativeRelX;
    final double dx = _ingX - topAbsX;
    final double catchDistance = dx.abs();

    const double maxCatchDistance = 0.95;
    if (catchDistance > maxCatchDistance) {
      _collapsed = true;
      _phase = _Phase.collapsing;
      _collapseProgress = 0.0;
      _message = 'MISSED INGREDIENT! Burger toppled over!';
      _messageColor = Colors.redAccent;
      input.clear();
      _touchDownLanes.clear();
      return;
    }

    // Evaluate press quality based on distance to target vs press duration
    const double maxMoveSpeed = 2.8;
    final double requiredDist = (_ingX - _startTopAbsX).abs();
    final double requiredDuration = requiredDist / maxMoveSpeed;

    PressResult pressResult;
    if (requiredDist < 0.12) {
      // Ingredient dropped right on top of the bun
      pressResult = PressResult.full;
    } else {
      final double ratio = _pressDurationThisTurn / requiredDuration;
      if (ratio >= 0.90) {
        pressResult = PressResult.full; // Moved full distance to target
      } else if (ratio >= 0.45) {
        pressResult = PressResult.half; // Moved at least halfway to target
      } else {
        pressResult = PressResult.none; // Less than half distance moved
      }
    }

    // Record evaluated press result for session stats
    _stats.add(pressResult);

    final bool isFullGrip = pressResult == PressResult.full;
    _lastCatchWasFirmGrip = isFullGrip;

    final double newRelX = dx * 0.75;
    _burgerStack.add(_BurgerLayer(
      _currentIngredient,
      _ingredientColors[_currentIngredient] ?? Colors.brown,
      newRelX,
      0.0,
      sizeScale: _currentSizeScale,
    ));

    _layersStacked++;

    double totalX = 0.0;
    double currentCumX = 0.0;
    for (int i = 0; i < _burgerStack.length; i++) {
      currentCumX += _burgerStack[i].relX;
      totalX += currentCumX;
    }

    final double comX = (totalX / _burgerStack.length).abs();
    final double heightFactor = 1.0 + (_layersStacked * 0.15);
    
    // Full press gives Firm Grip (-30% instability penalty)
    final double gripDampening = isFullGrip ? 0.70 : (pressResult == PressResult.half ? 0.90 : 1.0);
    _instability = (comX * heightFactor * gripDampening / 1.0).clamp(0.0, 1.2);

    if (_instability >= 1.0) {
      _collapsed = true;
      _phase = _Phase.collapsing;
      _collapseProgress = 0.0;
      _message = 'TOWER TOPPLED! Too unbalanced!';
      _messageColor = Colors.redAccent;
      input.clear();
      _touchDownLanes.clear();
      return;
    }

    int pointsEarned = 0;
    String catchQuality = '';
    if (catchDistance < 0.25) {
      pointsEarned = 350 + (_combo * 60);
      catchQuality = 'PERFECT CATCH!';
      _messageColor = Colors.greenAccent;
      _combo++;
    } else if (catchDistance < 0.6) {
      pointsEarned = 180 + (_combo * 25);
      catchQuality = 'GOOD CATCH!';
      _messageColor = Colors.lightBlueAccent;
      _combo++;
    } else {
      _combo = 1;
      pointsEarned = 60;
      catchQuality = 'OFF-CENTER CATCH!';
      _messageColor = Colors.orangeAccent;
    }

    if (pressResult == PressResult.full) {
      pointsEarned = (pointsEarned * 1.5).round();
      _message = '$catchQuality ✊ FULL PRESS (+50% pts, -30% sway)';
    } else if (pressResult == PressResult.half) {
      _message = '$catchQuality ⚡ HALF PRESS (Reached Halfway)';
    } else {
      _message = '$catchQuality ⚠️ SHORT PRESS (Under Halfway)';
    }

    _score += pointsEarned;
    _bestCombo = max(_bestCombo, _combo);
    _spawnNextIngredient();
  }

  void _finishSession() {
    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Sky Burger',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: _t.round(),
      correctAttempts: _layersStacked,
      incorrectAttempts: _collapsed ? 1 : 0,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !_collapsed,
      notes: 'Score $_score | Ingredients Caught $_layersStacked | '
          'Instability: ${(_instability * 100).toStringAsFixed(0)}% '
          '${_collapsed ? "[Toppled]" : ""}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sky Burger')),
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
        const Text('Sky Burger',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          'Move the bottom bun left and right to catch falling ingredients!\n\n'
          '• Use keys [D/F] for Left and [J/K] for Right, or tap screen buttons.\n'
          '• Holding press long enough to reach target = FULL PRESS (Firm Grip bonus).\n'
          '• Pressing enough to reach halfway = HALF PRESS.\n'
          '• Less than halfway = NO PRESS.\n'
          '• Off-center catches make your tower sway and tip over.',
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
          child: const Text('Start Catching',
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
                  color: _instability < 0.5 ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _instability < 0.5 ? Colors.greenAccent : Colors.redAccent),
                ),
                child: Text('Instability: ${(_instability * 100).toStringAsFixed(0)}%',
                    style: TextStyle(color: _instability < 0.5 ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Text('Caught: $_layersStacked',
                  style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Combo: x$_combo', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              Row(
                children: [
                  Icon(
                    _lastCatchWasFirmGrip ? Icons.back_hand_rounded : Icons.pan_tool_outlined,
                    size: 14,
                    color: _lastCatchWasFirmGrip ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _lastCatchWasFirmGrip ? 'FIRM GRIP ACTIVE' : 'LOOSE GRIP',
                    style: TextStyle(
                      color: _lastCatchWasFirmGrip ? Colors.greenAccent : Colors.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text('Best: x$_bestCombo', style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 32,
            child: Center(
              child: Text(_message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: _messageColor)),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(
                painter: _BurgerCatchPainter(
                  burgerStack: _burgerStack,
                  bunX: _bunX,
                  bunY: _bunY,
                  currentIngredient: _currentIngredient,
                  currentSizeScale: _currentSizeScale,
                  ingX: _ingX,
                  ingY: _ingY,
                  ingZ: _ingZ,
                  instability: _instability,
                  time: _t,
                  phase: _phase,
                  collapseProgress: _collapseProgress,
                  isFirmGripActive: _lastCatchWasFirmGrip,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildLeftRightButtons(),
          const SizedBox(height: 8),
          pressStatsBar(_stats, dark: true),
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

  Widget _buildLeftRightButtons() {
    return AnimatedBuilder(
      animation: input,
      builder: (context, _) {
        return Row(
          children: List.generate(2, (index) {
            final isPressed = _isLanePressed(index);
            final color = _laneColors[index];

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: Listener(
                  onPointerDown: (_) => setState(() => _touchDownLanes.add(index)),
                  onPointerUp: (_) => setState(() => _touchDownLanes.remove(index)),
                  onPointerCancel: (_) => setState(() => _touchDownLanes.remove(index)),
                  child: Container(
                    height: 72,
                    decoration: BoxDecoration(
                      color: isPressed ? color.withValues(alpha: 0.6) : const Color(0xFF14143A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: color,
                        width: isPressed ? 3.5 : 2.0,
                      ),
                      boxShadow: isPressed
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.65),
                                blurRadius: 14,
                                spreadRadius: 2,
                              )
                            ]
                          : [],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _laneDirLabels[index],
                          style: TextStyle(
                            color: isPressed ? Colors.white : color,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '[${_laneKeyLabels[index]}]',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

  Widget _summaryView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(_collapsed ? Icons.warning_rounded : Icons.emoji_events, size: 64, color: _collapsed ? Colors.redAccent : Colors.amber),
        const SizedBox(height: 8),
        Text(_collapsed ? 'Tower Toppled!' : 'Stack Session Complete!',
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
                _summaryRow('Ingredients Caught', '$_layersStacked'),
                const Divider(),
                _summaryRow('Best Combo', 'x$_bestCombo'),
                const Divider(),
                _summaryRow('Instability Peak', '${(_instability * 100).toStringAsFixed(0)}%'),
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

class _BurgerCatchPainter extends CustomPainter {
  final List<_BurgerLayer> burgerStack;
  final double bunX;
  final double bunY;
  final String currentIngredient;
  final double currentSizeScale;
  final double ingX;
  final double ingY;
  final double ingZ;
  final double instability;
  final double time;
  final _Phase phase;
  final double collapseProgress;
  final bool isFirmGripActive;

  _BurgerCatchPainter({
    required this.burgerStack,
    required this.bunX,
    required this.bunY,
    required this.currentIngredient,
    required this.currentSizeScale,
    required this.ingX,
    required this.ingY,
    required this.ingZ,
    required this.instability,
    required this.time,
    required this.phase,
    required this.collapseProgress,
    required this.isFirmGripActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
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
        ..color = isFirmGripActive
            ? Colors.greenAccent.withValues(alpha: 0.6)
            : Colors.cyanAccent.withValues(alpha: 0.4)
        ..strokeWidth = 3.0,
    );

    const double layerHeight = 22.0;
    final double stackHeightZ = burgerStack.length * layerHeight;
    final double cameraPanY = max(0.0, stackHeightZ - 100.0);

    final center = Offset(size.width / 2, size.height * 0.68 + cameraPanY);

    Offset isoToScreen(double x, double y, double zHeight) {
      final double screenX = center.dx + (x * 78.0);
      final double screenY = center.dy - zHeight + (y * 20.0);
      return Offset(screenX, screenY);
    }

    final Offset shadowCenter = isoToScreen(ingX, ingY, 0);
    canvas.drawOval(
      Rect.fromCenter(center: shadowCenter, width: 130 * currentSizeScale, height: 55 * currentSizeScale),
      Paint()..color = Colors.amberAccent.withValues(alpha: 0.2),
    );
    canvas.drawOval(
      Rect.fromCenter(center: shadowCenter, width: 130 * currentSizeScale, height: 55 * currentSizeScale),
      Paint()
        ..color = Colors.amberAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    double currentCumX = 0.0;
    double currentCumY = 0.0;
    final double swaySensing = sin(time * 3.0) * instability * 0.12;

    for (int i = 0; i < burgerStack.length; i++) {
      final layer = burgerStack[i];
      currentCumX += layer.relX;
      currentCumY += layer.relY;

      final double swayX = i * swaySensing;
      double x = bunX + currentCumX + swayX;
      double y = bunY + currentCumY;
      double zH = i * layerHeight;

      if (phase == _Phase.collapsing) {
        final scatterFactor = (i + 1) * 0.3;
        final dir = (i % 2 == 0 ? 1.0 : -1.0);
        x += collapseProgress * scatterFactor * dir * 2.0;
        y += collapseProgress * scatterFactor * (i % 3 == 0 ? 1.0 : -0.8) * 1.6;
        zH = max(-10.0, zH - (collapseProgress * collapseProgress) * (200.0 + i * 18.0));
      }

      final Offset layerCenter = isoToScreen(x, y, zH);
      _drawIsometricLayer(canvas, layerCenter, layer.name, layer.color, scale: layer.sizeScale);
    }

    if (phase == _Phase.playing) {
      final Offset fallingCenter = isoToScreen(ingX, ingY, ingZ + stackHeightZ);
      _drawIsometricLayer(
        canvas,
        fallingCenter,
        currentIngredient,
        _ingredientColors[currentIngredient] ?? Colors.brown,
        scale: currentSizeScale,
      );

      final Offset topStackCenter = isoToScreen(bunX + currentCumX, bunY + currentCumY, stackHeightZ);
      canvas.drawLine(
        fallingCenter,
        topStackCenter,
        Paint()
          ..color = isFirmGripActive
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.15)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawIsometricLayer(Canvas canvas, Offset center, String name, Color color, {double scale = 1.0}) {
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

  @override
  bool shouldRepaint(covariant _BurgerCatchPainter oldDelegate) => true;
}