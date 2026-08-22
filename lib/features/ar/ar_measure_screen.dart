import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Lightweight AR-style measurement screen.
/// Uses the device camera via image_picker — no ARCore native libs needed.
/// Provides tree height, canopy width, and distance estimation guides.

enum MeasureMode { treeHeight, canopyWidth, distance }

class ArMeasureScreen extends StatefulWidget {
  const ArMeasureScreen({super.key});

  @override
  State<ArMeasureScreen> createState() => _ArMeasureScreenState();
}

class _ArMeasureScreenState extends State<ArMeasureScreen> {
  MeasureMode _mode = MeasureMode.treeHeight;
  bool _isMetric = true;
  double? _measuredValue;
  double _knownHeight = 1.7;     // reference object height in metres (person)
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
  }

  String get _modeLabel {
    switch (_mode) {
      case MeasureMode.treeHeight:   return 'Tree Height';
      case MeasureMode.canopyWidth:  return 'Canopy Width';
      case MeasureMode.distance:     return 'Distance';
    }
  }

  IconData get _modeIcon {
    switch (_mode) {
      case MeasureMode.treeHeight:   return Icons.park_rounded;
      case MeasureMode.canopyWidth:  return Icons.device_hub_rounded;
      case MeasureMode.distance:     return Icons.straighten_rounded;
    }
  }

  String get _modeInstructions {
    switch (_mode) {
      case MeasureMode.treeHeight:
        return 'Take a photo of the tree with a person of known height standing beside it.\n'
               '1. Tap the top of the person\'s head\n'
               '2. Tap the bottom of their feet\n'
               '3. Then tap top and bottom of the tree';
      case MeasureMode.canopyWidth:
        return 'Take a photo of the canopy from below or side.\n'
               '1. Tap one edge of the canopy\n'
               '2. Tap the other edge';
      case MeasureMode.distance:
        return 'Take a photo with a known reference object.\n'
               '1. Tap both ends of the reference object\n'
               '2. Then tap the span you want to measure';
    }
  }

  Future<void> _takeMeasurementPhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (photo == null || !mounted) return;

    setState(() {
      _measuredValue = null;
    });

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PhotoMeasureDialog(
        imagePath: photo.path,
        mode: _mode,
        isMetric: _isMetric,
        knownHeight: _knownHeight,
        onResult: (value) {
          if (mounted) setState(() => _measuredValue = value);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D1117),
          foregroundColor: Colors.white,
          title: const Text('AR Measure',
              style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
          actions: [
            Switch(
              value: _isMetric,
              onChanged: (v) => setState(() { _isMetric = v; _measuredValue = null; }),
              activeColor: const Color(0xFF00E5FF),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(_isMetric ? 'm' : 'ft',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Mode selector ────────────────────────────────────────────────
            Container(
              color: const Color(0xFF0D1117),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: MeasureMode.values.map((m) {
                  final selected = m == _mode;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() { _mode = m; _measuredValue = null; }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? const Color(0xFF00E5FF) : Colors.white24,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              m == MeasureMode.treeHeight
                                  ? Icons.park_rounded
                                  : m == MeasureMode.canopyWidth
                                      ? Icons.device_hub_rounded
                                      : Icons.straighten_rounded,
                              color: selected ? const Color(0xFF00E5FF) : Colors.white38,
                              size: 20,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m == MeasureMode.treeHeight
                                  ? 'Height'
                                  : m == MeasureMode.canopyWidth
                                      ? 'Canopy'
                                      : 'Distance',
                              style: TextStyle(
                                color: selected ? const Color(0xFF00E5FF) : Colors.white38,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // ── Instruction card ─────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Result display
                    if (_measuredValue != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF00E5FF).withValues(alpha: 0.15),
                              const Color(0xFF2979FF).withValues(alpha: 0.10),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            Icon(_modeIcon, color: const Color(0xFF00E5FF), size: 36),
                            const SizedBox(height: 8),
                            Text(
                              _modeLabel,
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isMetric
                                  ? '${_measuredValue!.toStringAsFixed(2)} m'
                                  : '${(_measuredValue! * 3.28084).toStringAsFixed(2)} ft',
                              style: const TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Instructions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_modeIcon, color: const Color(0xFF00E5FF), size: 20),
                              const SizedBox(width: 8),
                              Text(_modeLabel,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _modeInstructions,
                            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Known height input (for tree height mode)
                    if (_mode == MeasureMode.treeHeight) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Reference Person Height',
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                            Slider(
                              value: _knownHeight,
                              min: 1.4,
                              max: 2.1,
                              divisions: 14,
                              activeColor: const Color(0xFF00E5FF),
                              label: '${_knownHeight.toStringAsFixed(2)} m',
                              onChanged: (v) => setState(() => _knownHeight = v),
                            ),
                            Text(
                              '${_knownHeight.toStringAsFixed(2)} m  (${(_knownHeight * 3.28084).toStringAsFixed(1)} ft)',
                              style: const TextStyle(
                                  color: Color(0xFF00E5FF), fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Camera button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _takeMeasurementPhoto,
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: const Text('Open Camera & Measure'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Works offline — no ARCore required',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
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

/// Dialog shown after taking a photo — user taps two points to measure
class _PhotoMeasureDialog extends StatefulWidget {
  final String imagePath;
  final MeasureMode mode;
  final bool isMetric;
  final double knownHeight;
  final void Function(double) onResult;

  const _PhotoMeasureDialog({
    required this.imagePath,
    required this.mode,
    required this.isMetric,
    required this.knownHeight,
    required this.onResult,
  });

  @override
  State<_PhotoMeasureDialog> createState() => _PhotoMeasureDialogState();
}

class _PhotoMeasureDialogState extends State<_PhotoMeasureDialog> {
  Offset? _pointA;
  Offset? _pointB;
  Offset? _pointC;
  Offset? _pointD;
  int _step = 0; // 0=tap ref top, 1=tap ref bottom, 2=tap obj top, 3=tap obj bottom
  double? _result;

  String get _stepInstruction {
    if (widget.mode == MeasureMode.treeHeight) {
      switch (_step) {
        case 0: return 'Tap TOP of the person (reference)';
        case 1: return 'Tap BOTTOM of the person (feet)';
        case 2: return 'Tap TOP of the tree';
        case 3: return 'Tap BOTTOM of the tree';
        default: return 'Done';
      }
    } else {
      switch (_step) {
        case 0: return 'Tap first point (A)';
        case 1: return 'Tap second point (B)';
        default: return 'Done';
      }
    }
  }

  void _onTap(TapDownDetails details, BoxConstraints constraints) {
    final pos = details.localPosition;
    setState(() {
      if (widget.mode == MeasureMode.treeHeight) {
        switch (_step) {
          case 0: _pointA = pos; _step = 1; break;
          case 1: _pointB = pos; _step = 2; break;
          case 2: _pointC = pos; _step = 3; break;
          case 3:
            _pointD = pos;
            _step = 4;
            _calculateTreeHeight(constraints);
            break;
        }
      } else {
        switch (_step) {
          case 0: _pointA = pos; _step = 1; break;
          case 1:
            _pointB = pos;
            _step = 2;
            _calculateSimple();
            break;
        }
      }
    });
  }

  void _calculateTreeHeight(BoxConstraints c) {
    if (_pointA == null || _pointB == null || _pointC == null || _pointD == null) return;
    final refPx = (_pointA! - _pointB!).distance;
    final objPx = (_pointC! - _pointD!).distance;
    if (refPx < 1) return;
    final ratio = widget.knownHeight / refPx; // metres per pixel
    _result = objPx * ratio;
    widget.onResult(_result!);
  }

  void _calculateSimple() {
    if (_pointA == null || _pointB == null) return;
    // For distance/canopy: pixel distance → use image diagonal as reference scale
    final px = (_pointA! - _pointB!).distance;
    // Provide a rough scale — user should calibrate with known reference
    _result = px * 0.01; // rough 1px ≈ 1cm at ~2m distance
    widget.onResult(_result!);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Step instruction
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF00E5FF),
            child: Text(
              _step < 4 ? _stepInstruction : '✅  Measurement complete',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          // Photo with tap overlay
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) => GestureDetector(
                onTapDown: _step < 4
                    ? (d) => _onTap(d, constraints)
                    : null,
                child: Stack(
                  children: [
                    Image.asset(
                      widget.imagePath,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Image.network(
                        widget.imagePath,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        fit: BoxFit.contain,
                      ),
                    ),
                    // Draw dots
                    for (final entry in {
                      'A': _pointA,
                      'B': _pointB,
                      'C': _pointC,
                      'D': _pointD,
                    }.entries)
                      if (entry.value != null)
                        Positioned(
                          left: entry.value!.dx - 12,
                          top: entry.value!.dy - 12,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: entry.key == 'A' || entry.key == 'C'
                                  ? Colors.red
                                  : Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Center(
                              child: Text(entry.key,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10)),
                            ),
                          ),
                        ),
                    // Draw measurement line
                    if (_pointA != null && _pointB != null)
                      CustomPaint(
                        painter: _LinePainter(
                          from: _pointA!,
                          to: _pointB!,
                          color: Colors.yellow,
                        ),
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                    if (_pointC != null && _pointD != null)
                      CustomPaint(
                        painter: _LinePainter(
                          from: _pointC!,
                          to: _pointD!,
                          color: const Color(0xFF00E5FF),
                        ),
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Result bar + buttons
          Container(
            color: const Color(0xFF0D1117),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (_result != null)
                  Expanded(
                    child: Text(
                      '${(_result!).toStringAsFixed(2)} m  ≈  ${(_result! * 3.28084).toStringAsFixed(2)} ft',
                      style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  const Expanded(
                    child: Text('Tap on the photo to measure',
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _pointA = _pointB = _pointC = _pointD = null;
                      _step = 0;
                      _result = null;
                    });
                  },
                  child: const Text('Reset', style: TextStyle(color: Colors.orange)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Color(0xFF00E5FF))),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final Color color;

  const _LinePainter({required this.from, required this.to, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(from, to, paint);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.from != from || old.to != to;
}
