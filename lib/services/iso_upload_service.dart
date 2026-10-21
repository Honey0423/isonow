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
// projects/{projectId}/isoHistory/{autoId}
//   action: upload / replace / delete
//   fileName, isoName, revision, notInList, by, at
//
// 목록은 index 문서 1건만 읽고,
// PDF는 열 때만 해당 문서 1건을 읽는다.
//
// 파일명 규칙 (필수):
//   {도면번호}-REV{숫자}.pdf
//   예) 1F-15A-CDA(IA)-ST1-N-9011-01-REV1.pdf
//       → 도면 1F-15A-CDA(IA)-ST1-N-9011-01 / REV1
//   (REV0, REV1, REV2 ... 앞에 0 없이 · 같은 도면에 같은 번호는 1개만)
// =============================================================

// 업로드 전 검사 결과
enum IsoCandidateStatus {
  // 바로 업로드 가능
  ok,

  // 업로드 가능하지만 ISO 목록(Welding Log 등)에 없는 도면 → 강제 추가
  notInList,

  // 업로드 불가
  invalidName,
  duplicateRevision,
  tooLarge,
  deletedMark,
  duplicateDownload,
  duplicateInBatch,
}

class IsoUploadCandidate {
  final String fileName;
  final Uint8List bytes;
  final String isoName;
  final String revision;
  final int revisionNumber;
  final IsoCandidateStatus status;

  // 같은 파일명이 이미 올라가 있으면 교체
  final bool replaces;

  IsoUploadCandidate({
    required this.fileName,
    required this.bytes,
    required this.isoName,
    required this.revision,
    required this.revisionNumber,
    required this.status,
    required this.replaces,
  });

  bool get canUpload =>
      status == IsoCandidateStatus.ok ||
      status == IsoCandidateStatus.notInList;

  String get statusText {
    switch (status) {
      case IsoCandidateStatus.ok:
        return replaces ? '교체' : '업로드';
      case IsoCandidateStatus.notInList:
        return '목록에 없음 → 강제 추가';
      case IsoCandidateStatus.invalidName:
        return '제외: 파일명 끝에 -REV0, -REV1 형식 필요 (앞에 0 붙이지 않음)';
      case IsoCandidateStatus.duplicateRevision:
        return '제외: 이미 등록된 리비전 ($revision) · 바꾸려면 기존 것을 먼저 삭제';
      case IsoCandidateStatus.tooLarge:
        return '제외: ${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB (1MB 초과)';
      case IsoCandidateStatus.deletedMark:
        return '제외: ■삭제 파일';
      case IsoCandidateStatus.duplicateDownload:
        return '제외: 중복 다운로드 파일 (1)';
      case IsoCandidateStatus.duplicateInBatch:
        return '제외: 같은 도면·리비전을 2번 넣음';
    }
  }
}

class IsoUploadResult {
  final List<String> uploaded;
  final List<String> replaced;
  final List<String> failed;

  IsoUploadResult({
    required this.uploaded,
    required this.replaced,
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

  CollectionReference<Map<String, dynamic>> _historyRef(
    String projectId,
  ) {
    return _firestore
        .collection('projects')
        .doc(projectId)
        .collection('isoHistory');
  }

  String _actor(String? userName) {
    final email = _auth.currentUser?.email ?? '';
    final name = userName?.trim() ?? '';

    if (name.isNotEmpty && email.isNotEmpty) {
      return '$name ($email)';
    }

    return name.isNotEmpty
        ? name
        : (email.isNotEmpty ? email : (_auth.currentUser?.uid ?? ''));
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
  // 파일 선택 (끌어다 놓기가 안 될 때 보조용)
  // =========================================================

  Future<List<({String name, Uint8List bytes})>> pickRawFiles() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'zip'],
    );

    final result = <({String name, Uint8List bytes})>[];

    for (final file in picked) {
      result.add((
        name: file.name,
        bytes: await file.readAsBytes(),
      ));
    }

    return result;
  }

  // =========================================================
  // ZIP 풀기: PDF만 꺼내서 목록으로
  // =========================================================

  List<({String name, Uint8List bytes})> expandZips(
    List<({String name, Uint8List bytes})> files,
  ) {
    final result = <({String name, Uint8List bytes})>[];

    for (final file in files) {
      final lower = file.name.toLowerCase();

      if (lower.endsWith('.pdf')) {
        result.add(file);
        continue;
      }

      if (!lower.endsWith('.zip')) {
        continue;
      }

      try {
        final archive =
            ZipDecoder().decodeBytes(file.bytes);

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

          result.add((
            name: name,
            bytes: Uint8List.fromList(
              entry.content as List<int>,
            ),
          ));
        }
      } catch (e) {
        debugPrint('ZIP 읽기 실패 ${file.name}: $e');
      }
    }

    return result;
  }

  // =========================================================
  // 업로드 전 검사
  //
  // knownIsoNames: 화면 ISO 목록에 있는 도면 이름
  //   (Welding Log 도면 + 앱 포함 도면 + 업로드한 도면)
  // =========================================================

  //
  // existingRevisions: 이미 있는 '도면이름|리비전번호'
  //   (앱 포함 도면 REV0 + 화면에 보이는 업로드 도면)
  //   서버의 최신 업로드 목록도 여기서 다시 읽어 합친다.
  // =========================================================

  Future<List<IsoUploadCandidate>> checkFiles({
    required String projectId,
    required List<({String name, Uint8List bytes})> files,
    required Set<String> knownIsoNames,
    Set<String> existingRevisions = const {},
  }) async {
    final existing = await loadIndex(projectId);

    final takenRevisions = <String>{
      ...existingRevisions,
      for (final item in existing)
        revisionKey(
          item['isoName']?.toString() ?? '',
          (item['revisionNumber'] as num?)?.toInt() ?? 0,
        ),
    };

    final seen = <String>{};
    final result = <IsoUploadCandidate>[];

    for (final file in files) {
      final fileName = file.name.trim();
      final stem = fileName.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );

      final parsed = parseRevision(stem);

      IsoCandidateStatus status;

      if (fileName.contains('■삭제')) {
        status = IsoCandidateStatus.deletedMark;
      } else if (RegExp(r'\s*\(\d+\)$').hasMatch(stem)) {
        status = IsoCandidateStatus.duplicateDownload;
      } else if (parsed == null) {
        status = IsoCandidateStatus.invalidName;
      } else if (!seen.add(
        revisionKey(parsed.isoName, parsed.revisionNumber),
      )) {
        status = IsoCandidateStatus.duplicateInBatch;
      } else if (takenRevisions.contains(
        revisionKey(parsed.isoName, parsed.revisionNumber),
      )) {
        status = IsoCandidateStatus.duplicateRevision;
      } else if (file.bytes.length > maxPdfBytes) {
        status = IsoCandidateStatus.tooLarge;
      } else if (!knownIsoNames.contains(parsed.isoName)) {
        status = IsoCandidateStatus.notInList;
      } else {
        status = IsoCandidateStatus.ok;
      }

      result.add(
        IsoUploadCandidate(
          fileName: fileName,
          bytes: file.bytes,
          isoName: parsed?.isoName ?? stem,
          revision: parsed?.revision ?? '',
          revisionNumber: parsed?.revisionNumber ?? -1,
          status: status,
          // 같은 리비전은 막으므로 교체는 없다 (삭제 후 다시 업로드)
          replaces: false,
        ),
      );
    }

    // 업로드 가능 → 경고 → 제외 순, 같은 그룹은 이름순
    int rank(IsoUploadCandidate c) =>
        c.status == IsoCandidateStatus.ok
            ? 0
            : c.status == IsoCandidateStatus.notInList
                ? 1
                : 2;

    result.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.fileName.compareTo(b.fileName);
    });

    return result;
  }

  // =========================================================
  // 업로드 (검사 통과한 것만)
  // =========================================================

  Future<IsoUploadResult> uploadCandidates({
    required String projectId,
    required List<IsoUploadCandidate> candidates,
    String? userName,
    void Function(int done, int total)? onProgress,
  }) async {
    final uploaded = <String>[];
    final replaced = <String>[];
    final failed = <String>[];

    final actor = _actor(userName);
    final today = _formatDate(DateTime.now());

    final targets =
        candidates.where((c) => c.canUpload).toList();

    // 기존 목록 (같은 파일명은 덮어쓰기)
    final existing = await loadIndex(projectId);

    final Map<String, Map<String, dynamic>> byFileName = {
      for (final item in existing)
        (item['fileName']?.toString() ?? ''): item,
    };

    int done = 0;

    for (final c in targets) {
      try {
        final old = byFileName[c.fileName];
        final oldDocId = old?['docId']?.toString() ?? '';

        final ref = oldDocId.isNotEmpty
            ? _filesRef(projectId).doc(oldDocId)
            : _filesRef(projectId).doc();

        final entry = <String, dynamic>{
          'docId': ref.id,
          'fileName': c.fileName,
          'isoName': c.isoName,
          'revision': c.revision,
          'revisionNumber': c.revisionNumber,
          'size': c.bytes.length,
          'modifiedDate': today,
          'uploadedBy': actor,
        };

        // PDF 저장 + 히스토리 기록을 한 번에
        final batch = _firestore.batch();

        batch.set(ref, {
          ...entry,
          'projectId': projectId,
          'data': Blob(c.bytes),
          'uploadedAt': FieldValue.serverTimestamp(),
        });

        batch.set(_historyRef(projectId).doc(), {
          'action': old != null ? 'replace' : 'upload',
          'fileName': c.fileName,
          'isoName': c.isoName,
          'revision': c.revision,
          'notInList': c.status == IsoCandidateStatus.notInList,
          'size': c.bytes.length,
          'by': actor,
          'at': FieldValue.serverTimestamp(),
        });

        await batch.commit();

        byFileName[c.fileName] = entry;

        if (old != null) {
          replaced.add(c.fileName);
        } else {
          uploaded.add(c.fileName);
        }
      } catch (e) {
        debugPrint('ISO 업로드 실패 ${c.fileName}: $e');
        failed.add(c.fileName);
      }

      done++;
      onProgress?.call(done, targets.length);
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
      failed: failed,
    );
  }

  // =========================================================
  // 업로드 ISO 삭제
  //
  // PDF 문서 삭제 + 목록에서 제거 + 히스토리 기록 (한 번에)
  // 앱에 포함된 assets 도면은 여기서 지울 수 없다.
  // =========================================================

  Future<void> deleteIso({
    required String projectId,
    required String docId,
    String? userName,
  }) async {
    final indexRef = _indexRef(projectId);
    final actor = _actor(userName);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(indexRef);

      final files = snapshot.data()?['files'];

      final all = files is List
          ? files
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];

      final target = all
          .where((item) => item['docId']?.toString() == docId)
          .firstOrNull;

      final remaining = all
          .where((item) => item['docId']?.toString() != docId)
          .toList();

      transaction.set(indexRef, {
        'projectId': projectId,
        'files': remaining,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.delete(
        _filesRef(projectId).doc(docId),
      );

      transaction.set(_historyRef(projectId).doc(), {
        'action': 'delete',
        'fileName': target?['fileName'] ?? '',
        'isoName': target?['isoName'] ?? '',
        'revision': target?['revision'] ?? '',
        'by': actor,
        'at': FieldValue.serverTimestamp(),
      });
    });
  }

  // =========================================================
  // 히스토리 (최근 N건)
  // =========================================================

  // from/to(날짜, 포함)를 주면 그 기간만 서버에서 읽는다.
  Future<List<Map<String, dynamic>>> loadHistory(
    String projectId, {
    DateTime? from,
    DateTime? to,
    int limit = 300,
  }) async {
    Query<Map<String, dynamic>> query = _historyRef(projectId);

    if (from != null) {
      query = query.where(
        'at',
        isGreaterThanOrEqualTo: Timestamp.fromDate(
          DateTime(from.year, from.month, from.day),
        ),
      );
    }

    if (to != null) {
      query = query.where(
        'at',
        isLessThan: Timestamp.fromDate(
          DateTime(to.year, to.month, to.day + 1),
        ),
      );
    }

    final snapshot = await query
        .orderBy('at', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => {...doc.data(), 'id': doc.id})
        .toList();
  }

  // =========================================================
  // Revision 추출
  //
  // {도면번호}-REV{숫자}  (대소문자 무관, 필수)
  // 1F-15A-...-9011-01-REV1 → 1F-15A-...-9011-01 / REV1 / 1
  // REV01처럼 앞에 0이 붙으면 규칙 위반 (null)
  // 규칙에 안 맞으면 null
  // =========================================================

  static ({String isoName, String revision, int revisionNumber})?
      parseRevision(String stem) {
    final match = RegExp(
      r'^(.+)-REV(0|[1-9]\d*)$',
      caseSensitive: false,
    ).firstMatch(stem.trim());

    if (match == null) {
      return null;
    }

    final isoName = match.group(1)!.trim();
    final number = int.parse(match.group(2)!);

    if (isoName.isEmpty) {
      return null;
    }

    return (
      isoName: isoName,
      revision: 'REV$number',
      revisionNumber: number,
    );
  }

  // 도면 + 리비전 중복 판단 키 (대소문자 무시)
  static String revisionKey(String isoName, int revisionNumber) =>
      '${isoName.trim().toLowerCase()}|$revisionNumber';

  String _formatDate(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
