import 'package:flutter/material.dart';
import '../map_controller.dart';
import '../../../shared/theme.dart';

class LayerPanel extends StatelessWidget {
  final MapController controller;
  final VoidCallback onClose;

  const LayerPanel({
    super.key,
    required this.controller,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          width: 220,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.layers, color: AppTheme.greenAccent, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Map Layers',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.borderColor),

              // Polygon layer
              _LayerToggle(
                icon: Icons.pentagon,
                label: 'Drawn Polygons',
                color: AppTheme.greenPrimary,
                isVisible: controller.showPolygonLayer,
                count: controller.drawnShapes
                    .where((s) => s.type == DrawMode.polygon)
                    .length,
                onToggle: controller.togglePolygonLayer,
              ),

              // Village layer
              _LayerToggle(
                icon: Icons.location_city,
                label: 'Village Boundaries',
                color: const Color(0xFF388BFD),
                isVisible: controller.showVillageLayer,
                onToggle: controller.toggleVillageLayer,
              ),

              // KML layer
              _LayerToggle(
                icon: Icons.file_present,
                label: 'KML Layers',
                color: const Color(0xFFD29922),
                isVisible: controller.showKmlLayer,
                count: controller.kmlShapes.length,
                onToggle: controller.toggleKmlLayer,
              ),

              const Divider(height: 1, color: AppTheme.borderColor),

              // Legend
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Legend',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...AppTheme.polygonColors.take(4).map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: c.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(color: c),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _colorLabel(c),
                                style: const TextStyle(
                                    color: AppTheme.textSecondary, fontSize: 11),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _colorLabel(Color c) {
    if (c == AppTheme.greenPrimary) return 'Polygon';
    if (c == const Color(0xFF388BFD)) return 'Path';
    if (c == const Color(0xFFF85149)) return 'Highlight';
    if (c == const Color(0xFFD29922)) return 'KML';
    return 'Custom';
  }
}

class _LayerToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isVisible;
  final int? count;
  final VoidCallback onToggle;

  const _LayerToggle({
    required this.icon,
    required this.label,
    required this.color,
    required this.isVisible,
    required this.onToggle,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: isVisible ? color : AppTheme.textMuted, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isVisible ? AppTheme.textPrimary : AppTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            if (count != null && count! > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              isVisible ? Icons.visibility : Icons.visibility_off,
              size: 16,
              color: isVisible ? color : AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
