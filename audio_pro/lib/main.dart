import 'package:flutter/material.dart';
import 'services/audio_bridge_controller.dart';
import 'ui/screens/desktop_receiver_screen.dart';
import 'ui/screens/mobile_transmitter_screen.dart';
import 'ui/theme/cyber_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AudioProApp());
}

class AudioProApp extends StatefulWidget {
  const AudioProApp({super.key});

  @override
  State<AudioProApp> createState() => _AudioProAppState();
}

class _AudioProAppState extends State<AudioProApp> {
  late final AudioBridgeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AudioBridgeController();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AudioPro',
      debugShowCheckedModeBanner: false,
      theme: CyberTheme.buildDarkTheme(),
      home: _controller.isDesktopHost
          ? DesktopReceiverScreen(controller: _controller)
          : MobileTransmitterScreen(controller: _controller),
    );
  }
}
