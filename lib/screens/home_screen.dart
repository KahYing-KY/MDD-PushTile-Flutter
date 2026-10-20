import 'package:flutter/material.dart';
import '../main.dart';
import 'light_chase_screen.dart';
import 'interim_demo_screen.dart';
import 'rhythm_screen.dart';
import 'tictactoe_screen.dart';
import 'two_hand_play.dart';
import 'progress_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  void _go(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) {
      if (coolDownSummary != null) resetSession();
      if (mounted) setState(() {});
    });
  }

  void _hint(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final statusText = warmUpDone
        ? 'Warm-up baseline recorded. Pick a game!'
        : 'Start with the Light Chase warm-up to record your baseline.';

    return Scaffold(
      appBar: AppBar(title: const Text('RehabSudoku')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDFF1F1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Hello, Patient!',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: kInk)),
                      const SizedBox(height: 10),
                      const Text('Welcome to your rehabilitation session.',
                          style: TextStyle(fontSize: 17, color: kInk)),
                      const SizedBox(height: 10),
                      Text(statusText,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: kTeal)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text('What would you like to do today?',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600, color: kInk)),
                const SizedBox(height: 16),
                ActionCard(
                  icon: Icons.flash_on_rounded,
                  color: kBlue,
                  title: 'Warm-Up: Light Chase',
                  description:
                      'Push the tile that lights up. A full press counts as a hit. This records your baseline.',
                  buttonLabel: !warmUpDone
                      ? 'Start Warm-Up'
                      : (trainingStarted ? 'Warm-Up Done' : 'Redo Warm-Up'),
                  onPressed: (warmUpDone && trainingStarted)
                      ? null
                      : () => _go(const LightChaseScreen()),
                ),
                ActionCard(
                  icon: Icons.grid_view_rounded,
                  color: kTeal,
                  title: 'Interim Demo (Row-by-Row)',
                  description:
                      'Fill a 3x3 number board by pushing the 1, 2 or 3 tile for each highlighted cell.',
                  buttonLabel: 'Start Demo',
                  onPressed: () => _go(const InterimDemoScreen()),
                ),
                ActionCard(
                  icon: Icons.music_note_rounded,
                  color: kGreen,
                  title: 'Rhythm Game',
                  description:
                      'Hold the tiles as the notes arrive. Short, long and endurance holds. Choose your level.',
                  buttonLabel: 'Play Rhythm Game',
                  onPressed: () => _go(const RhythmGameScreen()),
                ),
                ActionCard(
                  icon: Icons.tag_rounded,
                  color: kTeal,
                  title: 'Tic-Tac-Toe',
                  description:
                      'Beat the computer by pushing tiles on the 3x3 board with a full press.',
                  buttonLabel: 'Play Tic-Tac-Toe',
                  onPressed: () => _go(const TicTacToeScreen()),
                ),
                ActionCard(
                  icon: Icons.back_hand_rounded,
                  color: kBlue,
                  title: 'Hold & Reach (Two Hands)',
                  description:
                      'One hand holds the anchor tile while the other reaches for the lit tile.',
                  buttonLabel: 'Play Hold & Reach',
                  onPressed: () => _go(const TwoHandPlayScreen()),
                ),
                ActionCard(
                  icon: Icons.flash_on_rounded,
                  color: kBlue,
                  locked: !(warmUpDone && trainingStarted),
                  title: 'Cool-Down',
                  description:
                      'Repeat the same Light Chase to compare how your arm moves after training.',
                  buttonLabel: (warmUpDone && trainingStarted)
                      ? 'Start Cool-Down'
                      : 'Finish a Game First',
                  onPressed: (warmUpDone && trainingStarted)
                      ? () => _go(const LightChaseScreen(coolDown: true))
                      : () => _hint(
                          'Finish the warm-up and play a game before your cool-down.'),
                ),
                ActionCard(
                  icon: Icons.bar_chart_rounded,
                  color: kGreen,
                  title: 'My Progress',
                  description: 'View your training history and progress.',
                  buttonLabel: 'View Progress',
                  onPressed: () => _go(const ProgressScreen()),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    "Move at your own pace and follow your therapist's guidance.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool locked;

  const ActionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final shade = locked ? Colors.grey : color;
    return Card(
      color: Colors.white,
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(locked ? Icons.lock_outline : icon, size: 44, color: shade),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w600, color: kInk)),
            const SizedBox(height: 8),
            Text(description,
                style: const TextStyle(fontSize: 17, color: kInk)),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: shade,
                minimumSize: const Size.fromHeight(58),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(buttonLabel,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}