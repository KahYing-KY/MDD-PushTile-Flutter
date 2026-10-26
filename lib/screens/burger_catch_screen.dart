import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

enum _Phase { setup, playing, done }

class _Ingredient {
  final String name;
  final String emoji;
  const _Ingredient(this.name, this.emoji);
}

const _ingredients = [
  _Ingredient('Lettuce', '🥬'),
  _Ingredient('Tomato', '🍅'),
  _Ingredient('Cheese', '🧀'),
  _Ingredient('Patty', '🥩'),
  _Ingredient('Pickle', '🥒'),
];

class BurgerCatchScreen extends StatefulWidget {
  const BurgerCatchScreen({super.key});

  @override
  State<BurgerCatchScreen> createState() => _BurgerCatchScreenState();
}

class _BurgerCatchScreenState extends State<BurgerCatchScreen>
    with SingleTickerProviderStateMixin {
  static const _cells = [3, 5]; // G, J
  final input = PushController();
  final _rng = Random();
  final _stats = PressStats();
  late final Ticker _ticker;

  _Phase _phase = _Phase.setup;
  Difficulty _difficulty = Difficulty.easy;
  late List<_Ingredient> _order;
  final List<_Ingredient> _stack = [];

  int _index = 0, _lane = 0, _bunLane = 0, _caught = 0, _missed = 0;
  int _score = 0, _moves = 0;
  double _time = 0, _spawnAt = 0;
  bool _early = false;

  String _message = '';
  Color _messageColor = Colors.white;

  double get _fallSeconds => switch (_difficulty) {
        Difficulty.easy => 5.0,
        Difficulty.medium => 3.5,
        Difficulty.hard => 2.5,
      };

  int get _orderLength => switch (_difficulty) {
        Difficulty.easy => 4,
        Difficulty.medium => 6,
        Difficulty.hard => 8,
      };

  double get _progress => ((_time - _spawnAt) / _fallSeconds).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    input.allowed = _cells;
    input.onDown = _onPress;
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    input.dispose();
    super.dispose();
  }

  void _start() {
    trainingStarted = true;
    if (_ticker.isActive) _ticker.stop();
    input.clear();
    setState(() {
      _order = List.generate(
        _orderLength,
        (_) => _ingredients[_rng.nextInt(_ingredients.length)],
      );
      _stack.clear();
      _index = _caught = _missed = _score = _moves = 0;
      _time = _spawnAt = 0;
      _bunLane = _rng.nextInt(2);
      _lane = _rng.nextInt(2);
      _early = false;
      _message = 'Catch ${_order.first.name}!';
      _messageColor = Colors.white;
      _stats.reset();
      _phase = _Phase.playing;
    });
    _ticker.start();
  }

  void _onPress(int cell) {
    if (_phase != _Phase.playing) return;
    final selected = _cells.indexOf(cell);
    if (selected < 0) return;

    setState(() {
      if (_bunLane != selected) _moves++;
      _bunLane = selected;
      _message = selected == 0 ? 'Bun moved LEFT' : 'Bun moved RIGHT';
      _messageColor = Colors.lightBlueAccent;
    });
  }

  void _tick(Duration elapsed) {
    if (!mounted || _phase != _Phase.playing) return;
    _time = elapsed.inMicroseconds / 1000000;

    setState(() {
      if (_progress >= 1) {
        if (_bunLane == _lane) {
          _stack.add(_order[_index]);
          _caught++;
          _score += 100;
          _stats.add(PressResult.full);
          _message = 'Caught ${_order[_index].name}! +100';
          _messageColor = Colors.greenAccent;
        } else {
          _missed++;
          _stats.add(PressResult.none);
          _message = 'Missed ${_order[_index].name}. Try the next one!';
          _messageColor = Colors.orangeAccent;
        }

        _index++;
        if (_index >= _order.length) {
          _finish();
        } else {
          _spawnAt = _time + 0.6;
          _lane = _rng.nextInt(2);
        }
      }
    });
  }

  void _finish({bool early = false}) {
    if (_phase != _Phase.playing) return;
    _ticker.stop();
    input.clear();
    _early = early;
    _phase = _Phase.done;

    TrainingHistoryService.instance.addSession(TrainingSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      activity: 'Burger Catch (2 Tiles)',
      date: DateTime.now(),
      difficulty: _difficulty.label,
      durationSeconds: _time.round(),
      correctAttempts: _caught,
      incorrectAttempts: _missed,
      fullPresses: _stats.full,
      halfPresses: _stats.half,
      noPresses: _stats.none,
      completed: !early,
      notes: 'Score $_score | catches $_caught/${_order.length} | '
          'lane changes $_moves | misses $_missed',
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Burger Catch')),
        body: SafeArea(
          child: PushKeyboard(
            controller: input,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: switch (_phase) {
                  _Phase.setup => _setup(),
                  _Phase.playing => _play(),
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
          const Icon(Icons.lunch_dining, size: 72, color: kTeal),
          const Text('Burger Catch 🍔',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
            'Build a burger! The order panel shows the next ingredient. '
            'Move your bun to the LEFT (G) or RIGHT (J) tile to catch '
            'the falling ingredient. Catch each one before it reaches the bottom.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 20),
          chipRow<Difficulty>(
            title: 'Difficulty',
            values: Difficulty.values,
            selected: _difficulty,
            label: (d) => d.label,
            onSelected: (d) => setState(() => _difficulty = d),
          ),
          const SizedBox(height: 12),
          Text('Fall time: ${_fallSeconds.toStringAsFixed(1)} seconds • '
              'Ingredients: $_orderLength'),
          const SizedBox(height: 12),
          const Text('Controls: G = LEFT, J = RIGHT. Tap a tile to move the bun.',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _start,
            style: FilledButton.styleFrom(
              backgroundColor: kTeal,
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Start Game', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to Home'),
          ),
        ],
      );

  Widget _play() {
    final ingredient = _order[_index];
    final p = _progress;

    return Container(
      color: const Color(0xFF10182A),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Score $_score', style: const TextStyle(color: Colors.white)),
              Text('${_index + 1}/${_order.length}',
                  style: const TextStyle(color: Colors.white)),
              Text('Caught $_caught',
                  style: const TextStyle(color: Colors.greenAccent)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF26354E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text('NEXT INGREDIENT',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text('${ingredient.emoji}  ${ingredient.name}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(_message,
              textAlign: TextAlign.center,
              style: TextStyle(color: _messageColor, fontSize: 15)),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final height = constraints.maxHeight;
              return Stack(
                children: [
                  Row(children: [
                    for (int lane = 0; lane < 2; lane++)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: lane == _bunLane
                                ? const Color(0xFF243F4C)
                                : const Color(0xFF1B2540),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                      ),
                  ]),
                  if (_time >= _spawnAt)
                    Positioned(
                      left: (_lane + 0.5) * constraints.maxWidth / 2 - 30,
                      top: (height - 125) * p,
                      child: Text(ingredient.emoji,
                          style: const TextStyle(fontSize: 56)),
                    ),
                  Positioned(
                    left: (_bunLane + 0.5) * constraints.maxWidth / 2 - 55,
                    bottom: 10,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in _stack.reversed.take(4))
                          Text(item.emoji,
                              style: const TextStyle(
                                  fontSize: 24, height: 0.9)),
                        const Text('🍞', style: TextStyle(fontSize: 58)),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 8),
          Row(children: [
            for (int lane = 0; lane < 2; lane++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: SizedBox(
                    height: 95,
                    child: PushTile(
                      cell: _cells[lane],
                      input: input,
                      style: TileStyle(
                        bg: const Color(0xFF192B40),
                        border: lane == _bunLane
                            ? Colors.greenAccent
                            : Colors.cyanAccent,
                        borderWidth: lane == _bunLane ? 4 : 2,
                        label: lane == 0 ? 'LEFT' : 'RIGHT',
                        labelColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ]),
          TextButton(
            onPressed: () => setState(() => _finish(early: true)),
            child: const Text('End session',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    final accuracy = _order.isEmpty ? 0.0 : 100 * _caught / _order.length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('🍔',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 72)),
        Text(_early ? 'Session stopped' : 'Burger complete!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              _resultRow('Score', '$_score'),
              _resultRow('Ingredients caught', '$_caught / ${_order.length}'),
              _resultRow('Catch accuracy', '${accuracy.toStringAsFixed(1)}%'),
              _resultRow('Missed ingredients', '$_missed'),
              _resultRow('Lane changes', '$_moves'),
              _resultRow('Duration', '${_time.toStringAsFixed(1)} s'),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Saved to My Progress', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => setState(() => _phase = _Phase.setup),
          style: FilledButton.styleFrom(backgroundColor: kTeal),
          child: const Text('Play Again'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to Home'),
        ),
      ],
    );
  }

  Widget _resultRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold))
            ]),
      );
}