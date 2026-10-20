import 'package:flutter/material.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  String filter = 'All';

  // activity name -> chip label
  static const Map<String, String> _filters = {
    'All': 'All',
    'Warm-Up': 'Warm-Up',
    'Interim Demo': 'Demo',
    'Rhythm Game': 'Rhythm',
    'Tic-Tac-Toe': 'Tic-Tac-Toe',
    'Hold & Reach': 'Hold & Reach',
    'Cool-Down': 'Cool-Down',
  };

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This removes all saved training sessions.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) TrainingHistoryService.instance.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final history = TrainingHistoryService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Progress'),
        actions: [
          IconButton(
            tooltip: 'Clear history',
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: history,
        builder: (context, child) {
          final sessions = history.sessions
              .where((s) => filter == 'All' || s.activity == filter)
              .toList();

          final scored = sessions.where((s) => s.hasAccuracy).toList();
          final averageAccuracy = scored.isEmpty
              ? null
              : scored.fold<double>(0, (sum, s) => sum + s.accuracy) /
                  scored.length;
          final totalSeconds =
              sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
          final full = sessions.fold<int>(0, (a, s) => a + s.fullPresses);
          final half = sessions.fold<int>(0, (a, s) => a + s.halfPresses);
          final none = sessions.fold<int>(0, (a, s) => a + s.noPresses);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Your Training History',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'Warm-ups, games, cool-downs and demos, with full, half and no-press counts.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: _metricCard('Sessions', '${sessions.length}',
                              Icons.history, kTeal)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _metricCard(
                              'Avg accuracy',
                              averageAccuracy == null
                                  ? '—'
                                  : '${averageAccuracy.toStringAsFixed(1)}%',
                              Icons.track_changes,
                              kTeal)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _metricCard('Total time',
                              _fmtDuration(totalSeconds), Icons.timer_outlined,
                              kTeal)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: _metricCard('Full presses', '$full',
                              Icons.check_circle_outline, kFullColor)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _metricCard('Half presses', '$half',
                              Icons.adjust, kHalfColor)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _metricCard('No press', '$none',
                              Icons.remove_circle_outline, kNoneColor)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _filters.entries.map((e) {
                      return ChoiceChip(
                        label: Text(e.value),
                        selected: filter == e.key,
                        onSelected: (_) => setState(() => filter = e.key),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('Session Records (${sessions.length})',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (sessions.isEmpty)
                    const Card(
                      color: Colors.white,
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.bar_chart_rounded,
                                size: 56, color: kTeal),
                            SizedBox(height: 12),
                            Text('No training sessions yet',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 17)),
                            SizedBox(height: 8),
                            Text(
                              'Complete a session and its results will appear here.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...sessions.map(_sessionCard),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String activity) {
    switch (activity) {
      case 'Interim Demo':
        return Icons.view_module;
      case 'Rhythm Game':
        return Icons.music_note_rounded;
      case 'Tic-Tac-Toe':
        return Icons.tag_rounded;
      case 'Hold & Reach':
        return Icons.back_hand_rounded;
      default:
        return Icons.flash_on_rounded;
    }
  }

  Color _colorFor(String activity) {
    switch (activity) {
      case 'Cool-Down':
        return kGreen;
      case 'Rhythm Game':
        return Colors.deepPurple;
      case 'Interim Demo':
        return Colors.orange;
      case 'Tic-Tac-Toe':
        return kTeal;
      default:
        return kBlue;
    }
  }

  Widget _sessionCard(TrainingSession session) {
    final d = session.date;
    final dateText = '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    final color = _colorFor(session.activity);

    final line1 = '$dateText  •  ${_fmtDuration(session.durationSeconds)}'
        '${session.hasAccuracy ? '  •  ${session.accuracy.toStringAsFixed(0)}%' : ''}';
    final line2 = session.hasPresses
        ? 'Full ${session.fullPresses}  •  Half ${session.halfPresses}  •  No press ${session.noPresses}'
        : null;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(_iconFor(session.activity), color: color),
        title: Text(session.activity,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(line2 == null ? line1 : '$line1\n$line2'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _detailRow('Level / board', session.difficulty),
          _detailRow('Duration', '${session.durationSeconds} seconds'),
          if (session.hasPresses) ...[
            _detailRow('Full presses', '${session.fullPresses}'),
            _detailRow('Half presses', '${session.halfPresses}'),
            _detailRow('No presses (too short)', '${session.noPresses}'),
            _detailRow('Total presses', '${session.totalPresses}'),
          ],
          if (session.hasAccuracy) ...[
            _detailRow('Successful', '${session.correctAttempts}'),
            _detailRow('Unsuccessful', '${session.incorrectAttempts}'),
            _detailRow('Accuracy', '${session.accuracy.toStringAsFixed(1)}%'),
          ],
          if (session.notes.isNotEmpty) _detailRow('Notes', session.notes),
          _detailRow(
              'Status', session.completed ? 'Completed' : 'Stopped early'),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}