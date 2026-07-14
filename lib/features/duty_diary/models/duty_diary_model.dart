class DutyDiaryModel {
  final int? id;
  final String date; // YYYY-MM-DD
  final String time; // HH:MM
  final String locations;
  final String activities;
  final double distance;
  final String createdAt;

  DutyDiaryModel({
    this.id,
    required this.date,
    required this.time,
    required this.locations,
    required this.activities,
    required this.distance,
    required this.createdAt,
  });

  factory DutyDiaryModel.fromMap(Map<String, dynamic> map) {
    return DutyDiaryModel(
      id: map['id'] as int?,
      date: map['date'] as String,
      time: map['time'] as String,
      locations: map['locations'] as String,
      activities: map['activities'] as String,
      distance: (map['distance'] as num).toDouble(),
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'date': date,
      'time': time,
      'locations': locations,
      'activities': activities,
      'distance': distance,
      'created_at': createdAt,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  DutyDiaryModel copyWith({
    int? id,
    String? date,
    String? time,
    String? locations,
    String? activities,
    double? distance,
    String? createdAt,
  }) {
    return DutyDiaryModel(
      id: id ?? this.id,
      date: date ?? this.date,
      time: time ?? this.time,
      locations: locations ?? this.locations,
      activities: activities ?? this.activities,
      distance: distance ?? this.distance,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

