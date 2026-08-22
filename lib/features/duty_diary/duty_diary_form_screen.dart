import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
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
  late TextEditingController _locationsCtrl;
  late TextEditingController _activitiesCtrl;
  late TextEditingController _distanceCtrl;
  
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;

  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _activeField = '';

  @override
  void initState() {
    super.initState();
    _locationsCtrl = TextEditingController(text: widget.entry?.locations ?? '');
    _activitiesCtrl = TextEditingController(text: widget.entry?.activities ?? '');
    _distanceCtrl = TextEditingController(text: widget.entry?.distance.toString() ?? '');

    if (widget.entry != null) {
      _selectedDate = DateTime.parse(widget.entry!.date);
      final timeParts = widget.entry!.time.split(':');
      _selectedTime = TimeOfDay(hour: int.parse(timeParts[0]), minute: int.parse(timeParts[1]));
    } else {
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay.now();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.greenPrimary,
              surface: AppTheme.bgCard,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.greenPrimary,
              surface: AppTheme.bgCard,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _listen(String field) async {
    if (_isListening) {
      // ── Stop current session first, then update UI ──────────────────────
      await _speech.stop();
      setState(() {
        _isListening = false;
        _activeField = null;
      });
      return;
    }

    // ── Start new session ─────────────────────────────────────────────────
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
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
      onError: (val) {
        if (mounted) setState(() => _isListening = false);
      },
    );

    if (!available) return;

    // Snapshot the current text ONCE at session start — new speech appends to this
    final String textAtStart = field == 'locations' ? _locationsCtrl.text : _activitiesCtrl.text;
    final String prefix = textAtStart.isEmpty
        ? ''
        : (textAtStart.endsWith(' ') ? textAtStart : '$textAtStart ');

    setState(() {
      _isListening = true;
      _activeField = field;
    });

    _speech.listen(
      localeId: 'kn_IN', // Kannada Language
      onResult: (val) {
        // Only update while THIS session is still the active one
        if (!_isListening || _activeField != field) return;
        if (mounted) {
          setState(() {
            if (field == 'locations') {
              _locationsCtrl.text = prefix + val.recognizedWords;
              // Keep cursor at end
              _locationsCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: _locationsCtrl.text.length),
              );
            } else if (field == 'activities') {
              _activitiesCtrl.text = prefix + val.recognizedWords;
              _activitiesCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: _activitiesCtrl.text.length),
              );
            }
          });
        }
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    final entry = DutyDiaryModel(
      id: widget.entry?.id,
      date: dateFormat.format(_selectedDate),
      time: timeFormat,
      locations: _locationsCtrl.text.trim(),
      activities: _activitiesCtrl.text.trim(),
      distance: double.tryParse(_distanceCtrl.text.trim()) ?? 0.0,
      createdAt: widget.entry?.createdAt ?? DateTime.now().toIso8601String(),
    );

    if (entry.id == null) {
      await DbHelper().insertDutyDiary(entry.toMap());
    } else {
      await DbHelper().updateDutyDiary(entry.toMap());
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
    return Scaffold(
      backgroundColor: AppTheme.bgSurface,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: Text(widget.entry == null ? 'New Diary Entry' : 'Edit Entry', style: const TextStyle(color: Colors.white)),
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
              // Date and Time Pickers
              Row(
                children: [
                  Expanded(
                    child: _buildDateTimeCard(
                      icon: Icons.calendar_today,
                      label: 'Date',
                      value: DateFormat('MMM d, yyyy').format(_selectedDate),
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDateTimeCard(
                      icon: Icons.access_time,
                      label: 'Time',
                      value: _selectedTime.format(context),
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              _buildVoiceTextField(
                controller: _locationsCtrl,
                label: 'Locations / Compartments',
                fieldKey: 'locations',
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              
              _buildVoiceTextField(
                controller: _activitiesCtrl,
                label: 'Key Activities & Observations',
                fieldKey: 'activities',
                maxLines: 4,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _distanceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: _inputDeco('Distance Traveled (km)', Icons.directions_walk),
                validator: (v) => v!.isEmpty ? 'Enter distance' : null,
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.greenPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('Save Entry', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimeCard({required IconData icon, required String label, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.greenAccent, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceTextField({
    required TextEditingController controller,
    required String label,
    required String fieldKey,
    required int maxLines,
  }) {
    bool isActive = _isListening && _activeField == fieldKey;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        filled: true,
        fillColor: AppTheme.bgCard,
        suffixIcon: IconButton(
          icon: Icon(
            isActive ? Icons.mic : Icons.mic_none,
            color: isActive ? Colors.redAccent : AppTheme.greenAccent,
          ),
          onPressed: () => _listen(fieldKey),
        ),
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
      validator: (v) => v!.isEmpty ? 'Field required' : null,
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 20),
        filled: true,
        fillColor: AppTheme.bgCard,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.borderColor)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.borderColor)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.greenPrimary, width: 2)),
      );
}

