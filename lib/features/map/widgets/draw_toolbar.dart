import 'package:flutter/material.dart';
import '../map_controller.dart';
import '../../../shared/theme.dart';

class DrawToolbar extends StatelessWidget {
  final MapController controller;

  const DrawToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
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
              // Drag handle
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const Icon(Icons.drag_indicator, size: 16, color: AppTheme.textMuted),
              ),
              _ToolButton(
                icon: Icons.pentagon_outlined,
                label: 'Polygon',
                isActive: controller.drawMode == DrawMode.polygon,
                color: AppTheme.greenPrimary,
                onTap: () {
                  if (controller.drawMode == DrawMode.polygon) {
                    controller.setDrawMode(DrawMode.none);
                  } else {
                    controller.setDrawMode(DrawMode.polygon);
                  }
                },
              ),
              _ToolButton(
                icon: Icons.polyline_outlined,
                label: 'Path',
                isActive: controller.drawMode == DrawMode.path,
                color: AppTheme.infoColor,
                onTap: () {
                  if (controller.drawMode == DrawMode.path) {
                    controller.setDrawMode(DrawMode.none);
                  } else {
                    controller.setDrawMode(DrawMode.path);
                  }
                },
              ),
              _ToolButton(
                icon: Icons.place_outlined,
                label: 'Marker',
                isActive: controller.drawMode == DrawMode.marker,
                color: AppTheme.errorColor,
                onTap: () {
                  if (controller.drawMode == DrawMode.marker) {
                    controller.setDrawMode(DrawMode.none);
                  } else {
                    controller.setDrawMode(DrawMode.marker);
                  }
                },
              ),
              const Divider(height: 1, color: AppTheme.borderColor),
              // Undo
              _ToolButton(
                icon: Icons.undo,
                label: 'Undo',
                isActive: false,
                color: AppTheme.textSecondary,
                onTap: controller.canUndo ? controller.undo : null,
              ),
              // Redo
              _ToolButton(
                icon: Icons.redo,
                label: 'Redo',
                isActive: false,
                color: AppTheme.textSecondary,
                onTap: controller.canRedo ? controller.redo : null,
              ),
              if (controller.drawMode == DrawMode.polygon &&
                  controller.currentPoints.length >= 3) ...[
                const Divider(height: 1, color: AppTheme.borderColor),
                _ToolButton(
                  icon: Icons.check_circle,
                  label: 'Close',
                  isActive: false,
                  color: AppTheme.greenAccent,
                  onTap: () => controller.closePolygon(context),
                ),
              ],
              if (controller.drawMode == DrawMode.path &&
                  controller.currentPoints.length >= 2) ...[
                const Divider(height: 1, color: AppTheme.borderColor),
                _ToolButton(
                  icon: Icons.check_circle,
                  label: 'Save',
                  isActive: false,
                  color: AppTheme.greenAccent,
                  onTap: controller.finalizePath,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color color;
  final VoidCallback? onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      preferBelow: false,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: onTap == null
                ? AppTheme.textMuted
                : isActive
                    ? color
                    : AppTheme.textSecondary,
            size: 22,
          ),
        ),
      ),
    );
  }
}
