class TrainingSession {
  final String id;
  final String activity;
  final DateTime date;
  final String difficulty;
  final int durationSeconds;
  final int correctAttempts;
  final int incorrectAttempts;

  // Press depth tracking (hold time = virtual flap angle)
  final int fullPresses;
  final int halfPresses;
  final int noPresses; // pressed but under the half-press time

  final bool completed;
  final String notes;

  const TrainingSession({
    required this.id,
    required this.activity,
    required this.date,
    required this.difficulty,
    required this.durationSeconds,
    this.correctAttempts = 0,
    this.incorrectAttempts = 0,
    this.fullPresses = 0,
    this.halfPresses = 0,
    this.noPresses = 0,
    required this.completed,
    this.notes = '',
  });

  int get totalAttempts => correctAttempts + incorrectAttempts;
  bool get hasAccuracy => totalAttempts > 0;

  double get accuracy {
    if (totalAttempts == 0) return 0;
    return correctAttempts / totalAttempts * 100;
  }

  int get totalPresses => fullPresses + halfPresses + noPresses;
  bool get hasPresses => totalPresses > 0;
}