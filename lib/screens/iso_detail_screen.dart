import 'package:flutter/material.dart';
import 'pdf_viewer_screen.dart';

class ISODetailScreen extends StatelessWidget {
  final String isoName;
  final String pdfPath;

  const ISODetailScreen({
    super.key,
    required this.isoName,
    required this.pdfPath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ISO 도면'),
      ),

      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isoName,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Revision',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.picture_as_pdf,
                  color: Colors.red,
                ),

                title: const Text(
                  'Rev.00',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                subtitle: const Text(
                  '2026-08-11',
                ),

                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                ),

                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PDFViewerScreen(
                        pdfPath: pdfPath,
                        title: isoName,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}