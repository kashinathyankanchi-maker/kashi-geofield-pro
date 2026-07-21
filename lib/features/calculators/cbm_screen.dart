import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// --- Data Model ---
class LogEntry {
  final double girth;
  final double length;
  LogEntry({required this.girth, required this.length});
  double get volume => (girth * girth * length) / 16;
  String get volumeFormatted {
    final v = volume;
    if (v % 1 == 0) return v.toInt().toString();
    final str = v.toStringAsFixed(4);
    return str.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}

class CbmScreen extends StatefulWidget {
  const CbmScreen({super.key});

  @override
  State<CbmScreen> createState() => _CbmScreenState();
}

class _CbmScreenState extends State<CbmScreen> with TickerProviderStateMixin {
  final List<LogEntry> _entries = [];
  final TextEditingController _girthController = TextEditingController();
  final TextEditingController _lengthController = TextEditingController();
  String _errorMessage = '';
  bool _isScanning = false;
  String _scannedRawText = '';
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  static const Color bgColor = Color(0xFF0D1117);
  static const Color cardColor = Color(0xFF161B22);
  static const Color borderCol = Color(0xFF30363D);
  static const Color textMain = Color(0xFFC9D1D9);
  static const Color textMuted = Color(0xFF8B949E);
  static const Color gitBlue = Color(0xFF58A6FF);
  static const Color gitGreen = Color(0xFF238636);
  static const Color gitRed = Color(0xFFDA3633);
  static const Color btnDark = Color(0xFF21262D);
  static const Color headerBg = Color(0xFF1C2128);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _girthController.dispose();
    _lengthController.dispose();
    _animController.dispose();
    super.dispose();
  }

  double get _totalVolume => _entries.fold(0.0, (s, e) => s + e.volume);

  String _fmt(double v) {
    if (v % 1 == 0) return v.toInt().toString();
    return v.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  void _addManualRow() {
    final g = double.tryParse(_girthController.text.trim());
    final l = double.tryParse(_lengthController.text.trim());
    if (g == null || l == null || g <= 0 || l <= 0) {
      setState(() => _errorMessage = 'Enter valid positive numbers.');
      return;
    }
    setState(() {
      _entries.add(LogEntry(girth: g, length: l));
      _girthController.clear();
      _lengthController.clear();
      _errorMessage = '';
    });
    _animController..reset()..forward();
  }

  void _deleteRow(int i) => setState(() => _entries.removeAt(i));

  void _clearAll() => setState(() {
    _entries.clear();
    _errorMessage = '';
    _scannedRawText = '';
    _girthController.clear();
    _lengthController.clear();
  });

  // -- OCR: Upload page from gallery --
  Future<void> _pickImage() async {
    setState(() { _isScanning = true; _errorMessage = ''; _scannedRawText = ''; });
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1080, maxHeight: 1920);
      if (img == null) { setState(() => _isScanning = false); return; }
      final rec = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await rec.processImage(InputImage.fromFilePath(img.path));
      await rec.close();
      final raw = result.text;
      setState(() { _scannedRawText = raw.isEmpty ? '(no text detected)' : raw; });
      if (raw.trim().isEmpty) {
        setState(() { _errorMessage = 'No text detected. Try a clearer image.'; _isScanning = false; }); return;
      }
      final newEntries = _parseFromBlocks(result);
      setState(() { _isScanning = false; });
      if (newEntries.isNotEmpty) {
        await _showScanReviewDialog(newEntries);
      } else {
        setState(() => _errorMessage = 'Could not extract pairs. Review raw text below and add manually.');
      }
    } catch (e) {
      setState(() { _errorMessage = 'Error: $e'; _isScanning = false; });
    }
  }

  // -- Post-scan review dialog --
  Future<void> _showScanReviewDialog(List<LogEntry> scanned) async {
    final gCtrls = scanned.map((e) => TextEditingController(text: e.girth.toStringAsFixed(2))).toList();
    final lCtrls = scanned.map((e) => TextEditingController(text: e.length.toStringAsFixed(2))).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFF30363D), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Text('Review Scanned Values',
              style: TextStyle(fontFamily: 'monospace', color: const Color(0xFFC9D1D9), fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('OCR may misread handwriting. Edit any wrong values before adding.',
                style: TextStyle(fontFamily: 'monospace', color: const Color(0xFF8B949E), fontSize: 11),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const SizedBox(width: 28),
              Expanded(child: Text('Girth (m)', style: TextStyle(fontFamily: 'monospace', color: const Color(0xFF58A6FF), fontSize: 12, fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              Expanded(child: Text('Length (m)', style: TextStyle(fontFamily: 'monospace', color: const Color(0xFF58A6FF), fontSize: 12, fontWeight: FontWeight.bold))),
            ]),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: gCtrls.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                child: Row(children: [
                  const SizedBox(width: 28),
                  Expanded(child: _reviewField(gCtrls[i])),
                  const SizedBox(width: 8),
                  Expanded(child: _reviewField(lCtrls[i])),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: () {
                final added = <LogEntry>[];
                for (int i = 0; i < gCtrls.length; i++) {
                  final g = double.tryParse(gCtrls[i].text.replaceAll(',', '.'));
                  final l = double.tryParse(lCtrls[i].text.replaceAll(',', '.'));
                  if (g != null && l != null && g > 0 && l > 0) added.add(LogEntry(girth: g, length: l));
                }
                Navigator.pop(ctx);
                if (added.isNotEmpty) {
                  setState(() => _entries.addAll(added));
                  _animController..reset()..forward();
                  _snack('Added ${added.length} logs to table!', const Color(0xFF3FB950));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3FB950), foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Confirm & Add Logs',
                  style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
    for (final c in gCtrls) c.dispose();
    for (final c in lCtrls) c.dispose();
  }

  Widget _reviewField(TextEditingController ctrl) => TextField(
    controller: ctrl,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    style: TextStyle(fontFamily: 'monospace', color: const Color(0xFFC9D1D9), fontSize: 13),
    decoration: InputDecoration(
      isDense: true,
      fillColor: const Color(0xFF0D1117), filled: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF30363D))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF58A6FF), width: 1.5)),
    ),
  );

  String? _cleanOcrNum(String raw) {
    var s = raw.trim();
    if (!RegExp(r'\d').hasMatch(s)) return null;
    s = s.replaceAllMapped(RegExp(r'(\d)-(\d)'), (m) => '${m[1]}.${m[2]}');
    final digitCnt  = RegExp(r'\d').allMatches(s).length;
    final letterCnt = RegExp(r'[A-Za-z]').allMatches(s).length;
    if (letterCnt > 0 && letterCnt <= digitCnt) {
      s = s.replaceAllMapped(RegExp(r'[A-Za-z]'), (m) {
        switch (m[0]!.toLowerCase()) {
          case 'd': case 'q': return '0';
          case 'o':           return '0';
          case 's':           return '5';
          case 'i': case 'l': return '1';
          case 'e':           return '';
          default:            return '';
        }
      });
    }
    s = s.replaceAll(RegExp(r'[^\d.]'), '');
    final dotIdx = s.indexOf('.');
    if (dotIdx >= 0) s = s.substring(0, dotIdx + 1) + s.substring(dotIdx + 1).replaceAll('.', '');
    if (s.isEmpty || s == '.') return null;
    return s;
  }

  List<LogEntry> _parseFromBlocks(RecognizedText result) {
    final headerRe = RegExp(r'(?:girth|length|lenght|lenth|girht|gith|girh)', caseSensitive: false);
    final List<MapEntry<double, double>> positioned = [];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final raw = element.text.trim();
          if (headerRe.hasMatch(raw) && !RegExp(r'\d').hasMatch(raw)) continue;
          final cleaned = _cleanOcrNum(raw);
          if (cleaned == null) continue;
          final v = double.tryParse(cleaned);
          if (v == null || v <= 0 || v > 50) continue;
          final cx = element.boundingBox.left + element.boundingBox.width / 2;
          positioned.add(MapEntry(cx, v));
        }
      }
    }
    if (positioned.length >= 2) {
      final sorted = positioned.map((e) => e.key).toList()..sort();
      final medianX = sorted[sorted.length ~/ 2];
      final girths  = positioned.where((e) => e.key <  medianX).map((e) => e.value).toList();
      final lengths = positioned.where((e) => e.key >= medianX).map((e) => e.value).toList();
      if (girths.isNotEmpty && lengths.isNotEmpty) {
        final count = girths.length < lengths.length ? girths.length : lengths.length;
        return List.generate(count, (i) => LogEntry(girth: girths[i], length: lengths[i]));
      }
    }
    return _parseTextFallback(result.text);
  }

  List<LogEntry> _parseTextFallback(String rawText) {
    final entries  = <LogEntry>[];
    final headerRe = RegExp(r'(?:girth|length|lenght|lenth|girht|gith|girh)', caseSensitive: false);
    final tokenRe  = RegExp(r'[A-Za-z]*\d[\dA-Za-z.,\-]*');
    final lines    = rawText.split(RegExp(r'[\n\r]+'));
    List<double> extractNums(String line) {
      return tokenRe.allMatches(line)
          .map((m) => _cleanOcrNum(m.group(0)!))
          .where((s) => s != null)
          .map((s) => double.tryParse(s!))
          .where((v) => v != null && v > 0 && v < 50)
          .cast<double>().toList();
    }
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || (headerRe.hasMatch(t) && !RegExp(r'\d').hasMatch(t))) continue;
      final nums = extractNums(t);
      if (nums.length >= 2) {
        int s = (nums[0] == nums[0].truncateToDouble() && nums[0] <= 99 && nums.length >= 3) ? 1 : 0;
        if (s + 1 < nums.length) entries.add(LogEntry(girth: nums[s], length: nums[s + 1]));
      }
    }
    if (entries.isNotEmpty) return entries;
    final allNums = <double>[];
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty || (headerRe.hasMatch(t) && !RegExp(r'\d').hasMatch(t))) continue;
      allNums.addAll(extractNums(t));
    }
    if (allNums.length >= 2) {
      if (allNums.length % 2 == 0) {
        final half = allNums.length ~/ 2;
        for (int i = 0; i < half; i++) entries.add(LogEntry(girth: allNums[i], length: allNums[half + i]));
      } else {
        for (int i = 0; i + 1 < allNums.length; i += 2) entries.add(LogEntry(girth: allNums[i], length: allNums[i + 1]));
      }
    }
    return entries;
  }


  void _snack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(fontFamily: 'monospace', color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: c, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bgColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerCard(),
            const SizedBox(height: 12),
            if (_entries.isNotEmpty) ...[_totalCard(), const SizedBox(height: 12)],
            _uploadCard(),
            const SizedBox(height: 12),
            _manualCard(),
            const SizedBox(height: 12),
            if (_entries.isNotEmpty) _table(),
            if (_errorMessage.isNotEmpty) ...[const SizedBox(height: 10), _errorBox()],
            if (_scannedRawText.isNotEmpty) ...[const SizedBox(height: 10), _rawBox()],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _headerCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderCol)),
    child: Row(
      children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: gitGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.forest, color: gitGreen, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Wood Log Volume Table', style: TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold, color: textMain)),
          const SizedBox(height: 2),
          Text('Quarter Girth  (G\u00b2 \u00d7 L) \u00f7 16', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: gitBlue)),
        ])),
        if (_entries.isNotEmpty) TextButton.icon(
          onPressed: _clearAll,
          icon: const Icon(Icons.delete_sweep, size: 16, color: gitRed),
          label: Text('Clear', style: TextStyle(fontFamily: 'monospace', color: gitRed, fontSize: 12)),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
        ),
      ],
    ),
  );

  // -- PDF Print / Export --
  Future<void> _printTable() async {
    if (_entries.isEmpty) { _snack('No data to print!', Colors.orange); return; }

    // Show headline editor dialog first
    final headlineCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Set Report Headline',
            style: TextStyle(fontFamily: 'monospace', color: const Color(0xFFC9D1D9), fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Type the headline/title for your printed report.',
              style: TextStyle(fontFamily: 'monospace', color: const Color(0xFF8B949E), fontSize: 12)),
          const SizedBox(height: 14),
          TextField(
            controller: headlineCtrl,
            autofocus: true,
            style: TextStyle(fontFamily: 'monospace', color: const Color(0xFFC9D1D9), fontSize: 14),
            decoration: InputDecoration(
              hintText: 'e.g. Timber Log Report - Site A',
              hintStyle: TextStyle(fontFamily: 'monospace', color: const Color(0xFF484F58), fontSize: 13),
              filled: true, fillColor: const Color(0xFF0D1117),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF30363D))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF58A6FF), width: 1.5)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(fontFamily: 'monospace', color: const Color(0xFF8B949E))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.print, size: 16),
            label: Text('Print', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3FB950), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ],
      ),
    );

    headlineCtrl.dispose();
    if (confirmed != true) return;

    final headline = headlineCtrl.text.trim().isEmpty ? 'CBM Log Report' : headlineCtrl.text.trim();
    final now = DateTime.now();
    final dateFmt = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final pdf = pw.Document();

    pw.Widget cell(String text, {bool header = false, pw.Alignment align = pw.Alignment.centerLeft}) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: pw.Align(
          alignment: align,
          child: pw.Text(text,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: header ? PdfColors.white : PdfColors.grey900,
            ),
          ),
        ),
      );
    }

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // User-defined headline (centered, large)
          pw.Center(
            child: pw.Text(headline,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text('Date: $dateFmt  |  Total Logs: ${_entries.length}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey500)),
          ),
          pw.SizedBox(height: 14),
          pw.Divider(color: PdfColors.blueGrey300, thickness: 1),
          pw.SizedBox(height: 10),
          // Table
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.blueGrey200, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(2.5),
              2: const pw.FlexColumnWidth(2.5),
              3: const pw.FlexColumnWidth(2.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                children: [
                  cell('#',           header: true, align: pw.Alignment.center),
                  cell('Girth (m)',   header: true),
                  cell('Length (m)',  header: true),
                  cell('Volume (m\u00b3)', header: true),
                ],
              ),
              ..._entries.asMap().entries.map((e) {
                final idx = e.key;
                final log = e.value;
                final vol = (log.girth * log.girth * log.length) / 16;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: idx.isEven ? PdfColors.blueGrey50 : PdfColors.white),
                  children: [
                    cell('${idx + 1}', align: pw.Alignment.center),
                    cell(log.girth.toStringAsFixed(2)),
                    cell(log.length.toStringAsFixed(2)),
                    cell(vol.toStringAsFixed(4)),
                  ],
                );
              }),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.green50),
                children: [
                  cell('', align: pw.Alignment.center),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: pw.Text('TOTAL ( log)',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.green800)),
                  ),
                  cell(''),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: pw.Text('${_fmt(_totalVolume)} m\u00b3',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.green800)),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Divider(color: PdfColors.blueGrey200),
          pw.SizedBox(height: 6),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('kashi app', style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400)),
            pw.Text('Total: ${_fmt(_totalVolume)} m\u00b3  |  Logs: ${_entries.length}',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400)),
          ]),
        ],
      ),
    ));

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: '$headline.pdf'.replaceAll(' ', '_'),
    );
  }
  Widget _totalCard() => FadeTransition(
    opacity: _fadeAnim,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      decoration: BoxDecoration(
        color: cardColor, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gitGreen, width: 1.5),
        boxShadow: [BoxShadow(color: gitGreen.withOpacity(0.12), blurRadius: 12, spreadRadius: 2)],
      ),
      child: Column(children: [
        Text('Total Log Volume', style: TextStyle(fontFamily: 'monospace', color: textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('${_fmt(_totalVolume)} m\u00b3', style: TextStyle(fontFamily: 'monospace', color: gitGreen, fontSize: 30, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text('${_entries.length} log${_entries.length == 1 ? "" : "s"}', style: TextStyle(fontFamily: 'monospace', color: textMuted, fontSize: 12)),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () {
              final t = _entries.map((e) => 'G:${e.girth}  L:${e.length}  V:${e.volumeFormatted}m\u00b3').join('\n');
              Clipboard.setData(ClipboardData(text: t));
              _snack('Table copied!', gitBlue);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text('Copy', style: TextStyle(fontFamily: 'monospace', fontSize: 13)),
            style: OutlinedButton.styleFrom(foregroundColor: gitBlue, side: const BorderSide(color: gitBlue),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
          OutlinedButton.icon(
            onPressed: _printTable,
            icon: const Icon(Icons.print, size: 16),
            label: Text('Print / PDF', style: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFF78166),
              side: const BorderSide(color: Color(0xFFF78166)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ]),
      ]),
    ),
  );


  Widget _manualCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderCol)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.edit, size: 15, color: textMuted), const SizedBox(width: 7),
        Text('Add Row Manually', style: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold, color: textMain))]),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: _input(_girthController, 'Girth (m)')),
        const SizedBox(width: 10),
        Expanded(child: _input(_lengthController, 'Length (m)')),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: _addManualRow,
          style: ElevatedButton.styleFrom(backgroundColor: gitBlue, foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: const Icon(Icons.add, size: 20),
        ),
      ]),
    ]),
  );

  Widget _input(TextEditingController c, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontFamily: 'monospace', color: textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
    const SizedBox(height: 5),
    TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(fontFamily: 'monospace', color: textMain, fontSize: 13), cursorColor: gitBlue,
      decoration: InputDecoration(hintText: '0.00', hintStyle: TextStyle(fontFamily: 'monospace', color: textMuted, fontSize: 13),
        fillColor: bgColor, filled: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: borderCol)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: gitBlue, width: 1.5))),
    ),
  ]);

  Widget _table() => Container(
    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderCol)),
    child: Column(children: [
      // Header row
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: headerBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          border: Border(bottom: BorderSide(color: borderCol))),
        child: Row(children: [
          SizedBox(width: 28, child: Text('#', style: TextStyle(fontFamily: 'monospace', color: textMuted, fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(child: Text('Girth (m)', style: TextStyle(fontFamily: 'monospace', color: gitBlue, fontSize: 12, fontWeight: FontWeight.bold))),
          Expanded(child: Text('Length (m)', style: TextStyle(fontFamily: 'monospace', color: gitBlue, fontSize: 12, fontWeight: FontWeight.bold))),
          Expanded(child: Text('Volume (m\u00b3)', style: TextStyle(fontFamily: 'monospace', color: gitGreen, fontSize: 12, fontWeight: FontWeight.bold))),
          const SizedBox(width: 28),
        ]),
      ),
      // Data rows
      ListView.separated(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: borderCol),
        itemBuilder: (ctx, i) {
          final e = _entries[i];
          return Container(
            color: i.isEven ? bgColor.withOpacity(0.3) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              SizedBox(width: 28, child: Text('${i + 1}', style: TextStyle(fontFamily: 'monospace', color: textMuted, fontSize: 12))),
              Expanded(child: Text(e.girth.toString(), style: TextStyle(fontFamily: 'monospace', color: textMain, fontSize: 13, fontWeight: FontWeight.w500))),
              Expanded(child: Text(e.length.toString(), style: TextStyle(fontFamily: 'monospace', color: textMain, fontSize: 13, fontWeight: FontWeight.w500))),
              Expanded(child: Text('${e.volumeFormatted} m\u00b3', style: TextStyle(fontFamily: 'monospace', color: gitGreen, fontSize: 13, fontWeight: FontWeight.bold))),
              SizedBox(width: 28, child: GestureDetector(onTap: () => _deleteRow(i), child: const Icon(Icons.close, size: 15, color: gitRed))),
            ]),
          );
        },
      ),
      // Footer total
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: headerBg,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
          border: Border(top: BorderSide(color: gitGreen.withOpacity(0.5)))),
        child: Row(children: [
          const SizedBox(width: 28),
          Expanded(flex: 2, child: Text('TOTAL', style: TextStyle(fontFamily: 'monospace', color: textMuted, fontSize: 12, fontWeight: FontWeight.bold))),
          Expanded(child: Text('${_fmt(_totalVolume)} m\u00b3', style: TextStyle(fontFamily: 'monospace', color: gitGreen, fontSize: 14, fontWeight: FontWeight.bold))),
          const SizedBox(width: 28),
        ]),
      ),
    ]),
  );

  Widget _errorBox() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: gitRed.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: gitRed.withOpacity(0.4))),
    child: Row(children: [
      const Icon(Icons.error_outline, color: gitRed, size: 15), const SizedBox(width: 8),
      Expanded(child: Text(_errorMessage, style: TextStyle(fontFamily: 'monospace', color: gitRed, fontSize: 12))),
    ]),
  );

  Widget _uploadCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderCol)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.upload_file, size: 18, color: gitBlue), const SizedBox(width: 8),
        Text('Upload Log Sheet', style: TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold, color: textMain)),
      ]),
      const SizedBox(height: 4),
      Text('Pick a photo of your log sheet — numbers are read automatically.',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: textMuted)),
      const SizedBox(height: 12),
      if (_isScanning)
        Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            const CircularProgressIndicator(color: gitBlue, strokeWidth: 2.5),
            const SizedBox(height: 8),
            Text('Reading page...', style: TextStyle(fontFamily: 'monospace', color: gitBlue, fontSize: 12, fontWeight: FontWeight.bold)),
          ])))
      else SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.upload_file, size: 17),
          label: Text('Upload Page', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: btnDark, foregroundColor: textMain,
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: const BorderSide(color: borderCol),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        ),
      ),
    ]),
  );

  Widget _rawBox() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(8), border: Border.all(color: borderCol)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Detected Raw Text', style: TextStyle(fontFamily: 'monospace', color: textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
        GestureDetector(onTap: () => setState(() => _scannedRawText = ''), child: const Icon(Icons.close, size: 14, color: textMuted)),
      ]),
      const SizedBox(height: 6),
      Text(_scannedRawText, style: TextStyle(fontFamily: 'monospace', color: textMain, fontSize: 11)),
    ]),
  );

}




