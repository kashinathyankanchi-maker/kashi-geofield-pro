import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../../shared/theme.dart';

class PdfViewerScreen extends StatefulWidget {
  final String title;
  final String pdfPath;

  const PdfViewerScreen({super.key, required this.title, required this.pdfPath});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late PdfControllerPinch _pdfController;
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  Future<void> _initPdf() async {
    try {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openAsset(widget.pdfPath),
      );
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load PDF: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading && _error.isEmpty)
            PdfPageNumber(
              controller: _pdfController,
              builder: (_, loadingState, page, pagesCount) => Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '$page / ${pagesCount ?? 0}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Text(
          _error,
          style: const TextStyle(color: Colors.red, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      );
    }
    return PdfViewPinch(
      controller: _pdfController,
      builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
        options: const DefaultBuilderOptions(),
        documentLoaderBuilder: (_) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        pageLoaderBuilder: (_) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        errorBuilder: (_, error) => Center(
          child: Text(error.toString(), style: const TextStyle(color: Colors.red)),
        ),
      ),
    );
  }
}
