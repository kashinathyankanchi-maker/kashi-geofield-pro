class KmlFileModel {
  final int? id;
  final String filename;
  final String filepath;
  final String layerColor;
  final bool isVisible;
  final String createdAt;

  const KmlFileModel({
    this.id,
    required this.filename,
    required this.filepath,
    required this.layerColor,
    this.isVisible = true,
    required this.createdAt,
  });

  factory KmlFileModel.fromMap(Map<String, dynamic> map) => KmlFileModel(
        id: map['id'] as int?,
        filename: map['filename'] as String,
        filepath: map['filepath'] as String,
        layerColor: map['layer_color'] as String? ?? '#2EA043',
        isVisible: (map['is_visible'] as int? ?? 1) == 1,
        createdAt: map['created_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'filename': filename,
        'filepath': filepath,
        'layer_color': layerColor,
        'is_visible': isVisible ? 1 : 0,
        'created_at': createdAt,
      };

  KmlFileModel copyWith({bool? isVisible, String? layerColor}) => KmlFileModel(
        id: id,
        filename: filename,
        filepath: filepath,
        layerColor: layerColor ?? this.layerColor,
        isVisible: isVisible ?? this.isVisible,
        createdAt: createdAt,
      );
}
