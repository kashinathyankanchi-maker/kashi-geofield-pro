import 'package:flutter/material.dart';
import '../../../shared/theme.dart';
import '../map_controller.dart';

/// Fixed horizontal bottom toolbar — always visible, never dragged off screen.
class DrawToolbar extends StatelessWidget {
  final MapController controller;

  const DrawToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isDrawingPolygon = controller.drawMode == DrawMode.polygon;
        final isDrawingPath = controller.drawMode == DrawMode.path;
        final isDrawingMarker = controller.drawMode == DrawMode.marker;
        final canClose = isDrawingPolygon && controller.currentPoints.length >= 3;
        final canSavePath = isDrawingPath && controller.currentPoints.length >= 2;

        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            border: Border(top: BorderSide(color: AppTheme.borderColor, width: 1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Draw Polygon
              _ToolBtn(
                icon: Icons.pentagon_outlined,
                label: 'Polygon',
                isActive: isDrawingPolygon,
                activeColor: AppTheme.greenPrimary,
                onTap: () => controller.drawMode == DrawMode.polygon
                    ? controller.setDrawMode(DrawMode.none)
                    : controller.setDrawMode(DrawMode.polygon),
              ),
              // Draw Path
              _ToolBtn(
                icon: Icons.polyline_outlined,
                label: 'Path',
                isActive: isDrawingPath,
                activeColor: AppTheme.infoColor,
                onTap: () => controller.drawMode == DrawMode.path
                    ? controller.setDrawMode(DrawMode.none)
                    : controller.setDrawMode(DrawMode.path),
              ),
              // Place Marker
              _ToolBtn(
                icon: Icons.place_outlined,
                label: 'Marker',
                isActive: isDrawingMarker,
                activeColor: AppTheme.errorColor,
                onTap: () => controller.drawMode == DrawMode.marker
                    ? controller.setDrawMode(DrawMode.none)
                    : controller.setDrawMode(DrawMode.marker),
              ),

              Container(width: 1, height: 36, color: AppTheme.borderColor),

              // Undo
              _ToolBtn(
                icon: Icons.undo_rounded,
                label: 'Undo',
                isActive: false,
                activeColor: AppTheme.textSecondary,
                onTap: controller.canUndo ? controller.undo : null,
              ),
              // Redo
              _ToolBtn(
                icon: Icons.redo_rounded,
                label: 'Redo',
                isActive: false,
                activeColor: AppTheme.textSecondary,
                onTap: controller.canRedo ? controller.redo : null,
              ),

              // Show Close/Save only when relevant
              if (canClose || canSavePath) ...[
                Container(width: 1, height: 36, color: AppTheme.borderColor),
                _ToolBtn(
                  icon: Icons.check_circle_rounded,
                  label: canClose ? 'Close' : 'Save',
                  isActive: true,
                  activeColor: AppTheme.greenAccent,
                  onTap: canClose
                      ? () => controller.closePolygon(context)
                      : controller.finalizePath,
                ),
              ],

              const Spacer(),

              // Cancel drawing
              if (controller.drawMode != DrawMode.none)
                _ToolBtn(
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                  isActive: false,
                  activeColor: AppTheme.errorColor,
                  onTap: () => controller.setDrawMode(DrawMode.none),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: isActive
                    ? activeColor
                    : enabled
                        ? AppTheme.textSecondary
                        : AppTheme.textMuted,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: isActive
                      ? activeColor
                      : enabled
                          ? AppTheme.textSecondary
                          : AppTheme.textMuted,
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
