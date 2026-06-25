class PolygonModel {
  final int? id;
  final String name;
  final String coordinates; // JSON encoded list of {lat, lng}
  final double areaHectares;
  final double perimeterMeters;
  final String color; // hex color string
  final String createdAt;

  const PolygonModel({
    this.id,
    required this.name,
    required this.coordinates,
    required this.areaHectares,
    required this.perimeterMeters,
    required this.color,
    required this.createdAt,
  });

  factory PolygonModel.fromMap(Map<String, dynamic> map) => PolygonModel(
        id: map['id'] as int?,
        name: map['name'] as String,
        coordinates: map['coordinates'] as String,
        areaHectares: map['area_hectares'] as double,
        perimeterMeters: map['perimeter_meters'] as double,
        color: map['color'] as String,
        createdAt: map['created_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'coordinates': coordinates,
        'area_hectares': areaHectares,
        'perimeter_meters': perimeterMeters,
        'color': color,
        'created_at': createdAt,
      };

  double get areaAcres => areaHectares * 2.47105;
  double get areaSqMeters => areaHectares * 10000;
  double get perimeterKm => perimeterMeters / 1000;

  PolygonModel copyWith({
    int? id,
    String? name,
    String? coordinates,
    double? areaHectares,
    double? perimeterMeters,
    String? color,
    String? createdAt,
  }) =>
      PolygonModel(
        id: id ?? this.id,
        name: name ?? this.name,
        coordinates: coordinates ?? this.coordinates,
        areaHectares: areaHectares ?? this.areaHectares,
        perimeterMeters: perimeterMeters ?? this.perimeterMeters,
        color: color ?? this.color,
        createdAt: createdAt ?? this.createdAt,
      );
}
