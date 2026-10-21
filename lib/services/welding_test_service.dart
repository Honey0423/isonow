import 'dart:typed_data';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';

class WeldingTestService extends ChangeNotifier {
  WeldingTestService._();

  static final WeldingTestService instance =
      WeldingTestService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  // =========================================================
  // 현재 현장
  //
  // 모든 Welding 데이터는 Firestore 현장 문서 ID(projectId)로 분리한다.
  // 현장 이름은 표시 / 파일명 / 문서 가독성용으로만 저장한다.
  // 화면에 들어갈 때 setCurrentProject()로 지정한다.
  // =========================================================

  String currentProjectId = '';

  String currentProjectName = '';

  void setCurrentProject({
    required String projectId,
    required String projectName,
  }) {
    if (currentProjectId != projectId) {
      // 다른 현장으로 바뀌면 이전 현장 데이터가 보이지 않게 비운다.
      weldingLogs.clear();
      dailyReports.clear();
      _weldingLogPageCache.clear();
      _weldingLogPageLastDocuments.clear();
      currentWeldingLogPage = 1;
      hasNextWeldingLogPage = false;
      _filterCode = '';
      _filterCommodity = '';
      _filterFloor = '';
      _filterIsoNo = '';
      _filterWelderNo = '';
      _filterPkgNo = '';
      _filterSheetNo = '';
      _filterIsoNos = [];
      _isoSearchNoMatch = false;
      _dailyReportsProjectId = '';
    }

    currentProjectId = projectId;
    currentProjectName = projectName;
  }

  // =========================================================
  // 현재 사용자
  // =========================================================

  String currentRole = 'user';

  String currentUserName = '';

  bool get canAccessDailyReport =>
      currentRole == 'super_admin' ||
      currentRole == 'admin' ||
      currentRole == 'pipefitter';

  bool isLoadingUser = false;

  Map<String, dynamic> userData = {};

  // =========================================================
  // Welding Log
  // =========================================================

  final List<Map<String, dynamic>> weldingLogs = [];

  bool isLoadingLogs = false;

  String _loadedProjectId = '';

  // =========================================================
  // Welding Log Pagination
  // =========================================================

  static const int _firstPageSize = 20;
  // 다음 페이지도 첫 페이지와 같은 개수
  static const int _nextPageSize = 20;

  int currentWeldingLogPage = 1;

  bool hasNextWeldingLogPage = false;

  bool get hasPreviousWeldingLogPage =>
      currentWeldingLogPage > 1;

  final List<List<Map<String, dynamic>>>
      _weldingLogPageCache = [];

  final List<DocumentSnapshot<Map<String, dynamic>>>
      _weldingLogPageLastDocuments = [];

  // =========================================================
  // Welding Log 필터
  // =========================================================

  // WeldingLog Total 형식 기준 필터
  // CODE / COMMODITY / Floor / DWG_NAME / Welder
  String _filterCode = '';
  String _filterCommodity = '';
  String _filterFloor = '';
  String _filterIsoNo = '';
  String _filterWelderNo = '';

  // 기존 호환
  String _filterPkgNo = '';
  String _filterSheetNo = '';

  String get filterCode => _filterCode;
  String get filterCommodity => _filterCommodity;
  String get filterFloor => _filterFloor;
  String get filterIsoNo => _filterIsoNo;
  String get filterWelderNo => _filterWelderNo;

  String get filterPkgNo => _filterPkgNo;
  String get filterSheetNo => _filterSheetNo;

  // =========================================================
  // ISO(DWG_NAME) 검색
  //
  // 화면에서 검색어로 도면 이름을 먼저 골라(로컬, Everything 방식)
  // 그 도면들만 Firestore에서 'in' 조건으로 불러온다. (최대 30개)
  // =========================================================

  static const int maxIsoSearchNames = 30;

  List<String> _filterIsoNos = [];

  // 검색어에 맞는 도면이 없을 때: 조회하지 않고 빈 목록
  bool _isoSearchNoMatch = false;

  List<String> get filterIsoNos => _filterIsoNos;

  bool get isIsoSearchActive =>
      _filterIsoNos.isNotEmpty || _isoSearchNoMatch;

  Future<void> applyIsoNoSearch({
    required String projectId,
    required List<String> isoNos,
  }) async {
    _filterIsoNos = isoNos.take(maxIsoSearchNames).toList();
    _isoSearchNoMatch = isoNos.isEmpty;

    await loadWeldingLogs(projectId);
  }

  // 화면에 다시 들어올 때 이전 검색이 남지 않도록 (조회 없이 초기화)
  void resetIsoNoSearch() {
    _filterIsoNos = [];
    _isoSearchNoMatch = false;
  }

  Future<void> clearIsoNoSearch(
    String projectId,
  ) async {
    if (!isIsoSearchActive) {
      return;
    }

    _filterIsoNos = [];
    _isoSearchNoMatch = false;

    await loadWeldingLogs(projectId);
  }

  // 공사일보는 현장당 한 번만 읽는다 (검색할 때마다 다시 읽지 않음)
  String _dailyReportsProjectId = '';

  // 빠르게 검색어를 바꿀 때 늦게 도착한 이전 결과 무시
  int _logQueryToken = 0;

  bool get hasWeldingLogFilter =>
      isIsoSearchActive ||
      _filterCode.isNotEmpty ||
      _filterCommodity.isNotEmpty ||
      _filterFloor.isNotEmpty ||
      _filterIsoNo.isNotEmpty ||
      _filterWelderNo.isNotEmpty ||
      _filterPkgNo.isNotEmpty ||
      _filterSheetNo.isNotEmpty;

  // =========================================================
  // 공사일보
  // =========================================================

  final List<Map<String, dynamic>> dailyReports = [];

  // =========================================================
  // 현재 사용자 정보
  // =========================================================

  Future<void> loadCurrentUser() async {
    final User? user = _auth.currentUser;

    if (user == null) {
      userData = {};
      currentRole = 'user';
      currentUserName = '';
      isLoadingUser = false;

      notifyListeners();
      return;
    }

    isLoadingUser = true;
    notifyListeners();

    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists || doc.data() == null) {
        userData = {};
        currentRole = 'user';
        currentUserName = '';
      } else {
        userData = doc.data()!;

        currentRole =
            userData['role']?.toString() ?? 'user';

        currentUserName =
            userData['name']?.toString() ??
                userData['displayName']?.toString() ??
                user.displayName ??
                '';
      }
    } catch (e) {
      debugPrint(
        '사용자 정보 불러오기 실패: $e',
      );

      userData = {};
      currentRole = 'user';
      currentUserName = '';
    }

    isLoadingUser = false;

    notifyListeners();
  }

  // =========================================================
  // Welding Log Query
  // =========================================================

  Query<Map<String, dynamic>> _buildWeldingLogQuery(
    String projectId,
  ) {
    Query<Map<String, dynamic>> query =
        _firestore.collection('weldingLogs');

    query = query.where(
      'projectId',
      isEqualTo: projectId,
    );

    if (_filterCode.isNotEmpty) {
      query = query.where(
        'code',
        isEqualTo: _filterCode,
      );
    }

    if (_filterCommodity.isNotEmpty) {
      query = query.where(
        'commodity',
        isEqualTo: _filterCommodity,
      );
    }

    if (_filterFloor.isNotEmpty) {
      query = query.where(
        'floor',
        isEqualTo: _filterFloor,
      );
    }

    if (_filterIsoNos.isNotEmpty) {
      query = query.where(
        'isoNo',
        whereIn: _filterIsoNos,
      );
    } else if (_filterIsoNo.isNotEmpty) {
      query = query.where(
        'isoNo',
        isEqualTo: _filterIsoNo,
      );
    }

    if (_filterWelderNo.isNotEmpty) {
      query = query.where(
        'welderNo',
        isEqualTo: _filterWelderNo,
      );
    }

    if (_filterPkgNo.isNotEmpty) {
      query = query.where(
        'pkgNo',
        isEqualTo: _filterPkgNo,
      );
    }

    if (_filterSheetNo.isNotEmpty) {
      query = query.where(
        'sheetNo',
        isEqualTo: _filterSheetNo,
      );
    }

    // Welding Log은 Excel의 NO 순서를 기준으로 표시한다.
    // NO가 같거나 없는 경우에는 ISO / Point를 보조 정렬에 사용한다.
    query = query.orderBy('no');

    return query;
  }

  // =========================================================
  // Welding Log 첫 페이지
  // =========================================================

  Future<void> loadWeldingLogs(
    String projectId,
  ) async {
    _loadedProjectId = projectId;

    await _loadFirstWeldingLogPage(
      projectId,
    );
  }

  Future<void> _loadFirstWeldingLogPage(
    String projectId,
  ) async {
    isLoadingLogs = true;

    currentWeldingLogPage = 1;
    hasNextWeldingLogPage = false;

    _weldingLogPageCache.clear();
    _weldingLogPageLastDocuments.clear();

    weldingLogs.clear();

    notifyListeners();

    final token = ++_logQueryToken;

    // 검색어에 맞는 도면 없음 → 조회 안 함
    if (_isoSearchNoMatch) {
      isLoadingLogs = false;
      notifyListeners();
      return;
    }

    try {
      final query =
          _buildWeldingLogQuery(projectId);

      final snapshot =
          await query.limit(_firstPageSize).get();

      // 그 사이 검색어가 바뀌었으면 이 결과는 버린다
      if (token != _logQueryToken) {
        return;
      }

      final loaded = snapshot.docs.map(
        (doc) {
          final data = doc.data();

          return <String, dynamic>{
            ...data,
            'id': doc.id,
          };
        },
      ).toList();

      weldingLogs
        ..clear()
        ..addAll(loaded);

      _weldingLogPageCache.add(
        List<Map<String, dynamic>>.from(
          loaded,
        ),
      );

      if (snapshot.docs.isNotEmpty) {
        _weldingLogPageLastDocuments.add(
          snapshot.docs.last,
        );
      }

      hasNextWeldingLogPage =
          snapshot.docs.length == _firstPageSize;

      if (_dailyReportsProjectId != projectId) {
        await _loadDailyReports(
          projectId,
        );

        _dailyReportsProjectId = projectId;
      }
    } catch (e) {
      if (token != _logQueryToken) {
        return;
      }

      debugPrint(
        'Welding Log 첫 페이지 불러오기 실패: $e',
      );

      weldingLogs.clear();
      _weldingLogPageCache.clear();
      _weldingLogPageLastDocuments.clear();
      hasNextWeldingLogPage = false;
    }

    isLoadingLogs = false;

    notifyListeners();
  }

  // =========================================================
  // 다음 페이지
  // =========================================================

  Future<void> nextWeldingLogPage() async {
    if (isLoadingLogs ||
        !hasNextWeldingLogPage ||
        _loadedProjectId.isEmpty) {
      return;
    }

    final currentIndex =
        currentWeldingLogPage - 1;

    if (currentIndex < 0 ||
        currentIndex >=
            _weldingLogPageLastDocuments.length) {
      return;
    }

    isLoadingLogs = true;
    notifyListeners();

    try {
      final lastDocument =
          _weldingLogPageLastDocuments[
              currentIndex];

      final query =
          _buildWeldingLogQuery(
        _loadedProjectId,
      );

      final snapshot = await query
          .startAfterDocument(
            lastDocument,
          )
          .limit(_nextPageSize)
          .get();

      final loaded = snapshot.docs.map(
        (doc) {
          final data = doc.data();

          return <String, dynamic>{
            ...data,
            'id': doc.id,
          };
        },
      ).toList();

      if (loaded.isEmpty) {
        hasNextWeldingLogPage = false;

        isLoadingLogs = false;
        notifyListeners();

        return;
      }

      currentWeldingLogPage++;

      weldingLogs
        ..clear()
        ..addAll(loaded);

      if (_weldingLogPageCache.length <
          currentWeldingLogPage) {
        _weldingLogPageCache.add(
          List<Map<String, dynamic>>.from(
            loaded,
          ),
        );
      } else {
        _weldingLogPageCache[
                currentWeldingLogPage - 1] =
            List<Map<String, dynamic>>.from(
          loaded,
        );
      }

      if (_weldingLogPageLastDocuments.length <
          currentWeldingLogPage) {
        _weldingLogPageLastDocuments.add(
          snapshot.docs.last,
        );
      } else {
        _weldingLogPageLastDocuments[
                currentWeldingLogPage - 1] =
            snapshot.docs.last;
      }

      hasNextWeldingLogPage =
          snapshot.docs.length == _nextPageSize;
    } catch (e) {
      debugPrint(
        'Welding Log 다음 페이지 불러오기 실패: $e',
      );
    }

    isLoadingLogs = false;

    notifyListeners();
  }

  // =========================================================
  // 이전 페이지
  // =========================================================

  Future<void> previousWeldingLogPage() async {
    if (isLoadingLogs ||
        !hasPreviousWeldingLogPage) {
      return;
    }

    final targetPage =
        currentWeldingLogPage - 1;

    if (targetPage <= 0 ||
        targetPage >
            _weldingLogPageCache.length) {
      return;
    }

    currentWeldingLogPage = targetPage;

    weldingLogs
      ..clear()
      ..addAll(
        List<Map<String, dynamic>>.from(
          _weldingLogPageCache[
              targetPage - 1],
        ),
      );

    hasNextWeldingLogPage =
        targetPage <
        _weldingLogPageCache.length;

    notifyListeners();
  }

  // =========================================================
  // 필터 적용
  // =========================================================

  Future<void> applyWeldingLogFilters({
    required String projectId,
    String? code,
    String? commodity,
    String? floor,
    String? isoNo,
    String? welderNo,
    String? pkgNo,
    String? sheetNo,
  }) async {
    _filterCode =
        code?.trim() ?? '';

    _filterCommodity =
        commodity?.trim() ?? '';

    _filterFloor =
        floor?.trim() ?? '';

    _filterIsoNo =
        isoNo?.trim() ?? '';

    _filterWelderNo =
        welderNo?.trim() ?? '';

    _filterPkgNo =
        pkgNo?.trim() ?? '';

    _filterSheetNo =
        sheetNo?.trim() ?? '';

    await loadWeldingLogs(
      projectId,
    );
  }

  // =========================================================
  // 필터 초기화
  // =========================================================

  Future<void> clearWeldingLogFilters(
    String projectId,
  ) async {
    _filterCode = '';
    _filterCommodity = '';
    _filterFloor = '';
    _filterIsoNo = '';
    _filterWelderNo = '';

    _filterPkgNo = '';
    _filterSheetNo = '';

    await loadWeldingLogs(
      projectId,
    );
  }

  // =========================================================
  // ISO Point
  // =========================================================

  List<Map<String, dynamic>> getPointsForIso(
    String isoNo,
  ) {
    return weldingLogs
        .where(
          (log) =>
              log['isoNo']?.toString() == isoNo &&
              log['active'] == true &&
              log['status']?.toString().trim().toUpperCase() != 'DEL',
        )
        .toList();
  }

  // =========================================================
  // ISO 전체 Point
  // =========================================================

  Future<List<Map<String, dynamic>>> loadPointsForIso({
    required String projectId,
    required String isoNo,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('weldingLogs')
          .where(
            'projectId',
            isEqualTo: projectId,
          )
          .where(
            'isoNo',
            isEqualTo: isoNo,
          )
          .where(
            'active',
            isEqualTo: true,
          )
          .get();

      final result = snapshot.docs.map(
        (doc) {
          return <String, dynamic>{
            ...doc.data(),
            'id': doc.id,
          };
        },
      ).toList();

      result.sort(
        (a, b) {
          return _pointNumber(
            a['pointNo'],
          ).compareTo(
            _pointNumber(
              b['pointNo'],
            ),
          );
        },
      );

      return result;
    } catch (e) {
      debugPrint(
        'ISO Point 조회 실패: $e',
      );

      return [];
    }
  }

  // =========================================================
  // FIELD 완료
  // =========================================================

  bool isPointCompleted(
    Map<String, dynamic> point,
  ) {
    final fieldDate =
        point['fieldDate'];

    if (fieldDate == null) {
      return false;
    }

    return fieldDate
        .toString()
        .trim()
        .isNotEmpty;
  }

  // =========================================================
  // 현재 페이지에서 Point
  // =========================================================

  Map<String, dynamic>? findPoint({
    required String isoNo,
    required String pointNo,
  }) {
    for (final log in weldingLogs) {
      if (log['isoNo']?.toString() != isoNo) {
        continue;
      }

      if (log['pointNo']?.toString() != pointNo) {
        continue;
      }

      return log;
    }

    return null;
  }

  // =========================================================
  // Firestore Point 직접 조회
  // =========================================================

  Future<Map<String, dynamic>?> _findPointFromFirestore({
    required String projectId,
    required String isoNo,
    required String pointNo,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('weldingLogs')
          .where(
            'projectId',
            isEqualTo: projectId,
          )
          .where(
            'isoNo',
            isEqualTo: isoNo,
          )
          .where(
            'pointNo',
            isEqualTo: pointNo,
          )
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      final doc =
          snapshot.docs.first;

      return {
        ...doc.data(),
        'id': doc.id,
      };
    } catch (e) {
      debugPrint(
        'Point 직접 조회 실패: $e',
      );

      return null;
    }
  }

  // =========================================================
  // 공사일보 제출
  // =========================================================

  Future<bool> submitDailyReport({
    required String projectId,
    required String isoNo,
    required List<String> pointNos,
    required DateTime workDate,
    required String comment,
    required String welderUid,
    required String welderName,
    required String welderNo,
  }) async {
    if (!canAccessDailyReport) {
      debugPrint(
        '공사일보 제출 권한 없음: role=$currentRole',
      );
      return false;
    }

    if (welderUid.trim().isEmpty ||
        welderName.trim().isEmpty ||
        welderNo.trim().isEmpty) {
      debugPrint(
        '공사일보 제출 실패: 용접사 정보가 없습니다.',
      );
      return false;
    }

    if (pointNos.isEmpty) {
      return false;
    }

    final date =
        _formatDate(workDate);

    final List<String>
        actuallyProcessed = [];

    final Map<String, double>
        processedDI = {};

    try {
      for (final pointNo in pointNos) {
        final existing =
            await _findPointFromFirestore(
          projectId: projectId,
          isoNo: isoNo,
          pointNo: pointNo,
        );

        if (existing == null) {
          continue;
        }

        // 비활성 / DEL Point는 오래된 화면에서 선택되어 넘어와도
        // 공사일보에 등록되지 않도록 방어적으로 다시 검사한다.
        final status = existing['status']?.toString().trim().toUpperCase();
        if (existing['active'] != true || status == 'DEL') {
          continue;
        }

        if (isPointCompleted(existing)) {
          continue;
        }

        final docId =
            existing['id']?.toString();

        if (docId == null ||
            docId.isEmpty) {
          continue;
        }

        final ref = _firestore
            .collection('weldingLogs')
            .doc(docId);

        final originalDI =
            _toDouble(
          existing['originalDI'],
        );

        bool updated = false;

        await _firestore.runTransaction(
          (transaction) async {
            final snapshot =
                await transaction.get(ref);

            if (!snapshot.exists) {
              return;
            }

            final data =
                snapshot.data();

            if (data == null) {
              return;
            }

            final existingFieldDate =
                data['fieldDate'];

            if (existingFieldDate != null &&
                existingFieldDate
                    .toString()
                    .trim()
                    .isNotEmpty) {
              return;
            }

            transaction.update(
              ref,
              {
                'welderNo': welderNo,
                'fieldDate': date,
                'fieldDI': originalDI,
                'updatedAt':
                    FieldValue.serverTimestamp(),
              },
            );

            updated = true;
          },
        );

        if (!updated) {
          continue;
        }

        // PKG 진행률 요약 갱신 (weldingLogMeta 1건만 수정)
        final pkgNo =
            existing['pkgNo']?.toString().trim() ?? '';

        if (pkgNo.isNotEmpty) {
          try {
            await _firestore
                .collection('weldingLogMeta')
                .doc(
                  Uri.encodeComponent(
                    projectId,
                  ),
                )
                .update({
              FieldPath([
                'pkgProgress',
                pkgNo,
                'completed',
              ]): FieldValue.increment(1),
            });
          } catch (e) {
            debugPrint(
              'PKG 진행률 갱신 실패: $e',
            );
          }
        }

        actuallyProcessed.add(
          pointNo,
        );

        processedDI[pointNo] =
            originalDI;

        final localPoint =
            findPoint(
          isoNo: isoNo,
          pointNo: pointNo,
        );

        if (localPoint != null) {
          localPoint['welderNo'] =
              welderNo;

          localPoint['fieldDate'] =
              date;

          localPoint['fieldDI'] =
              originalDI;
        }
      }

      if (actuallyProcessed.isEmpty) {
        return false;
      }

      final totalDI =
          actuallyProcessed.fold<double>(
        0.0,
        (sum, pointNo) =>
            sum +
            (processedDI[pointNo] ?? 0.0),
      );

      final reportRef = _firestore
          .collection(
            'weldingDailyReports',
          )
          .doc();

      await reportRef.set({
        'projectId':
            projectId,
        'projectName':
            currentProjectName,
        'isoNo':
            isoNo,
        'welderUid':
            welderUid.trim(),
        'welderNo':
            welderNo.trim(),
        'welderName':
            welderName.trim(),
        'pointNos':
            actuallyProcessed,
        'pointCount':
            actuallyProcessed.length,
        'di':
            totalDI,
        'date':
            date,
        'comment':
            comment,
        'approved':
            true,
        'createdAt':
            FieldValue.serverTimestamp(),
      });

      dailyReports.add({
        'id':
            reportRef.id,
        'projectId':
            projectId,
        'projectName':
            currentProjectName,
        'isoNo':
            isoNo,
        'welderUid':
            welderUid.trim(),
        'welderNo':
            welderNo.trim(),
        'welderName':
            welderName.trim(),
        'pointNos':
            actuallyProcessed,
        'pointCount':
            actuallyProcessed.length,
        'di':
            totalDI,
        'date':
            date,
        'comment':
            comment,
        'approved':
            true,
      });

      notifyListeners();

      return true;
    } catch (e) {
      debugPrint(
        '공사일보 제출 실패: $e',
      );

      return false;
    }
  }

  // =========================================================
  // 공사일보 불러오기
  // =========================================================

  Future<void> _loadDailyReports(
    String projectId,
  ) async {
    try {
      final snapshot =
          await _firestore
              .collection(
                'weldingDailyReports',
              )
              .where(
                'projectId',
                isEqualTo: projectId,
              )
              .get();

      dailyReports
        ..clear()
        ..addAll(
          snapshot.docs.map(
            (doc) => {
              ...doc.data(),
              'id': doc.id,
            },
          ),
        );
    } catch (e) {
      debugPrint(
        '공사일보 불러오기 실패: $e',
      );

      dailyReports.clear();
    }
  }

  // =========================================================
  // 날짜별 공사일보
  // =========================================================

  List<Map<String, dynamic>> getReportsByDate(
    DateTime date,
  ) {
    final target =
        _formatDate(date);

    return dailyReports
        .where(
          (report) =>
              report['date'] == target,
        )
        .toList();
  }

  // =========================================================
  // PKG별 Welding 진행률
  //
  // DEL / active:false Point는 총 물량에서 제외한다.
  // 완료 기준은 FIELD Date가 입력된 Point다.
  // =========================================================

  Future<List<Map<String, dynamic>>> getPkgProgress(
    String projectId,
  ) async {
    // weldingLogs 전체를 읽지 않는다. (5만 건 이상 → 읽기 비용 폭증)
    // 엑셀 업로드 때 계산해 둔 weldingLogMeta/{projectId}.pkgProgress
    // 문서 1건만 읽는다. 공사일보 제출 시 completed가 증가한다.
    try {
      final meta = await _firestore
          .collection('weldingLogMeta')
          .doc(
            Uri.encodeComponent(
              projectId,
            ),
          )
          .get();

      final raw = meta.data()?['pkgProgress'];

      if (raw is! Map) {
        return [];
      }

      final result = <Map<String, dynamic>>[];

      raw.forEach((key, value) {
        if (value is! Map) {
          return;
        }

        final total = (value['total'] as num?)?.toInt() ?? 0;
        final completed = (value['completed'] as num?)?.toInt() ?? 0;

        result.add({
          'pkgNo': key.toString(),
          'total': total,
          'completed': completed,
          'remaining': total - completed,
          'progress': total == 0
              ? 0.0
              : completed / total * 100.0,
        });
      });

      result.sort(
        (a, b) => _comparePkgNo(
          a['pkgNo'],
          b['pkgNo'],
        ),
      );

      return result;
    } catch (e) {
      debugPrint('PKG 진행률 조회 실패: $e');
      return [];
    }
  }

  // =========================================================
  // Welding Log 도면 목록 (weldingLogMeta 1건만 읽기)
  //
  // 엑셀 업로드 때 저장한 DWG_NAME 목록.
  // =========================================================

  Future<List<String>> getWeldingDwgNames(
    String projectId,
  ) async {
    try {
      final meta = await _firestore
          .collection('weldingLogMeta')
          .doc(
            Uri.encodeComponent(
              projectId,
            ),
          )
          .get();

      final raw = meta.data()?['dwgNames'];

      if (raw is! List) {
        return [];
      }

      return raw
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Welding 도면 목록 조회 실패: $e');
      return [];
    }
  }

  // =========================================================
  // Welding 도면 목록 다시 만들기 (관리자용, 1회)
  //
  // dwgNames가 생기기 전에 엑셀을 올린 현장은 목록이 비어 있다.
  // 엑셀을 다시 올리지 않고 현재 Welding Log에서 도면 이름만 모아 저장한다.
  // 주의: 그 현장 Welding Log 전체를 1번 읽는다. (M15X 약 5만 건)
  // =========================================================

  Future<int> rebuildWeldingDwgNames(
    String projectId,
  ) async {
    final snapshot = await _firestore
        .collection('weldingLogs')
        .where(
          'projectId',
          isEqualTo: projectId,
        )
        .where(
          'active',
          isEqualTo: true,
        )
        .get();

    final names = snapshot.docs
        .map((doc) => doc.data()['isoNo']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    await _firestore
        .collection('weldingLogMeta')
        .doc(
          Uri.encodeComponent(
            projectId,
          ),
        )
        .set(
      {
        'projectId': projectId,
        'dwgNames': names,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(
        mergeFields: [
          'projectId',
          'dwgNames',
          'updatedAt',
        ],
      ),
    );

    return names.length;
  }

  // PKG-2, PKG-10처럼 숫자가 들어간 PKG는 숫자 기준으로 정렬한다.
  int _comparePkgNo(
    dynamic a,
    dynamic b,
  ) {
    final aText = a?.toString().trim() ?? '';
    final bText = b?.toString().trim() ?? '';

    final aMatch = RegExp(r'\d+').firstMatch(aText);
    final bMatch = RegExp(r'\d+').firstMatch(bText);

    if (aMatch != null && bMatch != null) {
      final aNumber = int.tryParse(aMatch.group(0)!);
      final bNumber = int.tryParse(bMatch.group(0)!);

      if (aNumber != null && bNumber != null) {
        final numberCompare = aNumber.compareTo(bNumber);
        if (numberCompare != 0) {
          return numberCompare;
        }
      }
    }

    return aText.toLowerCase().compareTo(bText.toLowerCase());
  }

  // =========================================================
  // Excel 업로드
  // =========================================================

  Future<Map<String, int>> importExcel(
    String projectId,
  ) async {
    final PlatformFile? file =
        await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (file == null) {
      return {
        'inserted': 0,
        'updated': 0,
        'deactivated': 0,
      };
    }

    final Uint8List bytes =
        await file.readAsBytes();

    return importExcelBytes(
      projectId: projectId,
      bytes: bytes,
    );
  }

  // =========================================================
  // Excel → Firestore
  // =========================================================

  Future<Map<String, int>> importExcelBytes({
    required String projectId,
    required Uint8List bytes,
  }) async {
    Excel excel;

    try {
      final sanitizedBytes =
          _sanitizeXlsxNumFmts(
        bytes,
      );

      excel =
          Excel.decodeBytes(
        sanitizedBytes,
      );

      debugPrint(
        'Excel decode 성공',
      );
    } catch (e, stack) {
      debugPrint(
        'Excel decode 실패: $e',
      );

      debugPrint(
        stack.toString(),
      );

      rethrow;
    }

    if (excel.tables.isEmpty) {
      throw Exception(
        'Excel에 Sheet가 없습니다.',
      );
    }

    final sheetName =
        excel.tables.keys.first;

    final sheet =
        excel.tables[sheetName];

    if (sheet == null) {
      throw Exception(
        'Excel Sheet를 읽을 수 없습니다.',
      );
    }

    final rows =
        sheet.rows;

    if (rows.isEmpty) {
      throw Exception(
        'Excel 데이터가 없습니다.',
      );
    }

    // =======================================================
    // Header 찾기
    // =======================================================

    int headerRowIndex = -1;

    for (int i = 0;
        i < rows.length && i < 15;
        i++) {
      final row = rows[i];

      final values =
          row.map(_cellToString).toList();

      // 공백 / 점 / 언더바 등을 제거하고 비교한다.
      // 예) 'PointNo.' / 'Point No.' → 'pointno'
      //     'DWG_NAME'               → 'dwgname'
      final normalizedValues = values
          .map(_normalizeHeader)
          .toSet();

      final hasDrawing =
          normalizedValues.contains('dwgname') ||
              normalizedValues.contains('isono');

      final hasPoint =
          normalizedValues.contains('pointno') ||
              normalizedValues.contains('point');

      if (hasDrawing && hasPoint) {
        headerRowIndex = i;
        break;
      }
    }

    if (headerRowIndex < 0) {
      throw Exception(
        'Excel Header 행을 찾지 못했습니다.',
      );
    }

    final List<String> headers =
        rows[headerRowIndex]
            .map(_cellToString)
            .toList();

    // -------------------------------------------------------
    // 도면 키
    //
    // WeldingLog Total 형식에서는 DWG_NAME이
    // ISO PDF 파일명(1F-15A-...-01)과 같고,
    // 층 + Sheet까지 포함되어 Point를 구분할 수 있다.
    //
    // 앱 내부의 isoNo 필드 = DWG_NAME
    // Excel의 'ISO NO' 컬럼 = lineIsoNo 필드
    //
    // DWG_NAME이 없는 예전 형식이면 ISO NO를 사용한다.
    // -------------------------------------------------------
    int isoIndex =
        _findHeaderIndex(
      headers,
      _hDwgName,
    );

    if (isoIndex < 0) {
      isoIndex =
          _findHeaderIndex(
        headers,
        _hIsoNo,
      );
    }

    final pointIndex =
        _findHeaderIndex(
      headers,
      _hPointNo,
    );

    if (isoIndex < 0 ||
        pointIndex < 0) {
      throw Exception(
        'DWG_NAME(또는 ISO NO) / PointNo. 컬럼을 찾지 못했습니다.',
      );
    }

    // =======================================================
    // 현재 Firestore
    // =======================================================

    final currentSnapshot =
        await _firestore
            .collection('weldingLogs')
            .where(
              'projectId',
              isEqualTo: projectId,
            )
            .get();

    final Map<String,
            QueryDocumentSnapshot<
                Map<String, dynamic>>>
        existingByKey = {};

    for (final doc
        in currentSnapshot.docs) {
      final data =
          doc.data();

      final storedKey =
          data['pointKey']?.toString() ?? '';

      final key = storedKey.isNotEmpty
          ? storedKey
          : _makePointKey(
              projectId: projectId,
              isoNo: data['isoNo'],
              pointNo: data['pointNo'],
            );

      existingByKey[key] =
          doc;
    }

    final Set<String>
        uploadedKeys = {};

    final Map<String, int>
        keyOccurrences = {};

    // PKG별 {total, completed}
    final Map<String, Map<String, int>>
        pkgSummary = {};

    // Welding Log에 있는 도면(DWG_NAME) 목록.
    // ISO 탭에서 PDF가 없어도 도면을 띄우는 데 사용.
    final Set<String> dwgNames = {};

    int duplicated = 0;

    int unchanged = 0;

    int inserted = 0;
    int updated = 0;

    final List<Map<String, dynamic>>
        pendingRows = [];

    // =======================================================
    // Excel 데이터
    // =======================================================

    for (int rowIndex =
            headerRowIndex + 1;
        rowIndex < rows.length;
        rowIndex++) {
      final row =
          rows[rowIndex];

      if (_isEmptyRow(row)) {
        continue;
      }

      final List<dynamic>
          values =
          List<dynamic>.generate(
        headers.length,
        (index) {
          if (index >= row.length) {
            return null;
          }

          return _cellToFirestoreValue(
            row[index],
          );
        },
      );

      final isoNo =
          _valueAt(
        values,
        isoIndex,
      ).trim();

      final pointNo =
          _valueAt(
        values,
        pointIndex,
      ).trim();

      if (isoNo.isEmpty ||
          pointNo.isEmpty) {
        continue;
      }

      String key =
          _makePointKey(
        projectId: projectId,
        isoNo: isoNo,
        pointNo: pointNo,
      );

      // 같은 DWG_NAME + PointNo.가 Excel에 여러 번 있으면
      // (원본 데이터 중복) 덮어쓰지 않도록 순번을 붙인다.
      final occurrence =
          (keyOccurrences[key] ?? 0) + 1;

      keyOccurrences[key] =
          occurrence;

      if (occurrence > 1) {
        key = '$key#$occurrence';
        duplicated++;
      }

      uploadedKeys.add(key);

      final oldDoc =
          existingByKey[key];

      // =====================================================
      // 원본 Excel Row 보존
      // =====================================================

      final excelRow =
          <String, dynamic>{};

      for (int i = 0;
          i < values.length;
          i++) {
        excelRow['col_$i'] =
            values[i];
      }

      final mapped =
          _mapExcelRow(
        headers: headers,
        values: values,
      );

      // -----------------------------------------------------
      // Excel에 없는 컬럼은 저장하지 않는다.
      //
      // WeldingLog Total 원본에는 WELDER / SHOP / FIELD / PKG / STATUS가 없다.
      // null로 저장하면 앱에서 입력한 공사일보 실적(FIELD DATE 등)이
      // 재업로드 때 지워지므로, 컬럼이 있을 때만 덮어쓴다.
      // -----------------------------------------------------
      for (final (names, field) in _optionalColumns) {
        if (_findHeaderIndex(headers, names) < 0) {
          mapped.remove(field);
        }
      }

      // -----------------------------------------------------
      // D/I
      //
      // excel 패키지는 수식 셀의 계산값을 읽지 못하고
      // 수식 문자열만 돌려준다.
      // D/I가 숫자가 아니면 Excel 수식과 같은 규칙으로 계산한다.
      // -----------------------------------------------------
      if (mapped['originalDI'] is! num) {
        final parsed = double.tryParse(
          mapped['originalDI']?.toString().trim() ?? '',
        );

        mapped['originalDI'] = parsed ??
            _calculateDI(
              pointNo: pointNo,
              size: mapped['size'],
            );
      }

      final diIndex =
          _findHeaderIndex(
        headers,
        _hDI,
      );

      if (diIndex >= 0) {
        excelRow['col_$diIndex'] =
            mapped['originalDI'];
      }

      final data =
          <String, dynamic>{
        ...mapped,
        'projectId':
            projectId,
        'projectName':
            currentProjectName,
        'isoNo':
            isoNo,
        'pointNo':
            pointNo,
        'pointKey':
            key,
        'excelRow':
            excelRow,
        'excelHeaders':
            headers,
        // STATUS가 DEL이면 기록은 유지하되 용접 대상에서는 제외한다.
        'active':
            (mapped['status']?.toString().trim().toUpperCase() != 'DEL'),
        'updatedAt':
            FieldValue.serverTimestamp(),
      };

      _debugCheckFirestoreSafe(
        data,
        isoNo: isoNo,
        pointNo: pointNo,
      );

      // -----------------------------------------------------
      // PKG 진행률 요약 (업로드 시 한 번만 계산)
      //
      // Excel에 값이 없으면 기존 문서 값을 기준으로 본다.
      // -----------------------------------------------------
      final oldData =
          oldDoc?.data() ?? const <String, dynamic>{};

      final effectivePkgNo =
          (data.containsKey('pkgNo')
                  ? data['pkgNo']
                  : oldData['pkgNo'])
              ?.toString()
              .trim() ??
          '';

      if (data['active'] == true) {
        dwgNames.add(isoNo);
      }

      if (effectivePkgNo.isNotEmpty &&
          data['active'] == true) {
        final effectiveFieldDate =
            data.containsKey('fieldDate')
                ? data['fieldDate']
                : oldData['fieldDate'];

        final summary = pkgSummary.putIfAbsent(
          effectivePkgNo,
          () => {'total': 0, 'completed': 0},
        );

        summary['total'] = summary['total']! + 1;

        if (isPointCompleted({'fieldDate': effectiveFieldDate})) {
          summary['completed'] =
              summary['completed']! + 1;
        }
      }

      if (oldDoc != null) {
        // 바뀐 게 없으면 쓰지 않는다. (재업로드 시 쓰기 비용 절감)
        final changed = data.entries.any(
          (entry) =>
              entry.key != 'updatedAt' &&
              !_deepEquals(
                entry.value,
                oldData[entry.key],
              ),
        );

        if (!changed &&
            oldData['active'] == data['active']) {
          unchanged++;
          continue;
        }

        pendingRows.add({
          'type': 'update',
          'ref': oldDoc.reference,
          'data': data,
        });

        updated++;
      } else {
        final newDoc =
            _firestore
                .collection('weldingLogs')
                .doc();

        data['createdAt'] =
            FieldValue.serverTimestamp();

        pendingRows.add({
          'type': 'insert',
          'ref': newDoc,
          'data': data,
        });

        inserted++;
      }
    }

    // =======================================================
    // Batch 저장
    // =======================================================

    for (int start = 0;
        start < pendingRows.length;
        start += 450) {
      final end =
          (start + 450 <
                  pendingRows.length)
              ? start + 450
              : pendingRows.length;

      final batch =
          _firestore.batch();

      for (int i = start;
          i < end;
          i++) {
        final item =
            pendingRows[i];

        final DocumentReference
            ref = item['ref'];

        final Map<String, dynamic>
            data = item['data'];

        if (item['type'] == 'insert') {
          batch.set(
            ref,
            data,
          );
        } else {
          batch.set(
            ref,
            data,
            SetOptions(
              merge: true,
            ),
          );
        }
      }

      await batch.commit();
    }

    // =======================================================
    // 삭제된 Point 비활성
    // =======================================================

    int deactivated = 0;

    final List<DocumentReference>
        deactivateRefs = [];

    for (final entry
        in existingByKey.entries) {
      if (uploadedKeys.contains(
        entry.key,
      )) {
        continue;
      }

      final data =
          entry.value.data();

      if (data['active'] == false) {
        continue;
      }

      deactivateRefs.add(
        entry.value.reference,
      );

      deactivated++;
    }

    for (int start = 0;
        start < deactivateRefs.length;
        start += 450) {
      final end =
          (start + 450 <
                  deactivateRefs.length)
              ? start + 450
              : deactivateRefs.length;

      final batch =
          _firestore.batch();

      for (int i = start;
          i < end;
          i++) {
        batch.update(
          deactivateRefs[i],
          {
            'active': false,
            'updatedAt':
                FieldValue.serverTimestamp(),
          },
        );
      }

      await batch.commit();
    }

    // =======================================================
    // 메타데이터
    // =======================================================

    await _firestore
        .collection('weldingLogMeta')
        .doc(
          Uri.encodeComponent(
            projectId,
          ),
        )
        .set(
      {
        'projectId':
            projectId,
        'projectName':
            currentProjectName,
        'sheetName':
            sheetName,
        'headers':
            headers,
        'headerRowIndex':
            headerRowIndex,
        // PKG 진행률 요약.
        // 도면 화면에서는 weldingLogs 전체가 아니라 이 문서 1건만 읽는다.
        'pkgProgress':
            pkgSummary,
        'dwgNames':
            (dwgNames.toList()..sort()),
        'updatedAt':
            FieldValue.serverTimestamp(),
      },
      // pkgProgress는 통째로 교체 (없어진 PKG가 남지 않도록)
      SetOptions(
        mergeFields: [
          'projectId',
          'projectName',
          'sheetName',
          'headers',
          'headerRowIndex',
          'pkgProgress',
          'dwgNames',
          'updatedAt',
        ],
      ),
    );

    await loadWeldingLogs(
      projectId,
    );

    return {
      'inserted': inserted,
      'updated': updated,
      'deactivated': deactivated,
      'duplicated': duplicated,
      'unchanged': unchanged,
    };
  }

  // =========================================================
  // Firestore → Excel
  //
  // 중요:
  // 원본 excelRow에만 의존하지 않고
  // Firestore의 현재 값을 다시 매핑한다.
  // =========================================================

  Future<void> exportExcel(
    String projectId,
  ) async {
    final snapshot =
        await _firestore
            .collection('weldingLogs')
            .where(
              'projectId',
              isEqualTo: projectId,
            )
            .get();

    if (snapshot.docs.isEmpty) {
      throw Exception(
        '해당 현장의 Welding Log가 없습니다.',
      );
    }

    // =======================================================
    // Header 결정
    // =======================================================

    List<String> headers = [];

    try {
      final meta =
          await _firestore
              .collection('weldingLogMeta')
              .doc(
                Uri.encodeComponent(
                  projectId,
                ),
              )
              .get();

      if (meta.exists) {
        final data =
            meta.data();

        if (data != null &&
            data['headers'] is List) {
          headers =
              List<String>.from(
            data['headers'],
          );
        }
      }
    } catch (e) {
      debugPrint(
        'Excel header 메타데이터 읽기 실패: $e',
      );
    }

    // 메타데이터가 없으면 첫 문서의 헤더 사용
    if (headers.isEmpty) {
      final first =
          snapshot.docs.first.data();

      if (first['excelHeaders'] is List) {
        headers =
            List<String>.from(
          first['excelHeaders'],
        );
      }
    }

    if (headers.isEmpty) {
      headers =
          List<String>.from(
        _defaultHeaders,
      );
    }

    // =======================================================
    // NO 컬럼 확보
    //
    // 기존 Excel에 NO가 없으면 맨 앞에 추가
    // =======================================================

    final hasNoColumn =
        _findHeaderIndex(
              headers,
              [
                'NO',
                'No.',
                'NO.',
              ],
            ) >=
            0;

    if (!hasNoColumn) {
      headers = [
        'NO',
        ...headers,
      ];
    }

    // =======================================================
    // 작업 진행 컬럼 확보
    //
    // WeldingLog Total 원본에는 WELDER / SHOP / FIELD 컬럼이 없다.
    // 앱에서 입력한 값을 내보내기 위해 맨 뒤에 붙인다.
    // =======================================================

    for (final progressHeader
        in _progressHeaders) {
      final exists =
          _findHeaderIndex(
                headers,
                [progressHeader],
              ) >=
              0;

      if (!exists) {
        headers = [
          ...headers,
          progressHeader,
        ];
      }
    }

    // =======================================================
    // Workbook
    // =======================================================

    final workbook =
        Excel.createExcel();

    final defaultSheetName =
        workbook.tables.keys.first;

    if (defaultSheetName !=
        'Welding Log') {
      workbook.rename(
        defaultSheetName,
        'Welding Log',
      );
    }

    final sheet =
        workbook['Welding Log'];

    // =======================================================
    // 1행: SUBTOTAL (WeldingLog Total 형식)
    //
    // 2행이 Header, 3행부터 데이터.
    // 필터를 걸면 보이는 행의 합계만 표시된다.
    // =======================================================

    final lastExcelRow =
        snapshot.docs.length + 2;

    final List<CellValue?>
        subtotalRow =
        List<CellValue?>.filled(
      headers.length,
      null,
    );

    for (final names in [
      _hSize,
      _hDI,
      _hShopDI,
      _hFieldDI,
    ]) {
      final index =
          _findHeaderIndex(
        headers,
        names,
      );

      if (index < 0) {
        continue;
      }

      final col =
          _columnLetter(index);

      subtotalRow[index] =
          FormulaCellValue(
        'SUBTOTAL(9,${col}3:$col$lastExcelRow)',
      );
    }

    sheet.appendRow(
      subtotalRow,
    );

    // =======================================================
    // 2행: Header
    // =======================================================

    sheet.appendRow(
      headers
          .map<CellValue?>(
            (header) =>
                TextCellValue(
              header,
            ),
          )
          .toList(),
    );

    // =======================================================
    // NO 기준 정렬
    //
    // 숫자로 정렬:
    // 1 → 2 → 3 → 10 → 11
    //
    // NO가 없는 경우 ISO → Point 보조 정렬
    // =======================================================

    final sortedDocs =
        snapshot.docs.toList()
          ..sort(
            (a, b) {
              final ad =
                  a.data();

              final bd =
                  b.data();

              final noCompare =
                  _compareNo(
                ad['no'],
                bd['no'],
              );

              if (noCompare != 0) {
                return noCompare;
              }

              final isoCompare =
                  (ad['isoNo'] ?? '')
                      .toString()
                      .compareTo(
                        (bd['isoNo'] ?? '')
                            .toString(),
                      );

              if (isoCompare != 0) {
                return isoCompare;
              }

              return _pointNumber(
                ad['pointNo'],
              ).compareTo(
                _pointNumber(
                  bd['pointNo'],
                ),
              );
            },
          );

    // =======================================================
    // Row 생성
    // =======================================================

    for (int rowIndex = 0;
        rowIndex < sortedDocs.length;
        rowIndex++) {
      final data =
          sortedDocs[rowIndex].data();

      final List<dynamic>
          rowValues =
          List<dynamic>.filled(
        headers.length,
        null,
      );

      // -----------------------------------------------------
      // 기존 excelRow 복원
      // -----------------------------------------------------

      final excelRow =
          data['excelRow'];

      final excelHeaders =
          data['excelHeaders'];

      if (excelRow is Map &&
          excelHeaders is List) {
        final originalHeaders =
            List<String>.from(
          excelHeaders,
        );

        for (int i = 0;
            i < headers.length;
            i++) {
          final currentHeader =
              headers[i];

          if (currentHeader ==
              'NO') {
            continue;
          }

          final originalIndex =
              _findHeaderIndex(
            originalHeaders,
            [currentHeader],
          );

          if (originalIndex >= 0) {
            rowValues[i] =
                excelRow[
                    'col_$originalIndex'];
          }
        }
      }

      // -----------------------------------------------------
      // NO
      // -----------------------------------------------------

      final noIndex =
          _findHeaderIndex(
        headers,
        [
          'NO',
          'No.',
          'NO.',
        ],
      );

      if (noIndex >= 0) {
        final noValue =
            data['no'];

        rowValues[noIndex] =
            noValue ??
                (rowIndex + 1);
      }

      // -----------------------------------------------------
      // 현재 Firestore 값을 최우선 반영
      // -----------------------------------------------------

      final hasDwgNameColumn =
          _findHeaderIndex(
                headers,
                _hDwgName,
              ) >=
              0;

      final List<(List<String>, dynamic)>
          mappedValues = [
        (_hDwgName, data['dwgName'] ?? data['isoNo']),
        (_hFloor, data['floor']),
        (_hCode, data['code']),
        (_hCommodity, data['commodity']),
        (_hJobNo, data['jobNo']),
        (_hDesignPress, data['designPress']),
        (_hDesignTemp, data['designTemp']),
        (_hOperPress, data['operPress']),
        (_hOperTemp, data['operTemp']),
        (_hPAndId, data['pAndId']),
        (_hRefPlanDwg, data['refPlanDwg']),

        // DWG_NAME 컬럼이 있으면 ISO NO는 Excel 원래 값,
        // 예전 형식이면 isoNo를 그대로 쓴다.
        (_hIsoNo, hasDwgNameColumn
            ? data['lineIsoNo']
            : data['isoNo']),

        (_hSheetNo1, data['sheetNo']),
        (_hSheetNo2, data['sheetNo2']),
        (_hPointNo, data['pointNo']),
        (_hSize, data['size']),
        (_hDI, data['originalDI']),
        (_hClass, data['class']),
        (_hMaterial, data['material']),
        (_hSystem1, data['system1']),
        (_hSystem2, data['system2']),
        (_hWelder, data['welderNo']),
        (_hShopDate, data['shopDate']),
        (_hShopDI, data['shopDI']),
        (_hFieldDate, data['fieldDate']),
        (_hFieldDI, data['fieldDI']),
      ];

      for (final (names, value)
          in mappedValues) {
          _writeMappedValue(
            headers: headers,
            values: rowValues,
            names: names,
            value: value,
          );
      }

      sheet.appendRow(
        rowValues
            .map<CellValue?>(
              _dynamicToCellValue,
            )
            .toList(),
      );
    }

    // =======================================================
    // PKG Progress Sheet
    // =======================================================

    // WeldingLog Total 형식에는 PKG 컬럼이 없으므로
    // PKG 데이터가 있을 때만 시트를 만든다.
    final pkgProgress = await getPkgProgress(projectId);

    if (pkgProgress.isNotEmpty) {
    final progressSheet = workbook['PKG Progress'];

    progressSheet.appendRow([
      TextCellValue('PKG NO.'),
      TextCellValue('TOTAL QTY'),
      TextCellValue('COMPLETED QTY'),
      TextCellValue('REMAINING QTY'),
      TextCellValue('PROGRESS'),
    ]);

    for (final item in pkgProgress) {
      final pkgNo = item['pkgNo']?.toString() ?? '';
      final total = (item['total'] as num?)?.toInt() ?? 0;
      final completed = (item['completed'] as num?)?.toInt() ?? 0;
      final remaining = (item['remaining'] as num?)?.toInt() ?? 0;
      final progress = (item['progress'] as num?)?.toDouble() ?? 0.0;

      progressSheet.appendRow([
        TextCellValue(pkgNo),
        IntCellValue(total),
        IntCellValue(completed),
        IntCellValue(remaining),
        TextCellValue('${progress.toStringAsFixed(2)}%'),
      ]);
    }
    }

    // =======================================================
    // Encode
    // =======================================================

    final encoded =
        workbook.encode();

    if (encoded == null ||
        encoded.isEmpty) {
      throw Exception(
        'Excel 생성에 실패했습니다.',
      );
    }

    final bytes =
        Uint8List.fromList(
      encoded,
    );

    await FileSaver.instance.saveFile(
      name:
          '${_safeFileName(currentProjectName.isNotEmpty ? currentProjectName : projectId)}_WeldingLog',
      bytes:
          bytes,
      fileExtension:
          'xlsx',
      mimeType:
          MimeType.microsoftExcel,
    );
  }

  // =========================================================
  // Excel Row → Firestore
  // =========================================================

  Map<String, dynamic> _mapExcelRow({
    required List<String> headers,
    required List<dynamic> values,
  }) {
    dynamic get(
      List<String> names,
    ) {
      final index =
          _findHeaderIndex(
        headers,
        names,
      );

      if (index < 0 ||
          index >= values.length) {
        return null;
      }

      return values[index];
    }

    // -------------------------------------------------------
    // 도면 키
    //
    // isoNo   = DWG_NAME (앱 전체에서 도면/Point 조회에 사용)
    // lineIsoNo = Excel 'ISO NO' 컬럼
    //
    // DWG_NAME이 없는 예전 형식이면 ISO NO를 isoNo로 사용한다.
    // -------------------------------------------------------
    final dwgName = get(_hDwgName);
    final lineIsoNo = get(_hIsoNo);

    final hasDwgName =
        _findHeaderIndex(headers, _hDwgName) >= 0;

    // 예전 형식은 'D/I' 컬럼 없이 'Original D/I'에 물량이 있었다.
    final hasDI =
        _findHeaderIndex(headers, _hDI) >= 0;

    return {
      // ---------------- WeldingLog Total 형식 ----------------
      'no': get(_hNo),
      'dwgName': dwgName,
      'floor': get(_hFloor),
      'code': get(_hCode),
      'commodity': get(_hCommodity),
      'jobNo': get(_hJobNo),
      'designPress': get(_hDesignPress),
      'designTemp': get(_hDesignTemp),
      'operPress': get(_hOperPress),
      'operTemp': get(_hOperTemp),
      'pAndId': get(_hPAndId),
      'refPlanDwg': get(_hRefPlanDwg),
      'isoNo': hasDwgName ? dwgName : lineIsoNo,
      'lineIsoNo': lineIsoNo,
      'sheetNo': get(_hSheetNo1),
      'sheetNo2': get(_hSheetNo2),
      'pointNo': get(_hPointNo),

      // 'OriginalD/I' 컬럼에는 배관 Size(15, 25, 50 ...)가 들어있다.
      'size': hasDI ? get(_hSize) : null,

      // 실제 용접 물량(D/I). 공사일보 FIELD D/I 계산에 사용.
      'originalDI': hasDI ? get(_hDI) : get(_hSize),

      'class': get(_hClass),
      'material': get(_hMaterial),
      'system1': get(_hSystem1),
      'system2': get(_hSystem2),

      // ---------------- 작업 진행 컬럼 ----------------
      // 원본 Excel에는 없고 앱에서 입력/내보내기하는 값.
      // 앱에서 내려받은 Excel을 다시 올릴 때 읽힌다.
      'welderNo': get(_hWelder),
      'shopDate': get(_hShopDate),
      'shopDI': get(_hShopDI),
      'fieldDate': get(_hFieldDate),
      'fieldDI': get(_hFieldDI),

      // 예전 형식 호환 (있으면 읽고, 없으면 null)
      'status': get(['Status', 'STATUS']),
      'pkgNo': get(['PKG NO.', 'PKG NO', 'PKG']),
    };
  }

  // =========================================================
  // Header 이름 (WeldingLog Total 형식)
  //
  // _normalizeHeader로 공백 / 점 / 언더바 / 슬래시를 무시하고 비교한다.
  // =========================================================

  static const List<String> _hNo = ['NO', 'No.', 'NO.'];
  static const List<String> _hDwgName = ['DWG_NAME', 'DWG NAME'];
  static const List<String> _hFloor = ['Floor', 'FLOOR'];
  static const List<String> _hCode = ['CODE'];
  static const List<String> _hCommodity = ['COMMODITY'];
  static const List<String> _hJobNo = ['JOB_NO', 'JOB NO'];
  static const List<String> _hDesignPress = ['DESIGN_PRESS'];
  static const List<String> _hDesignTemp = ['DESIGN_TEMP'];
  static const List<String> _hOperPress = ['OPER_PRESS'];
  static const List<String> _hOperTemp = ['OPER_TEMP'];
  static const List<String> _hPAndId = ['P&ID', 'P&ID NO.'];
  static const List<String> _hRefPlanDwg = ['REF. PLAN DWG.', 'REF PLAN DWG'];
  static const List<String> _hIsoNo = ['ISO NO', 'ISO NO.', 'ISONO'];
  static const List<String> _hSheetNo1 = ['SHEETNo.1', 'SHEET No.', 'SHEET NO'];
  static const List<String> _hSheetNo2 = ['SHEETNo.2'];
  static const List<String> _hPointNo = ['PointNo.', 'Point No.', 'POINT NO', 'POINT'];
  static const List<String> _hSize = ['OriginalD/I', 'Original D/I'];
  static const List<String> _hDI = ['D/I'];
  static const List<String> _hClass = ['Class', 'CLASS'];
  static const List<String> _hMaterial = ['Metal/Non-Metal', 'Metal / Non-Metal'];
  static const List<String> _hSystem1 = ['System1', 'SYSTEM1'];
  static const List<String> _hSystem2 = ['System2', 'SYSTEM2'];

  static const List<String> _hWelder = ['WELDER', 'Welder'];
  static const List<String> _hShopDate = [
    'SHOP DATE',
    'SHOP Date',
    'Date (SHOP)',
    'Welding Completion / Date (SHOP)',
  ];
  static const List<String> _hShopDI = [
    'SHOP D/I',
    'D/I (SHOP)',
    'Welding Completion / D/I (SHOP)',
  ];
  static const List<String> _hFieldDate = [
    'FIELD DATE',
    'FIELD Date',
    'Date (FIELD)',
  ];
  static const List<String> _hFieldDI = [
    'FIELD D/I',
    'D/I (FIELD)',
  ];

  // Excel에 해당 컬럼이 있을 때만 저장하는 필드
  static const List<(List<String>, String)> _optionalColumns = [
    (_hWelder, 'welderNo'),
    (_hShopDate, 'shopDate'),
    (_hShopDI, 'shopDI'),
    (_hFieldDate, 'fieldDate'),
    (_hFieldDI, 'fieldDI'),
    (['Status', 'STATUS'], 'status'),
    (['PKG NO.', 'PKG NO', 'PKG'], 'pkgNo'),
  ];

  // 내보내기 때 원본 Excel 뒤에 붙이는 작업 진행 컬럼
  static const List<String> _progressHeaders = [
    'WELDER',
    'SHOP DATE',
    'SHOP D/I',
    'FIELD DATE',
    'FIELD D/I',
  ];

  // =========================================================
  // D/I 계산
  //
  // Excel 수식과 동일:
  // =IF(ISNUMBER(SEARCH("B", PointNo)), 0.5,
  //     SWITCH(VALUE(SUBSTITUTE(UPPER(Size), "A", "")),
  //       15, 0.5, 20, 0.75, 25, 1, ...))
  //
  // 표에 없는 Size(예: OD110)는 null.
  // =========================================================

  static const Map<int, double> _sizeToDI = {
    15: 0.5,
    20: 0.75,
    25: 1,
    32: 1.25,
    40: 1.5,
    50: 2,
    65: 2.5,
    80: 3,
    100: 4,
    125: 5,
    150: 6,
    200: 8,
    250: 10,
    300: 12,
    350: 14,
    400: 16,
    450: 18,
    500: 20,
    550: 22,
    600: 24,
    700: 28,
    750: 30,
    800: 32,
    900: 36,
  };

  double? _calculateDI({
    required dynamic pointNo,
    required dynamic size,
  }) {
    final point =
        pointNo?.toString().toUpperCase() ?? '';

    if (point.contains('B')) {
      return 0.5;
    }

    final sizeText = (size?.toString() ?? '')
        .toUpperCase()
        .replaceAll('A', '')
        .trim();

    final sizeNumber =
        double.tryParse(sizeText);

    if (sizeNumber == null ||
        sizeNumber != sizeNumber.roundToDouble()) {
      return null;
    }

    return _sizeToDI[sizeNumber.toInt()];
  }

  // =========================================================
  // Header 검색
  // =========================================================

  int _findHeaderIndex(
    List<String> headers,
    List<String> candidates,
  ) {
    for (int i = 0;
        i < headers.length;
        i++) {
      final normalized =
          _normalizeHeader(
        headers[i],
      );

      for (final candidate
          in candidates) {
        if (normalized ==
            _normalizeHeader(
              candidate,
            )) {
          return i;
        }
      }
    }

    return -1;
  }

  String _normalizeHeader(
    String value,
  ) {
    return value
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'[\s\._/\-]+',
          ),
          '',
        );
  }

  // =========================================================
  // Excel Cell → String
  // =========================================================

  String _cellToString(
    Data? cell,
  ) {
    if (cell == null) {
      return '';
    }

    final value =
        cell.value;

    if (value == null) {
      return '';
    }

    if (value is TextCellValue) {
      return value.value.toString();
    }

    if (value is IntCellValue) {
      return value.value.toString();
    }

    if (value is DoubleCellValue) {
      return value.value.toString();
    }

    if (value is BoolCellValue) {
      return value.value.toString();
    }

    if (value is FormulaCellValue) {
      return value.formula;
    }

    if (value is DateCellValue) {
      return value
          .asDateTimeLocal()
          .toString();
    }

    if (value is DateTimeCellValue) {
      return value
          .asDateTimeLocal()
          .toString();
    }

    if (value is TimeCellValue) {
      return value
          .asDuration()
          .toString();
    }

    return value.toString();
  }

  // =========================================================
  // Excel → Firestore
  // =========================================================

  dynamic _cellToFirestoreValue(
    Data? cell,
  ) {
    if (cell == null) {
      return null;
    }

    final value =
        cell.value;

    if (value == null) {
      return null;
    }

    switch (value) {
      case TextCellValue():
        return _textCellToPlainString(
          value.value,
        );

      case FormulaCellValue():
        return value.formula;

      case IntCellValue():
        return value.value;

      case DoubleCellValue():
        return value.value;

      case BoolCellValue():
        return value.value;

      case DateCellValue():
        return _formatDate(
          value.asDateTimeLocal(),
        );

      case DateTimeCellValue():
        return _formatDate(
          value.asDateTimeLocal(),
        );

      case TimeCellValue():
        return value
            .asDuration()
            .inMilliseconds;
    }
  }

  // =========================================================
  // Firestore → Excel Cell
  // =========================================================

  CellValue? _dynamicToCellValue(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return TextCellValue(
        _formatDate(
          value.toDate(),
        ),
      );
    }

    if (value is String) {
      return value.trim().isEmpty
          ? null
          : TextCellValue(value);
    }

    if (value is bool) {
      return BoolCellValue(value);
    }

    if (value is int) {
      return IntCellValue(value);
    }

    if (value is double) {
      return DoubleCellValue(value);
    }

    if (value is num) {
      return DoubleCellValue(
        value.toDouble(),
      );
    }

    if (value is DateTime) {
      return DateTimeCellValue(
        year: value.year,
        month: value.month,
        day: value.day,
        hour: value.hour,
        minute: value.minute,
        second: value.second,
        millisecond: value.millisecond,
        microsecond: value.microsecond,
      );
    }

    return TextCellValue(
      value.toString(),
    );
  }

  // =========================================================
  // Excel Row에 값 쓰기
  // =========================================================

  void _writeMappedValue({
    required List<String> headers,
    required List<dynamic> values,
    required List<String> names,
    required dynamic value,
  }) {
    final index =
        _findHeaderIndex(
      headers,
      names,
    );

    if (index < 0 ||
        index >= values.length) {
      return;
    }

    values[index] =
        _firestoreExportValue(
      value,
    );
  }

  dynamic _firestoreExportValue(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return _formatDate(
        value.toDate(),
      );
    }

    return value;
  }

  // =========================================================
  // NO 비교
  // =========================================================

  int _compareNo(
    dynamic a,
    dynamic b,
  ) {
    final aString =
        a?.toString().trim() ?? '';

    final bString =
        b?.toString().trim() ?? '';

    final aNumber =
        int.tryParse(aString);

    final bNumber =
        int.tryParse(bString);

    if (aNumber != null &&
        bNumber != null) {
      return aNumber.compareTo(
        bNumber,
      );
    }

    if (aNumber != null) {
      return -1;
    }

    if (bNumber != null) {
      return 1;
    }

    return aString.compareTo(
      bString,
    );
  }

  // =========================================================
  // Point Key
  // =========================================================

  String _makePointKey({
    required String projectId,
    required dynamic isoNo,
    required dynamic pointNo,
  }) {
    return '${projectId.trim()}'
        '|${isoNo?.toString().trim() ?? ''}'
        '|${pointNo?.toString().trim() ?? ''}'
        .toLowerCase();
  }

  // =========================================================
  // Empty Row
  // =========================================================

  bool _isEmptyRow(
    List<Data?> row,
  ) {
    for (final cell in row) {
      if (_cellToString(
        cell,
      ).trim().isNotEmpty) {
        return false;
      }
    }

    return true;
  }

  // =========================================================
  // Value
  // =========================================================

  String _valueAt(
    List<dynamic> values,
    int index,
  ) {
    if (index < 0 ||
        index >= values.length) {
      return '';
    }

    return values[index]
            ?.toString() ??
        '';
  }

  // =========================================================
  // Point 숫자
  // =========================================================

  int _pointNumber(
    dynamic value,
  ) {
    final number =
        int.tryParse(
      value?.toString() ?? '',
    );

    return number ?? 999999999;
  }

  // =========================================================
  // 날짜
  // =========================================================

  String _formatDate(
    DateTime date,
  ) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // =========================================================
  // 숫자
  // =========================================================

  double _toDouble(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0.0;
  }

  // =========================================================
  // 파일명
  // =========================================================

  // Firestore 값 비교 (Map / List 포함)
  bool _deepEquals(
    dynamic a,
    dynamic b,
  ) {
    if (a is num && b is num) {
      return a == b;
    }

    if (a is Map && b is Map) {
      if (a.length != b.length) {
        return false;
      }

      for (final key in a.keys) {
        if (!b.containsKey(key) ||
            !_deepEquals(a[key], b[key])) {
          return false;
        }
      }

      return true;
    }

    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }

      for (int i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) {
          return false;
        }
      }

      return true;
    }

    return a == b;
  }

  String _columnLetter(
    int index,
  ) {
    var n = index + 1;
    var result = '';

    while (n > 0) {
      final rem = (n - 1) % 26;
      result =
          String.fromCharCode(65 + rem) + result;
      n = (n - 1) ~/ 26;
    }

    return result;
  }

  String _safeFileName(
    String value,
  ) {
    return value.replaceAll(
      RegExp(
        r'[\\/:*?"<>|]',
      ),
      '_',
    );
  }

  // =========================================================
  // 기본 Header
  // =========================================================

  static const List<String>
      _defaultHeaders = [
    'NO',
    'DWG_NAME',
    'Floor',
    'CODE',
    'COMMODITY',
    'JOB_NO',
    'DESIGN_PRESS',
    'DESIGN_TEMP',
    'OPER_PRESS',
    'OPER_TEMP',
    'P&ID',
    'REF. PLAN DWG.',
    'ISO NO',
    'SHEETNo.1',
    'SHEETNo.2',
    'PointNo.',
    'OriginalD/I',
    'D/I',
    'Class',
    'Metal/Non-Metal',
    'System1',
    'System2',
  ];

  // =========================================================
  // XLSX numFmtId 보정
  // =========================================================

  Uint8List _sanitizeXlsxNumFmts(
    Uint8List bytes,
  ) {
    try {
      debugPrint(
        'sanitize 시작, 원본 크기: ${bytes.length}',
      );

      final archive =
          ZipDecoder().decodeBytes(
        bytes,
      );

      debugPrint(
        'zip decode 완료, 파일 수: ${archive.files.length}',
      );

      // -----------------------------------------------------
      // 고칠 파일 모으기
      //
      // 1) xl/styles.xml        : numFmtId 보정 (기존)
      // 2) xl/sharedStrings.xml : 중복 문자열 항목 보정
      //
      // excel 패키지는 sharedStrings에 똑같은 항목이 두 번 있으면
      // 하나로 합쳐버려서, 그 뒤의 문자열 번호가 전부 밀린다.
      // → 셀 값이 엉뚱하게 읽히고, 마지막 번호에서
      //   'Unexpected null value'로 죽는다.
      // (WeldingLog Total 파일: FR1 / ST1 / Metal 항목이 중복)
      // -----------------------------------------------------
      final Map<String, String> fixedFiles = {};

      for (final file
          in archive.files) {
        if (!file.isFile) {
          continue;
        }

        if (file.name ==
            'xl/styles.xml') {
          final originalXml =
              utf8.decode(
            file.content as List<int>,
          );

          final fixedXml =
              _remapBuiltinRangeNumFmtIds(
            originalXml,
          );

          if (fixedXml != originalXml) {
            fixedFiles[file.name] = fixedXml;
          }
        }

        if (file.name ==
            'xl/sharedStrings.xml') {
          final originalXml =
              utf8.decode(
            file.content as List<int>,
          );

          final fixedXml =
              _makeSharedStringsUnique(
            originalXml,
          );

          if (fixedXml != originalXml) {
            fixedFiles[file.name] = fixedXml;
          }
        }
      }

      if (fixedFiles.isEmpty) {
        debugPrint(
          '보정할 내용 없음, 원본 그대로 진행',
        );

        return bytes;
      }

      final newArchive =
          Archive();

      for (final file
          in archive.files) {
        if (!file.isFile) {
          continue;
        }

        final fixedXml =
            fixedFiles[file.name];

        if (fixedXml != null) {
          final data =
              utf8.encode(
            fixedXml,
          );

          newArchive.addFile(
            ArchiveFile(
              file.name,
              data.length,
              data,
            ),
          );
        } else {
          newArchive.addFile(
            ArchiveFile(
              file.name,
              file.content.length,
              file.content,
            ),
          );
        }
      }

      debugPrint(
        '${fixedFiles.keys.join(', ')} 보정 완료, 재압축 시작',
      );

      final encoded =
          ZipEncoder().encode(
        newArchive,
        level: 0,
      );

      if (encoded == null) {
        debugPrint(
          '재압축 실패(null), 원본 bytes로 진행',
        );

        return bytes;
      }

      debugPrint(
        '재압축 완료, 크기: ${encoded.length}',
      );

      return Uint8List.fromList(
        encoded,
      );
    } catch (e) {
      debugPrint(
        'numFmtId 보정 실패, 원본 bytes로 진행: $e',
      );

      return bytes;
    }
  }

  // =========================================================
  // sharedStrings 중복 항목 보정
  //
  // 같은 <si> 항목이 두 번째로 나오면 <t>에 의미 없는 속성을 붙여
  // 서로 다른 항목으로 인식되게 한다. 글자 내용은 그대로다.
  // =========================================================

  String _makeSharedStringsUnique(
    String sharedStringsXml,
  ) {
    final Map<String, int> seen = {};
    int fixedCount = 0;

    final fixed = sharedStringsXml.replaceAllMapped(
      RegExp(
        r'<si>.*?</si>',
        dotAll: true,
      ),
      (match) {
        final item = match.group(0)!;

        final count = (seen[item] ?? 0) + 1;
        seen[item] = count;

        if (count == 1) {
          return item;
        }

        fixedCount++;

        return item.replaceFirst(
          RegExp(r'<t(?=[\s>])'),
          '<t data-isonow-dup="$count"',
        );
      },
    );

    if (fixedCount > 0) {
      debugPrint(
        'sharedStrings 중복 항목 $fixedCount개 보정',
      );
    }

    return fixed;
  }

  String _remapBuiltinRangeNumFmtIds(
    String stylesXml,
  ) {
    final numFmtsMatch =
        RegExp(
      r'<numFmts count="\d+">(.*?)</numFmts>',
      dotAll: true,
    ).firstMatch(
      stylesXml,
    );

    if (numFmtsMatch == null) {
      return stylesXml;
    }

    final block =
        numFmtsMatch.group(1)!;

    final declaredIds =
        RegExp(
      r'numFmtId="(\d+)"',
    )
            .allMatches(
              block,
            )
            .map(
              (m) => int.parse(
                m.group(1)!,
              ),
            )
            .toSet();

    final badIds =
        declaredIds
            .where(
              (id) => id < 164,
            )
            .toList()
          ..sort();

    if (badIds.isEmpty) {
      return stylesXml;
    }

    final usedIds =
        Set<int>.from(
      declaredIds,
    );

    int nextFreeId(
      int from,
    ) {
      var candidate =
          from;

      while (usedIds.contains(
        candidate,
      )) {
        candidate++;
      }

      return candidate;
    }

    final Map<int, int>
        remap = {};

    var cursor = 164;

    for (final oldId
        in badIds) {
      final newId =
          nextFreeId(cursor);

      remap[oldId] =
          newId;

      usedIds.add(
        newId,
      );

      cursor =
          newId + 1;
    }

    var fixed =
        stylesXml;

    final sortedOldIds =
        remap.keys.toList()
          ..sort(
            (a, b) =>
                b.toString()
                    .length
                    .compareTo(
                      a.toString()
                          .length,
                    ),
          );

    for (final oldId
        in sortedOldIds) {
      final newId =
          remap[oldId]!;

      fixed =
          fixed.replaceAll(
        'numFmtId="$oldId"',
        'numFmtId="$newId"',
      );
    }

    return fixed;
  }

  // =========================================================
  // Rich Text → String
  // =========================================================

  String _textCellToPlainString(
    dynamic raw,
  ) {
    if (raw is String) {
      return raw;
    }

    if (raw == null) {
      return '';
    }

    final buffer =
        StringBuffer();

    void walk(
      dynamic node,
    ) {
      if (node == null) {
        return;
      }

      try {
        final dynamic text =
            (node as dynamic).text;

        if (text is String) {
          buffer.write(text);
        }
      } catch (_) {}

      try {
        final dynamic children =
            (node as dynamic).children;

        if (children is List) {
          for (final child
              in children) {
            walk(child);
          }
        }
      } catch (_) {}
    }

    walk(raw);

    return buffer.isEmpty
        ? raw.toString()
        : buffer.toString();
  }

  // =========================================================
  // Firestore 안전성 체크
  // =========================================================

  void _debugCheckFirestoreSafe(
    Map<String, dynamic> data, {
    required String isoNo,
    required String pointNo,
  }) {
    bool isSafe(
      dynamic v,
    ) {
      if (v == null) {
        return true;
      }

      if (v is String) {
        return true;
      }

      if (v is num) {
        return true;
      }

      if (v is bool) {
        return true;
      }

      if (v is FieldValue) {
        return true;
      }

      if (v is DateTime) {
        return true;
      }

      if (v is List) {
        return v.every(isSafe);
      }

      if (v is Map) {
        return v.values.every(isSafe);
      }

      return false;
    }

    data.forEach(
      (key, value) {
        if (!isSafe(value)) {
          debugPrint(
            '⚠️ Firestore에 못 들어가는 값 발견: '
            'ISO=$isoNo Point=$pointNo '
            'field="$key" '
            'runtimeType=${value.runtimeType} '
            'value=$value',
          );

          if (value is Map) {
            value.forEach(
              (k2, v2) {
                if (!isSafe(v2)) {
                  debugPrint(
                    '   └ 하위 필드 "$k2" '
                    'runtimeType=${v2.runtimeType} '
                    'value=$v2',
                  );
                }
              },
            );
          }
        }
      },
    );
  }
}