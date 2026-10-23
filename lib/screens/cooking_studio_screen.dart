import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum CookingHand { left, right, both }

class CookingTask {
  final String name, cue, emoji;
  final CookingHand hand;
  final double seconds;
  const CookingTask(this.name, this.cue, this.emoji, this.hand, this.seconds);
}

class CookingDish {
  final String cuisine, name, emoji;
  final List<CookingTask> tasks;
  const CookingDish(this.cuisine, this.name, this.emoji, this.tasks);
}

const dishes = <CookingDish>[
  CookingDish('Japanese', 'Ramen', '🍜', [
    CookingTask('Prepare vegetables', 'Hold LEFT to prepare vegetables', '🥬', CookingHand.left, 3),
    CookingTask('Stir broth', 'Hold RIGHT to stir broth', '🥣', CookingHand.right, 4),
    CookingTask('Steady and stir', 'Hold BOTH: left steadies the bowl, right stirs', '🍲', CookingHand.both, 4),
    CookingTask('Add noodles', 'Hold LEFT to add noodles', '🍜', CookingHand.left, 3),
    CookingTask('Plate ramen', 'Hold BOTH to plate the dish', '✨', CookingHand.both, 3),
  ]),
  CookingDish('Italian', 'Tomato Pasta', '🍝', [
    CookingTask('Prepare tomatoes', 'Hold RIGHT to prepare tomatoes', '🍅', CookingHand.right, 3),
    CookingTask('Steady ingredients', 'Hold BOTH to steady and prepare ingredients', '🥗', CookingHand.both, 4),
    CookingTask('Mix sauce', 'Hold LEFT to mix sauce', '🥫', CookingHand.left, 4),
    CookingTask('Combine pasta', 'Hold RIGHT to combine pasta and sauce', '🍝', CookingHand.right, 4),
    CookingTask('Plate pasta', 'Hold BOTH to plate pasta', '✨', CookingHand.both, 3),
  ]),
  CookingDish('Chinese', 'Fried Rice', '🍚', [
    CookingTask('Prepare vegetables', 'Hold LEFT to prepare vegetables', '🥕', CookingHand.left, 3),
    CookingTask('Mix ingredients', 'Hold RIGHT to mix ingredients', '🥣', CookingHand.right, 3),
    CookingTask('Steady pan and stir', 'Hold BOTH: left steadies pan, right stirs', '🍳', CookingHand.both, 5),
    CookingTask('Add seasoning', 'Hold LEFT to add seasoning', '🧂', CookingHand.left, 3),
    CookingTask('Serve rice', 'Hold BOTH to serve rice', '🍚', CookingHand.both, 3),
  ]),
  CookingDish('Mexican', 'Tacos', '🌮', [
    CookingTask('Prepare lettuce', 'Hold RIGHT to prepare lettuce', '🥬', CookingHand.right, 3),
    CookingTask('Mix salsa', 'Hold LEFT to mix salsa', '🍅', CookingHand.left, 4),
    CookingTask('Fill taco', 'Hold BOTH to steady the shell and add filling', '🌮', CookingHand.both, 4),
    CookingTask('Add toppings', 'Hold RIGHT to add toppings', '🧀', CookingHand.right, 3),
    CookingTask('Serve tacos', 'Hold BOTH to serve tacos', '✨', CookingHand.both, 3),
  ]),
  CookingDish('Indian', 'Vegetable Curry', '🍛', [
    CookingTask('Prepare vegetables', 'Hold LEFT to prepare vegetables', '🥔', CookingHand.left, 3),
    CookingTask('Add spices', 'Hold RIGHT to add spices', '🧂', CookingHand.right, 3),
    CookingTask('Steady pot and stir', 'Hold BOTH: left steadies pot, right stirs', '🍲', CookingHand.both, 5),
    CookingTask('Mix curry', 'Hold RIGHT to mix curry', '🥘', CookingHand.right, 4),
    CookingTask('Plate curry', 'Hold BOTH to plate curry', '🍛', CookingHand.both, 3),
  ]),
];

enum _Phase { menu, playing, finished }

class CookingStudioScreen extends StatefulWidget {
  const CookingStudioScreen({super.key});
  @override
  State<CookingStudioScreen> createState() => _CookingStudioScreenState();
}

class _CookingStudioScreenState extends State<CookingStudioScreen> {
  static const left = 3, right = 5; // G and J in push_input.dart
  final PushController input = PushController();
  Timer? _timer;
  DateTime? _previous;
  _Phase _phase = _Phase.menu;
  Difficulty _difficulty = Difficulty.easy;
  CookingDish _dish = dishes.first;
  int _index = 0, _completed = 0, _interruptions = 0;
  double _held = 0, _elapsed = 0;
  bool _early = false, _wasHolding = false;
  String _message = '';

  CookingTask get _task => _dish.tasks[_index];
  double get _target => _task.seconds * switch (_difficulty) {
    Difficulty.easy => 0.7,
    Difficulty.medium => 1.0,
    Difficulty.hard => 1.3,
  };

  @override
  void initState() {
    super.initState();
    input.allowed = const [left, right];
    input.addListener(_refresh);
  }

  void _refresh() {
    if (mounted && _phase == _Phase.playing) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    input.removeListener(_refresh);
    input.dispose();
    super.dispose();
  }

  bool get _correct {
    final l = input.isDown(left), r = input.isDown(right);
    return switch (_task.hand) {
      CookingHand.left => l && !r,
      CookingHand.right => r && !l,
      CookingHand.both => l && r,
    };
  }

  void _start(CookingDish dish) {
    _timer?.cancel();
    input.clear();
    trainingStarted = true;
    setState(() {
      _dish = dish;
      _phase = _Phase.playing;
      _index = _completed = _interruptions = 0;
      _held = _elapsed = 0;
      _early = _wasHolding = false;
      _message = 'Follow the cue and hold the correct tile(s).';
      _previous = DateTime.now();
    });
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _phase != _Phase.playing) return;
    final now = DateTime.now();
    final delta = now.difference(_previous ?? now).inMicroseconds / 1000000;
    _previous = now;
    setState(() {
      _elapsed += delta;
      if (_correct) {
        _wasHolding = true;
        _held += delta;
        _message = 'Great! Keep holding.';
        if (_held >= _target) {
          _completed++;
          _index++;
          _held = 0;
          _wasHolding = false;
          input.clear();
          _message = 'Step complete! Follow the next cue.';
          if (_index >= _dish.tasks.length) _finish();
        }
      } else if (_wasHolding) {
        _interruptions++;
        _held = 0;
        _wasHolding = false;
        _message = 'Hold interrupted. Try again.';
      }
    });
  }

  void _finish({bool early = false}) {
    if (_phase != _Phase.playing) return;
    _timer?.cancel();
    input.clear();
    _phase = _Phase.finished;
    _early = early;
    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Cooking Studio - ${_dish.name}',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: _elapsed.round(),
      correctAttempts: _completed,
      incorrectAttempts: _interruptions,
      completed: !early,
      notes: '${_dish.cuisine} | ${_dish.name} | '
          '$_completed/${_dish.tasks.length} tasks | $_interruptions interruptions',
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rehab Cooking Studio')),
    body: SafeArea(child: PushKeyboard(
      controller: input,
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: switch (_phase) {
          _Phase.menu => _menu(),
          _Phase.playing => _game(),
          _Phase.finished => _result(),
        },
      )),
    )),
  );

  Widget _menu() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('🍳 Rehab Cooking Studio', textAlign: TextAlign.center,
      style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12),
    const Text('Cook virtual dishes by holding LEFT, RIGHT, or BOTH tiles. '
      'All activities are simulated; no real utensils are needed.',
      textAlign: TextAlign.center),
    const SizedBox(height: 18),
    chipRow<Difficulty>(title: 'Hold duration', values: Difficulty.values,
      selected: _difficulty, label: (d) => d.label,
      onSelected: (d) => setState(() => _difficulty = d)),
    const SizedBox(height: 18),
    const Text('Choose a cuisine', style: TextStyle(fontSize: 20,
      fontWeight: FontWeight.bold)),
    for (final dish in dishes)
      Card(child: ListTile(
        leading: Text(dish.emoji, style: const TextStyle(fontSize: 34)),
        title: Text('${dish.cuisine} — ${dish.name}'),
        subtitle: Text('${dish.tasks.length} cooking tasks'),
        trailing: const Icon(Icons.play_arrow),
        onTap: () => _start(dish),
      )),
    const SizedBox(height: 12),
    const Text('Keyboard controls: G = LEFT, J = RIGHT. '
      'You can also hold the on-screen tiles. Use comfortable hold times.',
      style: TextStyle(color: Colors.black54)),
  ]);

  Widget _game() {
    final task = _task;
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Text('${_dish.emoji} ${_dish.name}',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      LinearProgressIndicator(value: _completed / _dish.tasks.length, minHeight: 8),
      const SizedBox(height: 8),
      Text('Step ${_index + 1} of ${_dish.tasks.length}'),
      const Spacer(),
      Text(task.emoji, style: const TextStyle(fontSize: 78)),
      Text(task.name, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Text(task.cue, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18)),
      const SizedBox(height: 12),
      Text(switch (task.hand) {
        CookingHand.left => 'HOLD LEFT (G)',
        CookingHand.right => 'HOLD RIGHT (J)',
        CookingHand.both => 'HOLD BOTH (G + J)',
      }, style: const TextStyle(fontSize: 20, color: kTeal,
        fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      LinearProgressIndicator(value: (_held / _target).clamp(0, 1), minHeight: 18),
      const SizedBox(height: 6),
      Text('${_held.toStringAsFixed(1)} / ${_target.toStringAsFixed(1)} seconds'),
      const SizedBox(height: 10),
      Text(_message, textAlign: TextAlign.center),
      const Spacer(),
      Row(children: [
        Expanded(child: _tile(left, 'LEFT', task.hand != CookingHand.right)),
        const SizedBox(width: 12),
        Expanded(child: _tile(right, 'RIGHT', task.hand != CookingHand.left)),
      ]),
      const SizedBox(height: 14),
      TextButton(onPressed: () => setState(() => _finish(early: true)),
        child: const Text('End session')),
    ]));
  }

  Widget _tile(int cell, String label, bool active) => SizedBox(height: 110,
    child: PushTile(cell: cell, input: input, style: TileStyle(
      bg: const Color(0xFFEBF4F5),
      border: active ? kTeal : Colors.grey,
      borderWidth: active ? 5 : 2,
      label: label, labelColor: kTeal,
    )));

  Widget _result() => ListView(padding: const EdgeInsets.all(22), children: [
    Text(_early ? 'Session ended' : '🍽️ Dish complete!',
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
    const SizedBox(height: 14),
    Text('${_dish.emoji} ${_dish.name}', textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24)),
    const SizedBox(height: 20),
    Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      _metric('Steps completed', '$_completed/${_dish.tasks.length}'),
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
    FilledButton(onPressed: () => setState(() => _phase = _Phase.menu),
      child: const Text('Choose another recipe')),
    OutlinedButton(onPressed: () => Navigator.pop(context),
      child: const Text('Back to Home')),
  ]);

  Widget _metric(String name, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [Text(name), Text(value,
      style: const TextStyle(fontWeight: FontWeight.bold))]);
}
