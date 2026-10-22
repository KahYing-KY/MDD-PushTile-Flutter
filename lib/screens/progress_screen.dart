import 'package:flutter/material.dart';
import '../main.dart';
import 'push_input.dart';
import 'training_session.dart';
import 'training_history_service.dart';
import 'demo_data.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  // false = Patient view, true = Therapist view
  bool therapistView = false;
  String filter = 'All';
  int rangeDays = 7; // 7, 30, or 0 (= all time)

  static const List<String> _activities = [
    'All',
    'Warm-Up',
    'Interim Demo',
    'Rhythm Game',
    'Tic-Tac-Toe',
    'Hold & Reach',
    'Cool-Down',
  ];

  // ===========================================================================
  // SMALL HELPERS
  // ===========================================================================
  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _addDays(DateTime d, int n) =>
      DateTime(d.year, d.month, d.day + n);

  String _two(int n) => n.toString().padLeft(2, '0');
  String _dateText(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '${m}m ${_two(s)}s' : '${s}s';
  }

  String _dayLabel(DateTime day) {
    final today = _dayOf(DateTime.now());
    if (day == today) return 'Today';
    if (day == _addDays(today, -1)) return 'Yesterday';
    return _dateText(day);
  }

  /// Average accuracy (%) of the sessions that have accuracy, or null.
  double? _avgAccuracy(Iterable<TrainingSession> list) {
    final scored = list.where((s) => s.hasAccuracy).toList();
    if (scored.isEmpty) return null;
    return scored.fold<double>(0, (sum, s) => sum + s.accuracy) /
        scored.length;
  }

  /// Share (%) of all presses that were full presses, or null.
  double? _fullRate(Iterable<TrainingSession> list) {
    final total = list.fold<int>(0, (a, s) => a + s.totalPresses);
    if (total == 0) return null;
    final full = list.fold<int>(0, (a, s) => a + s.fullPresses);
    return full / total * 100;
  }

  /// Number of days in a row with at least one session, counting back from
  /// today (or from yesterday if the patient has not trained yet today).
  int _streak(List<TrainingSession> all) {
    final days = all.map((s) => _dayOf(s.date)).toSet();
    var day = _dayOf(DateTime.now());
    if (!days.contains(day)) day = _addDays(day, -1);
    var count = 0;
    while (days.contains(day)) {
      count++;
      day = _addDays(day, -1);
    }
    return count;
  }

  /// One point per day: the average accuracy of that day's sessions.
  List<_TrendPoint> _trendPoints(List<TrainingSession> list) {
    final Map<DateTime, List<double>> byDay = {};
    for (final s in list.where((s) => s.hasAccuracy)) {
      byDay.putIfAbsent(_dayOf(s.date), () => []).add(s.accuracy);
    }
    final points = byDay.entries
        .map((e) => _TrendPoint(
            e.key, e.value.reduce((a, b) => a + b) / e.value.length))
        .toList();
    points.sort((a, b) => a.day.compareTo(b.day));
    return points;
  }

  // ===========================================================================
  // CLEAR HISTORY (therapist menu only)
  // ===========================================================================
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

  // ===========================================================================
  // BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final history = TrainingHistoryService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Progress'),
        actions: [
          // Only therapists see this menu, so patients cannot wipe data.
          if (therapistView)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (value) {
                if (value == 'clear') _confirmClear();
                if (value == 'demo') loadDemoSessions();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'demo', child: Text('Load demo data (testing)')),
                PopupMenuItem(value: 'clear', child: Text('Clear history')),
              ],
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: history,
        builder: (context, child) {
          final all = history.sessions; // newest first
          final byActivity = all
              .where((s) => filter == 'All' || s.activity == filter)
              .toList();

          final today = _dayOf(DateTime.now());
          final rangeStart = rangeDays == 0
              ? (byActivity.isEmpty ? today : _dayOf(byActivity.last.date))
              : _addDays(today, -(rangeDays - 1));
          final inRange = byActivity
              .where((s) => !_dayOf(s.date).isBefore(rangeStart))
              .toList();

          // "This week" = last 7 days, "last week" = the 7 days before that.
          final weekStart = _addDays(today, -6);
          final prevStart = _addDays(today, -13);
          final thisWeek = byActivity
              .where((s) => !_dayOf(s.date).isBefore(weekStart))
              .toList();
          final lastWeek = byActivity.where((s) {
            final d = _dayOf(s.date);
            return !d.isBefore(prevStart) && d.isBefore(weekStart);
          }).toList();

          return Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: therapistView ? 1000 : 700),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _viewToggle(),
                  const SizedBox(height: 12),
                  _filterBar(),
                  const SizedBox(height: 16),
                  if (byActivity.isEmpty)
                    _emptyCard(all.isEmpty)
                  else if (therapistView)
                    ..._therapistChildren(inRange)
                  else
                    ..._patientChildren(
                        all, inRange, thisWeek, lastWeek, rangeStart, today),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // TOP CONTROLS
  // ===========================================================================
  Widget _viewToggle() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
            value: false,
            label: Text('Patient'),
            icon: Icon(Icons.person_outline)),
        ButtonSegment(
            value: true,
            label: Text('Therapist'),
            icon: Icon(Icons.medical_services_outlined)),
      ],
      selected: {therapistView},
      onSelectionChanged: (s) => setState(() => therapistView = s.first),
    );
  }

  Widget _filterBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: filter,
              items: _activities
                  .map((a) => DropdownMenuItem(
                      value: a, child: Text(a == 'All' ? 'All activities' : a)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => filter = v);
              },
            ),
          ),
        ),
        for (final r in const [7, 30, 0])
          ChoiceChip(
            label: Text(r == 0 ? 'All time' : 'Last $r days'),
            selected: rangeDays == r,
            onSelected: (_) => setState(() => rangeDays = r),
          ),
      ],
    );
  }

  Widget _emptyCard(bool noDataAtAll) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.bar_chart_rounded, size: 56, color: kTeal),
            const SizedBox(height: 12),
            const Text('No training sessions yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            Text(
              noDataAtAll
                  ? 'Complete a session and its results will appear here.'
                  : 'No sessions for this activity yet.',
              textAlign: TextAlign.center,
            ),
            // TESTING ONLY: remove this button before real patients use the app.
            if (noDataAtAll) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: loadDemoSessions,
                child: const Text('Load demo data (for testing)'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PATIENT VIEW
  // ===========================================================================
  List<Widget> _patientChildren(
    List<TrainingSession> all,
    List<TrainingSession> inRange,
    List<TrainingSession> thisWeek,
    List<TrainingSession> lastWeek,
    DateTime rangeStart,
    DateTime today,
  ) {
    return [
      _summaryCard(thisWeek, lastWeek, _streak(all)),
      const SizedBox(height: 12),
      _trendCard(inRange, rangeStart, today),
      const SizedBox(height: 12),
      _headlineCards(thisWeek, lastWeek),
      const SizedBox(height: 6),
      const Text('Arrows compare this week with last week.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 12),
      _pressQualityCard(inRange),
      const SizedBox(height: 16),
      const Text('Your sessions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      if (inRange.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('No sessions in this period.'),
        )
      else
        ..._groupedHistory(inRange),
    ];
  }

  Widget _summaryCard(List<TrainingSession> thisWeek,
      List<TrainingSession> lastWeek, int streak) {
    final nowAcc = _avgAccuracy(thisWeek);
    final beforeAcc = _avgAccuracy(lastWeek);

    String headline;
    IconData icon;
    Color color;

    if (thisWeek.isEmpty) {
      headline =
          'No sessions this week yet. A short warm-up is a great way to start.';
      icon = Icons.wb_sunny_outlined;
      color = kBlue;
    } else if (nowAcc != null && beforeAcc != null) {
      final diff = nowAcc - beforeAcc;
      if (diff >= 2) {
        headline = 'Great work! Your accuracy rose from '
            '${beforeAcc.toStringAsFixed(0)}% to ${nowAcc.toStringAsFixed(0)}% '
            'this week.';
        icon = Icons.trending_up;
        color = kGreen;
      } else if (diff <= -2) {
        // Gentle wording on purpose: no red, no negative language.
        headline = 'A tougher week, but every session counts. Keep going!';
        icon = Icons.favorite_outline;
        color = kBlue;
      } else {
        headline = 'Steady progress. Your accuracy is consistent with last week.';
        icon = Icons.show_chart;
        color = kTeal;
      }
    } else {
      headline = 'You have done ${thisWeek.length} '
          'session${thisWeek.length == 1 ? '' : 's'} this week. Keep it up!';
      icon = Icons.thumb_up_alt_outlined;
      color = kTeal;
    }

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(headline,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.local_fire_department,
                    color: Colors.orange, size: 22),
                const SizedBox(width: 6),
                Text(
                  streak == 0
                      ? 'Train today to start a streak'
                      : '$streak-day streak',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendCard(List<TrainingSession> list, DateTime start, DateTime end) {
    final points = _trendPoints(list);
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Accuracy trend',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Each dot is one day. Higher is better.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            if (points.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No scored sessions in this period yet.')),
              )
            else
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendPainter(
                      points: points, start: start, end: end, color: kTeal),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _headlineCards(
      List<TrainingSession> thisWeek, List<TrainingSession> lastWeek) {
    final acc = _avgAccuracy(thisWeek);
    final accPrev = _avgAccuracy(lastWeek);
    final rate = _fullRate(thisWeek);
    final ratePrev = _fullRate(lastWeek);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _metricCard(
            'Sessions',
            '${thisWeek.length}',
            Icons.history,
            kTeal,
            delta: _delta(thisWeek.length.toDouble(),
                lastWeek.length.toDouble(), ''),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            'Accuracy',
            acc == null ? '—' : '${acc.toStringAsFixed(0)}%',
            Icons.track_changes,
            kTeal,
            delta: _delta(acc, accPrev, ' pts'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            'Full presses',
            rate == null ? '—' : '${rate.toStringAsFixed(0)}%',
            Icons.check_circle_outline,
            kFullColor,
            delta: _delta(rate, ratePrev, ' pts'),
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color,
      {Widget? delta}) {
    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
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
                      fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            if (delta != null) ...[
              const SizedBox(height: 6),
              delta,
            ],
          ],
        ),
      ),
    );
  }

  /// Small arrow + number comparing "now" with "before".
  /// Green up = better, blue down = lower (never red), dash = about the same.
  Widget _delta(double? now, double? before, String suffix) {
    if (now == null || before == null) return const SizedBox(height: 18);
    final diff = now - before;
    final same = diff.abs() < 0.5;

    IconData icon;
    Color color;
    if (same) {
      icon = Icons.remove;
      color = Colors.black45;
    } else if (diff > 0) {
      icon = Icons.arrow_upward;
      color = kGreen;
    } else {
      icon = Icons.arrow_downward;
      color = kBlue;
    }
    final text = same ? 'Same' : '${diff.abs().toStringAsFixed(0)}$suffix';

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Flexible(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }

  Widget _pressQualityCard(List<TrainingSession> list) {
    final full = list.fold<int>(0, (a, s) => a + s.fullPresses);
    final half = list.fold<int>(0, (a, s) => a + s.halfPresses);
    final none = list.fold<int>(0, (a, s) => a + s.noPresses);
    final total = full + half + none;

    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Press quality',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Aim to see more green over time.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            if (total == 0)
              const Text('No press data in this period yet.')
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 18,
                  child: Row(
                    children: [
                      if (full > 0)
                        Expanded(
                            flex: full, child: Container(color: kFullColor)),
                      if (half > 0)
                        Expanded(
                            flex: half, child: Container(color: kHalfColor)),
                      if (none > 0)
                        Expanded(
                            flex: none, child: Container(color: kNoneColor)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _legend(kFullColor, 'Full', full, total),
                  _legend(kHalfColor, 'Half', half, total),
                  _legend(kNoneColor, 'Too short', none, total),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legend(Color c, String label, int n, int total) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label ${(n / total * 100).toStringAsFixed(0)}%'),
      ],
    );
  }

  /// Sessions grouped under "Today", "Yesterday", then dates.
  List<Widget> _groupedHistory(List<TrainingSession> list) {
    final widgets = <Widget>[];
    DateTime? lastDay;
    for (final s in list) {
      final day = _dayOf(s.date);
      if (lastDay == null || day != lastDay) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(_dayLabel(day),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black54)),
        ));
        lastDay = day;
      }
      widgets.add(_patientSessionTile(s));
    }
    return widgets;
  }

  Widget _patientSessionTile(TrainingSession s) {
    final color = _colorFor(s.activity);
    final time = '${_two(s.date.hour)}:${_two(s.date.minute)}';

    Widget? trailing;
    if (s.hasAccuracy) {
      trailing = Text('${s.accuracy.toStringAsFixed(0)}%',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: color));
    } else if (s.hasPresses) {
      trailing = Text('${s.fullPresses}/${s.totalPresses} full',
          style: TextStyle(fontWeight: FontWeight.bold, color: color));
    }

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_iconFor(s.activity), color: color),
        title: Text(s.activity,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$time  •  ${_fmtDuration(s.durationSeconds)}'
            '${s.completed ? '' : '  •  Stopped early'}'),
        trailing: trailing,
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

  // ===========================================================================
  // THERAPIST VIEW
  // ===========================================================================
  List<Widget> _therapistChildren(List<TrainingSession> list) {
    if (list.isEmpty) {
      return [
        const Card(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No sessions in this period.')),
          ),
        ),
      ];
    }

    final acc = _avgAccuracy(list);
    final totalSeconds = list.fold<int>(0, (a, s) => a + s.durationSeconds);
    final full = list.fold<int>(0, (a, s) => a + s.fullPresses);
    final half = list.fold<int>(0, (a, s) => a + s.halfPresses);
    final none = list.fold<int>(0, (a, s) => a + s.noPresses);

    return [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _miniStat('Sessions', '${list.length}', kTeal),
          _miniStat('Total time', _fmtDuration(totalSeconds), kTeal),
          _miniStat('Avg accuracy',
              acc == null ? '—' : '${acc.toStringAsFixed(1)}%', kTeal),
          _miniStat('Full presses', '$full', kFullColor),
          _miniStat('Half presses', '$half', kHalfColor),
          _miniStat('No press', '$none', kNoneColor),
        ],
      ),
      const SizedBox(height: 12),
      _pressQualityCard(list),
      const SizedBox(height: 12),
      _tableCard('By activity', _activityTable(list)),
      const SizedBox(height: 12),
      _tableCard('All sessions (${list.length})', _sessionTable(list)),
    ];
  }

  Widget _miniStat(String label, String value, Color color) {
    return SizedBox(
      width: 150,
      child: Card(
        color: Colors.white,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableCard(String title, Widget table) {
    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          ),
        ],
      ),
    );
  }

  Widget _activityTable(List<TrainingSession> list) {
    final rows = <DataRow>[];
    for (final name in _activities.where((a) => a != 'All')) {
      final items = list.where((s) => s.activity == name).toList();
      if (items.isEmpty) continue;
      final acc = _avgAccuracy(items);
      final rate = _fullRate(items);
      final avgSeconds =
          items.fold<int>(0, (a, s) => a + s.durationSeconds) ~/ items.length;
      rows.add(DataRow(cells: [
        DataCell(Text(name)),
        DataCell(Text('${items.length}')),
        DataCell(Text(acc == null ? '—' : '${acc.toStringAsFixed(1)}%')),
        DataCell(Text(rate == null ? '—' : '${rate.toStringAsFixed(1)}%')),
        DataCell(Text(_fmtDuration(avgSeconds))),
      ]));
    }

    return DataTable(
      columnSpacing: 24,
      columns: const [
        DataColumn(label: Text('Activity')),
        DataColumn(label: Text('Sessions'), numeric: true),
        DataColumn(label: Text('Avg accuracy'), numeric: true),
        DataColumn(label: Text('Full-press rate'), numeric: true),
        DataColumn(label: Text('Avg time'), numeric: true),
      ],
      rows: rows,
    );
  }

  Widget _sessionTable(List<TrainingSession> list) {
    return DataTable(
      columnSpacing: 20,
      columns: const [
        DataColumn(label: Text('Date')),
        DataColumn(label: Text('Activity')),
        DataColumn(label: Text('Level / board')),
        DataColumn(label: Text('Time'), numeric: true),
        DataColumn(label: Text('Accuracy'), numeric: true),
        DataColumn(label: Text('Full'), numeric: true),
        DataColumn(label: Text('Half'), numeric: true),
        DataColumn(label: Text('No press'), numeric: true),
        DataColumn(label: Text('Status')),
        DataColumn(label: Text('Notes')),
      ],
      rows: list.map((s) {
        return DataRow(cells: [
          DataCell(Text('${_dateText(s.date)} '
              '${_two(s.date.hour)}:${_two(s.date.minute)}')),
          DataCell(Text(s.activity)),
          DataCell(Text(s.difficulty)),
          DataCell(Text(_fmtDuration(s.durationSeconds))),
          DataCell(Text(
              s.hasAccuracy ? '${s.accuracy.toStringAsFixed(1)}%' : '—')),
          DataCell(Text('${s.fullPresses}')),
          DataCell(Text('${s.halfPresses}')),
          DataCell(Text('${s.noPresses}')),
          DataCell(Text(s.completed ? 'Completed' : 'Stopped early')),
          DataCell(ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(s.notes.isEmpty ? '—' : s.notes,
                overflow: TextOverflow.ellipsis),
          )),
        ]);
      }).toList(),
    );
  }
}

// =============================================================================
// TREND CHART (drawn by hand, so no extra package is needed)
// =============================================================================
class _TrendPoint {
  final DateTime day;
  final double value; // 0 to 100
  const _TrendPoint(this.day, this.value);
}

class _TrendPainter extends CustomPainter {
  final List<_TrendPoint> points;
  final DateTime start;
  final DateTime end;
  final Color color;

  _TrendPainter({
    required this.points,
    required this.start,
    required this.end,
    required this.color,
  });

  /// Draws text. anchorX: 0 = text starts at x, 0.5 = centred, 1 = ends at x.
  void _label(Canvas canvas, String text, double x, double y, double anchorX) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 11, color: Colors.black54)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x - tp.width * anchorX, y - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0, right = 10.0, top = 10.0, bottom = 24.0;
    final w = size.width - left - right;
    final h = size.height - top - bottom;

    double yOf(double v) => top + h * (1 - v / 100);
    final span = end.difference(start).inDays;
    double xOf(DateTime d) => span <= 0
        ? left + w / 2
        : left + w * (d.difference(start).inDays / span);

    // Grid lines at 0%, 50%, 100%
    final grid = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    for (final v in [0, 50, 100]) {
      final y = yOf(v.toDouble());
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), grid);
      _label(canvas, '$v%', left - 6, y, 1);
    }

    // Line joining the dots
    if (points.length > 1) {
      final line = Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()
        ..moveTo(xOf(points.first.day), yOf(points.first.value));
      for (final p in points.skip(1)) {
        path.lineTo(xOf(p.day), yOf(p.value));
      }
      canvas.drawPath(path, line);
    }

    // Dots
    final dot = Paint()..color = color;
    final ring = Paint()..color = Colors.white;
    for (final p in points) {
      final o = Offset(xOf(p.day), yOf(p.value));
      canvas.drawCircle(o, 6, ring);
      canvas.drawCircle(o, 4, dot);
    }

    // Date labels under the chart
    final labelY = size.height - bottom / 2 + 4;
    _label(canvas, '${start.day}/${start.month}', left, labelY, 0);
    if (span > 0) {
      _label(canvas, '${end.day}/${end.month}', size.width - right, labelY, 1);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points ||
      old.start != start ||
      old.end != end ||
      old.color != color;
}