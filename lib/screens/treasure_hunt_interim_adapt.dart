import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

// ===========================================================================
// MRC Scale Definition for Stroke Muscle Evaluation (Grades 3 to 5)
// ===========================================================================
enum MrcLevel {
  mrc3(3, 'MRC 3', 'Against Gravity',
      'Target hold time: 0.6s | Moderate resistance'),
  mrc4(4, 'MRC 4', 'Against Resistance',
      'Target hold time: 0.8s | Increased muscle resistance'),
  mrc5(5, 'MRC 5', 'Normal Strength',
      'Target hold time: 1.0s | Maximum endurance and muscle force');

  final int level;
  final String label;
  final String description;
  final String details;

  const MrcLevel(
    this.level,
    this.label,
    this.description,
    this.details,
  );
}

// ===========================================================================
// Random Forest Machine Learning Engine for Adaptive Difficulty
// ===========================================================================
class PatientPerformanceFeatures {
  final double completionRate;
  final double fullPressRatio;
  final double halfPressRatio;
  final double noPressRatio;
  final double accuracy;
  final double comboRatio;
  final int currentMrcLevel;

  PatientPerformanceFeatures({
    required this.completionRate,
    required this.fullPressRatio,
    required this.halfPressRatio,
    required this.noPressRatio,
    required this.accuracy,
    required this.comboRatio,
    required this.currentMrcLevel,
  });
}

class DecisionTreeNode {
  final String? feature;
  final double? threshold;
  final DecisionTreeNode? left;
  final DecisionTreeNode? right;
  final int? predictedLevelDelta; // -1 (decrease), 0 (maintain), +1 (increase)

  DecisionTreeNode({
    this.feature,
    this.threshold,
    this.left,
    this.right,
    this.predictedLevelDelta,
  });

  bool get isLeaf => predictedLevelDelta != null;

  int predict(PatientPerformanceFeatures f) {
    if (isLeaf) return predictedLevelDelta!;
    double val = 0.0;
    switch (feature) {
      case 'completionRate':
        val = f.completionRate;
        break;
      case 'fullPressRatio':
        val = f.fullPressRatio;
        break;
      case 'halfPressRatio':
        val = f.halfPressRatio;
        break;
      case 'noPressRatio':
        val = f.noPressRatio;
        break;
      case 'accuracy':
        val = f.accuracy;
        break;
      case 'comboRatio':
        val = f.comboRatio;
        break;
      default:
        val = 0.0;
    }
    if (threshold != null && val >= threshold!) {
      return right?.predict(f) ?? 0;
    } else {
      return left?.predict(f) ?? 0;
    }
  }
}

class RandomForestResult {
  final MrcLevel recommendedMrcLevel;
  final double progressToNextLevel; // 0.0 to 1.0
  final int votesUp;
  final int votesStay;
  final int votesDown;
  final String summaryHeadline;
  final List<String> clinicalReasons;

  RandomForestResult({
    required this.recommendedMrcLevel,
    required this.progressToNextLevel,
    required this.votesUp,
    required this.votesStay,
    required this.votesDown,
    required this.summaryHeadline,
    this.clinicalReasons = const <String>[],
  });
}

class RandomForestClassifier {
  final List<DecisionTreeNode> _trees = [];

  RandomForestClassifier() {
    _buildForest();
  }

  void _buildForest() {
    _trees.add(DecisionTreeNode(
      feature: 'completionRate',
      threshold: 0.80,
      right: DecisionTreeNode(
        feature: 'fullPressRatio',
        threshold: 0.65,
        right: DecisionTreeNode(predictedLevelDelta: 1),
        left: DecisionTreeNode(predictedLevelDelta: 0),
      ),
      left: DecisionTreeNode(
        feature: 'noPressRatio',
        threshold: 0.35,
        right: DecisionTreeNode(predictedLevelDelta: -1),
        left: DecisionTreeNode(predictedLevelDelta: 0),
      ),
    ));

    _trees.add(DecisionTreeNode(
      feature: 'fullPressRatio',
      threshold: 0.70,
      right: DecisionTreeNode(
        feature: 'accuracy',
        threshold: 0.80,
        right: DecisionTreeNode(predictedLevelDelta: 1),
        left: DecisionTreeNode(predictedLevelDelta: 0),
      ),
      left: DecisionTreeNode(
        feature: 'fullPressRatio',
        threshold: 0.30,
        right: DecisionTreeNode(predictedLevelDelta: 0),
        left: DecisionTreeNode(predictedLevelDelta: -1),
      ),
    ));

    _trees.add(DecisionTreeNode(
      feature: 'comboRatio',
      threshold: 0.60,
      right: DecisionTreeNode(
        feature: 'completionRate',
        threshold: 0.75,
        right: DecisionTreeNode(predictedLevelDelta: 1),
        left: DecisionTreeNode(predictedLevelDelta: 0),
      ),
      left: DecisionTreeNode(
        feature: 'completionRate',
        threshold: 0.40,
        right: DecisionTreeNode(predictedLevelDelta: 0),
        left: DecisionTreeNode(predictedLevelDelta: -1),
      ),
    ));

    _trees.add(DecisionTreeNode(
      feature: 'accuracy',
      threshold: 0.85,
      right: DecisionTreeNode(
        feature: 'fullPressRatio',
        threshold: 0.50,
        right: DecisionTreeNode(predictedLevelDelta: 1),
        left: DecisionTreeNode(predictedLevelDelta: 0),
      ),
      left: DecisionTreeNode(
        feature: 'noPressRatio',
        threshold: 0.40,
        right: DecisionTreeNode(predictedLevelDelta: -1),
        left: DecisionTreeNode(predictedLevelDelta: 0),
      ),
    ));

    _trees.add(DecisionTreeNode(
      feature: 'noPressRatio',
      threshold: 0.15,
      left: DecisionTreeNode(
        feature: 'completionRate',
        threshold: 0.85,
        right: DecisionTreeNode(predictedLevelDelta: 1),
        left: DecisionTreeNode(predictedLevelDelta: 0),
      ),
      right: DecisionTreeNode(
        feature: 'noPressRatio',
        threshold: 0.45,
        right: DecisionTreeNode(predictedLevelDelta: -1),
        left: DecisionTreeNode(predictedLevelDelta: 0),
      ),
    ));
  }

  RandomForestResult predict(PatientPerformanceFeatures features) {
    int upVotes = 0;
    int stayVotes = 0;
    int downVotes = 0;

    for (final tree in _trees) {
      final delta = tree.predict(features);
      if (delta > 0) {
        upVotes++;
      } else if (delta == 0) {
        stayVotes++;
      } else {
        downVotes++;
      }
    }

    int delta = 0;
    if (upVotes > stayVotes && upVotes > downVotes) {
      delta = 1;
    } else if (downVotes > stayVotes && downVotes > upVotes) {
      delta = -1;
    }

    int nextLevelInt = (features.currentMrcLevel + delta).clamp(3, 5).toInt();

    MrcLevel recommendedLevel = MrcLevel.values.firstWhere(
      (level) => level.level == nextLevelInt,
      orElse: () => MrcLevel.mrc3,
    );

    double proficiency = (features.completionRate * 0.35) +
        (features.fullPressRatio * 0.40) +
        (features.accuracy * 0.25);

    double voteFraction = upVotes / _trees.length;
    double progressRatio = (proficiency * 0.5 + voteFraction * 0.5).clamp(0.0, 1.0);

    final reasons = <String>[];
    String headline = '';

    final fullPct = (features.fullPressRatio * 100).toStringAsFixed(0);
    final compPct = (features.completionRate * 100).toStringAsFixed(0);
    final missPct = (features.noPressRatio * 100).toStringAsFixed(0);

    if (delta > 0) {
      headline = 'Promoted to Next Strength Tier';
      reasons.add('High sustained muscle force: $fullPct% full press duration met threshold (>65%).');
      reasons.add('Strong movement accuracy: $compPct% of navigation steps completed successfully.');
      reasons.add('$upVotes of 5 Random Forest decision trees voted to increase difficulty.');
    } else if (delta < 0) {
      headline = 'Reduced Target Duration to Support Motor Control';
      if (features.noPressRatio > 0.35) {
        reasons.add('Fatigue or early release: $missPct% incomplete press attempts detected.');
      }
      if (features.fullPressRatio < 0.35) {
        reasons.add('Sustained press strength ($fullPct%) was insufficient for current tier target.');
      }
      reasons.add('$downVotes of 5 Random Forest decision trees voted to lower target duration.');
    } else {
      headline = 'Maintain Current Level for Consolidation';
      reasons.add('Consistent tile movement ($compPct% accuracy), consolidating muscle control.');
      reasons.add('Full press duration ($fullPct%) is progressing towards advancement threshold (>65%).');
      reasons.add('$stayVotes of 5 decision trees recommended consolidating strength.');
    }

    return RandomForestResult(
      recommendedMrcLevel: recommendedLevel,
      progressToNextLevel: progressRatio,
      votesUp: upVotes,
      votesStay: stayVotes,
      votesDown: downVotes,
      summaryHeadline: headline,
      clinicalReasons: List<String>.unmodifiable(reasons),
    );
  }
}

// ===========================================================================
// Game Phase & Map Definitions
// ===========================================================================
enum _HuntPhase { setup, playing, done }

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

// ===========================================================================
// Main Treasure Hunt Game Screen with Auto-Path Single Key Movement
// ===========================================================================
class TreasureHunt2D5ScreenInterim extends StatefulWidget {
  const TreasureHunt2D5ScreenInterim({super.key});

  @override
  State<TreasureHunt2D5ScreenInterim> createState() => _TreasureHunt2D5ScreenInterimState();
}

class _TreasureHunt2D5ScreenInterimState extends State<TreasureHunt2D5ScreenInterim>
    with SingleTickerProviderStateMixin {
  static const int mapWidth = 20;
  static const int mapHeight = 20;

  late final Ticker _ticker;
  final PushController input = PushController();
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  final PressStats _stats = PressStats();
  final Set<int> _touchDownLanes = {};

  final RandomForestClassifier _rfClassifier = RandomForestClassifier();
  RandomForestResult? _lastMlResult;

  _HuntPhase _phase = _HuntPhase.setup;
  MrcLevel _mrcLevel = MrcLevel.mrc3;
  double _t = 0;

  int _playerX = 2;
  int _playerY = 2;
  int _treasureX = 16;
  int _treasureY = 16;

  List<Point<int>> _solutionPath = [];
  int _pathIndex = 0;

  final Map<int, double> _lanePressStart = {};

  List<List<TileType>> _mapGrid = List<List<TileType>>.generate(
    mapHeight,
    (y) => List<TileType>.generate(mapWidth, (x) => TileType.grass),
  );
  List<LandmarkInfo> _landmarks = [];

  int _totalMoves = 0;
  int _blockedAttempts = 0;
  String _judgment = '';
  Color _judgmentColor = Colors.white;

  List<int> get _laneCells => const [0]; // Single input key/lane

  double get _targetHoldSec {
    switch (_mrcLevel) {
      case MrcLevel.mrc3:
        return 0.6;
      case MrcLevel.mrc4:
        return 0.8;
      case MrcLevel.mrc5:
        return 1.0;
    }
  }

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
    _mapGrid = List<List<TileType>>.generate(
      mapHeight,
      (y) => List<TileType>.generate(mapWidth, (x) => TileType.grass),
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

    _solutionPath = [];
    final solutionTiles = <Point<int>>{};
    for (int i = 0; i < pathNodes.length; i++) {
      final node = pathNodes[i];
      _solutionPath.add(node);
      solutionTiles.add(node);
      _mapGrid[node.y][node.x] = TileType.path;

      if (i < pathNodes.length - 1) {
        final next = pathNodes[i + 1];
        final mid = Point((node.x + next.x) ~/ 2, (node.y + next.y) ~/ 2);
        _solutionPath.add(mid);
        solutionTiles.add(mid);
        _mapGrid[mid.y][mid.x] = TileType.path;
      }
    }
    _pathIndex = 0;

    _mapGrid[_treasureY][_treasureX] = TileType.treasure;

    final landmarkDefs = [
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
    final parent = <Point<int>, Point<int>?>{};
    final visited = <Point<int>>{start};

    bool dfs(Point<int> current) {
      if (current == end) return true;

      final dirs = <Point<int>>[
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

    final path = <Point<int>>[];
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

    final isActionKey = event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.keyD;

    if (!isActionKey) return KeyEventResult.ignored;

    const lane = 0;
    if (event is KeyDownEvent) {
      if (!_touchDownLanes.contains(lane)) {
        setState(() => _touchDownLanes.add(lane));
        _onDown(lane);
      }
      return KeyEventResult.handled;
    } else if (event is KeyUpEvent) {
      if (_touchDownLanes.contains(lane)) {
        setState(() => _touchDownLanes.remove(lane));
        _onUp(lane);
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
      _attemptAutoMove(steps, result);
    } else {
      _flash('RELEASED EARLY', Colors.orangeAccent);
    }
  }

  void _attemptAutoMove(int requestedSteps, PressResult result) {
    if (_pathIndex >= _solutionPath.length - 1) return;

    int oldIndex = _pathIndex;
    _pathIndex = (_pathIndex + requestedSteps).clamp(0, _solutionPath.length - 1);
    int moved = _pathIndex - oldIndex;

    setState(() {
      _playerX = _solutionPath[_pathIndex].x;
      _playerY = _solutionPath[_pathIndex].y;
      _totalMoves++;

      if (moved > 0) {
        String typeLabel = result == PressResult.full ? 'FULL DASH (2 TILES)' : 'HALF STEP (1 TILE)';
        _flash('ADVANCED $moved TILE(S) ALONG PATH • $typeLabel', Colors.greenAccent);
      }
    });

    if (_playerX == _treasureX && _playerY == _treasureY) {
      _finish();
    }
  }

  void _finish({bool early = false}) {
    _ticker.stop();
    input.clear();
    _touchDownLanes.clear();

    final successfulMoves = _totalMoves - _blockedAttempts;
    final totalAttempts = _totalMoves;
    final accuracy = totalAttempts > 0 ? successfulMoves / totalAttempts : 0.0;
    final completionRate = early ? (totalAttempts > 0 ? successfulMoves / (totalAttempts + 5) : 0.0) : 1.0;

    final features = PatientPerformanceFeatures(
      completionRate: completionRate,
      fullPressRatio: _stats.total > 0 ? _stats.full / _stats.total : 0.0,
      halfPressRatio: _stats.total > 0 ? _stats.half / _stats.total : 0.0,
      noPressRatio: _stats.total > 0 ? _stats.none / _stats.total : 0.0,
      accuracy: accuracy,
      comboRatio: accuracy,
      currentMrcLevel: _mrcLevel.level,
    );

    _lastMlResult = _rfClassifier.predict(features);
    _phase = _HuntPhase.done;

    final safeReasons = _lastMlResult?.clinicalReasons ?? const <String>[];

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Treasure Hunt (Auto-Path Single Key)',
      date: DateTime.now(),
      difficulty: _mrcLevel.label,
      durationSeconds: _t.round(),
      correctAttempts: successfulMoves,
      incorrectAttempts: _blockedAttempts,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Time ${_t.toStringAsFixed(1)} s | Moves $_totalMoves | '
          'Grade ${_mrcLevel.label} | '
          'ML Rec Level: ${_lastMlResult?.recommendedMrcLevel.label ?? _mrcLevel.label} | '
          'Reasons: ${safeReasons.join("; ")}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;
    switch (_phase) {
      case _HuntPhase.setup:
        bodyContent = _setup();
        break;
      case _HuntPhase.playing:
        bodyContent = _play();
        break;
      case _HuntPhase.done:
        bodyContent = _summary();
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('2.5D Auto-Path Treasure Hunt')),
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
                child: bodyContent,
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
          'Interim Single-Key Mode:\n'
          'Press or hold SPACEBAR to automatically advance along the path toward the treasure chest!',
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
              Text('Half Hold (45%-90%) = Move 1 Tile Forward', style: TextStyle(color: kHalfColor)),
              Text('Full Hold (90%+) = Dash 2 Tiles Forward', style: TextStyle(color: kFullColor)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.medical_information, color: kTeal, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Therapist MRC Assessment Selection',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kTeal),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Column(
                children: MrcLevel.values.map((mrc) {
                  final isSelected = _mrcLevel == mrc;
                  return Card(
                    elevation: isSelected ? 2 : 0,
                    color: isSelected ? kTeal.withValues(alpha: 0.15) : Colors.white,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? kTeal : Colors.grey.shade300,
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      title: Text('${mrc.label} (${mrc.description})',
                          style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text(mrc.details, style: const TextStyle(fontSize: 11)),
                      trailing: Radio<MrcLevel>(
                        value: mrc,
                        groupValue: _mrcLevel,
                        activeColor: kTeal,
                        onChanged: (val) {
                          if (val != null) setState(() => _mrcLevel = val);
                        },
                      ),
                      onTap: () => setState(() => _mrcLevel = mrc),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _startGame,
          style: FilledButton.styleFrom(
              backgroundColor: kTeal, minimumSize: const Size.fromHeight(56)),
          child: Text('Start Session (${_mrcLevel.label})',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text('Grade: ${_mrcLevel.label}',
                              style: const TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text('Moves: $_totalMoves',
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 14, fontWeight: FontWeight.bold)),
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
          _buildSingleButton(),
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

  Widget _buildSingleButton() {
    return AnimatedBuilder(
      animation: input,
      builder: (context, _) {
        const index = 0;
        final cell = _laneCells[index];
        final isPressed = input.isDown(cell) || _touchDownLanes.contains(index);
        const color = kTeal;

        double fillRatio = 0.0;
        String labelText = 'PRESS & HOLD SPACEBAR / TAP TO MOVE FORWARD';
        Color labelColor = Colors.white;
        Color borderColor = color;
        double borderWidth = 3.0;
        Color fillColor = color.withValues(alpha: 0.45);

        if (_lanePressStart.containsKey(index)) {
          final held = _t - _lanePressStart[index]!;
          fillRatio = (held / _targetHoldSec).clamp(0.0, 1.0);
          final pct = (fillRatio * 100).round();
          final result = classifyNoteHold(held, _targetHoldSec);

          labelText = 'ADVANCING... ($pct%)';
          if (result == PressResult.full) {
            labelText = 'FULL DASH (2 TILES) • RELEASE!';
            labelColor = kFullColor;
            borderColor = kFullColor;
            borderWidth = 5.0;
            fillColor = kFullColor.withValues(alpha: 0.4);
          } else if (result == PressResult.half) {
            labelText = 'HALF STEP (1 TILE) • HOLD MORE FOR DASH';
            labelColor = kHalfColor;
            borderColor = kHalfColor;
            borderWidth = 4.0;
            fillColor = kHalfColor.withValues(alpha: 0.4);
          }
        } else if (isPressed) {
          fillRatio = 1.0;
        }

        return Padding(
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
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _summary() {
    final recMrc = _lastMlResult?.recommendedMrcLevel ?? _mrcLevel;
    final progressPct = ((_lastMlResult?.progressToNextLevel ?? 0.0) * 100).round();
    final clinicalReasons = _lastMlResult?.clinicalReasons ?? const <String>[];

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
            gradient: LinearGradient(
              colors: [Colors.indigo.shade900, Colors.purple.shade900],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Adaptive Difficulty Analysis',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Current: ${_mrcLevel.label}',
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.auto_graph_rounded, color: Colors.greenAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recommended Tier: ${recMrc.label} (${recMrc.description})',
                      style: const TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Progress to Next Level',
                      style: TextStyle(color: Colors.grey.shade300, fontSize: 12)),
                  Text('$progressPct%',
                      style: const TextStyle(
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _lastMlResult?.progressToNextLevel ?? 0.0,
                  minHeight: 10,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                ),
              ),
              const SizedBox(height: 14),
              if (clinicalReasons.isNotEmpty) ...[
                const Text('Key Assessment Factors:',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: clinicalReasons.map((reason) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          Expanded(
                            child: Text(
                              reason,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.90),
                                  fontSize: 12.5,
                                  height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
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
              _row('Full Dashes (2 Tiles)', '${_stats.full}'),
              const Divider(height: 16),
              _row('Half Steps (1 Tile)', '${_stats.half}'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _mrcLevel = recMrc;
              _startGame();
            });
          },
          icon: const Icon(Icons.replay),
          label: Text('Play Again with ${recMrc.label}', style: const TextStyle(fontSize: 16)),
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

// ===========================================================================
// Custom Painters for 2.5D Map and Minimap Visualizations
// ===========================================================================
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
    if (mapGrid.isEmpty || mapGrid[0].isEmpty) return;

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
    if (mapGrid.isEmpty || mapGrid[0].isEmpty) return;

    final rows = mapGrid.length;
    final cols = mapGrid[0].length;
    final cellW = size.width / cols;
    final cellH = size.height / rows;

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        Color c = const Color(0xFF1B3B1A);
        switch (mapGrid[y][x]) {
          case TileType.water:
            c = const Color(0xFF1E88E5);
            break;
          case TileType.path:
            c = const Color(0xFF8D6E63);
            break;
          case TileType.tree:
            c = const Color(0xFF1B5E20);
            break;
          default:
            c = const Color(0xFF1B3B1A);
            break;
        }
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