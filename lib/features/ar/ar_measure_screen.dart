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

import '../../shared/theme.dart';

enum MeasureMode { treeHeight, canopyWidth, distance }

class ArMeasureScreen extends StatefulWidget {
  const ArMeasureScreen({super.key});

  @override
  State<ArMeasureScreen> createState() => _ArMeasureScreenState();
}

class _ArMeasureScreenState extends State<ArMeasureScreen> {
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;

  MeasureMode _mode = MeasureMode.treeHeight;
  bool _isMetric = true;

  // Generic points for distance/canopy
  List<math.Vector3> points = [];
  double? _calculatedDistance;
  
  // Specific to Tree Height
  math.Vector3? _treeBasePoint;
  double? _treeHeight;

  @override
  void dispose() {
    arSessionManager?.dispose();
    super.dispose();
  }

  void onARViewCreated(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) {
    this.arSessionManager = arSessionManager;
    this.arObjectManager = arObjectManager;

    this.arSessionManager!.onInitialize(
          showFeaturePoints: false,
          showPlanes: true,
          customPlaneTexturePath: null,
          showWorldOrigin: false,
          handleTaps: true,
        );

    this.arObjectManager!.onInitialize();
    this.arSessionManager!.onPlaneOrPointTap = onPlaneOrPointTapped;
  }

  Future<void> onPlaneOrPointTapped(List<ARHitTestResult> hitTestResults) async {
    final hit = hitTestResults.firstWhere(
      (r) => r.type == ARHitTestResultType.plane,
      orElse: () => hitTestResults.first,
    );

    if (hit != null) {
      final position = hit.worldTransform.getTranslation();

      setState(() {
        if (_mode == MeasureMode.treeHeight) {
          _treeBasePoint = position;
          _treeHeight = null;
        } else {
          if (points.length >= 2) {
            points.clear();
            _calculatedDistance = null;
          }
          points.add(position);

          if (points.length == 2) {
            _calculatedDistance = points[0].distanceTo(points[1]);
          }
        }
      });
    }
  }

  Future<void> _recordTop() async {
    if (_treeBasePoint == null || arSessionManager == null) return;
    
    final matrix = await arSessionManager!.getCameraPose();
    if (matrix != null) {
      final cameraPosition = matrix.getTranslation();
      
      // Calculate horizontal distance (ignoring Y axis)
      final dx = cameraPosition.x - _treeBasePoint!.x;
      final dz = cameraPosition.z - _treeBasePoint!.z;
      final horizontalDistance = dart_math.sqrt(dx * dx + dz * dz);
      
      // Extract forward vector from camera matrix (-Z axis)
      final forward = matrix.forward;
      final horizontalForwardLength = dart_math.sqrt(forward.x * forward.x + forward.z * forward.z);
      
      if (horizontalForwardLength > 0) {
        final tanPitch = forward.y / horizontalForwardLength;
        final dy = cameraPosition.y - _treeBasePoint!.y;
        
        final calculatedHeight = (horizontalDistance * tanPitch) + dy;
        
        setState(() {
          _treeHeight = calculatedHeight > 0 ? calculatedHeight : 0;
        });
      }
    }
  }

  void _clearPoints() {
    setState(() {
      points.clear();
      _calculatedDistance = null;
      _treeBasePoint = null;
      _treeHeight = null;
    });
  }

  String _formatValue(double valueInMeters) {
    if (_isMetric) {
      return '${valueInMeters.toStringAsFixed(2)} m';
    } else {
      return '${(valueInMeters * 3.28084).toStringAsFixed(2)} ft';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ARView(
            onARViewCreated: onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
          ),
          
          _buildTopBar(),
          _buildMeasurementOverlay(),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            backgroundColor: Colors.black54,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const Text(
            'Measure Tree Height',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
            ),
          ),
          // Placeholder for symmetry
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildMeasurementOverlay() {
    bool hasData = false;
    String label = '';
    String value = '';

    if (_mode == MeasureMode.treeHeight) {
      if (_treeHeight != null) {
        hasData = true;
        label = 'Height: ';
        value = _formatValue(_treeHeight!);
      } else if (_treeBasePoint != null) {
        hasData = true;
        label = 'Base recorded. Point at Top & press Measure.';
        value = '';
      } else {
        hasData = true;
        label = 'Tap the ground at the base of the tree.';
        value = '';
      }
    } else {
      if (_calculatedDistance != null) {
        hasData = true;
        label = _mode == MeasureMode.distance ? 'Distance: ' : 'Width: ';
        value = _formatValue(_calculatedDistance!);
      } else if (points.length == 1) {
        hasData = true;
        label = 'Tap a second point.';
        value = '';
      } else {
        hasData = true;
        label = 'Tap two points to measure.';
        value = '';
      }
    }

    if (!hasData) return const SizedBox.shrink();

    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 100), // Push below center
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2C4C3B).withValues(alpha: 0.9), // AppTheme green
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          '$label$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 30,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tabs Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildModeTab('Tree Height', MeasureMode.treeHeight),
                _buildModeTab('Canopy Width', MeasureMode.canopyWidth),
                _buildModeTab('Distance', MeasureMode.distance),
                // Unit toggle
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isMetric = !_isMetric;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _isMetric ? 'm' : 'ft',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Clear button
                TextButton.icon(
                  onPressed: _clearPoints,
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  label: const Text('Clear', style: TextStyle(color: Colors.white)),
                ),
                
                // Measure button
                ElevatedButton(
                  onPressed: _mode == MeasureMode.treeHeight ? _recordTop : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50), // Bright green
                    disabledBackgroundColor: Colors.white12,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Measure',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                
                // Save button
                TextButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Saved to Diary!')),
                    );
                  },
                  icon: const Icon(Icons.save, color: Colors.white),
                  label: const Text('Save', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab(String title, MeasureMode mode) {
    final isSelected = _mode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _mode = mode;
          _clearPoints();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: isSelected ? const Border(bottom: BorderSide(color: Color(0xFF4CAF50), width: 2)) : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
