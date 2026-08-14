import 'dart:math' as dart_math;
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin_plus/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_plus/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_plus/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_plus/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_plus/managers/ar_location_manager.dart';
import 'package:vector_math/vector_math_64.dart' as math;

enum MeasureMode { treeHeight, canopyWidth, distance }

class ArMeasureScreen extends StatefulWidget {
  const ArMeasureScreen({super.key});

  @override
  State<ArMeasureScreen> createState() => _ArMeasureScreenState();
}

class _ArMeasureScreenState extends State<ArMeasureScreen> {
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;

  MeasureMode _mode = MeasureMode.treeHeight;
  bool _isMetric = true;
  bool _arReady = false;
  bool _isMeasuring = false;

  // Distance / canopy mode
  final List<math.Vector3> _points = [];
  double? _distance;

  // Tree height mode
  math.Vector3? _treeBase;
  double? _treeHeight;

  @override
  void dispose() {
    _arSessionManager?.dispose();
    super.dispose();
  }

  void _onARViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    _arSessionManager = sessionManager;
    _arObjectManager = objectManager;

    _arSessionManager!.onInitialize(
      showFeaturePoints: true,
      showPlanes: true,
      customPlaneTexturePath: null,
      showWorldOrigin: false,
      handleTaps: true,
    );
    _arObjectManager!.onInitialize();
    _arSessionManager!.onPlaneOrPointTap = _onTap;

    setState(() => _arReady = true);
  }

  Future<void> _onTap(List<ARHitTestResult> hits) async {
    if (hits.isEmpty) {
      _showStatus('No surface detected. Point at a flat surface.');
      return;
    }

    // Prefer plane hit, fallback to point
    ARHitTestResult? hit;
    try {
      hit = hits.firstWhere((r) => r.type == ARHitTestResultType.plane);
    } catch (_) {
      hit = hits.first;
    }

    final position = hit.worldTransform.getTranslation();

    setState(() {
      if (_mode == MeasureMode.treeHeight) {
        _treeBase = position;
        _treeHeight = null;
      } else {
        if (_points.length >= 2) {
          _points.clear();
          _distance = null;
        }
        _points.add(position);
        if (_points.length == 2) {
          _distance = _points[0].distanceTo(_points[1]);
        }
      }
    });
  }

  Future<void> _measureTreeHeight() async {
    if (_treeBase == null) {
      _showStatus('First tap the BASE of the tree on the ground.');
      return;
    }
    if (_arSessionManager == null) {
      _showStatus('AR session not ready. Please wait.');
      return;
    }

    setState(() => _isMeasuring = true);

    try {
      final cameraPose = await _arSessionManager!.getCameraPose();
      if (cameraPose == null) {
        _showStatus('Could not read camera pose. Try again.');
        setState(() => _isMeasuring = false);
        return;
      }

      final camPos = cameraPose.getTranslation();

      // Horizontal distance from camera to base (XZ plane)
      final dx = camPos.x - _treeBase!.x;
      final dz = camPos.z - _treeBase!.z;
      final horizontalDist = dart_math.sqrt(dx * dx + dz * dz);

      // Extract camera forward direction (-Z in camera space)
      // Row 2 of the rotation matrix is the camera's forward vector
      final forward = math.Vector3(
        cameraPose.entry(0, 2),
        cameraPose.entry(1, 2),
        cameraPose.entry(2, 2),
      ).normalized();

      // Pitch angle = angle between forward and horizontal plane
      final pitchRadians = dart_math.asin(-forward.y.clamp(-1.0, 1.0));

      if (pitchRadians <= 0) {
        _showStatus('Point your camera UPWARD at the TOP of the tree, then press Measure.');
        setState(() => _isMeasuring = false);
        return;
      }

      // Height = horizontal_distance * tan(pitch) + camera_height_above_base
      final cameraHeightAboveBase = camPos.y - _treeBase!.y;
      final calculatedHeight =
          (horizontalDist * dart_math.tan(pitchRadians)) + cameraHeightAboveBase;

      setState(() {
        _treeHeight = calculatedHeight > 0 ? calculatedHeight : 0;
        _isMeasuring = false;
      });
    } catch (e) {
      _showStatus('Measurement error: $e');
      setState(() => _isMeasuring = false);
    }
  }

  void _clearAll() {
    setState(() {
      _points.clear();
      _distance = null;
      _treeBase = null;
      _treeHeight = null;
    });
  }

  void _showStatus(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1B5E20),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _fmt(double meters) {
    if (_isMetric) return '${meters.toStringAsFixed(2)} m';
    return '${(meters * 3.28084).toStringAsFixed(2)} ft';
  }

  // ── Build helpers ─────────────────────────────────────────────────────────

  String get _instructionText {
    switch (_mode) {
      case MeasureMode.treeHeight:
        if (_treeBase == null) return '1. Tap the ground at the BASE of the tree';
        if (_treeHeight == null) {
          return '2. Aim camera at the TOP of the tree → press Measure';
        }
        return '✓ Height measured! Press Clear to reset.';
      case MeasureMode.canopyWidth:
      case MeasureMode.distance:
        if (_points.isEmpty) return 'Tap to place the FIRST point';
        if (_points.length == 1) return 'Tap to place the SECOND point';
        return '✓ Distance measured! Press Clear to reset.';
    }
  }

  String? get _resultText {
    if (_mode == MeasureMode.treeHeight && _treeHeight != null) {
      return 'Height: ${_fmt(_treeHeight!)}';
    }
    if (_mode != MeasureMode.treeHeight && _distance != null) {
      final label = _mode == MeasureMode.canopyWidth ? 'Width' : 'Distance';
      return '$label: ${_fmt(_distance!)}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── AR Camera view ──────────────────────────────────────────────
          ARView(
            onARViewCreated: _onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),

          // ── Loading overlay ─────────────────────────────────────────────
          if (!_arReady)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF4CAF50)),
                    SizedBox(height: 16),
                    Text(
                      'Starting AR camera…\nPoint at a flat surface',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          // ── Top bar ─────────────────────────────────────────────────────
          Positioned(
            top: 48,
            left: 12,
            right: 12,
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _mode == MeasureMode.treeHeight
                        ? 'Measure Tree Height'
                        : _mode == MeasureMode.canopyWidth
                            ? 'Measure Canopy Width'
                            : 'Measure Distance',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                ),
                // Unit toggle
                GestureDetector(
                  onTap: () => setState(() => _isMetric = !_isMetric),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Text(
                      _isMetric ? 'm' : 'ft',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Instruction card ─────────────────────────────────────────────
          if (_arReady)
            Positioned(
              top: 120,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  _instructionText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),

          // ── Crosshair center ─────────────────────────────────────────────
          if (_arReady && _mode == MeasureMode.treeHeight && _treeBase != null && _treeHeight == null)
            Center(
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF4CAF50), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.add, color: Color(0xFF4CAF50), size: 16),
                ),
              ),
            ),

          // ── Result overlay ───────────────────────────────────────────────
          if (_resultText != null)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 80),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white30),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 12)
                  ],
                ),
                child: Text(
                  _resultText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // ── Base marker label ────────────────────────────────────────────
          if (_mode == MeasureMode.treeHeight && _treeBase != null)
            Positioned(
              bottom: 220,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '📍 Base Point Set',
                    style: TextStyle(color: Color(0xFF80E27E), fontSize: 13),
                  ),
                ),
              ),
            ),

          // ── Bottom panel ─────────────────────────────────────────────────
          Positioned(
            bottom: 24,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mode tabs
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _modeTab('Tree Height', MeasureMode.treeHeight),
                      _modeTab('Canopy Width', MeasureMode.canopyWidth),
                      _modeTab('Distance', MeasureMode.distance),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Clear
                      OutlinedButton.icon(
                        onPressed: _clearAll,
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.white70, size: 18),
                        label: const Text('Clear',
                            style: TextStyle(color: Colors.white70)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                      ),

                      // Measure button
                      ElevatedButton(
                        onPressed: _mode == MeasureMode.treeHeight
                            ? (_isMeasuring ? null : _measureTreeHeight)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          disabledBackgroundColor: Colors.white12,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                        ),
                        child: _isMeasuring
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'Measure',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),

                      // Save
                      OutlinedButton.icon(
                        onPressed: _resultText != null
                            ? () {
                                _showStatus(
                                    'Measurement: ${_resultText!} (noted)');
                              }
                            : null,
                        icon: Icon(Icons.save,
                            color: _resultText != null
                                ? Colors.white70
                                : Colors.white24,
                            size: 18),
                        label: Text('Save',
                            style: TextStyle(
                                color: _resultText != null
                                    ? Colors.white70
                                    : Colors.white24)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: _resultText != null
                                  ? Colors.white24
                                  : Colors.white12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTab(String label, MeasureMode mode) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _mode = mode;
          _clearAll();
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2E7D32).withValues(alpha: 0.6)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0xFF4CAF50) : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white54,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
