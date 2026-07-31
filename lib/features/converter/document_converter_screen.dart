import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/theme.dart';
import '../../core/utils/storage_helper.dart';
import 'ocr_models.dart';
import 'cloud_vision_service.dart';

class DocumentConverterScreen extends StatefulWidget {
  const DocumentConverterScreen({super.key});

  @override
  State<DocumentConverterScreen> createState() => _DocumentConverterScreenState();
}

class _DocumentConverterScreenState extends State<DocumentConverterScreen> {
  // State
  File? _sourceFile;
  String _sourceType = ''; // 'image' or 'pdf'
  String _sourceName = '';
  bool _isProcessing = false;
  String _progressText = '';
  double _progress = 0;

  // Extracted data
  String _extractedText = '';
  List<List<String>> _tableData = [];
  final _textController = TextEditingController();
  bool _hasExtracted = false;

  // Export state
  String? _lastExportedPath;

  final _textRecognizer = TextRecognizer();
  final _imagePicker = ImagePicker();

  @override
  void dispose() {
    _textRecognizer.close();
    _textController.dispose();
    super.dispose();
  }

  // ── Source Picking ─────────────────────────────────────────────────────────

  Future<void> _pickFromCamera() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
    );
    if (image != null) {
      setState(() {
        _sourceFile = File(image.path);
        _sourceType = 'image';
        _sourceName = image.name;
        _hasExtracted = false;
        _extractedText = '';
        _tableData = [];
      });
      _processSource();
    }
  }

  Future<void> _pickFromGallery() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (image != null) {
      setState(() {
        _sourceFile = File(image.path);
        _sourceType = 'image';
        _sourceName = image.name;
        _hasExtracted = false;
        _extractedText = '';
        _tableData = [];
      });
      _processSource();
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _sourceFile = File(result.files.single.path!);
        _sourceType = 'pdf';
        _sourceName = result.files.single.name;
        _hasExtracted = false;
        _extractedText = '';
        _tableData = [];
      });
      _processSource();
    }
  }

  // ── OCR Processing ────────────────────────────────────────────────────────

  Future<void> _processSource() async {
    if (_sourceFile == null) return;

    setState(() {
      _isProcessing = true;
      _progressText = 'Preparing...';
      _progress = 0;
    });

    try {
      if (_sourceType == 'image') {
        await _processImage(_sourceFile!);
      } else if (_sourceType == 'pdf') {
        await _processPdf(_sourceFile!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _hasExtracted = _extractedText.isNotEmpty;
        _textController.text = _extractedText;
      });
    }
  }

  Future<String> _getCloudVisionApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('settings_cloud_vision_api_key') ?? '';
  }

  Future<void> _processImage(File imageFile) async {
    setState(() {
      _progressText = 'Running OCR on image...';
      _progress = 0.3;
    });

    final apiKey = await _getCloudVisionApiKey();
    List<OcrBlock> blocks;

    if (apiKey.isNotEmpty) {
      setState(() => _progressText = 'Running Cloud Vision OCR (Kannada Support)...');
      blocks = await CloudVisionService.recognizeText(imageFile, apiKey);
    } else {
      final inputImage = InputImage.fromFile(imageFile);
      final recognized = await _textRecognizer.processImage(inputImage);
      blocks = recognized.blocks.map((b) => OcrBlock(
        boundingBox: b.boundingBox,
        lines: b.lines.map((l) => OcrLine(text: l.text, boundingBox: l.boundingBox)).toList(),
      )).toList();
    }

    _buildStructuredOutput(blocks);

    setState(() {
      _progress = 1.0;
      _progressText = 'Done!';
    });
  }

  Future<void> _processPdf(File pdfFile) async {
    setState(() {
      _progressText = 'Opening PDF...';
      _progress = 0.1;
    });

    final document = await pdfx.PdfDocument.openFile(pdfFile.path);
    final pageCount = document.pagesCount;
    final allBlocks = <OcrBlock>[];
    final apiKey = await _getCloudVisionApiKey();

    for (int i = 1; i <= pageCount; i++) {
      setState(() {
        _progressText = 'Processing page $i of $pageCount...';
        _progress = 0.1 + (0.8 * i / pageCount);
      });

      final page = await document.getPage(i);
      final pageImage = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: pdfx.PdfPageImageFormat.png,
      );
      await page.close();

      if (pageImage != null && pageImage.bytes != null) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/pdf_page_$i.png');
        await tempFile.writeAsBytes(pageImage.bytes!);

        if (apiKey.isNotEmpty) {
          final blocks = await CloudVisionService.recognizeText(tempFile, apiKey);
          allBlocks.addAll(blocks);
        } else {
          final inputImage = InputImage.fromFile(tempFile);
          final recognized = await _textRecognizer.processImage(inputImage);
          final mappedBlocks = recognized.blocks.map((b) => OcrBlock(
            boundingBox: b.boundingBox,
            lines: b.lines.map((l) => OcrLine(text: l.text, boundingBox: l.boundingBox)).toList(),
          )).toList();
          allBlocks.addAll(mappedBlocks);
        }

        // Clean up temp file
        try { await tempFile.delete(); } catch (_) {}
      }
    }

    await document.close();

    // Build structured text from all pages
    _buildStructuredOutput(allBlocks);

    setState(() {
      _progress = 1.0;
      _progressText = 'Done!';
    });
  }

  void _buildStructuredOutput(List<OcrBlock> blocks) {
    if (blocks.isEmpty) {
      _extractedText = '';
      _tableData = [];
      return;
    }

    // Sort blocks by Y position (top to bottom), then X (left to right)
    final sortedBlocks = List<OcrBlock>.from(blocks);
    sortedBlocks.sort((a, b) {
      final yDiff = a.boundingBox.top - b.boundingBox.top;
      if (yDiff.abs() < 15) {
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      }
      return yDiff.toInt();
    });

    // Group lines by Y-position proximity to detect table rows
    final List<List<OcrLine>> rows = [];
    double lastY = -100;

    for (final block in sortedBlocks) {
      for (final line in block.lines) {
        final lineY = line.boundingBox.top;
        if (rows.isEmpty || (lineY - lastY).abs() > 20) {
          rows.add([line]);
          lastY = lineY;
        } else {
          rows.last.add(line);
          // Update lastY to average
          lastY = rows.last.map((l) => l.boundingBox.top).reduce((a, b) => a + b) / rows.last.length;
        }
      }
    }

    // Sort columns within each row by X position
    for (final row in rows) {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    }

    // Build plain text and table data
    final buffer = StringBuffer();
    _tableData = [];

    for (final row in rows) {
      final cells = row.map((line) => line.text.trim()).toList();
      _tableData.add(cells);
      buffer.writeln(cells.join('\t'));
    }

    _extractedText = buffer.toString().trim();
  }

  // ── Export to Excel ────────────────────────────────────────────────────────

  Future<void> _exportToExcel() async {
    if (_tableData.isEmpty && _textController.text.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _progressText = 'Creating Excel file...';
    });

    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Extracted Data'];

      // Re-parse from text controller (user may have edited)
      final lines = _textController.text.split('\n');
      for (int r = 0; r < lines.length; r++) {
        final cells = lines[r].split('\t');
        if (cells.length == 1 && cells[0].trim().isEmpty) continue;
        for (int c = 0; c < cells.length; c++) {
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
            .value = xl.TextCellValue(cells[c].trim());
        }
      }

      // Style the first row as header
      if (lines.isNotEmpty) {
        final headerCells = lines[0].split('\t');
        for (int c = 0; c < headerCells.length; c++) {
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            ..cellStyle = xl.CellStyle(
              bold: true,
              fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
              backgroundColorHex: xl.ExcelColor.fromHexString('#2D7A3A'),
            );
        }
      }

      // Remove default Sheet1 if exists
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final docsDir = await StorageHelper.getAppStorageDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'extracted_${_sourceName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_$timestamp.xlsx';
        final filePath = '$docsDir/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);

        setState(() => _lastExportedPath = filePath);

        if (mounted) {
          _showExportSuccess('Excel', filePath);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel export error: $e'), backgroundColor: Colors.red),
        );
      }
    }

    setState(() => _isProcessing = false);
  }

  // ── Export to PDF ──────────────────────────────────────────────────────────

  Future<void> _exportToPdf() async {
    if (_textController.text.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _progressText = 'Creating PDF...';
    });

    try {
      final doc = pw.Document();
      final lines = _textController.text.split('\n');

      // Detect if data is tabular (has tabs)
      final isTabular = lines.any((l) => l.contains('\t'));

      if (isTabular) {
        // Create table
        final rows = lines
            .where((l) => l.trim().isNotEmpty)
            .map((l) => l.split('\t').map((c) => c.trim()).toList())
            .toList();

        // Find max columns
        int maxCols = 0;
        for (final row in rows) {
          if (row.length > maxCols) maxCols = row.length;
        }

        // Pad rows to equal columns
        for (int i = 0; i < rows.length; i++) {
          while (rows[i].length < maxCols) {
            rows[i].add('');
          }
        }

        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (ctx) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Extracted from: $_sourceName',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text('Kashi GeoField Pro',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              ],
            ),
          ),
          build: (ctx) => [
            pw.TableHelper.fromTextArray(
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              headers: rows.isNotEmpty ? rows.first : [],
              data: rows.length > 1 ? rows.sublist(1) : [],
            ),
          ],
        ));
      } else {
        // Plain text PDF
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (ctx) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 16),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Extracted from: $_sourceName',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text('Kashi GeoField Pro',
                    style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
              ],
            ),
          ),
          build: (ctx) => [
            pw.Paragraph(
              text: _textController.text,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 4),
            ),
          ],
        ));
      }

      final docsDir = await StorageHelper.getAppStorageDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'extracted_${_sourceName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_$timestamp.pdf';
      final filePath = '$docsDir/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(await doc.save());

      setState(() => _lastExportedPath = filePath);

      if (mounted) {
        _showExportSuccess('PDF', filePath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export error: $e'), backgroundColor: Colors.red),
        );
      }
    }

    setState(() => _isProcessing = false);
  }

  // ── Print PDF Preview ─────────────────────────────────────────────────────

  Future<void> _printPreview() async {
    if (_textController.text.isEmpty) return;

    final doc = pw.Document();
    final lines = _textController.text.split('\n');
    final isTabular = lines.any((l) => l.contains('\t'));

    if (isTabular) {
      final rows = lines
          .where((l) => l.trim().isNotEmpty)
          .map((l) => l.split('\t').map((c) => c.trim()).toList())
          .toList();
      int maxCols = 0;
      for (final row in rows) {
        if (row.length > maxCols) maxCols = row.length;
      }
      for (int i = 0; i < rows.length; i++) {
        while (rows[i].length < maxCols) rows[i].add('');
      }
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            headers: rows.isNotEmpty ? rows.first : [],
            data: rows.length > 1 ? rows.sublist(1) : [],
          ),
        ],
      ));
    } else {
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Paragraph(text: _textController.text, style: const pw.TextStyle(fontSize: 11)),
        ],
      ));
    }

    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  // ── Share File ────────────────────────────────────────────────────────────

  Future<void> _shareFile(String path) async {
    await Share.shareXFiles([XFile(path)]);
  }

  // ── Success Dialog ────────────────────────────────────────────────────────

  void _showExportSuccess(String type, String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              type == 'Excel' ? Icons.table_chart_rounded : Icons.picture_as_pdf_rounded,
              color: type == 'Excel' ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 10),
            Text('$type Exported!', style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File saved to:',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                path.split('/').last,
                style: const TextStyle(color: AppTheme.greenAccent, fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.share_rounded, size: 16),
            label: const Text('Share'),
            onPressed: () {
              Navigator.pop(ctx);
              _shareFile(path);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.greenPrimary),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── UI Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        title: const Row(
          children: [
            Icon(Icons.document_scanner_rounded, color: AppTheme.greenAccent, size: 22),
            SizedBox(width: 10),
            Text('Document Scanner', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_hasExtracted)
            IconButton(
              icon: const Icon(Icons.print_rounded, color: AppTheme.greenAccent),
              tooltip: 'Print Preview',
              onPressed: _printPreview,
            ),
        ],
      ),
      body: _sourceFile == null ? _buildPickerUI() : _buildProcessingUI(),
    );
  }

  Widget _buildPickerUI() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.greenPrimary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.document_scanner_rounded, color: AppTheme.greenAccent, size: 40),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Scan & Convert Documents',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick an image or PDF to extract text data\nand convert to Excel or PDF soft copy',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Pick options
            _PickOptionCard(
              icon: Icons.camera_alt_rounded,
              title: 'Camera',
              subtitle: 'Take a photo of a document',
              color: const Color(0xFF00E5FF),
              onTap: _pickFromCamera,
            ),
            const SizedBox(height: 12),
            _PickOptionCard(
              icon: Icons.photo_library_rounded,
              title: 'Gallery',
              subtitle: 'Pick an image from gallery',
              color: const Color(0xFF69F0AE),
              onTap: _pickFromGallery,
            ),
            const SizedBox(height: 12),
            _PickOptionCard(
              icon: Icons.picture_as_pdf_rounded,
              title: 'PDF File',
              subtitle: 'Pick a PDF file from storage',
              color: const Color(0xFFFF8A65),
              onTap: _pickPdf,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingUI() {
    return Column(
      children: [
        // Source info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppTheme.bgCard,
          child: Row(
            children: [
              Icon(
                _sourceType == 'image' ? Icons.image_rounded : Icons.picture_as_pdf_rounded,
                color: AppTheme.greenAccent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _sourceName,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Change', style: TextStyle(fontSize: 12)),
                onPressed: () => setState(() {
                  _sourceFile = null;
                  _hasExtracted = false;
                  _extractedText = '';
                  _tableData = [];
                }),
              ),
            ],
          ),
        ),

        // Processing indicator
        if (_isProcessing)
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    color: AppTheme.greenAccent,
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _progressText,
                  style: const TextStyle(color: AppTheme.greenAccent, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'Extracting text using OCR...',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                ),
              ],
            ),
          ),

        // Extracted text editor
        if (_hasExtracted && !_isProcessing)
          Expanded(
            child: Column(
              children: [
                // Stats bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppTheme.greenPrimary.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppTheme.greenAccent, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${_tableData.length} rows detected  •  ${_extractedText.split(' ').length} words',
                        style: const TextStyle(color: AppTheme.greenAccent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        'Tap to edit',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                      ),
                    ],
                  ),
                ),

                // Editable text area
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace', height: 1.6),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.all(14),
                        border: InputBorder.none,
                        hintText: 'Extracted text will appear here...',
                        hintStyle: TextStyle(color: Colors.white24),
                      ),
                    ),
                  ),
                ),

                // Export buttons
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ExportButton(
                          icon: Icons.table_chart_rounded,
                          label: 'Export Excel',
                          color: const Color(0xFF2D7A3A),
                          onTap: _isProcessing ? null : _exportToExcel,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ExportButton(
                          icon: Icons.picture_as_pdf_rounded,
                          label: 'Export PDF',
                          color: const Color(0xFFD32F2F),
                          onTap: _isProcessing ? null : _exportToPdf,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ExportButton(
                          icon: Icons.print_rounded,
                          label: 'Print',
                          color: const Color(0xFF1565C0),
                          onTap: _isProcessing ? null : _printPreview,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // No text found
        if (!_isProcessing && !_hasExtracted && _sourceFile != null)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.text_snippet_outlined, color: Colors.white.withValues(alpha: 0.3), size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'No text detected in this file',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                    onPressed: _processSource,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Helper Widgets ──────────────────────────────────────────────────────────

class _PickOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PickOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.3), size: 16),
          ],
        ),
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ExportButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: onTap != null ? color : color.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          boxShadow: onTap != null
              ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
