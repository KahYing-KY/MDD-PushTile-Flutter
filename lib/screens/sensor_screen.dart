import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flserial/flserial.dart';

class PushPointScreen extends StatefulWidget {
  const PushPointScreen({super.key});

  @override
  State<PushPointScreen> createState() => _PushPointScreenState();
}

class _PushPointScreenState extends State<PushPointScreen> {
  String _statusText = "Tap 'Connect Port' to open serial connection...";
  late final FlSerial _serialPort;
  bool _isConnected = false;

  Map<String, dynamic> _data = {
    "hall_raw": 0,
    "hall_avg": 0.0,
    "hall_v": 0.0,
    "fsr_raw": 0,
    "fsr_avg": 0.0,
    "fsr_v": 0.0,
    "nfc_uid": "None"
  };

  @override
  void initState() {
    super.initState();
    _serialPort = FlSerial();
  }

  Future<void> _connectSerial() async {
    try {
      final ports = await FlSerial.availablePorts();
      if (ports.isEmpty) {
        setState(() => _statusText = "No serial ports found. Check USB connection.");
        return;
      }

      final targetPort = ports.first;
      final config = SerialConfig(baudRate: 115200);

      final success = await _serialPort.open(targetPort.path, config);

      if (!success) {
        setState(() => _statusText = "Failed to open port ${targetPort.path}");
        return;
      }

      setState(() {
        _isConnected = true;
        _statusText = "Connected to ${targetPort.path}";
      });

      // FIXED: Use flserial's events stream and filter by SerialEventType.data
      _serialPort.events.listen((event) {
        if (event.type == SerialEventType.data) {
          final data = event.data;
          if (data != null) {
            final line = utf8.decode(data).trim();
            try {
              if (line.startsWith("{") && line.endsWith("}")) {
                final parsedData = jsonDecode(line);
                setState(() {
                  _data = parsedData;
                });
              }
            } catch (e) {
              // Ignore incomplete fragments or console prints
            }
          }
        }
      }, onError: (error) {
        setState(() => _statusText = "Stream Error: $error");
      });
      
    } catch (e) {
      setState(() => _statusText = "Connection failed: $e");
    }
  }

  @override
  void dispose() {
    _serialPort.close();
    _serialPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PushPoint System Monitor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(_statusText, style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
                ),
                if (!_isConnected)
                  ElevatedButton.icon(
                    onPressed: _connectSerial,
                    icon: const Icon(Icons.usb),
                    label: const Text("Connect Port"),
                  ),
              ],
            ),
            const Divider(height: 20),
            
            // NFC Card
            Card(
              child: ListTile(
                title: const Text("PN532 NFC Reader", style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("UID: ${_data['nfc_uid']}", style: const TextStyle(fontSize: 18, color: Colors.blue)),
              ),
            ),
            const SizedBox(height: 10),

            // Hall Sensor Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("SS49E Hall Sensor", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 5),
                    Text("Raw ADC: ${_data['hall_raw']}"),
                    Text("Average ADC: ${_data['hall_avg']}"),
                    Text("Voltage: ${_data['hall_v']} mV"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // FSR Sensor Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("FSR Force Sensor", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 5),
                    Text("Raw ADC: ${_data['fsr_raw']}"),
                    Text("Average ADC: ${_data['fsr_avg']}"),
                    Text("Voltage: ${_data['fsr_v']} mV"),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}