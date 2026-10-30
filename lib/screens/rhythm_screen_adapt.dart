import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

// ===========================================================================
// MRC Scale Definition for Stroke Muscle Evaluation (Grades 1 to 5)
// ===========================================================================
enum MrcLevel {
  mrc1(1, 'MRC 1', 'Trace Contraction', 'Slow drop speed, short holds, simple single notes'),
  mrc2(2, 'MRC 2', 'Gravity Eliminated', 'Gentle speed, moderate holds, standard sequence'),
  mrc3(3, 'MRC 3', 'Against Gravity', 'Moderate speed, longer holds, mixed patterns'),
  mrc4(4, 'MRC 4', 'Moderate Resistance', 'Fast drop speed, long holds, high note density'),
  mrc5(5, 'MRC 5', 'Normal Strength', 'Very fast speed, maximum endurance, complex dual-lane chords');

  final int level;
  final String label;
  final String description;
  final String details;

  const MrcLevel(this.level, this.label, this.description, this.details);
}

// ===========================================================================
// Random Forest Machine Learning Engine with Null-Safe Clinical Reasoning
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
      case 'completionRate': val = f.completionRate; break;
      case 'fullPressRatio': val = f.fullPressRatio; break;
      case 'halfPressRatio': val = f.halfPressRatio; break;
      case 'noPressRatio':   val = f.noPressRatio; break;
      case 'accuracy':       val = f.accuracy; break;
      case 'comboRatio':      val = f.comboRatio; break;
      default: val = 0.0;
    }
    if (val >= threshold!) {
      return right!.predict(f);
    } else {
      return left!.predict(f);
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

    int nextLevelInt = (features.currentMrcLevel + delta).clamp(1, 5);
    MrcLevel recommendedLevel = MrcLevel.values[nextLevelInt - 1];

    double proficiency = (features.completionRate * 0.35) +
        (features.fullPressRatio * 0.40) +
        (features.accuracy * 0.25);

    double voteFraction = upVotes / _trees.length;
    double progressRatio = (proficiency * 0.5 + voteFraction * 0.5).clamp(0.0, 1.0);

    final List<String> reasons = [];
    String headline = '';

    final fullPct = (features.fullPressRatio * 100).toStringAsFixed(0);
    final compPct = (features.completionRate * 100).toStringAsFixed(0);
    final missPct = (features.noPressRatio * 100).toStringAsFixed(0);

    if (delta > 0) {
      headline = 'Promoted to Next Strength Tier';
      reasons.add('High sustained muscle force: $fullPct% full press duration met threshold (>65%).');
      reasons.add('Strong motor completion: $compPct% of notes successfully completed.');
      reasons.add('$upVotes of 5 Random Forest decision trees voted to increase difficulty.');
    } else if (delta < 0) {
      headline = 'Reduced Resistance to Support Motor Control';
      if (features.noPressRatio > 0.35) {
        reasons.add('Fatigue or missed targets: $missPct% missed/incomplete notes detected.');
      }
      if (features.fullPressRatio < 0.35) {
        reasons.add('Sustained press strength ($fullPct%) was insufficient for current tier target.');
      }
      reasons.add('$downVotes of 5 Random Forest decision trees voted to lower resistance.');
    } else {
      headline = 'Maintain Current Level for Consolidation';
      reasons.add('Consistent motor execution ($compPct% completed notes), but requires higher sustained force.');
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
// Core Note & Helper Data Structures
// ===========================================================================
class _Note {
  final int lane;
  double start;
  final double duration;
  final String kind;
  int state = 0;
  double pressAt = 0;
  int timingPts = 0;
  bool midReached = false;
  _Note(this.lane, this.start, this.duration, this.kind);
}

enum _RPhase { setup, playing, done }

const Map<String, Color> _kindColors = {
  'half': Color(0xFF00E5FF),
  'full': Color(0xFFFF4081),
  'endurance': Color(0xFFFFD740),
};

const List<Color> _laneColors = [
  Color(0xFFF0788C),
  Color(0xFF7BD095),
  Color(0xFFFFC95C),
  Color(0xFF63A7EF),
];

const List<String> _laneKeyLabels = ['D', 'F', 'J', 'K'];

PressResult classifyNoteHold(double heldSeconds, double targetDuration) {
  if (targetDuration <= 0) return PressResult.none;
  final ratio = heldSeconds / targetDuration;
  if (ratio >= 0.90) return PressResult.full;
  if (ratio >= 0.45) return PressResult.half;
  return PressResult.none;
}

// ===========================================================================
// Main Game Widget State
// ===========================================================================
class RhythmGameScreen extends StatefulWidget {
  const RhythmGameScreen({super.key});

  @override
  State<RhythmGameScreen> createState() => _RhythmGameScreenState();
}

class _RhythmGameScreenState extends State<RhythmGameScreen>
    with SingleTickerProviderStateMixin {
  static const double _window = 0.45;

  late final Ticker _ticker;
  final PushController input = PushController();
  final FocusNode _focusNode = FocusNode();
  final Random _random = Random();
  final List<_Note> _notes = [];
  final PressStats _stats = PressStats();
  final Set<int> _touchDownLanes = {};

  final RandomForestClassifier _rfClassifier = RandomForestClassifier();
  RandomForestResult? _lastMlResult;

  _RPhase _phase = _RPhase.setup;
  final BoardMode _mode = BoardMode.row;
  MrcLevel _mrcLevel = MrcLevel.mrc1;
  double _t = 0;

  List<int> get _laneCells => _mode.cells.length >= 4 
      ? _mode.cells.sublist(0, 4) 
      : const [0, 1, 2, 3];

  int _score = 0, _combo = 0, _bestCombo = 0;
  int _completed = 0, _missed = 0, _dropped = 0, _perfect = 0, _good = 0;
  double _longest = 0;
  bool _early = false;
  String _judgment = '';
  Color _judgmentColor = Colors.white;

  double get _lead => switch (_mrcLevel) {
        MrcLevel.mrc1 => 4.2,
        MrcLevel.mrc2 => 3.5,
        MrcLevel.mrc3 => 2.8,
        MrcLevel.mrc4 => 2.1,
        MrcLevel.mrc5 => 1.5,
      };

  double get _gap => switch (_mrcLevel) {
        MrcLevel.mrc1 => 2.0,
        MrcLevel.mrc2 => 1.6,
        MrcLevel.mrc3 => 1.2,
        MrcLevel.mrc4 => 0.8,
        MrcLevel.mrc5 => 0.5,
      };

  double get _halfSec => switch (_mrcLevel) {
        MrcLevel.mrc1 => 0.8,
        MrcLevel.mrc2 => 1.2,
        MrcLevel.mrc3 => 1.6,
        MrcLevel.mrc4 => 2.0,
        MrcLevel.mrc5 => 2.5,
      };

  double get _fullSec => switch (_mrcLevel) {
        MrcLevel.mrc1 => 1.5,
        MrcLevel.mrc2 => 2.2,
        MrcLevel.mrc3 => 3.0,
        MrcLevel.mrc4 => 4.0,
        MrcLevel.mrc5 => 5.0,
      };

  double get _enduranceSec => switch (_mrcLevel) {
        MrcLevel.mrc1 => 5.0,
        MrcLevel.mrc2 => 8.0,
        MrcLevel.mrc3 => 12.0,
        MrcLevel.mrc4 => 16.0,
        MrcLevel.mrc5 => 20.0,
      };

  List<String> get _pattern => switch (_mrcLevel) {
        MrcLevel.mrc1 => const ['half', 'half', 'full', 'half'],
        MrcLevel.mrc2 => const ['half', 'half', 'full', 'half', 'full', 'half', 'endurance'],
        MrcLevel.mrc3 => const ['half', 'full', 'half', 'full', 'full', 'endurance', 'half', 'full'],
        MrcLevel.mrc4 => const ['full', 'half', 'full', 'full', 'endurance', 'full', 'half', 'full', 'endurance', 'full'],
        MrcLevel.mrc5 => const ['full', 'chord', 'full', 'endurance', 'chord', 'full', 'half', 'chord', 'endurance', 'full'],
      };

  @override
  void initState() {
    super.initState();
    input.allowed = _laneCells;
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

  void _buildChart() {
    _notes.clear();
    double t = _lead + 1.0;
    int prev = -1;
    final lanes = _laneCells.length;

    for (final k in _pattern) {
      if (k == 'chord') {
        int lane1 = _random.nextInt(lanes);
        int lane2 = (lane1 + 2) % lanes;
        double d = _fullSec;
        _notes.add(_Note(lane1, t, d, 'full'));
        _notes.add(_Note(lane2, t, d, 'full'));
        t += d + _gap;
      } else {
        int lane;
        do {
          lane = _random.nextInt(lanes);
        } while (lane == prev && lanes > 1);
        prev = lane;

        final d = switch (k) {
          'half' => _halfSec,
          'full' => _fullSec,
          _ => _enduranceSec * PushConfig.scale,
        };
        _notes.add(_Note(lane, t, d, k));
        t += d + _gap;
      }
    }
  }

  void _startGame() {
    trainingStarted = true;
    input.allowed = _laneCells;
    input.clear();
    _touchDownLanes.clear();
    setState(() {
      _buildChart();
      _stats.reset();
      _score = 0;
      _combo = 0;
      _bestCombo = 0;
      _completed = 0;
      _missed = 0;
      _dropped = 0;
      _perfect = 0;
      _good = 0;
      _longest = 0;
      _early = false;
      _judgment = '';
      _t = 0;
      _phase = _RPhase.playing;
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
    if (_phase != _RPhase.playing) return KeyEventResult.ignored;

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
    final cell = _laneCells[laneIndex];

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

  void _onTick(Duration e) {
    _t = e.inMicroseconds / 1e6;
    if (_phase != _RPhase.playing) return;

    setState(() {
      for (final n in _notes) {
        if (n.state == 0 && _t > n.start + _window) {
          n.state = 3;
          _missed++;
          _combo = 0;
          _flash('MISS', Colors.redAccent);
        } else if (n.state == 1) {
          final held = _t - n.pressAt;

          if (!n.midReached && held >= n.duration * 0.5) {
            n.midReached = true;
            _flash('HALF WAY! (50%)', kHalfColor);
          }

          if (_t >= n.start + n.duration) {
            n.state = 2;
            _stats.add(classifyNoteHold(n.duration, n.duration));
            _completed++;
            _combo++;
            _bestCombo = max(_bestCombo, _combo);
            _longest = max(_longest, n.duration);
            final mult = 1 + min(_combo, 10) * 0.1;
            _score += ((n.timingPts + n.duration * 20) * mult).round();
            _flash('HOLD COMPLETE', Colors.greenAccent);
          }
        }
      }
      if (_notes.every((n) => n.state >= 2)) _finish();
    });
  }

  void _onDown(int cell) {
    if (_phase != _RPhase.playing) return;
    final lane = _laneCells.indexOf(cell);
    if (lane < 0) return;
    _Note? best;
    double bd = 99;
    for (final n in _notes) {
      if (n.lane == lane && n.state == 0) {
        final d = (_t - n.start).abs();
        if (d <= _window && d < bd) {
          best = n;
          bd = d;
        }
      }
    }
    if (best == null) return;
    final note = best;
    setState(() {
      if (bd <= 0.2) {
        note.timingPts = 100;
        _perfect++;
        _flash('PERFECT', Colors.greenAccent);
      } else {
        note.timingPts = 50;
        _good++;
        _flash('GOOD', Colors.lightBlueAccent);
      }
      note.state = 1;
      note.pressAt = _t;
      note.start = _t;
    });
  }

  void _onUp(int cell, double sec) {
    if (_phase != _RPhase.playing) return;
    final lane = _laneCells.indexOf(cell);
    if (lane < 0) return;
    for (final n in _notes) {
      if (n.lane == lane && n.state == 1) {
        setState(() {
          final held = _t - n.pressAt;
          n.state = 4;
          final r = classifyNoteHold(held, n.duration);
          _stats.add(r);
          _dropped++;
          _combo = 0;
          _longest = max(_longest, held);
          _score += (held * 10).round();
          _flash(
              r == PressResult.none
                  ? 'TOO SHORT'
                  : (r == PressResult.half ? 'RELEASED (HALF)' : 'RELEASED (FULL)'),
              Colors.orangeAccent);
        });
        break;
      }
    }
  }

  void _finish({bool early = false}) {
    _ticker.stop();
    input.clear();
    _touchDownLanes.clear();
    _early = early;

    final total = _notes.isEmpty ? 1 : _notes.length;
    final features = PatientPerformanceFeatures(
      completionRate: _completed / total,
      fullPressRatio: _stats.total > 0 ? _stats.full / _stats.total : 0.0,
      halfPressRatio: _stats.total > 0 ? _stats.half / _stats.total : 0.0,
      noPressRatio: _stats.total > 0 ? _stats.none / _stats.total : 0.0,
      accuracy: total > 0 ? (_perfect + _good) / total : 0.0,
      comboRatio: total > 0 ? _bestCombo / total : 0.0,
      currentMrcLevel: _mrcLevel.level,
    );

    _lastMlResult = _rfClassifier.predict(features);
    _phase = _RPhase.done;

    final List<String> safeReasons = _lastMlResult?.clinicalReasons ?? const <String>[];

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Rhythm Game (Adaptive MRC)',
      date: DateTime.now(),
      difficulty: _mrcLevel.label,
      durationSeconds: _t.round(),
      correctAttempts: _completed,
      incorrectAttempts: _notes.length - _completed,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Score $_score | Grade ${_mrcLevel.label} | holds $_completed/${_notes.length} | '
          'ML Rec Level: ${_lastMlResult?.recommendedMrcLevel.label ?? _mrcLevel.label} | '
          'Reasons: ${safeReasons.join("; ")}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rhythm Game (Adaptive MRC)')),
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
                  _RPhase.setup => _setup(),
                  _RPhase.playing => _play(),
                  _RPhase.done => _summary(),
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
        const Icon(Icons.fitness_center_rounded, size: 64, color: kTeal),
        const SizedBox(height: 8),
        const Text('Stroke Push Evaluation Game',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          'Press and hold tiles to match target strength durations. Adaptive ML automatically adjusts difficulty based on muscle performance.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.black87),
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
        const SizedBox(height: 16),
        practiceSwitch(PushConfig.practice,
            (v) => setState(() => PushConfig.practice = v)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _startGame,
          style: FilledButton.styleFrom(
              backgroundColor: kTeal, minimumSize: const Size.fromHeight(52)),
          child: Text('Start Session (${_mrcLevel.label})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }

  Widget _play() {
    final done = _notes.where((n) => n.state >= 2).length;
    const white = TextStyle(
        color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold);

    return Container(
      color: const Color(0xFF05051A),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Score $_score', style: white),
              Text('${_mrcLevel.label} | Note ${min(done + 1, _notes.length)}/${_notes.length}',
                  style: white.copyWith(color: Colors.cyanAccent)),
              Text('Combo x$_combo',
                  style: white.copyWith(color: Colors.orangeAccent)),
            ],
          ),
          SizedBox(
            height: 38,
            child: Center(
              child: Text(_judgment,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: _judgmentColor)),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AnimatedBuilder(
                animation: input,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _HighwayPainter(
                    _notes,
                    _t,
                    _lead,
                    {
                      for (var l = 0; l < 4; l++)
                        if (input.isDown(_laneCells[l]) ||
                            _touchDownLanes.contains(l))
                          l
                    },
                  ),
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
            child: const Text('End session',
                style: TextStyle(color: Colors.white70)),
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
            final isPressed =
                input.isDown(cell) || _touchDownLanes.contains(index);
            final color = _laneColors[index];

            _Note? holdNote;
            for (final n in _notes) {
              if (n.lane == index && n.state == 1) {
                holdNote = n;
                break;
              }
            }

            double fillRatio = 0.0;
            String labelText = _laneKeyLabels[index];
            Color labelColor = Colors.white;
            Color borderColor = color;
            double borderWidth = 3.0;
            Color fillColor = color.withValues(alpha: 0.45);

            if (holdNote != null) {
              final held = _t - holdNote.pressAt;
              fillRatio = (holdNote.duration > 0 ? held / holdNote.duration : 0.0)
                  .clamp(0.0, 1.0);
              final pct = (fillRatio * 100).round();
              final reachedMid = held >= holdNote.duration * 0.5;

              labelText = '$pct%';
              labelColor = reachedMid ? Colors.greenAccent : Colors.amberAccent;
              borderColor = reachedMid ? kFullColor : kHalfColor;
              borderWidth = reachedMid ? 5.0 : 3.0;
              fillColor = reachedMid
                  ? Colors.greenAccent.withValues(alpha: 0.4)
                  : Colors.amberAccent.withValues(alpha: 0.4);
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
                      boxShadow: isPressed || holdNote != null
                          ? [
                              BoxShadow(
                                color: borderColor.withValues(alpha: 0.65),
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
                                child: Container(color: fillColor),
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
    final accuracy = _notes.isEmpty ? 0.0 : _completed / _notes.length * 100;
    final progressPct = ((_lastMlResult?.progressToNextLevel ?? 0.0) * 100).round();
    final recMrc = _lastMlResult?.recommendedMrcLevel ?? _mrcLevel;

    final List<String> clinicalReasons =
        _lastMlResult?.clinicalReasons ?? const <String>[];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.emoji_events, size: 56, color: Colors.amber),
        const SizedBox(height: 6),
        Text(_early ? 'Session Stopped' : 'Performance Summary',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),

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
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              _row('Final Score', '$_score'),
              const Divider(height: 16),
              _row('Holds Completed', '$_completed / ${_notes.length}'),
              const Divider(height: 16),
              _row('Completion Accuracy', '${accuracy.toStringAsFixed(1)}%'),
              const Divider(height: 16),
              _row('Longest Sustained Hold', '${_longest.toStringAsFixed(1)} s'),
              const Divider(height: 16),
              _row('Perfect / Good Hits', '$_perfect / $_good'),
              const Divider(height: 16),
              _row('Released Early', '$_dropped'),
              const Divider(height: 16),
              _row('Missed Notes', '$_missed'),
              const Divider(height: 16),
              _row('Full / Half / No Press',
                  '${_stats.full} / ${_stats.half} / ${_stats.none}'),
            ],
          ),
        ),
        const SizedBox(height: 14),

        FilledButton.icon(
          onPressed: () {
            setState(() {
              if (_lastMlResult != null) {
                _mrcLevel = _lastMlResult!.recommendedMrcLevel;
              }
              _phase = _RPhase.setup;
            });
          },
          icon: const Icon(Icons.replay),
          label: Text('Continue with ${recMrc.label}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          style: FilledButton.styleFrom(
              backgroundColor: kTeal,
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

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
                fontWeight: FontWeight.w500)),
        Text(value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ===========================================================================
// Perspective Highway Painter
// ===========================================================================
class _HighwayPainter extends CustomPainter {
  final List<_Note> notes;
  final double t;
  final double lead;
  final Set<int> down;

  _HighwayPainter(this.notes, this.t, this.lead, this.down);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF05051A), Color(0xFF241046)],
        ).createShader(rect),
    );

    final hitY = s.height * 0.88;
    final horizon = s.height * 0.03;
    final span = hitY - horizon;
    final fullW = s.width * 0.96;

    double yAt(double p) => horizon + span * pow(p, 1.6).toDouble();
    double sc(double y) => 0.30 + 0.70 * ((y - horizon) / span);

    double cx(int lane, double y) =>
        s.width / 2 + (lane - 1.5) * (fullW / 4) * sc(y);
    double hw(double y) => (fullW / 4) * sc(y) / 2;

    for (var l = 0; l < 4; l++) {
      final path = Path()
        ..moveTo(cx(l, horizon) - hw(horizon), horizon)
        ..lineTo(cx(l, horizon) + hw(horizon), horizon)
        ..lineTo(cx(l, s.height) + hw(s.height), s.height)
        ..lineTo(cx(l, s.height) - hw(s.height), s.height)
        ..close();
      final isDown = down.contains(l);
      canvas.drawPath(
        path,
        Paint()
          ..color = isDown
              ? _laneColors[l].withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: l.isEven ? 0.04 : 0.08),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.15),
      );
    }

    canvas.drawLine(
      Offset(0, hitY),
      Offset(s.width, hitY),
      Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 3,
    );

    for (final n in notes) {
      if (n.state != 0 && n.state != 1) continue;
      final pHead = n.state == 1 ? 1.0 : (t - (n.start - lead)) / lead;
      if (pHead <= 0 || pHead > 1.25) continue;
      var pTail = (t - (n.start + n.duration - lead)) / lead;
      if (pTail < 0) pTail = 0;

      final yH = yAt(pHead);
      final yT = yAt(pTail);
      final color = _kindColors[n.kind] ?? Colors.cyan;
      const bw = 0.55;

      final body = Path()
        ..moveTo(cx(n.lane, yT) - hw(yT) * bw, yT)
        ..lineTo(cx(n.lane, yT) + hw(yT) * bw, yT)
        ..lineTo(cx(n.lane, yH) + hw(yH) * bw, yH)
        ..lineTo(cx(n.lane, yH) - hw(yH) * bw, yH)
        ..close();
      canvas.drawPath(
          body, Paint()..color = color.withValues(alpha: n.state == 1 ? 0.75 : 0.45));

      final pMid = (t - (n.start + n.duration / 2 - lead)) / lead;
      if (pMid > pTail && pMid < pHead) {
        final yM = yAt(pMid);
        final hwM = hw(yM) * bw;
        final bool isHeldPastMid =
            n.state == 1 && (t - n.pressAt >= n.duration * 0.5);

        if (isHeldPastMid) {
          canvas.drawLine(
            Offset(cx(n.lane, yM) - hwM * 1.2, yM),
            Offset(cx(n.lane, yM) + hwM * 1.2, yM),
            Paint()
              ..color = kHalfColor.withValues(alpha: 0.85)
              ..strokeWidth = 7.0
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
          );
        }

        canvas.drawLine(
          Offset(cx(n.lane, yM) - hwM, yM),
          Offset(cx(n.lane, yM) + hwM, yM),
          Paint()
            ..color =
                isHeldPastMid ? Colors.amberAccent : Colors.white.withValues(alpha: 0.85)
            ..strokeWidth = isHeldPastMid ? 3.5 : 2.0,
        );
      }

      final cap = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx(n.lane, yH), yH),
          width: hw(yH) * 2 * 0.9,
          height: 16 * sc(yH),
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(
          cap, Paint()..color = color.withValues(alpha: pHead > 1 ? 0.4 : 1.0));
    }
  }

  @override
  bool shouldRepaint(covariant _HighwayPainter old) => true;
}