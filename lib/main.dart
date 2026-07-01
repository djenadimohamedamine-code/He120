import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const HE120App());
}

class HE120App extends StatelessWidget {
  const HE120App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HE120 Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primarySwatch: Colors.blue,
      ),
      home: const ControllerScreen(),
    );
  }
}

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final String camIp = "192.168.0.10";
  final String camUser = "admin";
  final String camPass = "12345";
  
  String lastPtzCmd = "PTS5050";
  Timer? _ptzTimer;
  
  // Envoi de commande HTTP
  Future<void> sendCmd(String cmdStr) async {
    final url = Uri.parse('http://$camIp/cgi-bin/aw_ptz?cmd=%23$cmdStr&res=1');
    final String basicAuth = 'Basic ${base64Encode(utf8.encode('$camUser:$camPass'))}';
    try {
      await http.get(url, headers: {'authorization': basicAuth}).timeout(const Duration(milliseconds: 500));
    } catch (e) {
      // Ignorer silencieusement pour éviter de spammer la console
    }
  }

  // --- JOYSTICK LOGIC ---
  Offset _joystickPos = Offset.zero;
  final double _joystickRadius = 100.0;
  
  void _onJoystickUpdate(Offset localPosition) {
    Offset center = Offset(_joystickRadius, _joystickRadius);
    Offset diff = localPosition - center;
    double distance = diff.distance;
    
    if (distance > _joystickRadius) {
      diff = Offset(diff.dx / distance * _joystickRadius, diff.dy / distance * _joystickRadius);
    }
    
    setState(() {
      _joystickPos = diff;
    });

    double normX = diff.dx / _joystickRadius; // -1 to 1
    double normY = diff.dy / _joystickRadius; // -1 to 1

    int pan = (50 + (normX * 49)).round().clamp(1, 99);
    int tilt = (50 - (normY * 49)).round().clamp(1, 99); // Inversé car -1.0 Y est Haut (Up= >50)

    String ptz = "PTS${pan.toString().padLeft(2, '0')}${tilt.toString().padLeft(2, '0')}";
    
    if (ptz != lastPtzCmd) {
      lastPtzCmd = ptz;
      sendCmd(ptz);
    }
  }

  void _onJoystickEnd() {
    setState(() {
      _joystickPos = Offset.zero;
    });
    lastPtzCmd = "PTS5050";
    sendCmd("PTS5050");
  }

  // --- BOUTONS ZOOM ---
  void _startZoom(bool zoomIn) {
    sendCmd(zoomIn ? "Z99" : "Z01");
  }
  void _stopZoom() {
    sendCmd("Z50");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("PANASONIC HE120 - 192.168.0.10", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.black87,
        centerTitle: true,
      ),
      body: Row(
        children: [
          // GAUCHE : JOYSTICK
          Expanded(
            flex: 2,
            child: Center(
              child: GestureDetector(
                onPanUpdate: (details) => _onJoystickUpdate(details.localPosition),
                onPanEnd: (_) => _onJoystickEnd(),
                child: Container(
                  width: _joystickRadius * 2,
                  height: _joystickRadius * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white10,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // La bulle du joystick
                      Transform.translate(
                        offset: _joystickPos,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blueAccent,
                            boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 10)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // CENTRE : PRESETS
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("PRESETS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.5,
                    physics: const NeverScrollableScrollPhysics(),
                    children: List.generate(6, (i) {
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white12,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => sendCmd("R${i.toString().padLeft(2, '0')}"),
                        child: Text("PLAN ${i + 1}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),

          // DROITE : ZOOM
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("ZOOM", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 20),
                GestureDetector(
                  onTapDown: (_) => _startZoom(true),
                  onTapUp: (_) => _stopZoom(),
                  onTapCancel: () => _stopZoom(),
                  child: _zoomBtn(Icons.add, "IN", Colors.green),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTapDown: (_) => _startZoom(false),
                  onTapUp: (_) => _stopZoom(),
                  onTapCancel: () => _stopZoom(),
                  child: _zoomBtn(Icons.remove, "OUT", Colors.redAccent),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _zoomBtn(IconData icon, String label, Color color) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 36),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
