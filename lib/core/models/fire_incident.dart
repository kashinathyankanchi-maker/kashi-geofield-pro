class FireIncident {
  final double latitude;
  final double longitude;
  final double brightness; // Brightness temperature
  final double confidence; // Confidence (0-100)
  final String acqDate;   // Acquisition date
  final String acqTime;   // Acquisition time
  final String satellite; // Which satellite detected this fire

  const FireIncident({
    required this.latitude,
    required this.longitude,
    required this.brightness,
    required this.confidence,
    required this.acqDate,
    required this.acqTime,
    this.satellite = 'Unknown',
  });

  factory FireIncident.fromCsvRow(List<String> row, List<String> headers) {
    int latIdx    = headers.indexOf('latitude');
    int lngIdx    = headers.indexOf('longitude');
    int brightIdx = headers.indexOf('bright_ti4'); // VIIRS
    if (brightIdx == -1) brightIdx = headers.indexOf('brightness'); // MODIS
    int confIdx   = headers.indexOf('confidence');
    int dateIdx   = headers.indexOf('acq_date');
    int timeIdx   = headers.indexOf('acq_time');
    int satIdx    = headers.indexOf('satellite');

    double parseConf(String val) {
      switch (val.toLowerCase()) {
        case 'l':
        case 'low':    return 30.0;
        case 'n':
        case 'nominal': return 50.0;
        case 'h':
        case 'high':   return 90.0;
        default:       return double.tryParse(val) ?? 0.0;
      }
    }

    return FireIncident(
      latitude:   latIdx    != -1 ? (double.tryParse(row[latIdx])    ?? 0.0) : 0.0,
      longitude:  lngIdx    != -1 ? (double.tryParse(row[lngIdx])    ?? 0.0) : 0.0,
      brightness: brightIdx != -1 ? (double.tryParse(row[brightIdx]) ?? 0.0) : 0.0,
      confidence: confIdx   != -1 ? parseConf(row[confIdx]) : 0.0,
      acqDate:    dateIdx   != -1 ? row[dateIdx] : '',
      acqTime:    timeIdx   != -1 ? row[timeIdx] : '',
      satellite:  satIdx    != -1 ? row[satIdx]  : 'Unknown',
    );
  }

  /// High confidence fire (>= 80%)
  bool get isHighConfidence => confidence >= 80;

  /// Formatted tooltip string for map display
  String get tooltipText =>
      'Fire detected\n$satellite\n$acqDate ${acqTime.isNotEmpty ? acqTime.substring(0, 2) + ':' + acqTime.substring(2) : ''} UTC\nConf: ${confidence.toStringAsFixed(0)}%';
}
