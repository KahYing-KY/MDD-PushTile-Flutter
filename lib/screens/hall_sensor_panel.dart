import 'dart:async';
import 'package:flutter/material.dart';
import 'hall_sensor_service.dart';

class HallSensorPanel extends StatefulWidget {
  const HallSensorPanel({super.key});

  @override
  State<HallSensorPanel> createState() => _HallSensorPanelState();
}

class _HallSensorPanelState extends State<HallSensorPanel> {
  Timer? _timer;
  bool _fetching = false;
  bool _connected = false;
  bool? _hall1;
  bool? _hall2;
  String? _error;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final current = await HallSensorService.getHallData();
      final history = await HallSensorService.getHistory();
      if (!mounted) return;
      final connected = current['connected'] == true;
      setState(() {
        _connected = connected;
        _hall1 = connected ? current['hall1'] as bool? : null;
        _hall2 = connected ? current['hall2'] as bool? : null;
        _history = history;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _hall1 = null;
        _hall2 = null;
        _error = 'Cannot reach sensor server';
      });
      debugPrint('Hall sensor API: $e');
    } finally {
      _fetching = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _sensorTile(String title, bool? detected) {
    final label = detected == null
        ? 'Unknown'
        : detected ? 'MAGNET DETECTED' : 'No magnet';
    final color = detected == null
        ? Colors.orange : detected ? Colors.green : Colors.grey;
    return Card(
      color: Colors.white,
      child: ListTile(
        leading: Icon(Icons.sensors, color: color),
        title: Text(title),
        subtitle: Text(label, style: TextStyle(color: color)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hall Sensor Monitoring',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(_connected ? Icons.wifi : Icons.wifi_off,
                    color: _connected ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Expanded(child: Text(_connected
                    ? 'Sensor server connected'
                    : (_error ?? 'Sensor not connected'))),
                IconButton(
                  tooltip: 'Refresh sensor data',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            _sensorTile('Hall Sensor 1', _hall1),
            _sensorTile('Hall Sensor 2', _hall2),
            const SizedBox(height: 12),
            Text('Detection History (${_history.length} latest events)',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('No simulated sensor changes recorded yet.'),
              ),
            ..._history.take(20).map((event) {
              final detected = event['detected'] == true;
              final date = DateTime.tryParse('${event['timestamp']}')?.toLocal();
              final timestamp = date == null
                  ? '${event['timestamp']}'
                  : '${date.day}/${date.month}/${date.year} '
                    '${date.hour.toString().padLeft(2, '0')}:'
                    '${date.minute.toString().padLeft(2, '0')}:'
                    '${date.second.toString().padLeft(2, '0')}';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  detected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: detected ? Colors.green : Colors.grey,
                ),
                title: Text('${event['sensor']} — '
                    '${detected ? 'Magnet detected' : 'No magnet'}'),
                subtitle: Text(timestamp),
              );
            }),
            const SizedBox(height: 4),
            const Text('Sensor data is stored by the Python server, '
                'separately from training session results.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
