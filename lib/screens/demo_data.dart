import 'dart:math';
import 'training_session.dart';
import 'training_history_service.dart';

/// TESTING ONLY. Adds about three weeks of fake sessions whose accuracy
/// slowly improves, so you can see how the progress screen looks.
/// Delete this file (and its uses in progress_screen.dart) before real use.
void loadDemoSessions() {
  final service = TrainingHistoryService.instance;
  final rnd = Random(7); // fixed seed = same demo data every time
  final now = DateTime.now();

  const activities = [
    'Warm-Up',
    'Rhythm Game',
    'Tic-Tac-Toe',
    'Hold & Reach',
    'Cool-Down',
  ];

  var id = 0;
  for (var daysAgo = 20; daysAgo >= 0; daysAgo--) {
    // Skip some days so there are rest days (but always train today).
    if (daysAgo > 0 && rnd.nextInt(10) < 3) continue;

    final progress = (20 - daysAgo) / 20; // 0.0 (oldest) to 1.0 (today)
    final sessionsToday = 1 + rnd.nextInt(2);

    for (var i = 0; i < sessionsToday; i++) {
      const attempts = 10;
      const presses = 20;

      final correct = (attempts *
              (0.45 + 0.4 * progress + (rnd.nextDouble() - 0.5) * 0.15))
          .round()
          .clamp(0, attempts)
          .toInt();

      final full = (presses *
              (0.35 + 0.4 * progress + (rnd.nextDouble() - 0.5) * 0.15))
          .round()
          .clamp(0, presses)
          .toInt();
      final half = ((presses - full) * 0.6).round();
      final none = presses - full - half;

      final date = DateTime(now.year, now.month, now.day - daysAgo,
          9 + i * 4, rnd.nextInt(60));

      service.addSession(TrainingSession(
        id: 'demo-${id++}',
        activity: activities[rnd.nextInt(activities.length)],
        date: date,
        difficulty: 'Level ${1 + (progress * 2).floor()}',
        durationSeconds: 120 + rnd.nextInt(240),
        correctAttempts: correct,
        incorrectAttempts: attempts - correct,
        fullPresses: full,
        halfPresses: half,
        noPresses: none,
        completed: rnd.nextInt(10) > 0,
      ));
    }
  }
}
