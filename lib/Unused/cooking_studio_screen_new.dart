import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';
import 'cooking_scene.dart';

/// Four input positions, corresponding to G, J, T, and U.
/// Update the cell IDs if your physical board uses different IDs.
enum CookingPosition { topLeft, topRight, bottomLeft, bottomRight }

extension CookingPositionLabel on CookingPosition {
  int get cell => switch (this) {
    CookingPosition.topLeft => 1,
    CookingPosition.topRight => 2,
    CookingPosition.bottomLeft => 3,
    CookingPosition.bottomRight => 5,
  };
  String get label => switch (this) {
    CookingPosition.topLeft => 'TOP LEFT',
    CookingPosition.topRight => 'TOP RIGHT',
    CookingPosition.bottomLeft => 'BOTTOM LEFT',
    CookingPosition.bottomRight => 'BOTTOM RIGHT',
  };
  String get keyHint => switch (this) {
    CookingPosition.topLeft => 'T',
    CookingPosition.topRight => 'U',
    CookingPosition.bottomLeft => 'G',
    CookingPosition.bottomRight => 'J',
  };
}

class CookingAction {
  final String name;
  final String cue;
  final String emoji;
  final double seconds;
  final bool twoHands;
  const CookingAction(this.name, this.cue, this.emoji, this.seconds,
      {this.twoHands = false});
}

class CookingRecipe {
  final String cuisine, name, emoji;
  final List<CookingAction> actions;
  const CookingRecipe(this.cuisine, this.name, this.emoji, this.actions);
}

const cookingRecipes = <CookingRecipe>[
  CookingRecipe('Japanese', 'Ramen', '🍜', [
    CookingAction('Wash vegetables', 'Hold the vegetables while washing.', '🥬', 3, twoHands: true),
    CookingAction('Prepare vegetables', 'Prepare the washed vegetables.', '🥕', 3),
    CookingAction('Stir broth', 'Steady the pot while stirring.', '🥣', 4, twoHands: true),
    CookingAction('Add noodles', 'Add the noodles to the broth.', '🍜', 3),
    CookingAction('Plate ramen', 'Steady the bowl while serving.', '✨', 3, twoHands: true),
  ]),
  CookingRecipe('Italian', 'Tomato Pasta', '🍝', [
    CookingAction('Wash tomatoes', 'Hold the tomatoes while washing.', '🍅', 3, twoHands: true),
    CookingAction('Prepare tomatoes', 'Prepare the tomatoes.', '🔪', 3),
    CookingAction('Mix sauce', 'Steady the bowl while mixing.', '🥫', 4, twoHands: true),
    CookingAction('Combine pasta', 'Mix pasta into the sauce.', '🍝', 4),
    CookingAction('Serve pasta', 'Steady the plate while serving.', '✨', 3, twoHands: true),
  ]),
  CookingRecipe('Chinese', 'Fried Rice', '🍚', [
    CookingAction('Wash vegetables', 'Hold vegetables while rinsing.', '🥬', 3, twoHands: true),
    CookingAction('Prepare vegetables', 'Prepare the vegetables.', '🥕', 3),
    CookingAction('Mix ingredients', 'Hold the bowl while mixing.', '🥣', 3, twoHands: true),
    CookingAction('Add seasoning', 'Add seasoning to the rice.', '🧂', 3),
    CookingAction('Serve rice', 'Steady the plate while serving.', '🍚', 3, twoHands: true),
  ]),
  CookingRecipe('Mexican', 'Tacos', '🌮', [
    CookingAction('Wash lettuce', 'Hold the lettuce while washing.', '🥬', 3, twoHands: true),
    CookingAction('Prepare filling', 'Prepare the filling.', '🍅', 3),
    CookingAction('Fill taco', 'Steady the shell while adding filling.', '🌮', 4, twoHands: true),
    CookingAction('Add toppings', 'Add toppings to your tacos.', '🧀', 3),
    CookingAction('Serve tacos', 'Hold the plate steady while serving.', '✨', 3, twoHands: true),
  ]),
  CookingRecipe('Indian', 'Vegetable Curry', '🍛', [
    CookingAction('Wash vegetables', 'Hold vegetables while rinsing.', '🥔', 3, twoHands: true),
    CookingAction('Prepare vegetables', 'Prepare vegetables for cooking.', '🥕', 3),
    CookingAction('Add spices', 'Add spices to the pot.', '🧂', 3),
    CookingAction('Stir curry', 'Steady the pot while stirring.', '🥘', 5, twoHands: true),
    CookingAction('Plate curry', 'Steady the dish while serving.', '🍛', 3, twoHands: true),
  ]),
];

enum _CookingPhase { menu, playing, finished }

class CookingStudioScreenNew extends StatefulWidget {
  const CookingStudioScreenNew({super.key});

  @override
  State<CookingStudioScreenNew> createState() => _CookingStudioScreenNewState();
}

class _CookingStudioScreenNewState extends State<CookingStudioScreenNew> {
  final PushController input = PushController();
  Timer? _timer;
  DateTime? _previous;
  _CookingPhase _phase = _CookingPhase.menu;
  Difficulty _difficulty = Difficulty.easy;
  CookingRecipe _recipe = cookingRecipes.first;
  int _index = 0, _completed = 0, _interruptions = 0;
  double _held = 0, _elapsed = 0, _motion = 0;
  bool _reducedMotion = false, _wasHolding = false, _early = false;
  String _message = '';

  CookingAction get _action => _recipe.actions[_index];

  /// Easy: lower pair; Medium: diagonal pair; Hard: upper pair.
  /// Single-handed actions alternate between the two positions.
  List<CookingPosition> get _requestedPositions {
    final pair = switch (_difficulty) {
      Difficulty.easy => const [CookingPosition.bottomLeft, CookingPosition.bottomRight],
      Difficulty.medium => const [CookingPosition.topLeft, CookingPosition.bottomRight],
      Difficulty.hard => const [CookingPosition.topLeft, CookingPosition.topRight],
    };
    return _action.twoHands ? pair : [pair[_index % pair.length]];
  }

  double get _target => _action.seconds * switch (_difficulty) {
    Difficulty.easy => 0.7,
    Difficulty.medium => 1.0,
    Difficulty.hard => 1.3,
  };

  bool get _correct {
    final expected = _requestedPositions.map((p) => p.cell).toSet();
    return CookingPosition.values.every((p) =>
        input.isDown(p.cell) == expected.contains(p.cell));
  }

  @override
  void initState() {
    super.initState();
    input.allowed = CookingPosition.values.map((p) => p.cell).toList();
    input.addListener(_refresh);
  }

  void _refresh() {
    if (mounted && _phase == _CookingPhase.playing) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    input.removeListener(_refresh);
    input.dispose();
    super.dispose();
  }

  void _start(CookingRecipe recipe) {
    _timer?.cancel();
    input.clear();
    trainingStarted = true;
    setState(() {
      _recipe = recipe;
      _phase = _CookingPhase.playing;
      _index = _completed = _interruptions = 0;
      _held = _elapsed = _motion = 0;
      _early = _wasHolding = false;
      _message = 'Hold only the highlighted tile(s).';
      _previous = DateTime.now();
    });
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _phase != _CookingPhase.playing) return;
    final now = DateTime.now();
    final delta = now.difference(_previous ?? now).inMicroseconds / 1000000;
    _previous = now;
    setState(() {
      _elapsed += delta;
      if (_correct) {
        _wasHolding = true;
        _held += delta;
        _motion = (_motion + delta * 1.8) % 1;
        _message = 'Great! Keep holding.';
        if (_held >= _target) {
          _completed++;
          _index++;
          _held = 0;
          _wasHolding = false;
          input.clear();
          _message = 'Step complete! Follow the next highlighted tile(s).';
          if (_index >= _recipe.actions.length) _finish();
        }
      } else if (_wasHolding) {
        _interruptions++;
        _wasHolding = false;
        _message = 'Paused. Hold only the highlighted tile(s) to continue.';
      }
    });
  }

  void _finish({bool early = false}) {
    if (_phase != _CookingPhase.playing) return;
    _timer?.cancel();
    input.clear();
    _phase = _CookingPhase.finished;
    _early = early;
    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Cooking Studio 4-Tile - ${_recipe.name}',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: _elapsed.round(),
      correctAttempts: _completed,
      incorrectAttempts: _interruptions,
      completed: !early,
      notes: '${_recipe.cuisine} | ${_recipe.name} | '
          '$_completed/${_recipe.actions.length} tasks | '
          '$_interruptions interruptions | 4-tile layout',
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rehab Cooking Studio • 4 Tiles')),
    body: SafeArea(child: PushKeyboard(
      controller: input,
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: switch (_phase) {
          _CookingPhase.menu => _menu(),
          _CookingPhase.playing => _game(),
          _CookingPhase.finished => _result(),
        },
      )),
    )),
  );

  Widget _menu() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('🍳 Rehab Cooking Studio', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    const Text('Follow the highlighted positions on a four-tile board. '
        'Some actions require one tile, others require two. '
        'All cooking actions are virtual.', textAlign: TextAlign.center),
    const SizedBox(height: 18),
    chipRow<Difficulty>(title: 'Tile position & hold duration',
        values: Difficulty.values, selected: _difficulty,
        label: (d) => d.label,
        onSelected: (d) => setState(() => _difficulty = d)),
    const SizedBox(height: 8),
    const Text('Easy: bottom tiles • Medium: one top + one bottom '
        '• Hard: top tiles'),
    SwitchListTile(title: const Text('Reduced motion'), value: _reducedMotion,
        onChanged: (v) => setState(() => _reducedMotion = v)),
    const SizedBox(height: 18),
    const Text('Choose a cuisine', style: TextStyle(
        fontSize: 20, fontWeight: FontWeight.bold)),
    for (final recipe in cookingRecipes)
      Card(child: ListTile(
        leading: Text(recipe.emoji, style: const TextStyle(fontSize: 34)),
        title: Text('${recipe.cuisine} — ${recipe.name}'),
        subtitle: Text('${recipe.actions.length} cooking tasks'),
        trailing: const Icon(Icons.play_arrow),
        onTap: () => _start(recipe),
      )),
    const SizedBox(height: 12),
    const Text('Keyboard: T = top left, U = top right, '
        'G = bottom left, J = bottom right. '
        'Adjust these bindings in push_input.dart if needed.'),
  ]);

  Widget _game() {
    final action = _action;
    final requested = _requestedPositions;
    return LayoutBuilder(builder: (context, constraints) =>
      SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
        Text('${_recipe.emoji} ${_recipe.name}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: _completed / _recipe.actions.length, minHeight: 8),
        const SizedBox(height: 8),
        Text('Step ${_index + 1} of ${_recipe.actions.length}'),
        const SizedBox(height: 12),
        SizedBox(height: 185, child: CookingScene(
          taskName: action.name,
          dishName: _recipe.name,
          progress: (_held / _target).clamp(0.0, 1.0),
          motion: _motion,
          // The scene still accepts only two logical hand channels.
          leftDown: requested.where((p) => p == CookingPosition.topLeft ||
              p == CookingPosition.bottomLeft).any((p) => input.isDown(p.cell)),
          rightDown: requested.where((p) => p == CookingPosition.topRight ||
              p == CookingPosition.bottomRight).any((p) => input.isDown(p.cell)),
          completedSteps: _completed,
          reducedMotion: _reducedMotion,
        )),
        const SizedBox(height: 10),
        Text(action.name, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(action.cue, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17)),
        const SizedBox(height: 10),
        Text('HOLD: ${requested.map((p) => '${p.label} (${p.keyHint})').join(' + ')}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, color: kTeal,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: (_held / _target).clamp(0, 1), minHeight: 16),
        const SizedBox(height: 5),
        Text('${_held.toStringAsFixed(1)} / ${_target.toStringAsFixed(1)} seconds'),
        const SizedBox(height: 7),
        Text(_message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        _board(requested.toSet()),
        const SizedBox(height: 12),
        TextButton(onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End session')),
      ])),
    );
  }

  Widget _board(Set<CookingPosition> requested) => Column(children: [
    Row(children: [
      Expanded(child: _tile(CookingPosition.topLeft, requested)),
      const SizedBox(width: 18),
      Expanded(child: _tile(CookingPosition.topRight, requested)),
    ]),
    const SizedBox(height: 22),
    Row(children: [
      Expanded(child: _tile(CookingPosition.bottomLeft, requested)),
      const SizedBox(width: 18),
      Expanded(child: _tile(CookingPosition.bottomRight, requested)),
    ]),
  ]);

  Widget _tile(CookingPosition position, Set<CookingPosition> requested) {
    final active = requested.contains(position);
    return SizedBox(height: 90, child: PushTile(
      cell: position.cell,
      input: input,
      style: TileStyle(
        bg: active ? const Color(0xFFD9F3ED) : const Color(0xFFEBF4F5),
        border: active ? kTeal : Colors.grey,
        borderWidth: active ? 5 : 2,
        label: '${position.label}\n(${position.keyHint})',
        labelColor: active ? kTeal : Colors.black54,
      ),
    ));
  }

  Widget _result() => ListView(padding: const EdgeInsets.all(22), children: [
    Text(_early ? 'Session ended' : '🍽️ Dish complete!',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
    const SizedBox(height: 14),
    Text('${_recipe.emoji} ${_recipe.name}', textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24)),
    const SizedBox(height: 20),
    Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      _metric('Steps completed', '$_completed/${_recipe.actions.length}'),
      const Divider(),
      _metric('Interrupted holds', '$_interruptions'),
      const Divider(),
      _metric('Total time', '${_elapsed.toStringAsFixed(1)} s'),
      const Divider(),
      _metric('Difficulty', _difficulty.label),
    ]))),
    const SizedBox(height: 12),
    const Text('Saved to My Progress', textAlign: TextAlign.center),
    const SizedBox(height: 20),
    FilledButton(onPressed: () => setState(() => _phase = _CookingPhase.menu),
        child: const Text('Choose another recipe')),
    OutlinedButton(onPressed: () => Navigator.pop(context),
        child: const Text('Back to Home')),
  ]);

  Widget _metric(String name, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [Text(name), Text(value,
        style: const TextStyle(fontWeight: FontWeight.bold))],
  );
}
