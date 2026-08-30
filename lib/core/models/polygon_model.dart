class PolygonModel {
  final int? id;
  final String name;
  final String coordinates; // JSON encoded list of {lat, lng}
  final double areaHectares;
  final double perimeterMeters;
  final String color; // hex color string
  final String createdAt;

  // Marker metadata (nullable, mostly used when representing points)
  final String? description;
  final String? category;
  final String? photoPath;
  final String? voiceNotePath;
  final String? officerName;
  final String? gpsAccuracy;
  final String? altitude;

  const PolygonModel({
    this.id,
    required this.name,
    required this.coordinates,
    required this.areaHectares,
    required this.perimeterMeters,
    required this.color,
    required this.createdAt,
    this.description,
    this.category,
    this.photoPath,
    this.voiceNotePath,
    this.officerName,
    this.gpsAccuracy,
    this.altitude,
  });

  factory PolygonModel.fromMap(Map<String, dynamic> map) => PolygonModel(
        id: map['id'] as int?,
        name: map['name'] as String,
        coordinates: map['coordinates'] as String,
        areaHectares: map['area_hectares'] as double,
        perimeterMeters: map['perimeter_meters'] as double,
        color: map['color'] as String,
        createdAt: map['created_at'] as String,
        description: map['description'] as String?,
        category: map['category'] as String?,
        photoPath: map['photo_path'] as String?,
        voiceNotePath: map['voice_note_path'] as String?,
        officerName: map['officer_name'] as String?,
        gpsAccuracy: map['gps_accuracy'] as String?,
        altitude: map['altitude'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'coordinates': coordinates,
        'area_hectares': areaHectares,
        'perimeter_meters': perimeterMeters,
        'color': color,
        'created_at': createdAt,
        if (description != null) 'description': description,
        if (category != null) 'category': category,
        if (photoPath != null) 'photo_path': photoPath,
        if (voiceNotePath != null) 'voice_note_path': voiceNotePath,
        if (officerName != null) 'officer_name': officerName,
        if (gpsAccuracy != null) 'gps_accuracy': gpsAccuracy,
        if (altitude != null) 'altitude': altitude,
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
    String? description,
    String? category,
    String? photoPath,
    String? voiceNotePath,
    String? officerName,
    String? gpsAccuracy,
    String? altitude,
  }) =>
      PolygonModel(
        id: id ?? this.id,
        name: name ?? this.name,
        coordinates: coordinates ?? this.coordinates,
        areaHectares: areaHectares ?? this.areaHectares,
        perimeterMeters: perimeterMeters ?? this.perimeterMeters,
        color: color ?? this.color,
        createdAt: createdAt ?? this.createdAt,
        description: description ?? this.description,
        category: category ?? this.category,
        photoPath: photoPath ?? this.photoPath,
        voiceNotePath: voiceNotePath ?? this.voiceNotePath,
        officerName: officerName ?? this.officerName,
        gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
        altitude: altitude ?? this.altitude,
      );
}
