class DutyDiaryModel {
  final int? id;
  final String date;          // YYYY-MM-DD

  // New Kannada diary format fields
  final String campStation;   // ಕೇಂದ್ರ, ಸ್ಥಾನ (ಮುಕ್ಕಾಂ)
  final String departureTime; // ಹೊರಟ ವೇಳೆ
  final String placesVisited; // ತಿರುಗಾಡಿದ ಸ್ಥಳ
  final String returnTime;    // ಹಿಂತಿರುಗಿದ ವೇಳೆ
  final String modeAndKm;     // ತಿರುಗಾಡಿದ ರೀತಿ & ಕಿ.ಮೀ
  final String workDone;      // ಕೆಲಸ ಮಾಡಿದ ವಿವರ

  // Legacy fields kept for backward-compatible DB reads
  final String time;
  final String locations;
  final String activities;
  final double distance;

  final String createdAt;

  DutyDiaryModel({
    this.id,
    required this.date,
    this.campStation = '',
    this.departureTime = '',
    this.placesVisited = '',
    this.returnTime = '',
    this.modeAndKm = '',
    this.workDone = '',
    // Legacy
    this.time = '',
    this.locations = '',
    this.activities = '',
    this.distance = 0,
    required this.createdAt,
  });

  factory DutyDiaryModel.fromMap(Map<String, dynamic> map) {
    return DutyDiaryModel(
      id: map['id'] as int?,
      date: map['date'] as String? ?? '',
      campStation:   map['camp_station']   as String? ?? '',
      departureTime: map['departure_time'] as String? ?? '',
      placesVisited: map['places_visited'] as String? ?? '',
      returnTime:    map['return_time']    as String? ?? '',
      modeAndKm:     map['mode_and_km']   as String? ?? '',
      workDone:      map['work_done']     as String? ?? '',
      // Legacy
      time:       map['time']       as String? ?? '',
      locations:  map['locations']  as String? ?? '',
      activities: map['activities'] as String? ?? '',
      distance:   (map['distance'] as num?)?.toDouble() ?? 0.0,
      createdAt:  map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'date':           date,
      'camp_station':   campStation,
      'departure_time': departureTime,
      'places_visited': placesVisited,
      'return_time':    returnTime,
      'mode_and_km':    modeAndKm,
      'work_done':      workDone,
      // Legacy — still written so old queries don't break
      'time':       time,
      'locations':  locations,
      'activities': activities,
      'distance':   distance,
      'created_at': createdAt,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  DutyDiaryModel copyWith({
    int? id,
    String? date,
    String? campStation,
    String? departureTime,
    String? placesVisited,
    String? returnTime,
    String? modeAndKm,
    String? workDone,
    String? time,
    String? locations,
    String? activities,
    double? distance,
    String? createdAt,
  }) {
    return DutyDiaryModel(
      id:            id            ?? this.id,
      date:          date          ?? this.date,
      campStation:   campStation   ?? this.campStation,
      departureTime: departureTime ?? this.departureTime,
      placesVisited: placesVisited ?? this.placesVisited,
      returnTime:    returnTime    ?? this.returnTime,
      modeAndKm:     modeAndKm    ?? this.modeAndKm,
      workDone:      workDone     ?? this.workDone,
      time:          time         ?? this.time,
      locations:     locations    ?? this.locations,
      activities:    activities   ?? this.activities,
      distance:      distance     ?? this.distance,
      createdAt:     createdAt    ?? this.createdAt,
    );
  }
}
