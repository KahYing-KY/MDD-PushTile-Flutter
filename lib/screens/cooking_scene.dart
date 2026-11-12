import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lightweight, dependency-free first-person cooking scene.
/// progress is the cumulative fraction of the current cooking action.
class CookingScene extends StatelessWidget {
  final String taskName;
  final String dishName;
  final double progress;
  final double motion;
  final bool leftDown;
  final bool rightDown;
  final bool reducedMotion;
  final int completedSteps;

  const CookingScene({
    super.key,
    required this.taskName,
    required this.dishName,
    required this.progress,
    required this.motion,
    required this.leftDown,
    required this.rightDown,
    required this.completedSteps,
    this.reducedMotion = false,
  });

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1.5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: CustomPaint(
            painter: _KitchenPainter(
              taskName.toLowerCase(),
              dishName.toLowerCase(),
              progress.clamp(0.0, 1.0),
              reducedMotion ? 0 : motion,
              leftDown,
              rightDown,
              completedSteps,
            ),
          ),
        ),
      );
}

class _KitchenPainter extends CustomPainter {
  final String task, dish;
  final double progress, phase;
  final bool left, right;
  final int completed;

  _KitchenPainter(
    this.task,
    this.dish,
    this.progress,
    this.phase,
    this.left,
    this.right,
    this.completed,
  );

  void oval(Canvas c, Rect r, Color color, {double stroke = 0}) {
    c.drawOval(
      r,
      Paint()
        ..color = color
        ..style = stroke > 0 ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = stroke,
    );
  }

  void rect(Canvas c, Rect r, Color color, {double radius = 0}) {
    c.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  void line(Canvas c, Offset a, Offset b, Color color, double width) {
    c.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void hand(Canvas c, Offset wrist, Offset tip, bool active) {
    final skin = active ? const Color(0xFFE6A87B) : const Color(0xFFD7A080);
    line(c, wrist.translate(3, 5), tip.translate(3, 5), const Color(0x44000000), 22);
    line(c, wrist, tip, skin, 20);
    oval(c, Rect.fromCircle(center: tip, radius: 13), skin);
    oval(c, Rect.fromCircle(center: tip.translate(-3, -3), radius: 4), const Color(0x55FFF0CF));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 600, size.height / 400);
    final c = canvas;

    rect(c, const Rect.fromLTWH(0, 0, 600, 400), const Color(0xFFF1E4CE));
    rect(c, const Rect.fromLTWH(0, 0, 600, 64), const Color(0xFFB7D5CE));
    rect(c, const Rect.fromLTWH(0, 58, 600, 342), const Color(0xFFD5A77E));

    for (var i = 0; i < 7; i++) {
      line(c, Offset(i * 105.0 - 30, 65), Offset(i * 105.0 - 75, 400), const Color(0x1A6B3D1E), 2);
    }

    rect(c, const Rect.fromLTWH(20, 20, 124, 30), const Color(0xFFF7F7EE), radius: 8);
    final tp = TextPainter(
      text: const TextSpan(
        text: 'REHAB KITCHEN',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF376E68)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, const Offset(31, 26));

    final isChop = task.contains('prepare') || task.contains('steady ingredients');
    final isPlate = task.contains('plate') || task.contains('serve');
    final isAdd = task.contains('add') || task.contains('fill') || task.contains('topping');
    final isStir = !isChop && !isPlate && !isAdd;
    final wiggle = math.sin(phase * math.pi * 2);
    final action = left || right;
    final amount = progress;

    if (isChop) {
      rect(c, const Rect.fromLTWH(116, 125, 370, 220), const Color(0x40000000), radius: 25);
      rect(c, const Rect.fromLTWH(112, 117, 370, 220), const Color(0xFFF3D29B), radius: 25);
      rect(c, const Rect.fromLTWH(128, 133, 338, 188), const Color(0xFFDBB57F), radius: 16);
      oval(c, const Rect.fromLTWH(425, 257, 23, 23), const Color(0xFFF3D29B));

      final tomato = dish.contains('pasta') || dish.contains('taco');
      final food = tomato ? const Color(0xFFE75241) : const Color(0xFF74AF57);
      final cut = (amount * 9).floor();

      for (var i = 0; i < 9; i++) {
        final x = 200.0 + i * 22;
        final separated = i < cut;
        oval(
          c,
          Rect.fromLTWH(
            x + (separated ? i * 1.7 : 0),
            196 + (separated ? (i.isEven ? 13 : -9) : 0),
            separated ? 15 : 26,
            62,
          ),
          food,
        );
        if (separated) {
          line(
            c,
            Offset(x + 5 + i * 1.7, 203 + (i.isEven ? 13 : -9)),
            Offset(x + 5 + i * 1.7, 248 + (i.isEven ? 13 : -9)),
            const Color(0x88FFF3C2),
            2,
          );
        }
      }

      final bladeY = action ? wiggle * 19 : 0.0;
      hand(c, const Offset(565, 380), Offset(360, 185 + bladeY), right);

      final knife = Path()
        ..moveTo(343, 183 + bladeY)
        ..lineTo(276, 215 + bladeY)
        ..lineTo(354, 230 + bladeY)
        ..close();
      c.drawPath(knife, Paint()..color = const Color(0xFFDCE5E7));
      line(c, Offset(348, 191 + bladeY), Offset(389, 173 + bladeY), const Color(0xFF4B5960), 12);
      hand(c, const Offset(35, 385), const Offset(217, 270), left);
    } else {
      oval(c, const Rect.fromLTWH(121, 108, 366, 245), const Color(0x55000000));
      oval(c, const Rect.fromLTWH(117, 101, 366, 245), const Color(0xFF343D43));
      oval(c, const Rect.fromLTWH(137, 117, 326, 214), const Color(0xFF78858A));
      oval(
        c,
        const Rect.fromLTWH(152, 130, 296, 186),
        isPlate ? const Color(0xFFF9F3E4) : const Color(0xFFD98945),
      );

      if (!isPlate) {
        oval(
          c,
          const Rect.fromLTWH(161, 139, 277, 169),
          dish.contains('curry')
              ? const Color(0xFFE2B13D)
              : dish.contains('ramen')
                  ? const Color(0xFFB9854E)
                  : const Color(0xFFE6A452),
        );
      }

      final count = 6 + (amount * 12).floor() + completed * 2;
      for (var i = 0; i < count; i++) {
        final a = i * 2.399 + (isStir && action ? phase * 0.9 : 0);
        final radius = 18.0 + math.sqrt(i / (count + 1)) * 110;
        final x = 300 + math.cos(a) * radius;
        final y = 222 + math.sin(a) * radius * 0.57;
        final colors = [
          const Color(0xFF70A94B),
          const Color(0xFFEA5E42),
          const Color(0xFFF6D889),
          const Color(0xFFB5D077),
        ];
        oval(c, Rect.fromCircle(center: Offset(x, y), radius: 7 + i % 4.0), colors[i % colors.length]);
      }

      if (isStir) {
        final double x = 296.0 + (action ? wiggle * 45 : 0.0);
        final double y = 213.0 + (action ? math.cos(phase * math.pi * 2) * 22 : 0.0);
        hand(c, const Offset(565, 388), Offset(x + 35, y - 48), right);
        line(c, Offset(x + 30, y - 42), Offset(x, y + 5), const Color(0xFF9CAEB0), 10);
        oval(c, Rect.fromCircle(center: Offset(x, y + 9), radius: 19), const Color(0xFFCAD6D4));
        hand(c, const Offset(20, 380), const Offset(160, 255), left);
      } else if (isAdd) {
        hand(c, const Offset(565, 380), Offset(365 + (action ? wiggle * 10 : 0), 117), right);
        rect(c, Rect.fromLTWH(330, 75 + (action ? wiggle * 8 : 0), 75, 55), const Color(0xFFE9EFE7), radius: 9);
        for (var i = 0; i < (amount * 12).floor(); i++) {
          final x = 310.0 + (i % 5) * 13;
          final y = 148.0 + (i * 19 % 62);
          oval(c, Rect.fromCircle(center: Offset(x, y), radius: 4), const Color(0xFF6D9B4B));
        }
        hand(c, const Offset(22, 380), const Offset(180, 267), left);
      } else {
        hand(c, const Offset(25, 390), Offset(235, 253 - (action ? wiggle * 8 : 0)), left);
        hand(c, const Offset(575, 390), Offset(372, 253 + (action ? wiggle * 8 : 0)), right);
        oval(c, Rect.fromLTWH(215, 184, 170 * amount, 74), const Color(0x88E5AD56));
      }

      if (action && !isPlate) {
        for (var i = 0; i < 3; i++) {
          final rise = (phase + i / 3) % 1;
          oval(
            c,
            Rect.fromCircle(center: Offset(240 + i * 55.0, 125 - rise * 50), radius: 8 * (1 - rise)),
            const Color(0x77FFFFFF),
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KitchenPainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.left != left ||
      old.right != right ||
      old.task != task ||
      old.dish != dish ||
      old.completed != completed;
}