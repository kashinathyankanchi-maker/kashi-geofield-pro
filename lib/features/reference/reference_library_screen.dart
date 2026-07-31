import 'package:flutter/material.dart';
import '../../shared/theme.dart';
import 'pdf_viewer_screen.dart';

class ReferenceLibraryScreen extends StatelessWidget {
  const ReferenceLibraryScreen({super.key});

  final List<Map<String, String>> _pdfs = const [
    {
      'title': 'Karnataka Forest Act, 1963 (English)',
      'subtitle': 'Official translation of the Karnataka Forest Act',
      'path': 'assets/pdfs/karnataka_forest_act_1963_en.pdf',
    },
    {
      'title': 'Karnataka Forest Act, 1963 (Kannada)',
      'subtitle': 'ಕನಾಟಕ ಅರಣ ಅಯಮ, 1963',
      'path': 'assets/pdfs/karnataka_forest_act_1963_kn.pdf',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        title: const Text('Reference Library'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pdfs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final pdf = _pdfs[index];
          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.picture_as_pdf_rounded, color: AppTheme.primaryColor),
              ),
              title: Text(
                pdf['title']!,
                style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  pdf['subtitle']!,
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PdfViewerScreen(
                      title: pdf['title']!,
                      pdfPath: pdf['path']!,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
