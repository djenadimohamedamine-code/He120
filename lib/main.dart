import 'dart:async';
import 'dart:convert';
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
  // IPs des caméras
  String cam1Ip = "192.168.0.10";
  String cam2Ip = "192.168.0.11"; // IP par défaut, modifiable
  
  // Caméra active (1 ou 2)
  int activeCam = 1;

  final String camUser = "admin";
  final String camPass = "12345";
  
  String lastPtzCmd = "PTS5050";
  
  String get currentIp => activeCam == 1 ? cam1Ip : cam2Ip;

  // Envoi de commande HTTP
  Future<void> sendCmd(String cmdStr) async {
    final url = Uri.parse('http://$currentIp/cgi-bin/aw_ptz?cmd=%23$cmdStr&res=1');
    final String basicAuth = 'Basic ${base64Encode(utf8.encode('$camUser:$camPass'))}';
    try {
      await http.get(url, headers: {'authorization': basicAuth}).timeout(const Duration(milliseconds: 500));
    } catch (e) {
      // Ignorer silencieusement
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

    double normX = diff.dx / _joystickRadius; 
    double normY = diff.dy / _joystickRadius; 

    int pan = (50 + (normX * 49)).round().clamp(1, 99);
    int tilt = (50 - (normY * 49)).round().clamp(1, 99);

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

  // --- BOITE DE DIALOGUE IP CAM 2 ---
  void _editCam2Ip() {
    TextEditingController ipController = TextEditingController(text: cam2Ip);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text("Changer l'IP Caméra 2"),
          content: TextField(
            controller: ipController,
            decoration: const InputDecoration(labelText: "Adresse IP"),
            keyboardType: TextInputType.number,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler"),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  cam2Ip = ipController.text;
                });
                Navigator.pop(context);
              },
              child: const Text("Sauvegarder"),
            )
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Contrôle : CAM $activeCam ($currentIp)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.black87,
        centerTitle: true,
        actions: [
          if (activeCam == 2)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.orangeAccent),
              tooltip: "Changer l'IP",
              onPressed: _editCam2Ip,
            ),
        ],
      ),
      body: Column(
        children: [
          // SÉLECTEUR DE CAMÉRA
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.white10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _camSelector(1, "CAMÉRA 1", Colors.green),
                const SizedBox(width: 20),
                _camSelector(2, "CAMÉRA 2", Colors.orange),
              ],
            ),
          ),
          
          Expanded(
            child: Row(
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
                            Transform.translate(
                              offset: _joystickPos,
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: activeCam == 1 ? Colors.green : Colors.orange,
                                  boxShadow: [BoxShadow(color: (activeCam == 1 ? Colors.green : Colors.orange).withOpacity(0.5), blurRadius: 10)],
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
                                backgroundColor: activeCam == 1 ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: activeCam == 1 ? Colors.green : Colors.orange, width: 1),
                                ),
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
                        child: _zoomBtn(Icons.add, "IN", Colors.white70),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTapDown: (_) => _startZoom(false),
                        onTapUp: (_) => _stopZoom(),
                        onTapCancel: () => _stopZoom(),
                        child: _zoomBtn(Icons.remove, "OUT", Colors.white70),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _camSelector(int camId, String label, Color color) {
    bool isSelected = activeCam == camId;
    return GestureDetector(
      onTap: () {
        setState(() {
          activeCam = camId;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isSelected ? color : Colors.white24, width: 2),
        ),
        child: Row(
          children: [
            Icon(Icons.videocam, color: isSelected ? color : Colors.white54),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontWeight: FontWeight.bold,
              fontSize: 16
            )),
          ],
        ),
      ),
    );
  }

  Widget _zoomBtn(IconData icon, String label, Color color) {
    Color themeColor = activeCam == 1 ? Colors.green : Colors.orange;
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withOpacity(0.5), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: themeColor, size: 36),
          Text(label, style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
