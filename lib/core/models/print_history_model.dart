class PrintHistoryModel {
  final int? id;
  final String mapType;
  final String mapName;
  final String pdfPath;
  final String printedAt;

  const PrintHistoryModel({
    this.id,
    required this.mapType,
    required this.mapName,
    required this.pdfPath,
    required this.printedAt,
  });

  factory PrintHistoryModel.fromMap(Map<String, dynamic> map) =>
      PrintHistoryModel(
        id: map['id'] as int?,
        mapType: map['map_type'] as String,
        mapName: map['map_name'] as String,
        pdfPath: map['pdf_path'] as String,
        printedAt: map['printed_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'map_type': mapType,
        'map_name': mapName,
        'pdf_path': pdfPath,
        'printed_at': printedAt,
      };
}
