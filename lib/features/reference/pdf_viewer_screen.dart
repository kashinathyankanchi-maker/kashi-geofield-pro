import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../shared/theme.dart';

class PdfViewerScreen extends StatefulWidget {
  final String title;
  final String pdfPath;

  const PdfViewerScreen({super.key, required this.title, required this.pdfPath});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  PdfTextSearchResult _searchResult = PdfTextSearchResult();
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _pdfViewerController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _searchFocusNode.requestFocus();
    });
  }

  void _stopSearch() {
    _searchResult.clear();
    _searchController.clear();
    setState(() {
      _isSearching = false;
    });
  }

  void _performSearch(String query) async {
    if (query.isEmpty) {
      _searchResult.clear();
      setState(() {});
      return;
    }
    _searchResult = await _pdfViewerController.searchText(query);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white),
                    onPressed: () {
                      _searchController.clear();
                      _searchResult.clear();
                      setState(() {});
                    },
                  ),
                ),
                onSubmitted: _performSearch,
                textInputAction: TextInputAction.search,
              )
            : Text(widget.title, style: const TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.greenPrimary,
        foregroundColor: Colors.white,
        actions: [
          if (_isSearching && _searchResult.hasResult) ...[
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: () {
                _searchResult.previousInstance();
                setState(() {});
              },
            ),
            Center(
              child: Text(
                '${_searchResult.currentInstanceIndex} / ${_searchResult.totalInstanceCount}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () {
                _searchResult.nextInstance();
                setState(() {});
              },
            ),
          ],
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _startSearch,
            )
          else
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _stopSearch,
            ),
        ],
      ),
      body: SfPdfViewer.asset(
        widget.pdfPath,
        controller: _pdfViewerController,
        canShowScrollHead: true, // This enables the slide bar / scrollbar
        canShowScrollStatus: true,
      ),
    );
  }
}
