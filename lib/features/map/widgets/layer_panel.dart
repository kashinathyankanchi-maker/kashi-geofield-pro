import 'package:flutter/material.dart';
import '../map_controller.dart';
import '../../../shared/theme.dart';
import '../../globe/earth_3d_screen.dart';

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
                color: Colors.black.withValues(alpha: 0.3),
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
              // Map Style Toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'Street', label: Text('Street', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: 'Satellite', label: Text('Satellite', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {controller.mapStyle},
                        onSelectionChanged: (Set<String> newSelection) {
                          controller.setMapStyle(newSelection.first);
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: WidgetStateProperty.resolveWith<Color>(
                            (Set<WidgetState> states) {
                              if (states.contains(WidgetState.selected)) {
                                return AppTheme.greenPrimary.withValues(alpha: 0.2);
                              }
                              return Colors.transparent;
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 3D Google Earth Mode Launch Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: InkWell(
                  onTap: () {
                    onClose();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const Earth3dScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF00E5FF).withValues(alpha: 0.2),
                          const Color(0xFF2979FF).withValues(alpha: 0.2),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00E5FF), width: 1.2),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.public_rounded, color: Color(0xFF00E5FF), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Launch 3D Google Earth Mode',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF00E5FF), size: 12),
                      ],
                    ),
                  ),
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

              // Fire Layer
              _LayerToggle(
                icon: Icons.local_fire_department,
                label: 'Active Fires (FIRMS)',
                color: Colors.redAccent,
                isVisible: controller.showFireLayer,
                count: controller.fireIncidents.length,
                onToggle: controller.toggleFireLayer,
              ),

              const Divider(height: 1, color: AppTheme.borderColor),

              // My Shapes List
              if (controller.drawnShapes.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'My Shapes',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: controller.drawnShapes.length,
                    itemBuilder: (context, index) {
                      final shape = controller.drawnShapes[index];
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: Icon(
                          shape.type == DrawMode.path ? Icons.timeline : Icons.pentagon,
                          color: shape.color,
                          size: 16,
                        ),
                        title: Text(
                          shape.name,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.errorColor, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            controller.deleteShape(shape.id);
                          },
                        ),
                        onTap: () {
                          controller.selectShape(shape);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],

              const Divider(height: 1, color: AppTheme.borderColor),
              
              // Offline Tool
              InkWell(
                onTap: () {
                  onClose();
                  controller.toggleOfflineDownloadMode();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.download_for_offline, color: AppTheme.textPrimary, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Download Map Area',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
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
