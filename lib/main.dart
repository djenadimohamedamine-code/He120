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
  // IPs des caméras
  String cam1Ip = "192.168.0.10";
  String cam2Ip = "192.168.0.11"; 
  
  // Caméra active (1 ou 2)
  int activeCam = 1;

  final String camUser = "admin";
  final String camPass = "12345";
  
  // États de contrôle
  String lastPtzCmd = "PTS5050";
  String lastZoomCmd = "Z50";
  String lastFocusCmd = "F50";
  
  bool isAutoFocus = false;
  bool isAutoIris = false;

  String get currentIp => activeCam == 1 ? cam1Ip : cam2Ip;

  // Envoi de commande HTTP PTZ (Pan/Tilt/Zoom)
  Future<void> sendCmd(String cmdStr) async {
    final url = Uri.parse('http://$currentIp/cgi-bin/aw_ptz?cmd=%23$cmdStr&res=1');
    final String basicAuth = 'Basic ${base64Encode(utf8.encode('$camUser:$camPass'))}';
    try {
      await http.get(url, headers: {'authorization': basicAuth}).timeout(const Duration(milliseconds: 500));
    } catch (e) {
      // Ignorer
    }
  }

  // Envoi de commande HTTP CAM (Focus/Iris)
  Future<void> sendCamCmd(String cmdStr) async {
    final url = Uri.parse('http://$currentIp/cgi-bin/aw_cam?cmd=%23$cmdStr&res=1');
    final String basicAuth = 'Basic ${base64Encode(utf8.encode('$camUser:$camPass'))}';
    try {
      await http.get(url, headers: {'authorization': basicAuth}).timeout(const Duration(milliseconds: 500));
    } catch (e) {
      // Ignorer
    }
  }

  // Fonction de calcul exponentiel pour la sensibilité
  int calculateProportionalSpeed(double normalizedValue) {
    // normalizedValue entre -1.0 et 1.0
    double curve = normalizedValue.sign * pow(normalizedValue.abs(), 2.0); 
    int speed = (50 + (curve * 49)).round();
    return speed.clamp(1, 99);
  }

  // --- JOYSTICK PAN/TILT ---
  Offset _joystickPos = Offset.zero;
  final double _joystickRadius = 120.0;
  
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

    int pan = calculateProportionalSpeed(normX);
    int tilt = calculateProportionalSpeed(-normY);

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

  // --- JOYSTICK ZOOM ---
  Offset _zoomPos = Offset.zero;
  final double _sliderRadius = 100.0;
  
  void _onZoomUpdate(double dy) {
    double clampedDy = dy.clamp(-_sliderRadius, _sliderRadius);
    setState(() => _zoomPos = Offset(0, clampedDy));
    
    double normY = clampedDy / _sliderRadius;
    int zoom = calculateProportionalSpeed(-normY); // Haut = Z51~Z99 (IN), Bas = Z49~Z01 (OUT)
    String zCmd = "Z${zoom.toString().padLeft(2, '0')}";
    
    if (zCmd != lastZoomCmd) {
      lastZoomCmd = zCmd;
      sendCmd(zCmd);
    }
  }

  void _onZoomEnd() {
    setState(() => _zoomPos = Offset.zero);
    lastZoomCmd = "Z50";
    sendCmd("Z50");
  }

  // --- JOYSTICK FOCUS ---
  Offset _focusPos = Offset.zero;
  
  void _onFocusUpdate(double dy) {
    if (isAutoFocus) return;
    double clampedDy = dy.clamp(-_sliderRadius, _sliderRadius);
    setState(() => _focusPos = Offset(0, clampedDy));
    
    double normY = clampedDy / _sliderRadius;
    int focus = calculateProportionalSpeed(-normY); // Haut = Near, Bas = Far
    String fCmd = "F${focus.toString().padLeft(2, '0')}";
    
    if (fCmd != lastFocusCmd) {
      lastFocusCmd = fCmd;
      sendCamCmd(fCmd);
    }
  }

  void _onFocusEnd() {
    setState(() => _focusPos = Offset.zero);
    lastFocusCmd = "F50";
    if (!isAutoFocus) {
      sendCamCmd("F50");
    }
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

  // --- BUILDERS UI ---
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
                // GAUCHE : JOYSTICK PAN/TILT
                Expanded(
                  flex: 3,
                  child: _buildPanTiltSection(),
                ),
                
                // CENTRE : FOCUS & IRIS
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Expanded(child: _buildFocusSection()),
                      Expanded(child: _buildIrisAndPresetsSection()),
                    ],
                  ),
                ),

                // DROITE : ZOOM
                Expanded(
                  flex: 2,
                  child: _buildZoomSection(),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanTiltSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("PAN / TILT", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 20),
        GestureDetector(
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
                Container(width: 2, height: 20, color: Colors.white24),
                Container(width: 20, height: 2, color: Colors.white24),
                Transform.translate(
                  offset: _joystickPos,
                  child: Container(
                    width: 70,
                    height: 70,
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
      ],
    );
  }

  Widget _buildFocusSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("FOCUS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 16),
        _buildAutoButton("AUTO FOCUS", isAutoFocus, (val) {
          setState(() => isAutoFocus = val);
          sendCamCmd(val ? "D10" : "D11");
        }),
        const SizedBox(height: 20),
        _buildVerticalSlider(_focusPos, _onFocusUpdate, _onFocusEnd, isAutoFocus),
      ],
    );
  }

  Widget _buildIrisAndPresetsSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("IRIS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 16),
        _buildAutoButton("AUTO IRIS", isAutoIris, (val) {
          setState(() => isAutoIris = val);
          sendCamCmd(val ? "D30" : "D31");
        }),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTapDown: isAutoIris ? null : (_) => sendCamCmd("I01"),
              onTapUp: isAutoIris ? null : (_) => sendCamCmd("I50"),
              onTapCancel: isAutoIris ? null : () => sendCamCmd("I50"),
              child: _buildIrisBtn(Icons.remove, isAutoIris),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTapDown: isAutoIris ? null : (_) => sendCamCmd("I99"),
              onTapUp: isAutoIris ? null : (_) => sendCamCmd("I50"),
              onTapCancel: isAutoIris ? null : () => sendCamCmd("I50"),
              child: _buildIrisBtn(Icons.add, isAutoIris),
            ),
          ],
        ),
        const SizedBox(height: 30),
        const Text("PRESETS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 12),
        SizedBox(
          width: 200,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.5,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(6, (i) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: activeCam == 1 ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: activeCam == 1 ? Colors.green : Colors.orange, width: 1),
                  ),
                ),
                onPressed: () => sendCmd("R${i.toString().padLeft(2, '0')}"),
                child: Text("${i + 1}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildZoomSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("ZOOM", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 20),
        _buildVerticalSlider(_zoomPos, _onZoomUpdate, _onZoomEnd, false),
      ],
    );
  }

  Widget _buildVerticalSlider(Offset pos, Function(double) onUpdate, VoidCallback onEnd, bool disabled) {
    return GestureDetector(
      onVerticalDragUpdate: disabled ? null : (details) {
        onUpdate(details.localPosition.dy - _sliderRadius);
      },
      onVerticalDragEnd: disabled ? null : (_) => onEnd(),
      child: Container(
        width: 80,
        height: _sliderRadius * 2,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: disabled ? Colors.white12 : Colors.white24, width: 2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(height: 2, width: 40, color: Colors.white24),
            Transform.translate(
              offset: pos,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: disabled ? Colors.white24 : (activeCam == 1 ? Colors.green : Colors.orange),
                  boxShadow: disabled ? [] : [
                    BoxShadow(color: (activeCam == 1 ? Colors.green : Colors.orange).withOpacity(0.5), blurRadius: 10)
                  ]
                ),
                child: Center(
                  child: Icon(Icons.unfold_more, color: disabled ? Colors.black26 : Colors.white54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoButton(String label, bool isActive, Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!isActive),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? Colors.red : Colors.white24, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? Colors.red : Colors.black45,
                boxShadow: isActive ? [const BoxShadow(color: Colors.red, blurRadius: 8)] : [],
              ),
            ),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildIrisBtn(IconData icon, bool disabled) {
    Color themeColor = activeCam == 1 ? Colors.green : Colors.orange;
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: disabled ? Colors.white12 : themeColor.withOpacity(0.5), width: 2),
      ),
      child: Icon(icon, color: disabled ? Colors.white24 : themeColor, size: 30),
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
}
