import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';
import 'hall_sensor_service.dart';

// =============================================================================
// 1. RANDOM FOREST INFERENCE ENGINE
// =============================================================================

class TreeNode {
  final int? featureIndex;
  final double? threshold;
  final TreeNode? left;
  final TreeNode? right;
  final double? leafValue;

  TreeNode({
    this.featureIndex,
    this.threshold,
    this.left,
    this.right,
    this.leafValue,
  });

  bool get isLeaf => leafValue != null;

  factory TreeNode.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('value')) {
      return TreeNode(leafValue: (json['value'] as num).toDouble());
    }
    return TreeNode(
      featureIndex: json['feature'] as int,
      threshold: (json['threshold'] as num).toDouble(),
      left: TreeNode.fromJson(json['left'] as Map<String, dynamic>),
      right: TreeNode.fromJson(json['right'] as Map<String, dynamic>),
    );
  }

  double predict(List<double> features) {
    if (isLeaf) return leafValue!;
    if (features[featureIndex!] <= threshold!) {
      return left!.predict(features);
    } else {
      return right!.predict(features);
    }
  }
}

class RandomForestModel {
  final List<TreeNode> trees;

  RandomForestModel(this.trees);

  factory RandomForestModel.fromJsonString(String jsonStr) {
    final Map<String, dynamic> parsed = jsonDecode(jsonStr);
    final List<dynamic> treeList = parsed['trees'];
    return RandomForestModel(
      treeList
          .map((t) => TreeNode.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  double predict(List<double> features) {
    if (trees.isEmpty) return 1.0;
    final double total =
        trees.fold(0.0, (sum, tree) => sum + tree.predict(features));
    return total / trees.length;
  }
}

/// Offline-trained Random Forest model JSON
const String _defaultRfModelJson = '''
{
  "trees": [
    {
      "feature": 0,
      "threshold": 0.6,
      "left": {
        "feature": 1,
        "threshold": 2.0,
        "left": {"value": 0.60},
        "right": {"value": 0.75}
      },
      "right": {
        "feature": 1,
        "threshold": 1.2,
        "left": {"value": 1.40},
        "right": {"value": 1.20}
      }
    },
    {
      "feature": 2,
      "threshold": 15.0,
      "left": {"value": 1.30},
      "right": {"value": 0.65}
    }
  ]
}
''';

// =============================================================================
// 2. ENUMS & DATA STRUCTURES
// =============================================================================

enum _HuntPhase { setup, playing, done }

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

// =============================================================================
// 3. TREASURE HUNT INTERIM SCREEN WITH INTER-SESSION DDA
// =============================================================================

class TreasureHuntInterimScreen extends StatefulWidget {
  const TreasureHuntInterimScreen({super.key});

  @override
  State<TreasureHuntInterimScreen> createState() =>
      _TreasureHuntInterimScreenState();
}

class _TreasureHuntInterimScreenState extends State<TreasureHuntInterimScreen>
    with SingleTickerProviderStateMixin {
  static const int mapWidth = 20;
  static const int mapHeight = 20;

  late final Ticker _ticker;
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  final PressStats _stats = PressStats();

  _HuntPhase _phase = _HuntPhase.setup;
  Difficulty _difficulty = Difficulty.easy;
  double _t = 0;

  int _playerX = 2;
  int _playerY = 2;
  int _treasureX = 16;
  int _treasureY = 16;

  final List<Point<int>> _route = [];
  int _routeIndex = 0;
  Timer? _sensorTimer;
  bool _polling = false;
  bool? _lastSensorState;
  bool _sensorConnected = false;
  bool _useSensor = true;
  bool _virtualPressed = false;
  late List<List<TileType>> _mapGrid;
  List<LandmarkInfo> _landmarks = [];

  int _totalMoves = 0;
  int _blockedAttempts = 0;
  String _judgment = '';
  Color _judgmentColor = Colors.white;

  // Adaptive Difficulty State
  late final RandomForestModel _ddaModel;
  double _difficultyMultiplier = 1.0; // 0.5 (Easy Map) -> 1.5 (Hard Map)
  static const int _stepDistance = 2;

  @override
  void initState() {
    super.initState();
    _ddaModel = RandomForestModel.fromJsonString(_defaultRfModelJson);
    _ticker = createTicker(_onTick);
    _generateMap();
    _sensorTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _pollSensor(),
    );
    _pollSensor();
  }

  @override
  void dispose() {
    _sensorTimer?.cancel();
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Feature Telemetry & Inter-Session DDA Evaluation
  // ---------------------------------------------------------------------
  List<double> _extractTelemetryFeatures() {
    final moves = max(_totalMoves, 1);
    final elapsed = max(_t, 0.1);

    final moveRate = moves / elapsed;
    final avgTimePerMove = elapsed / moves;
    final totalDuration = elapsed;

    return [moveRate, avgTimePerMove, totalDuration];
  }

  void _evaluateNextSessionDifficulty() {
    final features = _extractTelemetryFeatures();
    final rawTarget = _ddaModel.predict(features);

    const double alpha = 0.5;
    _difficultyMultiplier =
        (alpha * rawTarget) + ((1.0 - alpha) * _difficultyMultiplier);
    _difficultyMultiplier = _difficultyMultiplier.clamp(0.5, 1.5);
  }

  String get _mapDifficultyLabel {
    if (_difficultyMultiplier >= 1.12) {
      return 'Hard (Long Route & Dense Forest)';
    } else if (_difficultyMultiplier <= 0.88) {
      return 'Easy (Short Route & Open Fields)';
    } else {
      return 'Medium (Standard Map)';
    }
  }

  Future<void> _pollSensor() async {
    if (_polling || !_useSensor) return;
    _polling = true;
    try {
      final data = await HallSensorService.getHallData();
      final online = data['connected'] == true;
      final state = data['hall1'];
      if (!mounted) return;
      if (!online || state is! bool) {
        if (_sensorConnected) setState(() => _sensorConnected = false);
        _lastSensorState = null;
        return;
      }
      if (!_sensorConnected) setState(() => _sensorConnected = true);
      final freshPress = _lastSensorState == false && state == true;
      _lastSensorState = state;
      if (freshPress && _phase == _HuntPhase.playing) _fullPush();
    } catch (_) {
      if (mounted && _sensorConnected) {
        setState(() => _sensorConnected = false);
      }
      _lastSensorState = null;
    } finally {
      _polling = false;
    }
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

    int treeCount = 35;
    bool createRiver = true;

    if (_difficultyMultiplier >= 1.12) {
      _playerX = 2;
      _playerY = 2;
      _treasureX = 18;
      _treasureY = 18;
      treeCount = 60;
    } else if (_difficultyMultiplier <= 0.88) {
      _playerX = 4;
      _playerY = 4;
      _treasureX = 10;
      _treasureY = 10;
      treeCount = 15;
      createRiver = false;
    } else {
      _playerX = 2;
      _playerY = 2 + (_random.nextInt(2) * 2);
      _treasureX = 14 + (_random.nextInt(2) * 2);
      _treasureY = 14 + (_random.nextInt(2) * 2);
      treeCount = 35;
    }

    final pathNodes = _generate2StepPath(
      Point(_playerX, _playerY),
      Point(_treasureX, _treasureY),
    );

    _route.clear();
    for (int i = 0; i < pathNodes.length; i++) {
      if (i > 0) {
        final previous = pathNodes[i - 1];
        final current = pathNodes[i];
        _route.add(Point(
          (previous.x + current.x) ~/ 2,
          (previous.y + current.y) ~/ 2,
        ));
      }
      _route.add(pathNodes[i]);
    }
    _routeIndex = 0;

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

    if (createRiver) {
      int riverX = 8 + _random.nextInt(4);
      for (int y = 2; y < mapHeight - 2; y++) {
        Point<int> rPoint = Point(riverX, y);
        if (!solutionTiles.contains(rPoint)) {
          _mapGrid[y][riverX] = TileType.water;
        }
      }
    }

    for (int i = 0; i < treeCount; i++) {
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
        if (next.x >= 2 && next.x <= mapWidth - 2 && next.y >= 2 && next.y <= mapHeight - 2) {
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
    _virtualPressed = false;
    _lastSensorState = null;
    _generateMap();
    setState(() {
      _stats.reset();
      _totalMoves = 0;
      _blockedAttempts = 0;
      _judgment = '';
      _t = 0;
      _phase = _HuntPhase.playing;
    });
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
  }

  void _flash(String message, Color color) {
    _judgment = message;
    _judgmentColor = color;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space ||
        _phase != _HuntPhase.playing) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent && !_virtualPressed) {
      setState(() => _virtualPressed = true);
      _fullPush();
    } else if (event is KeyUpEvent) {
      setState(() => _virtualPressed = false);
    }
    return KeyEventResult.handled;
  }

  void _onTick(Duration elapsed) {
    _t = elapsed.inMicroseconds / 1e6;
    if (_phase == _HuntPhase.playing) setState(() {});
  }

  void _fullPush() {
    if (!mounted || _phase != _HuntPhase.playing) return;

    final nextIndex = min(_routeIndex + _stepDistance, _route.length - 1);
    if (nextIndex <= _routeIndex) return;

    final next = _route[nextIndex];
    final distance = nextIndex - _routeIndex;

    setState(() {
      _routeIndex = nextIndex;
      _playerX = next.x;
      _playerY = next.y;
      _stats.add(PressResult.full);
      _totalMoves++;
      _flash('MOVED $distance TILES FORWARD', Colors.greenAccent);
    });

    if (_playerX == _treasureX && _playerY == _treasureY) {
      _finish();
    }
  }

  void _finish({bool early = false}) {
    _ticker.stop();
    
    if (!early) {
      _evaluateNextSessionDifficulty();
    }
    
    _phase = _HuntPhase.done;

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Treasure Hunt Interim',
      date: DateTime.now(),
      difficulty: '${_difficulty.label} (${_difficultyMultiplier.toStringAsFixed(2)}x Dynamic Map)',
      durationSeconds: _t.round(),
      correctAttempts: _totalMoves - _blockedAttempts,
      incorrectAttempts: _blockedAttempts,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Time ${_t.toStringAsFixed(1)} s | Moves $_totalMoves | '
          'Next Session DDA Multiplier ${_difficultyMultiplier.toStringAsFixed(2)}x | '
          'Simulated/ESP32 Hall 1 input',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Treasure Hunt • Interim'),
      ),
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
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
    );
  }

  Widget _setup() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.castle_rounded, size: 72, color: kTeal),
        const SizedBox(height: 8),
        const Text('Treasure Hunt • One Tile',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text(
          'Dynamic difficulty adjusts map size, path length, and obstacle density between sessions based on your play speed!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Active Map Tier:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kTeal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kTeal),
                      ),
                      child: Text(
                        'DDA: ${_difficultyMultiplier.toStringAsFixed(2)}x',
                        style: const TextStyle(
                            color: kTeal, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _mapDifficultyLabel,
                    style: const TextStyle(
                        color: kTeal, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                const Divider(height: 20),
                const Text('One-button interim mode',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Press the single button or Space to move along the route. '
                    'Hall Sensor 1 rising edge does the same.'),
                SwitchListTile(
                  title: const Text('Listen to simulated Raspberry Pi'),
                  subtitle: const Text('http://127.0.0.1:5000/api/hall'),
                  value: _useSensor,
                  onChanged: (value) => setState(() {
                    _useSensor = value;
                    _lastSensorState = null;
                    _sensorConnected = false;
                  }),
                ),
              ],
            ),
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
                          Text('Time: ${_t.toStringAsFixed(1)}s',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          Text('DDA: ${_difficultyMultiplier.toStringAsFixed(2)}x',
                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                          Text('Moves: $_totalMoves',
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
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
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CALCULATED DDA: ${_difficultyMultiplier.toStringAsFixed(2)}x • ${_mapDifficultyLabel.toUpperCase()}',
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
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
          _buildOneButton(),
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

  Widget _buildOneButton() {
    return Column(
      children: [
        Text(
          _useSensor
              ? (_sensorConnected ? 'Hall Sensor 1: CONNECTED' : 'Hall Sensor 1: OFFLINE — virtual button works')
              : 'Virtual button mode',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Listener(
          onPointerDown: (_) {
            if (_virtualPressed || _phase != _HuntPhase.playing) return;
            setState(() => _virtualPressed = true);
            _fullPush();
          },
          onPointerUp: (_) => setState(() => _virtualPressed = false),
          onPointerCancel: (_) => setState(() => _virtualPressed = false),
          child: Container(
            width: double.infinity,
            height: 82,
            decoration: BoxDecoration(
              color: _virtualPressed ? kFullColor : const Color(0xFF14143A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kFullColor, width: 3),
            ),
            child: Center(
              child: Text(
                _virtualPressed ? 'FULL PUSH DETECTED' : 'PUSH TO MOVE FORWARD  →',
                style: const TextStyle(color: Colors.white,
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
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
              _row('Full Pushes', '${_stats.full}'),
              const Divider(height: 16),
              _row('Calculated DDA Multiplier', '${_difficultyMultiplier.toStringAsFixed(2)}x'),
              const Divider(height: 16),
              _row('Next Session Map Difficulty', _mapDifficultyLabel),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _startGame,
          icon: const Icon(Icons.replay),
          label: const Text('Play Next Map', style: TextStyle(fontSize: 16)),
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
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 15, color: Colors.black54)),
        ),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// =============================================================================
// 4. CUSTOM PAINTERS
// =============================================================================

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