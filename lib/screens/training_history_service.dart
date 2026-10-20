import 'package:flutter/foundation.dart';
import 'training_session.dart';

class TrainingHistoryService extends ChangeNotifier {
  TrainingHistoryService._();

  static final TrainingHistoryService instance = TrainingHistoryService._();

  final List<TrainingSession> _sessions = [];

  List<TrainingSession> get sessions {
    final result = List<TrainingSession>.from(_sessions);
    result.sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(result);
  }

  void addSession(TrainingSession session) {
    _sessions.add(session);
    notifyListeners();
  }

  void clearHistory() {
    _sessions.clear();
    notifyListeners();
  }
}