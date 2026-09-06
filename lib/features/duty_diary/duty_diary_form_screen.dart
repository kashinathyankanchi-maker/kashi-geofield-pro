import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/duty_diary_model.dart';
import '../../core/database/db_helper.dart';
import '../../shared/theme.dart';

class DutyDiaryFormScreen extends StatefulWidget {
  final DutyDiaryModel? entry;

  const DutyDiaryFormScreen({super.key, this.entry});

  @override
  State<DutyDiaryFormScreen> createState() => _DutyDiaryFormScreenState();
}

class _DutyDiaryFormScreenState extends State<DutyDiaryFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers for all 6 Kannada diary columns ──────────────────────────
  late TextEditingController _campStationCtrl;   // ಕೇಂದ್ರ, ಸ್ಥಾನ (ಮುಕ್ಕಾಂ)
  late TextEditingController _departureTimeCtrl; // ಹೊರಟ ವೇಳೆ
  late TextEditingController _placesVisitedCtrl; // ತಿರುಗಾಡಿದ ಸ್ಥಳ
  late TextEditingController _returnTimeCtrl;    // ಹಿಂತಿರುಗಿದ ವೇಳೆ
  late TextEditingController _modeAndKmCtrl;     // ತಿರುಗಾಡಿದ ರೀತಿ & ಕಿ.ಮೀ
  late TextEditingController _workDoneCtrl;      // ಕೆಲಸ ಮಾಡಿದ ವಿವರ

  late DateTime _selectedDate;

  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String? _activeField;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _campStationCtrl   = TextEditingController(text: e?.campStation   ?? '');
    _departureTimeCtrl = TextEditingController(text: e?.departureTime ?? '');
    _placesVisitedCtrl = TextEditingController(text: e?.placesVisited ?? '');
    _returnTimeCtrl    = TextEditingController(text: e?.returnTime    ?? '');
    _modeAndKmCtrl     = TextEditingController(text: e?.modeAndKm    ?? '');
    _workDoneCtrl      = TextEditingController(text: e?.workDone     ?? '');
    _selectedDate = e != null ? DateTime.parse(e.date) : DateTime.now();

    if (e == null) {
      _loadDefaultCamp();
    }
  }

  Future<void> _loadDefaultCamp() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultCamp = prefs.getString('diary_default_camp') ?? '';
    if (defaultCamp.isNotEmpty && _campStationCtrl.text.isEmpty && mounted) {
      setState(() => _campStationCtrl.text = defaultCamp);
    }
  }

  @override
  void dispose() {
    _campStationCtrl.dispose();
    _departureTimeCtrl.dispose();
    _placesVisitedCtrl.dispose();
    _returnTimeCtrl.dispose();
    _modeAndKmCtrl.dispose();
    _workDoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.greenPrimary,
            surface: AppTheme.bgCard,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  // ── Voice input ───────────────────────────────────────────────────────────
  TextEditingController _controllerFor(String field) {
    switch (field) {
      case 'campStation':   return _campStationCtrl;
      case 'placesVisited': return _placesVisitedCtrl;
      case 'modeAndKm':     return _modeAndKmCtrl;
      case 'workDone':      return _workDoneCtrl;
      default:              return _workDoneCtrl;
    }
  }

  void _listen(String field) async {
    if (_isListening) {
      await _speech.stop();
      setState(() { _isListening = false; _activeField = null; });
      return;
    }

    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission denied', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    bool available = await _speech.initialize(
      onStatus: (val) {
        if (val == 'done' || val == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (val) { if (mounted) setState(() => _isListening = false); },
    );
    if (!available) return;

    final ctrl = _controllerFor(field);
    final String prefix = ctrl.text.isEmpty ? '' : (ctrl.text.endsWith(' ') ? ctrl.text : '${ctrl.text} ');

    setState(() { _isListening = true; _activeField = field; });

    _speech.listen(
      localeId: 'kn_IN',
      onResult: (val) {
        if (!_isListening || _activeField != field) return;
        if (mounted) {
          setState(() {
            ctrl.text = prefix + val.recognizedWords;
            ctrl.selection = TextSelection.fromPosition(TextPosition(offset: ctrl.text.length));
          });
        }
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final entry = DutyDiaryModel(
      id:            widget.entry?.id,
      date:          DateFormat('yyyy-MM-dd').format(_selectedDate),
      campStation:   _campStationCtrl.text.trim(),
      departureTime: _departureTimeCtrl.text.trim(),
      placesVisited: _placesVisitedCtrl.text.trim(),
      returnTime:    _returnTimeCtrl.text.trim(),
      modeAndKm:     _modeAndKmCtrl.text.trim(),
      workDone:      _workDoneCtrl.text.trim(),
      createdAt:     widget.entry?.createdAt ?? DateTime.now().toIso8601String(),
    );

    if (entry.id == null) {
      await DbHelper().insertDutyDiary(entry.toMap());
    } else {
      await DbHelper().updateDutyDiary(entry.toMap());
    }

    if (entry.campStation.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('diary_default_camp', entry.campStation);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(entry.id == null ? 'Diary entry saved!' : 'Diary entry updated!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayName = DateFormat('EEEE').format(_selectedDate);
    final weekStr = 'ವಾರ ${_weekNumber(_selectedDate)}';

    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          widget.entry == null ? 'ದಿನಚರಿ ನಮೂದು' : 'ದಿನಚರಿ ಸಂಪಾದನೆ',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_rounded, color: Colors.greenAccent),
            tooltip: 'Save Entry',
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Date & Week row ──────────────────────────────────────────
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.greenPrimary.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: AppTheme.greenAccent, size: 22),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ವಾರ/ದಿನಾಂಕ  •  $weekStr',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$dayName  –  ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.edit_calendar_outlined, color: AppTheme.textMuted, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Column 2: ಕೇಂದ್ರ, ಸ್ಥಾನ (ಮುಕ್ಕಾಂ) ──────────────────────
              _buildField(
                controller: _campStationCtrl,
                labelKannada: 'ಕೇಂದ್ರ, ಸ್ಥಾನ (ಮುಕ್ಕಾಂ)',
                labelEnglish: 'Camp / Head Station',
                icon: Icons.home_work_outlined,
                fieldKey: 'campStation',
                voiceEnabled: true,
                required: true,
              ),
              const SizedBox(height: 14),

              // ── Column 3 & 5: Departure / Return times ───────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _departureTimeCtrl,
                      labelKannada: 'ಹೊರಟ ವೇಳೆ',
                      labelEnglish: 'Departure Time',
                      icon: Icons.arrow_upward_rounded,
                      fieldKey: 'departureTime',
                      voiceEnabled: false,
                      hint: 'e.g. 06:30',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _returnTimeCtrl,
                      labelKannada: 'ಹಿಂತಿರುಗಿದ ವೇಳೆ',
                      labelEnglish: 'Return Time',
                      icon: Icons.arrow_downward_rounded,
                      fieldKey: 'returnTime',
                      voiceEnabled: false,
                      hint: 'e.g. 18:00',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Column 4: ತಿರುಗಾಡಿದ ಸ್ಥಳ ──────────────────────────────
              _buildField(
                controller: _placesVisitedCtrl,
                labelKannada: 'ತಿರುಗಾಡಿದ ಸ್ಥಳ',
                labelEnglish: 'Places Visited / Compartments',
                icon: Icons.place_outlined,
                fieldKey: 'placesVisited',
                voiceEnabled: true,
                maxLines: 3,
                required: true,
              ),
              const SizedBox(height: 14),

              // ── Column 6: ತಿರುಗಾಡಿದ ರೀತಿ & ಕಿ.ಮೀ ─────────────────────
              _buildField(
                controller: _modeAndKmCtrl,
                labelKannada: 'ತಿರುಗಾಡಿದ ರೀತಿ & ಕಿ.ಮೀ',
                labelEnglish: 'Mode of Travel & KM',
                icon: Icons.directions_bike_outlined,
                fieldKey: 'modeAndKm',
                voiceEnabled: true,
                hint: 'e.g. ಪಾದಚಾರಿ 12 ಕಿ.ಮೀ',
              ),
              const SizedBox(height: 14),

              // ── Column 7: ಕೆಲಸ ಮಾಡಿದ ವಿವರ ─────────────────────────────
              _buildField(
                controller: _workDoneCtrl,
                labelKannada: 'ಕೆಲಸ ಮಾಡಿದ ವಿವರ',
                labelEnglish: 'Work Done Details',
                icon: Icons.assignment_outlined,
                fieldKey: 'workDone',
                voiceEnabled: true,
                maxLines: 5,
                required: true,
              ),
              const SizedBox(height: 32),

              // ── Save button ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.greenPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                  label: const Text('ಉಳಿಸಿ  /  Save Entry',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Field builder ─────────────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required String labelKannada,
    required String labelEnglish,
    required IconData icon,
    required String fieldKey,
    bool voiceEnabled = false,
    int maxLines = 1,
    bool required = false,
    String? hint,
  }) {
    final isActive = _isListening && _activeField == fieldKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bilingual label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: labelKannada,
                  style: const TextStyle(
                    color: AppTheme.greenAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: '  •  $labelEnglish',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 20),
            filled: true,
            fillColor: AppTheme.bgCard,
            suffixIcon: voiceEnabled
                ? IconButton(
                    icon: Icon(
                      isActive ? Icons.mic : Icons.mic_none,
                      color: isActive ? Colors.redAccent : AppTheme.greenAccent,
                    ),
                    tooltip: 'Voice Input (Kannada)',
                    onPressed: () => _listen(fieldKey),
                  )
                : null,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.borderColor)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.borderColor)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.greenPrimary, width: 2)),
          ),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required / ಅಗತ್ಯ' : null : null,
        ),
      ],
    );
  }

  // ── Compute ISO week number ───────────────────────────────────────────────
  int _weekNumber(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    final diff = date.difference(startOfYear).inDays;
    return (diff / 7).ceil() + 1;
  }
}
