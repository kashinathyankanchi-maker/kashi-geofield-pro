class KmlFileModel {
  final int? id;
  final String filename;
  final String filepath;
  final String layerColor;
  final bool isVisible;
  final double opacity; // 0.0 to 1.0
  final bool smartOpacity; // Smart Background Opacity enabled
  final String createdAt;

  const KmlFileModel({
    this.id,
    required this.filename,
    required this.filepath,
    required this.layerColor,
    this.isVisible = true,
    this.opacity = 1.0,
    this.smartOpacity = false,
    required this.createdAt,
  });

  factory KmlFileModel.fromMap(Map<String, dynamic> map) => KmlFileModel(
        id: map['id'] as int?,
        filename: map['filename'] as String,
        filepath: map['filepath'] as String,
        layerColor: map['layer_color'] as String? ?? '#2EA043',
        isVisible: (map['is_visible'] as int? ?? 1) == 1,
        opacity: (map['opacity'] as num? ?? 100).toDouble() / 100.0,
        smartOpacity: (map['smart_opacity'] as int? ?? 0) == 1,
        createdAt: map['created_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'filename': filename,
        'filepath': filepath,
        'layer_color': layerColor,
        'is_visible': isVisible ? 1 : 0,
        'opacity': (opacity * 100).round(),
        'smart_opacity': smartOpacity ? 1 : 0,
        'created_at': createdAt,
      };

  KmlFileModel copyWith({bool? isVisible, String? layerColor, double? opacity, bool? smartOpacity}) => KmlFileModel(
        id: id,
        filename: filename,
        filepath: filepath,
        layerColor: layerColor ?? this.layerColor,
        isVisible: isVisible ?? this.isVisible,
        opacity: opacity ?? this.opacity,
        smartOpacity: smartOpacity ?? this.smartOpacity,
        createdAt: createdAt,
      );
}
