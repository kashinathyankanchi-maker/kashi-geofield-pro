class FireIncident {
  final double latitude;
  final double longitude;
  final double brightness; // Brightness temperature
  final double confidence; // Confidence (usually 0-100 or specific strings)
  final String acqDate; // Acquisition date
  final String acqTime; // Acquisition time

  const FireIncident({
    required this.latitude,
    required this.longitude,
    required this.brightness,
    required this.confidence,
    required this.acqDate,
    required this.acqTime,
  });

  factory FireIncident.fromCsvRow(List<String> row, List<String> headers) {
    int latIdx = headers.indexOf('latitude');
    int lngIdx = headers.indexOf('longitude');
    int brightIdx = headers.indexOf('bright_ti4'); // VIIRS uses bright_ti4, MODIS uses brightness
    if (brightIdx == -1) brightIdx = headers.indexOf('brightness');
    int confIdx = headers.indexOf('confidence');
    int dateIdx = headers.indexOf('acq_date');
    int timeIdx = headers.indexOf('acq_time');

    double parseConf(String val) {
      if (val.toLowerCase() == 'l' || val.toLowerCase() == 'low') return 30.0;
      if (val.toLowerCase() == 'n' || val.toLowerCase() == 'nominal') return 50.0;
      if (val.toLowerCase() == 'h' || val.toLowerCase() == 'high') return 90.0;
      return double.tryParse(val) ?? 0.0;
    }

    return FireIncident(
      latitude: latIdx != -1 ? (double.tryParse(row[latIdx]) ?? 0.0) : 0.0,
      longitude: lngIdx != -1 ? (double.tryParse(row[lngIdx]) ?? 0.0) : 0.0,
      brightness: brightIdx != -1 ? (double.tryParse(row[brightIdx]) ?? 0.0) : 0.0,
      confidence: confIdx != -1 ? parseConf(row[confIdx]) : 0.0,
      acqDate: dateIdx != -1 ? row[dateIdx] : '',
      acqTime: timeIdx != -1 ? row[timeIdx] : '',
    );
  }
}
