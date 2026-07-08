import 'package:flutter/material.dart';
import '../../../shared/theme.dart';

class QuarterGirthCalculator extends StatefulWidget {
  const QuarterGirthCalculator({super.key});

  @override
  State<QuarterGirthCalculator> createState() => _QuarterGirthCalculatorState();
}

class _QuarterGirthCalculatorState extends State<QuarterGirthCalculator> {
  final TextEditingController _girthCtrl = TextEditingController();
  final TextEditingController _lengthCtrl = TextEditingController();
  String _result = '';
  String _unit = 'Meters'; // 'Meters' or 'Feet'

  void _calculate() {
    final gStr = _girthCtrl.text.trim();
    final lStr = _lengthCtrl.text.trim();

    if (gStr.isEmpty || lStr.isEmpty) {
      setState(() => _result = 'Please enter both values');
      return;
    }

    final g = double.tryParse(gStr);
    final l = double.tryParse(lStr);

    if (g == null || l == null) {
      setState(() => _result = 'Invalid number format');
      return;
    }

    // Formula: Volume = (Girth / 4)^2 * Length
    final volume = (g / 4) * (g / 4) * l;
    
    if (_unit == 'Meters') {
      setState(() {
        _result = '${volume.toStringAsFixed(4)} Cubic Meters (m³)';
      });
    } else {
      // In Feet, standard Hoppus volume is in Hoppus cubic feet
      setState(() {
        _result = '${volume.toStringAsFixed(4)} Hoppus Feet (hft)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0D1410),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.borderBright, width: 1),
      ),
      title: const Row(
        children: [
          Icon(Icons.calculate_rounded, color: AppTheme.greenAccent, size: 20),
          SizedBox(width: 8),
          Text(
            'QUARTER GIRTH CALC',
            style: TextStyle(
              color: AppTheme.greenAccent,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unit Switcher
            Row(
              children: [
                const Text(
                  'UNIT:',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Meters', label: Text('METERS')),
                      ButtonSegment(value: 'Feet', label: Text('FEET')),
                    ],
                    selected: {_unit},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() {
                        _unit = newSelection.first;
                        _result = ''; // clear on unit change
                      });
                    },
                    style: SegmentedButton.styleFrom(
                      backgroundColor: AppTheme.bgSurface,
                      selectedBackgroundColor: AppTheme.greenDim,
                      foregroundColor: AppTheme.textSecondary,
                      selectedForegroundColor: AppTheme.greenAccent,
                      textStyle: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      side: const BorderSide(color: AppTheme.borderColor),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Girth Input
            TextField(
              controller: _girthCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                labelText: 'Girth (Circumference)',
                labelStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7)),
                suffixText: _unit == 'Meters' ? 'm' : 'ft',
                suffixStyle: const TextStyle(color: AppTheme.greenAccent),
                filled: true,
                fillColor: AppTheme.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppTheme.borderColor, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppTheme.borderColor, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppTheme.greenAccent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Length Input
            TextField(
              controller: _lengthCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                labelText: 'Length of Log',
                labelStyle: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7)),
                suffixText: _unit == 'Meters' ? 'm' : 'ft',
                suffixStyle: const TextStyle(color: AppTheme.greenAccent),
                filled: true,
                fillColor: AppTheme.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppTheme.borderColor, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppTheme.borderColor, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppTheme.greenAccent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Calculate Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.greenPrimary,
                  foregroundColor: AppTheme.greenAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: AppTheme.greenAccent, width: 1),
                  ),
                ),
                onPressed: _calculate,
                child: const Text(
                  'CALCULATE VOLUME',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 2.0,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            
            // Result Display
            if (_result.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.greenAccent.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'ESTIMATED VOLUME:',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _result,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppTheme.greenAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
            side: const BorderSide(color: AppTheme.borderColor),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE', style: TextStyle(fontFamily: 'monospace', letterSpacing: 1.5)),
        ),
      ],
    );
  }
}
