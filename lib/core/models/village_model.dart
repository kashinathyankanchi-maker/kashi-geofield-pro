class VillageModel {
  final int? id;
  final String villageName;
  final String district;
  final String state;
  final String coordinates; // JSON encoded polygon coords
  final double areaHectares;
  final String sourceFile;
  final String createdAt;

  const VillageModel({
    this.id,
    required this.villageName,
    required this.district,
    required this.state,
    required this.coordinates,
    required this.areaHectares,
    required this.sourceFile,
    required this.createdAt,
  });

  factory VillageModel.fromMap(Map<String, dynamic> map) => VillageModel(
        id: map['id'] as int?,
        villageName: map['village_name'] as String,
        district: map['district'] as String? ?? '',
        state: map['state'] as String? ?? '',
        coordinates: map['coordinates'] as String,
        areaHectares: (map['area_hectares'] as num).toDouble(),
        sourceFile: map['source_file'] as String? ?? '',
        createdAt: map['created_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'village_name': villageName,
        'district': district,
        'state': state,
        'coordinates': coordinates,
        'area_hectares': areaHectares,
        'source_file': sourceFile,
        'created_at': createdAt,
      };

  double get areaAcres => areaHectares * 2.47105;
}
