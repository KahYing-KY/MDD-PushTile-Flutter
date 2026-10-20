import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';
import 'screens/push_input.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://placeholder.supabase.co',
    publishableKey: 'placeholder-key',
  );

  runApp(const RehabSudokuApp());
}

// ===========================================================================
// COLORS
// ===========================================================================
const kTeal = Color(0xFF187D8A);
const kBlue = Color(0xFF5374B5);
const kGreen = Color(0xFF4A9A77);
const kBg = Color(0xFFF4F8FB);
const kInk = Color(0xFF1A1F22);

// ===========================================================================
// SHARED SESSION STATE
// ===========================================================================
bool warmUpDone = false;
bool trainingStarted = false;

/// The Light Chase sequence + board used in the warm-up, replayed in cool-down.
List<int>? sessionSeq;
BoardMode sessionMode = BoardMode.grid;

class WarmUpSummary {
  final double avgReaction;
  final double totalSeconds;
  final int full;
  final int half;
  final int none;
  final int done;
  final int failed;
  final int total;
  WarmUpSummary({
    required this.avgReaction,
    required this.totalSeconds,
    required this.full,
    required this.half,
    required this.none,
    required this.done,
    required this.failed,
    required this.total,
  });
}

WarmUpSummary? warmUpSummary;
WarmUpSummary? coolDownSummary;

void resetSession() {
  warmUpDone = false;
  trainingStarted = false;
  sessionSeq = null;
  warmUpSummary = null;
  coolDownSummary = null;
}

String fmtSeconds(double s) => '${s.toStringAsFixed(1)} s';

// ===========================================================================
// APP ROOT
// ===========================================================================
class RehabSudokuApp extends StatelessWidget {
  const RehabSudokuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RehabSudoku',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kTeal),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: kTeal,
          foregroundColor: Colors.white,
          centerTitle: true,
          titleTextStyle: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}