import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pdf_viewer_screen.dart';

class ProjectScreen extends StatefulWidget {
  final String projectName;

  const ProjectScreen({
    super.key,
    required this.projectName,
  });

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  List<Map<String, dynamic>> pdfList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadPdfMetadata();
  }

  Future<void> loadPdfMetadata() async {
    final jsonString = await rootBundle.loadString(
      'assets/pdf_metadata.json',
    );

    final List<dynamic> data = json.decode(jsonString);

    setState(() {
      pdfList = data
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      isLoading = false;
    });
  }

  // 같은 ISO끼리 묶기
  Map<String, List<Map<String, dynamic>>> groupByIso() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final pdf in pdfList) {
      final isoName = pdf['isoName'] as String;

      grouped.putIfAbsent(isoName, () => []);
      grouped[isoName]!.add(pdf);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final groupedIsos = groupByIso();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName),
      ),

      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : groupedIsos.isEmpty
              ? const Center(
                  child: Text('등록된 PDF가 없습니다.'),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: groupedIsos.entries.map((entry) {
                    final isoName = entry.key;
                    final revisions = entry.value;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15),

                      child: Padding(
                        padding: const EdgeInsets.all(16),

                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,

                          children: [

                            // ISO 이름
                            Text(
                              isoName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Revision 버튼들
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,

                              children: revisions.map((pdf) {
                                final revision =
                                    pdf['revision'] as String;

                                final modifiedDate =
                                    pdf['modifiedDate'] as String;

                                final pdfPath =
                                    pdf['path'] as String;

                                return OutlinedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            PDFViewerScreen(
                                          pdfPath: pdfPath,
                                          title:
                                              '$isoName - $revision',
                                        ),
                                      ),
                                    );
                                  },

                                  child: Column(
                                    mainAxisSize:
                                        MainAxisSize.min,

                                    children: [
                                      Text(
                                        revision,
                                        style: const TextStyle(
                                          fontWeight:
                                              FontWeight.bold,
                                        ),
                                      ),

                                      Text(
                                        modifiedDate,
                                        style:
                                            const TextStyle(
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}