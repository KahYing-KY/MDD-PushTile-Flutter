import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _HuntPhase { setup, playing, done }

const List<Color> _dirColors = [
  Color(0xFFF0788C), // West / Left
  Color(0xFF7BD095), // South / Down
  Color(0xFFFFC95C), // North / Up
  Color(0xFF63A7EF), // East / Right
];

const List<String> _dirLabels = ['D  ←', 'F  ↓', 'J  ↑', 'K  →'];
const List<String> _dirKeyNames = ['D', 'F', 'J', 'K'];

PressResult classifyNoteHold(double heldSeconds, double targetDuration) {
  if (targetDuration <= 0) return PressResult.none;
  final ratio = heldSeconds / targetDuration;
  if (ratio >= 0.90) return PressResult.full;
  if (ratio >= 0.45) return PressResult.half;
  return PressResult.none;
}

enum TileType {
  grass,
  path,
  water,
  tree,
  landmarkWatchtower,
  landmarkObelisk,
  landmarkGrove,
  landmarkCrag,
  treasure,
}

class LandmarkInfo {
  final String name;
  final String code;
  final Color color;
  final IconData icon;
  final int x;
  final int y;

  const LandmarkInfo(this.name, this.code, this.color, this.icon, this.x, this.y);
}

class TreasureHunt2D5Screen extends StatefulWidget {
  const TreasureHunt2D5Screen({super.key});

  @override
  State<TreasureHunt2D5Screen> createState() => _TreasureHunt2D5ScreenState();
}

class _TreasureHunt2D5ScreenState extends State<TreasureHunt2D5Screen>
    with SingleTickerProviderStateMixin {
  static const int mapWidth = 20;
  static const int mapHeight = 20;

  late final Ticker _ticker;
  final PushController input = PushController();
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  final PressStats _stats = PressStats();
  final Set<int> _touchDownLanes = {};

  _HuntPhase _phase = _HuntPhase.setup;
  Difficulty _difficulty = Difficulty.easy;
  double _t = 0;

  int _playerX = 2;
  int _playerY = 2;
  int _treasureX = 16;
  int _treasureY = 16;

  final Map<int, double> _lanePressStart = {};
  late List<List<TileType>> _mapGrid;
  List<LandmarkInfo> _landmarks = [];

  int _totalMoves = 0;
  int _blockedAttempts = 0;
  String _judgment = '';
  Color _judgmentColor = Colors.white;

  List<int> get _laneCells => const [0, 1, 2, 3];

  double get _targetHoldSec => switch (_difficulty) {
        Difficulty.easy => 0.6,
        Difficulty.medium => 0.8,
        Difficulty.hard => 1.0,
      };

  @override
  void initState() {
    super.initState();
    input.allowed = _laneCells;
    input.onDown = _onDown;
    input.onUp = (lane, _) => _onUp(lane);
    _ticker = createTicker(_onTick);
    _generateMap();
  }

  @override
  void dispose() {
    _ticker.dispose();
    input.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _generateMap() {
    _mapGrid = List.generate(
      mapHeight,
      (y) => List.generate(mapWidth, (x) => TileType.grass),
    );

    for (int x = 0; x < mapWidth; x++) {
      _mapGrid[0][x] = TileType.tree;
      _mapGrid[mapHeight - 1][x] = TileType.tree;
    }
    for (int y = 0; y < mapHeight; y++) {
      _mapGrid[y][0] = TileType.tree;
      _mapGrid[y][mapWidth - 1] = TileType.tree;
    }

    _playerX = 2;
    _playerY = 2 + (_random.nextInt(2) * 2);

    _treasureX = 14 + (_random.nextInt(2) * 2);
    _treasureY = 14 + (_random.nextInt(2) * 2);

    final pathNodes = _generate2StepPath(
      Point(_playerX, _playerY),
      Point(_treasureX, _treasureY),
    );

    final Set<Point<int>> solutionTiles = {};
    for (int i = 0; i < pathNodes.length; i++) {
      final node = pathNodes[i];
      solutionTiles.add(node);
      _mapGrid[node.y][node.x] = TileType.path;

      if (i < pathNodes.length - 1) {
        final next = pathNodes[i + 1];
        final mid = Point((node.x + next.x) ~/ 2, (node.y + next.y) ~/ 2);
        solutionTiles.add(mid);
        _mapGrid[mid.y][mid.x] = TileType.path;
      }
    }

    _mapGrid[_treasureY][_treasureX] = TileType.treasure;

    final List<Map<String, dynamic>> landmarkDefs = [
      {'name': 'Mystic Obelisk', 'code': 'O', 'color': Colors.cyanAccent, 'icon': Icons.details, 'type': TileType.landmarkObelisk},
      {'name': 'Watchtower Ruin', 'code': 'W', 'color': Colors.amber, 'icon': Icons.fort, 'type': TileType.landmarkWatchtower},
      {'name': 'Ancient Grove', 'code': 'G', 'color': Colors.lightGreenAccent, 'icon': Icons.park, 'type': TileType.landmarkGrove},
      {'name': 'Stone Crag Peak', 'code': 'P', 'color': Colors.orangeAccent, 'icon': Icons.landscape, 'type': TileType.landmarkCrag},
    ]..shuffle(_random);

    _landmarks = [];
    for (final ldef in landmarkDefs) {
      Point<int>? lmPos;
      for (int attempt = 0; attempt < 50; attempt++) {
        int lx = 2 + _random.nextInt(mapWidth - 4);
        int ly = 2 + _random.nextInt(mapHeight - 4);
        Point<int> candidate = Point(lx, ly);

        if (!solutionTiles.contains(candidate) &&
            candidate != Point(_playerX, _playerY) &&
            candidate != Point(_treasureX, _treasureY) &&
            !_landmarks.any((lm) => lm.x == lx && lm.y == ly)) {
          lmPos = candidate;
          break;
        }
      }

      if (lmPos != null) {
        _mapGrid[lmPos.y][lmPos.x] = ldef['type'] as TileType;
        _landmarks.add(LandmarkInfo(
          ldef['name'] as String,
          ldef['code'] as String,
          ldef['color'] as Color,
          ldef['icon'] as IconData,
          lmPos.x,
          lmPos.y,
        ));
      }
    }

    int riverX = 8 + _random.nextInt(4);
    for (int y = 2; y < mapHeight - 2; y++) {
      Point<int> rPoint = Point(riverX, y);
      if (!solutionTiles.contains(rPoint)) {
        _mapGrid[y][riverX] = TileType.water;
      }
    }

    for (int i = 0; i < 35; i++) {
      int rx = 1 + _random.nextInt(mapWidth - 2);
      int ry = 1 + _random.nextInt(mapHeight - 2);
      Point<int> treeCandidate = Point(rx, ry);

      if (!solutionTiles.contains(treeCandidate) && _mapGrid[ry][rx] == TileType.grass) {
        _mapGrid[ry][rx] = TileType.tree;
      }
    }
  }

  List<Point<int>> _generate2StepPath(Point<int> start, Point<int> end) {
    Map<Point<int>, Point<int>?> parent = {};
    Set<Point<int>> visited = {start};

    bool dfs(Point<int> current) {
      if (current == end) return true;

      List<Point<int>> dirs = [
        const Point(2, 0),
        const Point(-2, 0),
        const Point(0, 2),
        const Point(0, -2),
      ]..shuffle(_random);

      for (final d in dirs) {
        final next = Point(current.x + d.x, current.y + d.y);
        if (next.x >= 2 && next.x <= mapWidth - 3 && next.y >= 2 && next.y <= mapHeight - 3) {
          if (!visited.contains(next)) {
            visited.add(next);
            parent[next] = current;
            if (dfs(next)) return true;
          }
        }
      }
      return false;
    }

    dfs(start);

    List<Point<int>> path = [];
    Point<int>? curr = end;
    while (curr != null) {
      path.add(curr);
      curr = parent[curr];
    }
    return path.reversed.toList();
  }

  void _startGame() {
    trainingStarted = true;
    input.allowed = _laneCells;
    input.clear();
    _touchDownLanes.clear();
    _lanePressStart.clear();
    _generateMap();

    setState(() {
      _stats.reset();
      _totalMoves = 0;
      _blockedAttempts = 0;
      _judgment = '';
      _t = 0;
      _phase = _HuntPhase.playing;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });

    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
  }

  void _flash(String text, Color c) {
    _judgment = text;
    _judgmentColor = c;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_phase != _HuntPhase.playing) return KeyEventResult.ignored;

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

    if (event is KeyDownEvent) {
      if (!_touchDownLanes.contains(laneIndex)) {
        setState(() => _touchDownLanes.add(laneIndex!));
        _onDown(laneIndex);
      }
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      if (_touchDownLanes.contains(laneIndex)) {
        setState(() => _touchDownLanes.remove(laneIndex!));
        _onUp(laneIndex);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onTick(Duration e) {
    _t = e.inMicroseconds / 1e6;
    if (_phase != _HuntPhase.playing) return;
    setState(() {});
  }

  void _onDown(int lane) {
    if (_phase != _HuntPhase.playing) return;
    _lanePressStart[lane] = _t;
  }

  void _onUp(int lane) {
    if (_phase != _HuntPhase.playing) return;
    final start = _lanePressStart.remove(lane);
    if (start == null) return;

    final held = _t - start;
    final result = classifyNoteHold(held, _targetHoldSec);
    _stats.add(result);

    int steps = 0;
    if (result == PressResult.half) {
      steps = 1;
    } else if (result == PressResult.full) {
      steps = 2;
    }

    if (steps > 0) {
      _attemptMove(lane, steps, result);
    } else {
      _flash('RELEASED EARLY', Colors.orangeAccent);
    }
  }

  void _attemptMove(int lane, int requestedSteps, PressResult result) {
    final (dx, dy) = switch (lane) {
      0 => (-1, 0),
      1 => (0, 1),
      2 => (0, -1),
      3 => (1, 0),
      _ => (0, 0),
    };

    int moved = 0;
    int targetX = _playerX;
    int targetY = _playerY;

    for (int i = 0; i < requestedSteps; i++) {
      int nextX = targetX + dx;
      int nextY = targetY + dy;

      if (_isWalkable(nextX, nextY)) {
        targetX = nextX;
        targetY = nextY;
        moved++;
      } else {
        break;
      }
    }

    setState(() {
      _playerX = targetX;
      _playerY = targetY;
      _totalMoves++;

      if (moved > 0) {
        String typeLabel = result == PressResult.full ? 'FULL DASH (2 TILES)' : 'HALF STEP (1 TILE)';
        _flash('MOVED $moved TILE(S) • $typeLabel', Colors.greenAccent);
      } else {
        _blockedAttempts++;
        _flash('BLOCKED BY OBSTACLE!', Colors.redAccent);
      }
    });

    if (_playerX == _treasureX && _playerY == _treasureY) {
      _finish();
    }
  }

  bool _isWalkable(int x, int y) {
    if (x < 0 || x >= mapWidth || y < 0 || y >= mapHeight) return false;
    final tile = _mapGrid[y][x];
    return tile == TileType.grass || tile == TileType.path || tile == TileType.treasure;
  }

  void _finish({bool early = false}) {
    _ticker.stop();
    input.clear();
    _touchDownLanes.clear();
    _phase = _HuntPhase.done;

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Treasure Hunt',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: _t.round(),
      correctAttempts: _totalMoves - _blockedAttempts,
      incorrectAttempts: _blockedAttempts,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Time ${_t.toStringAsFixed(1)} s | Moves $_totalMoves | '
          'Blocked $_blockedAttempts | Outer Minimap Dashboard Layout',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('2.5D Tilemap Treasure Hunt')),
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: PushKeyboard(
            controller: input,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: switch (_phase) {
                  _HuntPhase.setup => _setup(),
                  _HuntPhase.playing => _play(),
                  _HuntPhase.done => _summary(),
                },
              ),
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
        const Icon(Icons.castle_rounded, size: 72, color: kTeal),
        const SizedBox(height: 8),
        const Text('2.5D Treasure Hunt',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          'Every game session generates a unique randomized map.\n'
          'Use full presses (2-tile dashes) to reach the golden treasure chest!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF14143A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            children: [
              Text('Hold Controls', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('Half Hold (45%-90%) = Move 1 Tile', style: TextStyle(color: kHalfColor)),
              Text('Full Hold (90%+) = Dash 2 Tiles (Solution Path)', style: TextStyle(color: kFullColor)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        chipRow<Difficulty>(
          title: 'Difficulty',
          values: Difficulty.values,
          selected: _difficulty,
          label: (d) => d.label,
          onSelected: (d) => setState(() => _difficulty = d),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _startGame,
          style: FilledButton.styleFrom(
              backgroundColor: kTeal, minimumSize: const Size.fromHeight(56)),
          child: const Text('Start New Random Map',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _play() {
    return Container(
      color: const Color(0xFF090D16),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF101625),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 125,
                  height: 125,
                  decoration: BoxDecoration(
                    color: const Color(0xEE090D16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber, width: 2.0),
                    boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 8)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: _MinimapPainter(
                        mapGrid: _mapGrid,
                        playerX: _playerX,
                        playerY: _playerY,
                        treasureX: _treasureX,
                        treasureY: _treasureY,
                        landmarks: _landmarks,
                        t: _t,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Time: ${_t.toStringAsFixed(1)} s',
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          Text('Moves: $_totalMoves',
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 22,
                        child: Text(
                          _judgment,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _judgmentColor),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('LANDMARKS MAP KEY',
                                style: TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 8,
                              runSpacing: 2,
                              children: _landmarks.map((lm) => Text(
                                '${lm.code}: ${lm.name}',
                                style: const TextStyle(color: Colors.white70, fontSize: 9),
                              )).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CustomPaint(
                size: Size.infinite,
                painter: _TileMap2D5Painter(
                  mapGrid: _mapGrid,
                  playerX: _playerX,
                  playerY: _playerY,
                  treasureX: _treasureX,
                  treasureY: _treasureY,
                  t: _t,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildFourButtonRow(),
          const SizedBox(height: 8),
          pressStatsBar(_stats, dark: true),
          TextButton(
            onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End Session', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildFourButtonRow() {
    return AnimatedBuilder(
      animation: input,
      builder: (context, _) {
        return Row(
          children: List.generate(4, (index) {
            final cell = _laneCells[index];
            final isPressed = input.isDown(cell) || _touchDownLanes.contains(index);
            final color = _dirColors[index];

            double fillRatio = 0.0;
            String labelText = _dirLabels[index];
            Color labelColor = Colors.white;
            Color borderColor = color;
            double borderWidth = 3.0;
            Color fillColor = color.withValues(alpha: 0.45);

            if (_lanePressStart.containsKey(index)) {
              final held = _t - _lanePressStart[index]!;
              fillRatio = (held / _targetHoldSec).clamp(0.0, 1.0);
              final pct = (fillRatio * 100).round();
              final result = classifyNoteHold(held, _targetHoldSec);

              labelText = '${_dirKeyNames[index]} ($pct%)';
              if (result == PressResult.full) {
                labelColor = kFullColor;
                borderColor = kFullColor;
                borderWidth = 5.0;
                fillColor = kFullColor.withValues(alpha: 0.4);
              } else if (result == PressResult.half) {
                labelColor = kHalfColor;
                borderColor = kHalfColor;
                borderWidth = 4.0;
                fillColor = kHalfColor.withValues(alpha: 0.4);
              }
            } else if (isPressed) {
              fillRatio = 1.0;
            }

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: Listener(
                  onPointerDown: (_) {
                    setState(() => _touchDownLanes.add(index));
                    _onDown(cell);
                  },
                  onPointerUp: (_) {
                    setState(() => _touchDownLanes.remove(index));
                    _onUp(cell);
                  },
                  onPointerCancel: (_) {
                    setState(() => _touchDownLanes.remove(index));
                    _onUp(cell);
                  },
                  child: Container(
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFF14143A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor, width: borderWidth),
                      boxShadow: isPressed || _lanePressStart.containsKey(index)
                          ? [
                              BoxShadow(
                                color: borderColor.withValues(alpha: 0.65),
                                blurRadius: 12,
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
                                child: Container(color: fillColor),
                              ),
                            ),
                          Center(
                            child: Text(
                              labelText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: labelColor,
                                fontSize: 16,
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
        const Icon(Icons.stars_rounded, size: 72, color: Colors.amber),
        const SizedBox(height: 8),
        const Text('Treasure Chest Opened!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              _row('Time Taken', '${_t.toStringAsFixed(1)} s'),
              const Divider(height: 16),
              _row('Total Moves', '$_totalMoves'),
              const Divider(height: 16),
              _row('Blocked Attempts', '$_blockedAttempts'),
              const Divider(height: 16),
              _row('Full Dashes (2 Tiles)', '${_stats.full}'),
              const Divider(height: 16),
              _row('Half Steps (1 Tile)', '${_stats.half}'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _startGame,
          icon: const Icon(Icons.replay),
          label: const Text('Play Again (New Map)', style: TextStyle(fontSize: 16)),
          style: FilledButton.styleFrom(
              backgroundColor: kTeal, padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 15, color: Colors.black54)),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _TileMap2D5Painter extends CustomPainter {
  final List<List<TileType>> mapGrid;
  final int playerX;
  final int playerY;
  final int treasureX;
  final int treasureY;
  final double t;

  _TileMap2D5Painter({
    required this.mapGrid,
    required this.playerX,
    required this.playerY,
    required this.treasureX,
    required this.treasureY,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rows = mapGrid.length;
    final cols = mapGrid[0].length;

    final tileW = size.width / cols;
    final tileH = (size.height - 35) / rows;

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        final tile = mapGrid[y][x];

        double h = 5.0;
        Color topColor = const Color(0xFF388E3C);
        Color frontColor = const Color(0xFF2E7D32);
        Color sideColor = const Color(0xFF1B5E20);

        switch (tile) {
          case TileType.water:
            h = 0.0;
            topColor = const Color(0xFF1E88E5);
            frontColor = const Color(0xFF1565C0);
            sideColor = const Color(0xFF0D47A1);
            break;
          case TileType.path:
            h = 3.0;
            topColor = const Color(0xFFD7CCC8);
            frontColor = const Color(0xFFA1887F);
            sideColor = const Color(0xFF8D6E63);
            break;
          case TileType.grass:
            h = 6.0;
            topColor = const Color(0xFF4CAF50);
            frontColor = const Color(0xFF388E3C);
            sideColor = const Color(0xFF2E7D32);
            break;
          case TileType.tree:
            h = 18.0;
            topColor = const Color(0xFF2E7D32);
            frontColor = const Color(0xFF1B5E20);
            sideColor = const Color(0xFF0F3813);
            break;
          case TileType.landmarkObelisk:
            h = 28.0;
            topColor = const Color(0xFF00E5FF);
            frontColor = const Color(0xFF00B0FF);
            sideColor = const Color(0xFF00838F);
            break;
          case TileType.landmarkWatchtower:
            h = 32.0;
            topColor = const Color(0xFFFFC107);
            frontColor = const Color(0xFFFFA000);
            sideColor = const Color(0xFFFF8F00);
            break;
          case TileType.landmarkGrove:
            h = 22.0;
            topColor = const Color(0xFF76FF03);
            frontColor = const Color(0xFF64DD17);
            sideColor = const Color(0xFF33691E);
            break;
          case TileType.landmarkCrag:
            h = 26.0;
            topColor = const Color(0xFFFF6D00);
            frontColor = const Color(0xFFE65100);
            sideColor = const Color(0xFFBF360C);
            break;
          case TileType.treasure:
            h = 10.0;
            topColor = const Color(0xFF4E342E);
            frontColor = const Color(0xFF3E2723);
            sideColor = const Color(0xFF271C19);
            break;
        }

        final baseLeft = x * tileW;
        final baseTop = y * tileH + 35.0;

        final baseRect = Rect.fromLTWH(baseLeft, baseTop, tileW, tileH);
        final topRect = Rect.fromLTWH(baseLeft, baseTop - h, tileW, tileH);

        if (h > 10.0) {
          final shadowPath = Path()
            ..moveTo(baseRect.left + 4, baseRect.bottom)
            ..lineTo(baseRect.right + 6, baseRect.bottom + 4)
            ..lineTo(baseRect.right + 2, baseRect.bottom + 8)
            ..lineTo(baseRect.left - 2, baseRect.bottom + 4)
            ..close();
          canvas.drawPath(shadowPath, Paint()..color = Colors.black.withValues(alpha: 0.28));
        }

        if (h > 0) {
          final frontPath = Path()
            ..moveTo(topRect.left, topRect.bottom)
            ..lineTo(topRect.right, topRect.bottom)
            ..lineTo(baseRect.right, baseRect.bottom)
            ..lineTo(baseRect.left, baseRect.bottom)
            ..close();
          canvas.drawPath(frontPath, Paint()..color = frontColor);

          final sidePath = Path()
            ..moveTo(topRect.right, topRect.top)
            ..lineTo(topRect.right, topRect.bottom)
            ..lineTo(baseRect.right, baseRect.bottom)
            ..lineTo(baseRect.right, baseRect.top)
            ..close();
          canvas.drawPath(sidePath, Paint()..color = sideColor);
        }

        canvas.drawRect(topRect, Paint()..color = topColor);
        canvas.drawRect(
          topRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5
            ..color = Colors.white24,
        );

        if (tile == TileType.landmarkObelisk) {
          canvas.drawCircle(topRect.center, tileW * 0.25, Paint()..color = Colors.white);
        } else if (tile == TileType.treasure) {
          _drawAnimatedTreasureChest(canvas, topRect, tileW, t);
        }
      }

      if (y == playerY) {
        final pBaseLeft = playerX * tileW;
        final pBaseTop = playerY * tileH + 35.0;

        final bounce = sin(t * 8) * 3.0;
        final floatHeight = 16.0 + bounce;

        final shadowCenter = Offset(pBaseLeft + tileW / 2, pBaseTop + tileH / 2);
        canvas.drawOval(
          Rect.fromCenter(center: shadowCenter, width: tileW * 0.7, height: tileH * 0.4),
          Paint()..color = Colors.black45,
        );

        final playerCenter = Offset(pBaseLeft + tileW / 2, pBaseTop + tileH / 2 - floatHeight);

        canvas.drawCircle(playerCenter, tileW * 0.4, Paint()..color = Colors.yellowAccent);
        canvas.drawCircle(
          playerCenter,
          tileW * 0.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = Colors.deepOrangeAccent,
        );
        canvas.drawCircle(playerCenter, tileW * 0.15, Paint()..color = Colors.redAccent);
      }
    }
  }

  void _drawAnimatedTreasureChest(Canvas canvas, Rect tileRect, double tileW, double time) {
    final c = tileRect.center;
    final chestW = tileW * 0.85;
    final chestH = tileW * 0.65;

    final glowPulse = (sin(time * 5) * 0.2 + 0.8);
    canvas.drawCircle(
      c,
      tileW * 0.6 * glowPulse,
      Paint()
        ..color = Colors.amberAccent.withValues(alpha: 0.35 * glowPulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    for (int i = 0; i < 3; i++) {
      final pTime = (time * 2.5 + i * 1.2) % 2.0;
      final sparkleY = c.dy - (pTime * 12);
      final sparkleX = c.dx + sin(time * 4 + i) * 6;
      final sparkleAlpha = (1.0 - (pTime / 2.0)).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(sparkleX, sparkleY),
        1.8,
        Paint()..color = Colors.yellowAccent.withValues(alpha: sparkleAlpha),
      );
    }

    final chestRect = Rect.fromCenter(center: c, width: chestW, height: chestH);

    final baseRect = Rect.fromLTWH(
      chestRect.left,
      chestRect.top + chestH * 0.35,
      chestW,
      chestH * 0.65,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(baseRect, const Radius.circular(3)),
      Paint()..color = const Color(0xFF6D4C41),
    );

    final bandPaint = Paint()..color = const Color(0xFFFFD700);
    canvas.drawRect(Rect.fromLTWH(baseRect.left + 3, baseRect.top, 3, baseRect.height), bandPaint);
    canvas.drawRect(Rect.fromLTWH(baseRect.right - 6, baseRect.top, 3, baseRect.height), bandPaint);

    final lockCenter = Offset(c.dx, baseRect.top + 4);
    canvas.drawCircle(lockCenter, 3.5, bandPaint);
    canvas.drawCircle(lockCenter, 1.5, Paint()..color = Colors.black87);

    final lidOpenOffset = (sin(time * 3).abs() * 5.0);
    final lidRect = Rect.fromLTWH(
      chestRect.left,
      chestRect.top - lidOpenOffset,
      chestW,
      chestH * 0.45,
    );

    if (lidOpenOffset > 1.0) {
      final innerGlowPath = Path()
        ..moveTo(chestRect.left + 2, baseRect.top)
        ..lineTo(chestRect.right - 2, baseRect.top)
        ..lineTo(lidRect.right, lidRect.bottom)
        ..lineTo(lidRect.left, lidRect.bottom)
        ..close();
      canvas.drawPath(
        innerGlowPath,
        Paint()..color = Colors.amber.withValues(alpha: 0.8),
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(lidRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF8D6E63),
    );
    canvas.drawRect(
      Rect.fromLTWH(lidRect.left + 3, lidRect.top, 3, lidRect.height),
      bandPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(lidRect.right - 6, lidRect.top, 3, lidRect.height),
      bandPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TileMap2D5Painter old) => true;
}

class _MinimapPainter extends CustomPainter {
  final List<List<TileType>> mapGrid;
  final int playerX;
  final int playerY;
  final int treasureX;
  final int treasureY;
  final List<LandmarkInfo> landmarks;
  final double t;

  _MinimapPainter({
    required this.mapGrid,
    required this.playerX,
    required this.playerY,
    required this.treasureX,
    required this.treasureY,
    required this.landmarks,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rows = mapGrid.length;
    final cols = mapGrid[0].length;
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        Color c = switch (mapGrid[y][x]) {
          TileType.water => const Color(0xFF1E88E5),
          TileType.path => const Color(0xFF8D6E63),
          TileType.tree => const Color(0xFF1B5E20),
          _ => const Color(0xFF1B3B1A),
        };
        canvas.drawRect(
          Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH),
          Paint()..color = c,
        );
      }
    }

    for (final lm in landmarks) {
      final lmPos = Offset((lm.x + 0.5) * cellW, (lm.y + 0.5) * cellH);
      canvas.drawCircle(lmPos, cellW * 1.6, Paint()..color = lm.color);
      canvas.drawCircle(
        lmPos,
        cellW * 1.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.black87,
      );
    }

    final chestCenter = Offset((treasureX + 0.5) * cellW, (treasureY + 0.5) * cellH);
    _drawMinimapChestIcon(canvas, chestCenter, cellW, t);

    final pPos = Offset((playerX + 0.5) * cellW, (playerY + 0.5) * cellH);
    canvas.drawCircle(pPos, cellW * 1.4, Paint()..color = Colors.cyanAccent);
    canvas.drawCircle(pPos, cellW * 2.5 * (1.0 + (t % 1)), Paint()..color = Colors.cyanAccent.withValues(alpha: 0.3));

    _drawCompassOverlay(canvas, size);
  }

  void _drawMinimapChestIcon(Canvas canvas, Offset center, double cellW, double time) {
    final pulse = (sin(time * 6) * 0.2 + 1.0);
    canvas.drawCircle(
      center,
      cellW * 1.8 * pulse,
      Paint()..color = Colors.amber.withValues(alpha: 0.4),
    );

    final rect = Rect.fromCenter(center: center, width: cellW * 2.2, height: cellW * 1.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = const Color(0xFFFFD700),
    );
    canvas.drawRect(
      Rect.fromCenter(center: center, width: cellW * 0.8, height: cellW * 0.8),
      Paint()..color = const Color(0xFF5D4037),
    );
  }

  void _drawCompassOverlay(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx, 14), Offset(center.dx, size.height - 14), linePaint);
    canvas.drawLine(Offset(14, center.dy), Offset(size.width - 14, center.dy), linePaint);

    void drawText(String label, Offset offset, Color color) {
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        offset - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }

    drawText('N', Offset(size.width / 2, 8), Colors.redAccent);
    drawText('S', Offset(size.width / 2, size.height - 8), Colors.white);
    drawText('W', Offset(8, size.height / 2), Colors.white);
    drawText('E', Offset(size.width - 8, size.height / 2), Colors.white);
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter old) => true;
}