import 'package:flutter/material.dart';
import '../main.dart';
import 'light_chase_screen.dart';
import 'rhythm_screen_adapt.dart';
import 'two_hand_play.dart';
import 'progress_screen.dart';
import 'cutting_game.dart';
import 'cooking_studio_screen_new.dart';
import 'sky_burger_real.dart';
import 'treasure_hunt.dart';
import 'dart:async';
import 'treasure_hunt_interim.dart';
import 'chatbot_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollTimer;

  // Increased scrolling speed (previously 12.0)
  static const double _scrollSpeed = 20.0;

  void _startScrolling(double direction) {
    _stopScrolling();

    // Scroll immediately when the button is first pressed.
    _scroll(direction);

    // Continue scrolling while the button is held (~60fps updates)
    _scrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _scroll(direction),
    );
  }

  void _scroll(double direction) {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final newOffset = (_scrollController.offset +
            direction * _scrollSpeed)
        .clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        )
        .toDouble();

    _scrollController.jumpTo(newOffset);
  }

  void _stopScrolling() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  @override
  void dispose() {
    _stopScrolling();
    _scrollController.dispose();
    super.dispose();
  }

  void _go(Widget screen) {
    _stopScrolling();

    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) {
      if (coolDownSummary != null) resetSession();
      if (mounted) setState(() {});
    });
  }

  void _hint(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _scrollButton({
    required IconData icon,
    required double direction,
    required String label,
  }) {
    return Listener(
      onPointerDown: (_) => _startScrolling(direction),
      onPointerUp: (_) => _stopScrolling(),
      onPointerCancel: (_) => _stopScrolling(),
      child: Semantics(
        button: true,
        label: 'Hold to scroll $label',
        child: Container(
          width: 66,
          height: 82,
          decoration: BoxDecoration(
            color: kTeal,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 38,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusText = warmUpDone
        ? 'Warm-up baseline recorded. Pick a game!'
        : 'Start with the Light Chase warm-up to record your baseline.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('RehabSudoku'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 750),
            child: Row(
              children: [
                // MAIN CONTENT
                Expanded(
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true,
                    thickness: 12,
                    radius: const Radius.circular(10),
                    child: ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 20, 28, 20),
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
                              const Text(
                                'Hello, Patient!',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  color: kInk,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Welcome to your rehabilitation session.',
                                style: TextStyle(
                                  fontSize: 17,
                                  color: kInk,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                statusText,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: kTeal,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        const Text(
                          'What would you like to do today?',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: kInk,
                          ),
                        ),

                        const SizedBox(height: 16),

                        ActionCard(
                          icon: Icons.flash_on_rounded,
                          color: kBlue,
                          title: 'Warm-Up: Light Chase',
                          description:
                              'Push the tile that lights up. A full press counts as a hit. This records your baseline.',
                          buttonLabel: !warmUpDone
                              ? 'Start Warm-Up'
                              : (trainingStarted
                                  ? 'Warm-Up Done'
                                  : 'Redo Warm-Up'),
                          onPressed: (warmUpDone && trainingStarted)
                              ? null
                              : () => _go(const LightChaseScreen()),
                        ),

                        ActionCard(
                          icon: Icons.music_note_rounded,
                          color: kGreen,
                          title: 'Rhythm Game',
                          description:
                              'Hold the tiles as the notes arrive. Short, long and endurance holds. Choose your level.',
                          buttonLabel: 'Play Rhythm Game',
                          onPressed: () =>
                              _go(const RhythmGameScreen()),
                        ),

                        ActionCard(
                          icon: Icons.diamond_rounded,
                          color: kGreen,
                          title: 'Treasure Hunt',
                          description:
                              'Observe the minimap clues to find the treasure in the shortest time possible.',
                          buttonLabel: 'Play Treasure Hunt',
                          onPressed: () =>
                              _go(const TreasureHunt2D5Screen()),
                        ),

                        ActionCard(
                          icon: Icons.touch_app_rounded,
                          color: kTeal,
                          title: 'Treasure Hunt (Interim)',
                          description:
                              'One-tile prototype. Each detected magnet press '
                              'moves the player two tiles automatically '
                              'towards the treasure.',
                          buttonLabel: 'Play Interim Treasure Hunt',
                          onPressed: () =>
                              _go(const TreasureHuntInterimScreen()),
                        ),

                        ActionCard(
                          icon: Icons.back_hand_rounded,
                          color: kBlue,
                          title: 'Hold & Reach (Two Hands)',
                          description:
                              'One hand holds the anchor tile while the other reaches for the lit tile.',
                          buttonLabel: 'Play Hold & Reach',
                          onPressed: () =>
                              _go(const TwoHandPlayScreen()),
                        ),

                        ActionCard(
                          icon: Icons.lunch_dining_rounded,
                          color: kTeal,
                          title: 'Sky Burger',
                          description:
                              'Catch the falling ingredients by pressing the tiles at the right time.',
                          buttonLabel: 'Play Sky Burger',
                          onPressed: () =>
                              _go(const SkyBurger2DScreen()),
                        ),

                        ActionCard(
                          icon: Icons.lunch_dining_rounded,
                          color: kTeal,
                          title: 'Kitchen Cutter',
                          description:
                              'Cut ingredients by pushing tiles on the board.',
                          buttonLabel: 'Play Kitchen Cutter',
                          onPressed: () =>
                              _go(const FourTileKitchenCutterScreen()),
                        ),

                        ActionCard(
                          icon: Icons.restaurant_menu_rounded,
                          color: kTeal,
                          title: 'Cooking Studio',
                          description:
                              'Become a virtual chef! Choose from 5 cuisines and prepare '
                              'delicious dishes by holding the left, right, or both tiles. '
                              'Practise alternating hands, sustained holds, and two-hand coordination.',
                          buttonLabel: 'Start Cooking',
                          onPressed: () =>
                              _go(const CookingStudioScreenNew()),
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
                              ? () => _go(
                                    const LightChaseScreen(
                                      coolDown: true,
                                    ),
                                  )
                              : () => _hint(
                                    'Finish the warm-up and play a game before your cool-down.',
                                  ),
                        ),

                        ActionCard(
                          icon: Icons.bar_chart_rounded,
                          color: kGreen,
                          title: 'My Progress',
                          description:
                              'View your training history and progress.',
                          buttonLabel: 'View Progress',
                          onPressed: () =>
                              _go(const ProgressScreen()),
                        ),

                        const SizedBox(height: 8),

                        const Center(
                          child: Text(
                            "Move at your own pace and follow your therapist's guidance.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

                // UP AND DOWN SCROLL BUTTONS
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _scrollButton(
                        icon: Icons.keyboard_arrow_up_rounded,
                        direction: -1,
                        label: 'up',
                      ),
                      const SizedBox(height: 18),
                      _scrollButton(
                        icon: Icons.keyboard_arrow_down_rounded,
                        direction: 1,
                        label: 'down',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // CHATBOT BUTTON
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Need help?'),
        onPressed: () {
          _stopScrolling();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ChatbotScreen(),
            ),
          );
        },
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