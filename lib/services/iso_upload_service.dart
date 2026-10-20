import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// =============================================================
// ISO 업로드 (앱에서 올리는 ISO PDF)
//
// Spark(무료) 요금제라 Firebase Storage를 쓸 수 없어서
// PDF 자체를 Firestore 문서에 Blob으로 저장한다.
//
// projects/{projectId}/isoFiles/{docId}
//   fileName, isoName, revision, revisionNumber,
//   size, modifiedDate, uploadedBy, uploadedAt,
//   data: Blob(PDF bytes)          ← 1MB 미만만 가능
//
// projects/{projectId}/isoIndex/main
//   files: [ {docId, fileName, isoName, revision, revisionNumber,
//             size, modifiedDate, uploadedBy}, ... ]
//
// 목록은 index 문서 1건만 읽고,
// PDF는 열 때만 해당 문서 1건을 읽는다.
// =============================================================

class IsoUploadResult {
  final List<String> uploaded;
  final List<String> replaced;
  final List<String> skipped;
  final List<String> failed;

  IsoUploadResult({
    required this.uploaded,
    required this.replaced,
    required this.skipped,
    required this.failed,
  });
}

class IsoUploadService {
  IsoUploadService._();

  static final IsoUploadService instance =
      IsoUploadService._();

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  // Firestore 문서 최대 1MiB. 다른 필드 여유를 두고 제한.
  static const int maxPdfBytes = 1000000;

  DocumentReference<Map<String, dynamic>> _indexRef(
    String projectId,
  ) {
    return _firestore
        .collection('projects')
        .doc(projectId)
        .collection('isoIndex')
        .doc('main');
  }

  CollectionReference<Map<String, dynamic>> _filesRef(
    String projectId,
  ) {
    return _firestore
        .collection('projects')
        .doc(projectId)
        .collection('isoFiles');
  }

  // =========================================================
  // 업로드된 ISO 목록 (문서 1건)
  //
  // 반환 형식은 assets 메타데이터와 같게 맞춘다.
  // + source: 'upload', docId
  // =========================================================

  Future<List<Map<String, dynamic>>> loadIndex(
    String projectId,
  ) async {
    try {
      final doc =
          await _indexRef(projectId).get();

      final files = doc.data()?['files'];

      if (files is! List) {
        return [];
      }

      return files
          .whereType<Map>()
          .map(
            (item) => <String, dynamic>{
              ...Map<String, dynamic>.from(item),
              'source': 'upload',
            },
          )
          .toList();
    } catch (e) {
      debugPrint('업로드 ISO 목록 조회 실패: $e');
      return [];
    }
  }

  // =========================================================
  // PDF 내용 (열 때만 1건 읽기)
  // =========================================================

  Future<Uint8List> loadPdfBytes({
    required String projectId,
    required String docId,
  }) async {
    final doc =
        await _filesRef(projectId).doc(docId).get();

    final data = doc.data()?['data'];

    if (data is Blob) {
      return data.bytes;
    }

    throw Exception('PDF 데이터를 찾을 수 없습니다.');
  }

  // =========================================================
  // 파일 선택 → 업로드
  //
  // PDF 여러 개 또는 ZIP(안의 PDF 전부)을 한 번에 올릴 수 있다.
  // =========================================================

  Future<IsoUploadResult?> pickAndUpload({
    required String projectId,
    void Function(int done, int total)? onProgress,
  }) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'zip'],
    );

    if (picked.isEmpty) {
      return null;
    }

    final List<({String name, Uint8List bytes})> pdfs = [];
    final List<String> skipped = [];

    for (final file in picked) {
      final bytes = await file.readAsBytes();
      final lower = file.name.toLowerCase();

      if (lower.endsWith('.zip')) {
        try {
          final archive =
              ZipDecoder().decodeBytes(bytes);

          for (final entry in archive.files) {
            if (!entry.isFile) {
              continue;
            }

            // 폴더 경로 제거
            final name = entry.name
                .split('/')
                .last
                .split('\\')
                .last;

            if (!name.toLowerCase().endsWith('.pdf') ||
                name.startsWith('._')) {
              continue;
            }

            pdfs.add((
              name: name,
              bytes: Uint8List.fromList(
                entry.content as List<int>,
              ),
            ));
          }
        } catch (e) {
          debugPrint('ZIP 읽기 실패: $e');
          skipped.add('${file.name} (ZIP 읽기 실패)');
        }
      } else if (lower.endsWith('.pdf')) {
        pdfs.add((name: file.name, bytes: bytes));
      }
    }

    final result = await uploadPdfs(
      projectId: projectId,
      pdfs: pdfs,
      onProgress: onProgress,
    );

    return IsoUploadResult(
      uploaded: result.uploaded,
      replaced: result.replaced,
      skipped: [...skipped, ...result.skipped],
      failed: result.failed,
    );
  }

  Future<IsoUploadResult> uploadPdfs({
    required String projectId,
    required List<({String name, Uint8List bytes})> pdfs,
    void Function(int done, int total)? onProgress,
  }) async {
    final uploaded = <String>[];
    final replaced = <String>[];
    final skipped = <String>[];
    final failed = <String>[];

    final uploader =
        _auth.currentUser?.email ?? _auth.currentUser?.uid ?? '';

    final today = _formatDate(DateTime.now());

    // 기존 목록 (같은 파일명은 덮어쓰기)
    final existing = await loadIndex(projectId);

    final Map<String, Map<String, dynamic>> byFileName = {
      for (final item in existing)
        (item['fileName']?.toString() ?? ''): item,
    };

    final Set<String> seenInBatch = {};

    int done = 0;

    for (final pdf in pdfs) {
      final fileName = pdf.name.trim();
      final stem = fileName.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );

      // ■삭제 파일 제외
      if (fileName.contains('■삭제')) {
        skipped.add('$fileName (■삭제)');
      }
      // 중복 다운로드 파일 제외: "xxx (1).pdf"
      else if (RegExp(r'\s*\(\d+\)$').hasMatch(stem)) {
        skipped.add('$fileName (중복 다운로드 파일)');
      } else if (!seenInBatch.add(fileName)) {
        skipped.add('$fileName (같은 파일 2번 선택)');
      } else if (pdf.bytes.length > maxPdfBytes) {
        skipped.add(
          '$fileName (${(pdf.bytes.length / 1024 / 1024).toStringAsFixed(1)}MB, 1MB 초과)',
        );
      } else {
        try {
          final parsed = _parseRevision(stem);

          final old = byFileName[fileName];
          final oldDocId = old?['docId']?.toString() ?? '';

          final ref = oldDocId.isNotEmpty
              ? _filesRef(projectId).doc(oldDocId)
              : _filesRef(projectId).doc();

          final entry = <String, dynamic>{
            'docId': ref.id,
            'fileName': fileName,
            'isoName': parsed.isoName,
            'revision': parsed.revision,
            'revisionNumber': parsed.revisionNumber,
            'size': pdf.bytes.length,
            'modifiedDate': today,
            'uploadedBy': uploader,
          };

          await ref.set({
            ...entry,
            'projectId': projectId,
            'data': Blob(pdf.bytes),
            'uploadedAt': FieldValue.serverTimestamp(),
          });

          byFileName[fileName] = entry;

          if (old != null) {
            replaced.add(fileName);
          } else {
            uploaded.add(fileName);
          }
        } catch (e) {
          debugPrint('ISO 업로드 실패 $fileName: $e');
          failed.add(fileName);
        }
      }

      done++;
      onProgress?.call(done, pdfs.length);
    }

    // 목록 문서 갱신 (실패가 있어도 성공한 것은 반영)
    if (uploaded.isNotEmpty || replaced.isNotEmpty) {
      final files = byFileName.values
          .where((item) => (item['fileName'] ?? '').toString().isNotEmpty)
          .map(
            (item) => Map<String, dynamic>.from(item)
              ..remove('source'),
          )
          .toList()
        ..sort(
          (a, b) => a['fileName']
              .toString()
              .toLowerCase()
              .compareTo(
                b['fileName'].toString().toLowerCase(),
              ),
        );

      await _indexRef(projectId).set({
        'projectId': projectId,
        'files': files,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    return IsoUploadResult(
      uploaded: uploaded,
      replaced: replaced,
      skipped: skipped,
      failed: failed,
    );
  }

  // =========================================================
  // 업로드 ISO 삭제
  //
  // PDF 문서 삭제 + 목록 문서에서 제거 (쓰기 2건)
  // 앱에 포함된 assets 도면은 여기서 지울 수 없다.
  // =========================================================

  Future<void> deleteIso({
    required String projectId,
    required String docId,
  }) async {
    final indexRef = _indexRef(projectId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(indexRef);

      final files = snapshot.data()?['files'];

      final remaining = files is List
          ? files
              .whereType<Map>()
              .where(
                (item) => item['docId']?.toString() != docId,
              )
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];

      transaction.set(indexRef, {
        'projectId': projectId,
        'files': remaining,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.delete(
        _filesRef(projectId).doc(docId),
      );
    });
  }

  // =========================================================
  // Revision 추출 (tools/generate_pdf_metadata.py와 같은 규칙)
  //
  // OD25-POW-E-0038-01_Rev01.pdf → OD25-POW-E-0038-01 / Rev.01
  // =========================================================

  ({String isoName, String revision, int revisionNumber})
      _parseRevision(String stem) {
    final match = RegExp(
      r'_Rev(\d+)$',
      caseSensitive: false,
    ).firstMatch(stem);

    if (match == null) {
      return (
        isoName: stem,
        revision: 'Rev.?',
        revisionNumber: -1,
      );
    }

    final number = int.parse(match.group(1)!);

    return (
      isoName: stem.substring(0, match.start),
      revision: 'Rev.${number.toString().padLeft(2, '0')}',
      revisionNumber: number,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
