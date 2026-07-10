import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/theme.dart';

class AiScannerScreen extends StatefulWidget {
  const AiScannerScreen({super.key});

  @override
  State<AiScannerScreen> createState() => _AiScannerScreenState();
}

class _AiScannerScreenState extends State<AiScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _imageFile;
  bool _isAnalyzing = false;
  String? _errorMessage;

  // Species ID State
  Map<String, dynamic>? _speciesResult;
  String _apiKey = '';

  // Coordinate Extractor State
  List<LatLng> _extractedPoints = [];
  bool _isModeSpecies = true;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('settings_gemini_api_key') ?? '';
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 80);
      if (picked != null) {
        setState(() {
          _imageFile = File(picked.path);
          _speciesResult = null;
          _extractedPoints = [];
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load image.');
    }
  }

  Future<void> _processImage() async {
    if (_imageFile == null) return;
    
    if (_isModeSpecies) {
      await _analyzeSpecies();
    } else {
      await _extractCoordinates();
    }
  }

  Future<void> _analyzeSpecies() async {
    if (_apiKey.isEmpty) {
      setState(() => _errorMessage = 'API Key is missing. Please add it in Settings.');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _speciesResult = null;
    });

    try {
      final imageBytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\$_apiKey');
      
      final payload = {
        "contents": [
          {
            "parts": [
              {
                "text": '''
Analyze this image and identify the tree, plant, or wildlife.
Respond ONLY with a valid JSON object matching this structure (no markdown formatting, no code blocks):
{
  "commonName": "string",
  "scientificName": "string",
  "confidence": "number (0-100)",
  "characteristics": ["string1", "string2"]
}
'''
              },
              {
                "inline_data": {
                  "mime_type": "image/jpeg",
                  "data": base64Image
                }
              }
            ]
          }
        ]
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String jsonStr = data['candidates'][0]['content']['parts'][0]['text'].toString().trim();
        if (jsonStr.startsWith('```json')) {
          jsonStr = jsonStr.substring(7);
          if (jsonStr.endsWith('```')) {
            jsonStr = jsonStr.substring(0, jsonStr.length - 3);
          }
        }
        setState(() {
          _speciesResult = jsonDecode(jsonStr);
        });
      } else {
        setState(() => _errorMessage = 'API Error: \${response.statusCode} - \${response.body}');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error analyzing image: \$e');
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  Future<void> _extractCoordinates() async {
    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
      _extractedPoints = [];
    });

    try {
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(_imageFile!.path);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      String text = recognizedText.text;
      textRecognizer.close();

      // Find floating point numbers (e.g. 14.961848)
      final regex = RegExp(r'[-+]?\d{1,3}\.\d{4,}');
      final matches = regex.allMatches(text).map((m) => double.tryParse(m.group(0) ?? '')).whereType<double>().toList();

      List<LatLng> points = [];
      // Group by pairs (assuming Lat then Lng or Lng then Lat).
      // Standard is Lat (smaller number in India usually 8-37) Lng (68-97)
      for (int i = 0; i < matches.length - 1; i += 2) {
        double n1 = matches[i];
        double n2 = matches[i + 1];
        
        // Basic heuristic for India (Lat is smaller than Lng)
        double lat = n1 < n2 ? n1 : n2;
        double lng = n1 > n2 ? n1 : n2;
        
        // If outside India bounds, just take as-is (n1=Lat, n2=Lng)
        if (lat < 8 || lat > 40 || lng < 60 || lng > 100) {
           lat = n1;
           lng = n2;
        }

        points.add(LatLng(lat, lng));
      }

      if (points.isEmpty) {
        setState(() => _errorMessage = 'No valid coordinates found in the image.');
      } else {
        setState(() {
          _extractedPoints = points;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error extracting text: \$e');
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  Future<void> _generateKml() async {
    if (_extractedPoints.isEmpty) return;

    try {
      final coords = [
        ..._extractedPoints.map((p) => '\${p.longitude},\${p.latitude},0'),
      ].join('\n          ');

      final kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Extracted Coordinates</name>
    <Style id="polyStyle">
      <LineStyle><color>ff0000ff</color><width>2</width></LineStyle>
      <PolyStyle><color>400000ff</color></PolyStyle>
    </Style>
    <Placemark>
      <name>Scanned Polygon</name>
      <styleUrl>#polyStyle</styleUrl>
      <Polygon>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
          $coords
          \${_extractedPoints.first.longitude},\${_extractedPoints.first.latitude},0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>
  </Document>
</kml>''';

      final dir = await getApplicationDocumentsDirectory();
      final file = File('\${dir.path}/extracted_polygon.kml');
      await file.writeAsString(kml);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/vnd.google-earth.kml+xml')],
        subject: 'Extracted GPS Polygon',
      );
    } catch (e) {
      setState(() => _errorMessage = 'Failed to generate KML: \$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text('AI Assistant'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode Switcher
            Container(
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isModeSpecies = true;
                        _errorMessage = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isModeSpecies ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _isModeSpecies
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)]
                              : [],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Identify Species',
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: _isModeSpecies ? FontWeight.bold : FontWeight.normal,
                            color: _isModeSpecies ? AppTheme.primaryColor : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isModeSpecies = false;
                        _errorMessage = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isModeSpecies ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: !_isModeSpecies
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)]
                              : [],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Extract Coordinates',
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: !_isModeSpecies ? FontWeight.bold : FontWeight.normal,
                            color: !_isModeSpecies ? AppTheme.primaryColor : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Image Preview Area
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
              ),
              child: _imageFile != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(_imageFile!, fit: BoxFit.cover),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined, size: 48, color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'No Image Selected',
                          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_imageFile != null)
              ElevatedButton.icon(
                onPressed: _isAnalyzing ? null : _processImage,
                icon: _isAnalyzing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(_isModeSpecies ? Icons.psychology : Icons.document_scanner),
                label: Text(_isAnalyzing ? 'Processing...' : (_isModeSpecies ? 'Identify Species' : 'Extract Coordinates')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),

            const SizedBox(height: 24),

            // Error Message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppTheme.errorColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: AppTheme.bodyMedium.copyWith(color: AppTheme.errorColor),
                      ),
                    ),
                  ],
                ),
              ),

            // Species Results Card
            if (_isModeSpecies && _speciesResult != null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.park_rounded, color: AppTheme.greenPrimary, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _speciesResult!['commonName']?.toString() ?? 'Unknown',
                                style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _speciesResult!['scientificName']?.toString() ?? '',
                                style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "\${_speciesResult!['confidence']}% Match",
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Text(
                      'Characteristics',
                      style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (_speciesResult!['characteristics'] is List)
                      ...(_speciesResult!['characteristics'] as List).map(
                        (char) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check_circle_outline, size: 18, color: AppTheme.textSecondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(char.toString(), style: AppTheme.bodyMedium),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            // Coordinate Results Card
            if (!_isModeSpecies && _extractedPoints.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Extracted Coordinates (\${_extractedPoints.length} points)',
                      style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: _extractedPoints.length,
                        itemBuilder: (context, index) {
                          final p = _extractedPoints[index];
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 12,
                              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                              child: Text('\${index + 1}', style: const TextStyle(fontSize: 10)),
                            ),
                            title: Text('\${p.latitude}, \${p.longitude}'),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _generateKml,
                      icon: const Icon(Icons.map),
                      label: const Text('Generate Polygon KML'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.greenPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
