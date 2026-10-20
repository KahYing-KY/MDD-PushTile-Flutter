import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ===========================================================================
// Colours used by press feedback
// ===========================================================================
const Color kFullColor = Color(0xFF2E9E5B);
const Color kHalfColor = Color(0xFFF2A33A);
const Color kNoneColor = Color(0xFF8A939B);

// ===========================================================================
// Shared enums
// ===========================================================================
enum Difficulty { easy, medium, hard }

extension DifficultyLabel on Difficulty {
  String get label => name[0].toUpperCase() + name.substring(1);
}

enum BoardMode { row, grid }

extension BoardModeInfo on BoardMode {
  String get label => this == BoardMode.row ? '1 x 3' : '3 x 3';

  /// Board cells (0..8, row-major) used by this mode.
  /// 1x3 uses the MIDDLE row (G H J).
  List<int> get cells => this == BoardMode.row
      ? const [3, 4, 5]
      : const [0, 1, 2, 3, 4, 5, 6, 7, 8];
}

// ===========================================================================
// Hold rules (hold time = virtual flap angle)
// ===========================================================================
enum PressResult { none, half, full }

class PushConfig {
  static bool practice = false;

  static const double normalHalf = 2.5;
  static const double normalFull = 5.0;

  static double get halfSec => practice ? 1.0 : normalHalf;
  static double get fullSec => practice ? 2.0 : normalFull;
  static double get scale => fullSec / normalFull;

  static const double maxAngle = 40.0;
  static const double tileTimeoutSec = 20.0;
  static const int maxTries = 3;
}

PressResult classifyHold(double seconds) {
  if (seconds >= PushConfig.fullSec) return PressResult.full;
  if (seconds >= PushConfig.halfSec) return PressResult.half;
  return PressResult.none;
}

double angleForHold(double seconds) =>
    (seconds / PushConfig.fullSec).clamp(0.0, 1.0) * PushConfig.maxAngle;

class PressStats {
  int full = 0, half = 0, none = 0;

  void add(PressResult r) {
    switch (r) {
      case PressResult.full:
        full++;
        break;
      case PressResult.half:
        half++;
        break;
      case PressResult.none:
        none++;
        break;
    }
  }

  void reset() {
    full = 0;
    half = 0;
    none = 0;
  }

  int get total => full + half + none;
}

// ===========================================================================
// Keyboard mapping  (cells 0..8, row-major)
//   T Y U
//   G H J
//   V B N
// ===========================================================================
const List<String> kKeyLabels = ['T', 'Y', 'U', 'G', 'H', 'J', 'V', 'B', 'N'];

final List<LogicalKeyboardKey> kTileKeys = [
  LogicalKeyboardKey.keyT,
  LogicalKeyboardKey.keyY,
  LogicalKeyboardKey.keyU,
  LogicalKeyboardKey.keyG,
  LogicalKeyboardKey.keyH,
  LogicalKeyboardKey.keyJ,
  LogicalKeyboardKey.keyV,
  LogicalKeyboardKey.keyB,
  LogicalKeyboardKey.keyN,
];

// ===========================================================================
// Controller: tracks which tiles are held and for how long
// (keyboard now; an ESP32 sensor can call press()/release() later)
// ===========================================================================
class PushController extends ChangeNotifier {
  void Function(int cell)? onDown;
  void Function(int cell, double seconds)? onUp;

  List<int> allowed = const [0, 1, 2, 3, 4, 5, 6, 7, 8];
  final Map<int, Stopwatch> _down = {};
  Timer? _timer;

  PushController() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_down.isNotEmpty) notifyListeners();
    });
  }

  bool isDown(int cell) => _down.containsKey(cell);
  bool get anyDown => _down.isNotEmpty;

  double holdSeconds(int cell) {
    final sw = _down[cell];
    return sw == null ? 0 : sw.elapsedMilliseconds / 1000;
  }

  void press(int cell) {
    if (_down.containsKey(cell) || !allowed.contains(cell)) return;
    _down[cell] = Stopwatch()..start();
    onDown?.call(cell);
    notifyListeners();
  }

  void release(int cell) {
    final sw = _down.remove(cell);
    if (sw == null) return;
    sw.stop();
    onUp?.call(cell, sw.elapsedMilliseconds / 1000);
    notifyListeners();
  }

  /// Forget all held tiles without firing callbacks.
  void clear() {
    _down.clear();
    notifyListeners();
  }

  bool handleKey(KeyEvent e) {
    final i = kTileKeys.indexOf(e.logicalKey);
    if (i < 0) return false;
    if (e is KeyDownEvent) {
      press(i);
    } else if (e is KeyUpEvent) {
      release(i);
    }
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class PushKeyboard extends StatelessWidget {
  final PushController controller;
  final Widget child;
  const PushKeyboard({super.key, required this.controller, required this.child});

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => controller.handleKey(event)
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: child,
    );
  }
}

// ===========================================================================
// Tile + board widgets
// ===========================================================================
class TileStyle {
  final Color bg;
  final Color border;
  final double borderWidth;
  final String? label;
  final Color labelColor;
  final Widget? overlay;

  const TileStyle({
    this.bg = Colors.white,
    this.border = const Color(0xFFCFD8DC),
    this.borderWidth = 2,
    this.label,
    this.labelColor = const Color(0xFF1A1F22),
    this.overlay,
  });
}

class PushTile extends StatelessWidget {
  final int cell;
  final PushController input;
  final TileStyle style;

  const PushTile({
    super.key,
    required this.cell,
    required this.input,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: input,
      builder: (context, _) {
        final down = input.isDown(cell);
        final held = input.holdSeconds(cell);
        final frac = down ? (held / PushConfig.fullSec).clamp(0.0, 1.0) : 0.0;
        final res = classifyHold(held);
        final fill = res == PressResult.full
            ? kFullColor
            : (res == PressResult.half ? kHalfColor : kNoneColor);

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => input.press(cell),
          onPointerUp: (_) => input.release(cell),
          onPointerCancel: (_) => input.release(cell),
          child: LayoutBuilder(builder: (context, c) {
            final m = min(c.maxWidth, c.maxHeight);
            return Container(
              decoration: BoxDecoration(
                color: style.bg,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: style.border, width: style.borderWidth),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: frac,
                        widthFactor: 1,
                        child: ColoredBox(color: fill.withValues(alpha: 0.5)),
                      ),
                    ),
                    // half-press marker
                    Align(
                      alignment: Alignment.center,
                      child: Container(height: 1.5, color: Colors.black12),
                    ),
                    if (style.overlay != null)
                      Positioned.fill(child: IgnorePointer(child: style.overlay!)),
                    if (style.label != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              style.label!,
                              style: TextStyle(
                                fontSize: m * 0.32,
                                fontWeight: FontWeight.bold,
                                color: style.labelColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 4,
                      left: 8,
                      child: Text(
                        kKeyLabels[cell],
                        style: TextStyle(
                          fontSize: max(11.0, m * 0.13),
                          fontWeight: FontWeight.bold,
                          color: style.labelColor.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    if (down)
                      Positioned(
                        bottom: 4,
                        right: 8,
                        child: Text(
                          '${angleForHold(held).round()}°',
                          style: TextStyle(
                            fontSize: max(11.0, m * 0.13),
                            fontWeight: FontWeight.bold,
                            color: style.labelColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class PushBoard extends StatelessWidget {
  final BoardMode mode;
  final PushController input;
  final TileStyle Function(int cell) styleOf;

  const PushBoard({
    super.key,
    required this.mode,
    required this.input,
    required this.styleOf,
  });

  @override
  Widget build(BuildContext context) {
    if (mode == BoardMode.row) {
      return LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final h = min(w / 3, c.maxHeight.isFinite ? c.maxHeight : w / 3);
        return Center(
          child: SizedBox(
            height: h,
            child: Row(
              children: [
                for (final cell in mode.cells)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: PushTile(
                          cell: cell, input: input, style: styleOf(cell)),
                    ),
                  ),
              ],
            ),
          ),
        );
      });
    }

    return LayoutBuilder(builder: (context, c) {
      final side =
          min(c.maxWidth, c.maxHeight.isFinite ? c.maxHeight : c.maxWidth);
      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: Column(
            children: [
              for (var r = 0; r < 3; r++)
                Expanded(
                  child: Row(
                    children: [
                      for (var col = 0; col < 3; col++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: PushTile(
                              cell: r * 3 + col,
                              input: input,
                              style: styleOf(r * 3 + col),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

// ===========================================================================
// Small shared UI helpers
// ===========================================================================
Widget chipRow<T>({
  required String title,
  required List<T> values,
  required T selected,
  required String Function(T) label,
  required ValueChanged<T> onSelected,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: values
            .map((v) => ChoiceChip(
                  label: Text(label(v)),
                  selected: v == selected,
                  onSelected: (_) => onSelected(v),
                ))
            .toList(),
      ),
    ],
  );
}

Widget practiceSwitch(bool value, ValueChanged<bool> onChanged) {
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('Practice mode'),
    subtitle: const Text(
        'Shorter holds for testing with a keyboard (1 s half, 2 s full).'),
    value: value,
    onChanged: onChanged,
  );
}

String pressRulesText() {
  final h = PushConfig.halfSec.toStringAsFixed(1);
  final f = PushConfig.fullSec.toStringAsFixed(1);
  return 'Under $h s = no press   •   $h to $f s = half press   •   '
      '$f s or more = full press.\n'
      'Keys: 1x3 uses G H J.  3x3 uses T Y U / G H J / V B N.  '
      'You can also hold a tile with the mouse or your finger.';
}

Widget _statChip(String label, int n, Color color, bool dark) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color),
    ),
    child: Text('$label $n',
        style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: dark ? Colors.white : const Color(0xFF1A1F22))),
  );
}

Widget pressStatsBar(PressStats s, {bool dark = false}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _statChip('Full', s.full, kFullColor, dark),
      _statChip('Half', s.half, kHalfColor, dark),
      _statChip('No press', s.none, kNoneColor, dark),
    ],
  );
}