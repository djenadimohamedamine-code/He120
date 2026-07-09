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
  // Proxy relais (IP du PC sur le WiFi)
  final String proxyHost = "192.168.1.30";
  final int proxyPort = 8098;
  
  // Caméra active (1 ou 2)
  int activeCam = 1;

  final String camUser = "admin";
  final String camPass = "12345";
  
  // États de contrôle
  String lastPtzCmd = "PTS5050";
  String lastZoomCmd = "Z50";
  String lastFocusCmd = "F50";
  
  bool isAutoFocus = false;
  bool isAutoIris = true;
  double pedestal = 50;
  Timer? _irisTimer;

  // Limiteur de vitesse (PTZ/Focus Speed)
  double globalSpeedScale = 1.0; 

  String get proxyBase => "http://$proxyHost:$proxyPort/cam$activeCam";

  // Envoi de commande HTTP PTZ (Pan/Tilt/Zoom)
  Future<void> sendCmd(String cmdStr) async {
    final url = Uri.parse('$proxyBase/cgi-bin/aw_ptz?cmd=%23$cmdStr&res=1');
    final String basicAuth = 'Basic ${base64Encode(utf8.encode('$camUser:$camPass'))}';
    try {
      await http.get(url, headers: {'authorization': basicAuth}).timeout(const Duration(milliseconds: 500));
    } catch (e) {
      // Ignorer
    }
  }

  // Envoi de commande HTTP PTZ (Pan/Tilt/Zoom/Focus/Iris)
  Future<void> sendCamCmd(String cmdStr) async {
    final url = Uri.parse('$proxyBase/cgi-bin/aw_ptz?cmd=%23$cmdStr&res=1');
    final String basicAuth = 'Basic ${base64Encode(utf8.encode('$camUser:$camPass'))}';
    try {
      await http.get(url, headers: {'authorization': basicAuth}).timeout(const Duration(milliseconds: 500));
    } catch (e) {
      // Ignorer
    }
  }

  // Envoi de commande via aw_cam (réglages image, iris mode)
  Future<void> sendCamSetup(String cmdStr) async {
    final url = Uri.parse('$proxyBase/cgi-bin/aw_cam?cmd=$cmdStr&res=1');
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
    // Appliquer le limiteur de vitesse
    curve = curve * globalSpeedScale;
    int speed = (50 + (curve * 49)).round();
    return speed.clamp(1, 99);
  }

  // --- JOYSTICK PAN/TILT ---
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
  final double _sliderRadius = 80.0;
  
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

  // --- BUILDERS UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("HE120 : CAM $activeCam (proxy)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.black87,
        centerTitle: true,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // GAUCHE : IRIS & ZOOM
          Expanded(
            flex: 2,
            child: _buildLeftZone(),
          ),
          
          // CENTRE : CAMERAS, PRESETS & FOCUS
          Expanded(
            flex: 4,
            child: _buildCenterZone(),
          ),

          // DROITE : SPEED LIMITER & PAN/TILT
          Expanded(
            flex: 3,
            child: _buildRightZone(),
          )
        ],
      ),
    );
  }

  Widget _buildLeftZone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildIrisSection(),
        _buildZoomSection(),
      ],
    );
  }

  Widget _buildCenterZone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _camSelector(1, "CAM 1", Colors.green),
                const SizedBox(width: 16),
                _camSelector(2, "CAM 2", Colors.orange),
              ],
            ),
            const SizedBox(height: 20),
            _buildPresets(),
          ],
        ),
        _buildFocusSection(),
      ],
    );
  }

  Widget _buildRightZone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildSpeedLimiter(),
        _buildPanTiltSection(),
      ],
    );
  }

  Widget _buildSpeedLimiter() {
    return Column(
      children: [
        const Text("PTZ/FOCUS SPEED", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
        Slider(
          value: globalSpeedScale,
          min: 0.1,
          max: 1.0,
          activeColor: activeCam == 1 ? Colors.green : Colors.orange,
          inactiveColor: Colors.white24,
          onChanged: (val) {
            setState(() {
              globalSpeedScale = val;
            });
          },
        ),
        Text("Limiteur : ${(globalSpeedScale * 100).toInt()}%", style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }

  Widget _buildPanTiltSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("PAN / TILT", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 10),
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
      ],
    );
  }

  Widget _buildFocusSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("FOCUS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAutoButton("AUTO", isAutoFocus, (val) {
              setState(() => isAutoFocus = val);
              sendCamCmd(val ? "D10" : "D11");
            }),
            const SizedBox(width: 20),
            _buildVerticalSlider(_focusPos, _onFocusUpdate, _onFocusEnd, isAutoFocus),
          ],
        ),
      ],
    );
  }

  void _irisStart(String dir) {
    sendCamSetup("ORS:0");
    _irisStop();
    sendCamSetup(dir);
    _irisTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      sendCamSetup(dir);
    });
  }

  void _irisStop() {
    _irisTimer?.cancel();
    _irisTimer = null;
    sendCamSetup("LIT");
  }

  Widget _buildIrisSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("IRIS", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAutoButton("AUTO", isAutoIris, (val) {
              setState(() => isAutoIris = val);
              sendCamSetup("ORS:${val ? 1 : 0}");
            }),
            const SizedBox(width: 16),
            Column(
              children: [
                GestureDetector(
                  onTapDown: isAutoIris ? null : (_) => _irisStart("LIO"),
                  onTapUp: isAutoIris ? null : (_) => _irisStop(),
                  onTapCancel: isAutoIris ? null : () => _irisStop(),
                  child: _buildIrisBtn(Icons.add, isAutoIris),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTapDown: isAutoIris ? null : (_) => _irisStart("LIC"),
                  onTapUp: isAutoIris ? null : (_) => _irisStop(),
                  onTapCancel: isAutoIris ? null : () => _irisStop(),
                  child: _buildIrisBtn(Icons.remove, isAutoIris),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresets() {
    return Column(
      children: [
        const Text("PRESET MEMORY", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
        const SizedBox(height: 10),
        SizedBox(
          width: 240,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.5,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(6, (i) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: activeCam == 1 ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: activeCam == 1 ? Colors.green : Colors.orange, width: 1),
                  ),
                ),
                onPressed: () => sendCmd("R${i.toString().padLeft(2, '0')}"),
                onLongPress: () {
                  sendCmd("M${i.toString().padLeft(2, '0')}");
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Preset ${i + 1} enregistré pour la Caméra $activeCam", textAlign: TextAlign.center),
                      duration: const Duration(seconds: 2),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
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
        const SizedBox(height: 10),
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
        width: 60,
        height: _sliderRadius * 2,
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: disabled ? Colors.white12 : Colors.white24, width: 2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(height: 2, width: 30, color: Colors.white24),
            Transform.translate(
              offset: pos,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: disabled ? Colors.white24 : (activeCam == 1 ? Colors.green : Colors.orange),
                  boxShadow: disabled ? [] : [
                    BoxShadow(color: (activeCam == 1 ? Colors.green : Colors.orange).withOpacity(0.5), blurRadius: 8)
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? Colors.red : Colors.white24, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? Colors.red : Colors.black26,
                boxShadow: isActive ? [const BoxShadow(color: Colors.red, blurRadius: 6)] : [],
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildIrisBtn(IconData icon, bool disabled) {
    Color themeColor = activeCam == 1 ? Colors.green : Colors.orange;
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: disabled ? Colors.white12 : themeColor.withOpacity(0.5), width: 2),
      ),
      child: Icon(icon, color: disabled ? Colors.white24 : themeColor, size: 24),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.3) : Colors.black45,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.white24, width: 2),
        ),
        child: Row(
          children: [
            Icon(Icons.videocam, color: isSelected ? color : Colors.white54, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontWeight: FontWeight.bold,
              fontSize: 14
            )),
          ],
        ),
      ),
    );
  }
}
