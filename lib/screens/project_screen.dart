import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pdf_viewer_screen.dart';
import '../services/iso_upload_service.dart';
import '../services/welding_test_service.dart';

class ProjectScreen extends StatefulWidget {
  // Firestore 현장 문서 ID. 모든 데이터는 이 값으로 분리한다.
  final String projectId;

  // 현장 이름. 화면 제목 / 도면 폴더(assets/sites/{현장이름}/)에 사용.
  final String projectName;

  const ProjectScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen>
    with SingleTickerProviderStateMixin {
  // =========================================================
  // SK 보고용 Welding 기능 표시 여부
  //
  // true  = Welding 관련 UI 표시
  // false = Welding 관련 UI 숨김
  //
  // 기능/데이터/서비스 코드는 그대로 유지됩니다.
  // =========================================================
  static const bool SHOW_WELDING_FEATURES = true;

  // =========================================================
  // Metadata
  // =========================================================

  List<Map<String, dynamic>> isoFiles = [];
  List<Map<String, dynamic>> pkgFiles = [];

  // 앱에서 업로드한 ISO (Firestore)
  List<Map<String, dynamic>> uploadedIsoFiles = [];

  // Welding Log에 있는 도면 이름 (PDF 없어도 ISO 탭에 표시)
  List<String> weldingDwgNames = [];
  Set<String> weldingDwgNameSet = {};
  bool isWeldingDwgLoaded = false;
  bool isRebuildingDwgNames = false;

  // ISO 탭 보기: 'all' = 전체, 'welding' = Welding Log 도면만
  String isoViewFilter = 'all';

  bool isUploadingIso = false;
  String isoUploadProgress = '';

  final IsoUploadService isoUploadService =
      IsoUploadService.instance;
  List<Map<String, dynamic>> planFiles = [];

  // Welding PKG 진행률
  List<Map<String, dynamic>> pkgProgress = [];
  bool isLoadingPkgProgress = false;

  bool isLoading = true;
  String searchQuery = '';

  final TextEditingController searchController =
      TextEditingController();

  late TabController tabController;

  // =========================================================
  // Firebase / Welding
  // =========================================================

  final WeldingTestService weldingService =
      WeldingTestService.instance;

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  // =========================================================
  // Init
  // =========================================================

  @override
  void initState() {
    super.initState();

    tabController = TabController(
      length: 3,
      vsync: this,
    );

    // 현장별 데이터 분리: 이 화면의 현장을 먼저 지정한다.
    weldingService.setCurrentProject(
      projectId: widget.projectId,
      projectName: widget.projectName,
    );

    weldingService.addListener(_onDataChanged);

    loadCurrentUser();
    loadMetadata();
    loadPkgProgress();
    loadUploadedIsos();
    loadWeldingDwgNames();
  }

  @override
  void dispose() {
    weldingService.removeListener(_onDataChanged);

    searchController.dispose();
    tabController.dispose();

    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;

    setState(() {});
  }

  Future<void> loadCurrentUser() async {
    await weldingService.loadCurrentUser();

    if (!mounted) return;

    setState(() {});
  }

  // =========================================================
  // Metadata
  // =========================================================

  // 현장별 도면 폴더
  //
  // assets/sites/{현장이름}/iso/
  // assets/sites/{현장이름}/pkg/
  // assets/sites/{현장이름}/plan_dwg/
  // assets/sites/{현장이름}/iso_metadata.json ...
  //
  // 폴더 이름은 Firestore 현장 문서의 name과 같아야 한다. (예: M17)
  // 메타데이터는 tools/generate_pdf_metadata.py로 만든다.
  String get _siteAssetDir =>
      'assets/sites/${widget.projectName.trim()}';

  // 현장 폴더에 메타데이터가 없으면 빈 목록
  Future<List<Map<String, dynamic>>> _loadSiteMetadata(
    String fileName,
  ) async {
    try {
      final jsonString = await rootBundle.loadString(
        '$_siteAssetDir/$fileName',
      );

      final List<dynamic> data =
          json.decode(jsonString);

      return data
          .map(
            (item) => Map<String, dynamic>.from(item),
          )
          .toList();
    } catch (e) {
      debugPrint(
        '현장 도면 메타데이터 없음: $_siteAssetDir/$fileName ($e)',
      );

      return [];
    }
  }

  Future<void> loadMetadata() async {
    try {
      final loadedIsoFiles =
          await _loadSiteMetadata('iso_metadata.json');

      final loadedPkgFiles =
          await _loadSiteMetadata('pkg_metadata.json');

      final loadedPlanFiles =
          await _loadSiteMetadata('plan_metadata.json');

      loadedPkgFiles.sort(
        (a, b) => (a['fileName'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo(
              (b['fileName'] ?? '')
                  .toString()
                  .toLowerCase(),
            ),
      );

      loadedPlanFiles.sort(
        (a, b) => (a['fileName'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo(
              (b['fileName'] ?? '')
                  .toString()
                  .toLowerCase(),
            ),
      );

      if (!mounted) return;

      setState(() {
        isoFiles = loadedIsoFiles;
        pkgFiles = loadedPkgFiles;
        planFiles = loadedPlanFiles;
        isLoading = false;
      });
    } catch (e) {
      debugPrint(
        'Metadata 불러오기 오류: $e',
      );

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    }
  }

  // =========================================================
  // Welding PKG 진행률
  // =========================================================

  Future<void> loadPkgProgress() async {
    if (isLoadingPkgProgress) return;

    setState(() {
      isLoadingPkgProgress = true;
    });

    final result = await weldingService.getPkgProgress(
      widget.projectId,
    );

    if (!mounted) return;

    setState(() {
      pkgProgress = result;
      isLoadingPkgProgress = false;
    });
  }

  // =========================================================
  // 업로드 ISO / Welding 도면 목록 (각각 문서 1건 읽기)
  // =========================================================

  Future<void> loadUploadedIsos() async {
    final result =
        await isoUploadService.loadIndex(
      widget.projectId,
    );

    if (!mounted) return;

    setState(() {
      uploadedIsoFiles = result;
    });
  }

  Future<void> loadWeldingDwgNames() async {
    if (!SHOW_WELDING_FEATURES) {
      return;
    }

    final result =
        await weldingService.getWeldingDwgNames(
      widget.projectId,
    );

    if (!mounted) return;

    setState(() {
      weldingDwgNames = result;
      weldingDwgNameSet = result.toSet();
      isWeldingDwgLoaded = true;

      // Welding 도면이 있으면 공사일보 기입용 목록을 기본으로 보여준다.
      if (result.isNotEmpty) {
        isoViewFilter = 'welding';
      }
    });
  }

  // 관리자: Welding 도면 목록 만들기 (엑셀 재업로드 없이 1회)
  Future<void> _rebuildWeldingDwgNames() async {
    if (!_canManageIso || isRebuildingDwgNames) {
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Welding 도면 목록 만들기'),
        content: const Text(
          '현재 Welding Log에서 도면 이름을 모아 ISO 목록에 표시합니다.\n'
          'Welding Log 전체를 한 번 읽습니다. (Firestore 읽기 사용량 주의)\n\n'
          '엑셀을 다시 업로드해도 같은 목록이 자동으로 만들어집니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('만들기'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) {
      return;
    }

    setState(() {
      isRebuildingDwgNames = true;
    });

    try {
      final count =
          await weldingService.rebuildWeldingDwgNames(
        widget.projectId,
      );

      await loadWeldingDwgNames();

      _showMessage('Welding 도면 $count개를 ISO 목록에 표시합니다.');
    } catch (e) {
      _showMessage('Welding 도면 목록 만들기 실패\n$e');
    } finally {
      if (mounted) {
        setState(() {
          isRebuildingDwgNames = false;
        });
      }
    }
  }

  // 관리자: 업로드한 ISO 삭제
  Future<void> _deleteUploadedIso(
    String isoName,
    Map<String, dynamic> iso,
  ) async {
    if (!_canManageIso) {
      return;
    }

    final docId = iso['docId']?.toString() ?? '';
    final fileName = iso['fileName']?.toString() ?? isoName;

    if (docId.isEmpty) {
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ISO 삭제'),
        content: Text(
          '$fileName\n\n이 PDF를 삭제할까요? 되돌릴 수 없습니다.\n'
          '(Welding Log와 공사일보 기록은 그대로 남습니다.)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

    try {
      await isoUploadService.deleteIso(
        projectId: widget.projectId,
        docId: docId,
      );

      await loadUploadedIsos();

      _showMessage('삭제했습니다: $fileName');
    } catch (e) {
      _showMessage('ISO 삭제 실패\n$e');
    }
  }

  // =========================================================
  // ISO 업로드 권한
  //
  // super_admin: 모든 현장
  // admin: users.projects에 이 현장이 승인된 경우만
  // =========================================================

  bool get _canManageIso {
    final role = weldingService.currentRole;

    if (role == 'super_admin') {
      return true;
    }

    if (role != 'admin') {
      return false;
    }

    final projects =
        weldingService.userData['projects'];

    return projects is List &&
        projects.contains(widget.projectId);
  }

  // =========================================================
  // ISO 업로드
  // =========================================================

  Future<void> _uploadIsos() async {
    if (!_canManageIso || isUploadingIso) {
      return;
    }

    setState(() {
      isUploadingIso = true;
      isoUploadProgress = '파일 읽는 중...';
    });

    try {
      final result =
          await isoUploadService.pickAndUpload(
        projectId: widget.projectId,
        onProgress: (done, total) {
          if (!mounted) return;

          setState(() {
            isoUploadProgress =
                '업로드 중 $done / $total';
          });
        },
      );

      if (result == null || !mounted) {
        return;
      }

      await loadUploadedIsos();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('ISO 업로드 결과'),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      '신규 ${result.uploaded.length}개 · '
                      '교체 ${result.replaced.length}개 · '
                      '제외 ${result.skipped.length}개 · '
                      '실패 ${result.failed.length}개',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (result.skipped.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('제외된 파일'),
                      ...result.skipped.map(
                        (name) => Text(
                          '· $name',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    if (result.failed.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('실패한 파일 (다시 올려주세요)'),
                      ...result.failed.map(
                        (name) => Text(
                          '· $name',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(),
                child: const Text('확인'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      _showMessage('ISO 업로드 실패\n$e');
    } finally {
      if (mounted) {
        setState(() {
          isUploadingIso = false;
          isoUploadProgress = '';
        });
      }
    }
  }

  // =========================================================
  // ISO 그룹화
  //
  // 1) 앱에 포함된 ISO (assets)
  // 2) 앱에서 업로드한 ISO (Firestore)
  // 3) Welding Log에만 있는 도면 → PDF 없이 이름만 (공사일보 기입용)
  // =========================================================

  Map<String, List<Map<String, dynamic>>> groupByIso() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final iso in [
      ...isoFiles,
      ...uploadedIsoFiles,
    ]) {
      final isoName =
          iso['isoName']?.toString() ?? '';

      grouped.putIfAbsent(
        isoName,
        () => [],
      );

      grouped[isoName]!.add(iso);
    }

    for (final dwgName in weldingDwgNames) {
      grouped.putIfAbsent(
        dwgName,
        () => [],
      );
    }

    // 도면 이름순, 같은 도면은 Revision 순
    final sortedKeys = grouped.keys.toList()..sort();

    return {
      for (final key in sortedKeys)
        key: grouped[key]!
          ..sort(
            (a, b) => ((a['revisionNumber'] as num?) ?? -1)
                .compareTo(
              (b['revisionNumber'] as num?) ?? -1,
            ),
          ),
    };
  }

  // =========================================================
  // 검색
  // =========================================================

  List<String> getSearchKeywords() {
    return searchQuery
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where(
          (keyword) => keyword.isNotEmpty,
        )
        .toList();
  }

  Map<String, List<Map<String, dynamic>>> getFilteredIsos() {
    var grouped = groupByIso();

    // Welding Log 도면만 보기
    if (isoViewFilter == 'welding') {
      grouped = {
        for (final entry in grouped.entries)
          if (weldingDwgNameSet.contains(entry.key))
            entry.key: entry.value,
      };
    }

    final keywords = getSearchKeywords();

    if (keywords.isEmpty) {
      return grouped;
    }

    final Map<String, List<Map<String, dynamic>>> filtered = {};

    for (final entry in grouped.entries) {
      final isoName =
          entry.key.toLowerCase();

      final matches = keywords.every(
        (keyword) => isoName.contains(keyword),
      );

      if (matches) {
        filtered[entry.key] = entry.value;
      }
    }

    return filtered;
  }

  List<Map<String, dynamic>> getFilteredPkgFiles() {
    final keywords = getSearchKeywords();

    if (keywords.isEmpty) {
      return pkgFiles;
    }

    return pkgFiles.where(
      (file) {
        final fileName =
            file['fileName']
                    ?.toString()
                    .toLowerCase() ??
                '';

        return keywords.every(
          (keyword) => fileName.contains(keyword),
        );
      },
    ).toList();
  }

  List<Map<String, dynamic>> getFilteredPlanFiles() {
    final keywords = getSearchKeywords();

    if (keywords.isEmpty) {
      return planFiles;
    }

    return planFiles.where(
      (file) {
        final fileName =
            file['fileName']
                    ?.toString()
                    .toLowerCase() ??
                '';

        return keywords.every(
          (keyword) => fileName.contains(keyword),
        );
      },
    ).toList();
  }

  // =========================================================
  // 검색창
  // =========================================================

  Widget buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        15,
        20,
        10,
      ),
      child: TextField(
        controller: searchController,
        onChanged: (value) {
          setState(() {
            searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: '검색 (예: POW 7002)',
          prefixIcon: const Icon(
            Icons.search,
          ),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.clear,
                  ),
                  onPressed: () {
                    searchController.clear();

                    setState(() {
                      searchQuery = '';
                    });
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(
              12,
            ),
          ),
          filled: true,
        ),
      ),
    );
  }

  // =========================================================
  // ISO
  // =========================================================

  Widget buildIsoTab() {
    final filteredIsos =
        getFilteredIsos();

    final entries =
        filteredIsos.entries.toList();

    return Column(
      children: [
        // =================================================
        // ISO 업로드 (현장 admin 이상)
        // =================================================

        if (_canManageIso)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              10,
              20,
              0,
            ),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: isUploadingIso
                      ? null
                      : _uploadIsos,
                  icon: const Icon(
                    Icons.upload_file,
                    size: 18,
                  ),
                  label: const Text(
                    'ISO 업로드',
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Text(
                    isUploadingIso
                        ? isoUploadProgress
                        : 'PDF 여러 개 또는 ZIP 선택 가능 · 파일당 1MB 이하 · 같은 파일명은 교체',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        if (isUploadingIso)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: LinearProgressIndicator(
              minHeight: 2,
            ),
          ),

        // =================================================
        // 보기 전환: Welding Log 도면(공사일보용) / 전체
        // =================================================

        if (SHOW_WELDING_FEATURES)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              10,
              20,
              0,
            ),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(
                    'Welding Log 도면 (${weldingDwgNames.length})',
                  ),
                  selected: isoViewFilter == 'welding',
                  onSelected: (_) {
                    setState(() {
                      isoViewFilter = 'welding';
                    });
                  },
                ),

                const SizedBox(width: 8),

                ChoiceChip(
                  label: const Text('전체'),
                  selected: isoViewFilter == 'all',
                  onSelected: (_) {
                    setState(() {
                      isoViewFilter = 'all';
                    });
                  },
                ),

                const Spacer(),

                Text(
                  '${entries.length}개',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

        // Welding 도면 목록이 아직 없을 때 (관리자에게만 버튼)
        if (SHOW_WELDING_FEATURES &&
            isWeldingDwgLoaded &&
            weldingDwgNames.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              10,
              20,
              0,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(
                  color: Colors.amber.shade200,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Welding 도면 목록이 없습니다. '
                      'Welding Log 엑셀을 업로드하면 자동으로 만들어집니다.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (_canManageIso)
                    TextButton(
                      onPressed: isRebuildingDwgNames
                          ? null
                          : _rebuildWeldingDwgNames,
                      child: Text(
                        isRebuildingDwgNames
                            ? '만드는 중...'
                            : '지금 목록 만들기',
                      ),
                    ),
                ],
              ),
            ),
          ),

        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    searchQuery.trim().isEmpty
                        ? '등록된 ISO가 없습니다.'
                        : '검색 결과가 없습니다.',
                  ),
                )
              // 도면이 수천 개라 화면에 보이는 것만 그린다.
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];

                    return _buildIsoCard(
                      entry.key,
                      entry.value,
                    );
                  },
                ),
        ),
      ],
    );
  }

  // 도면이 수천 개라 한 줄짜리 컴팩트 카드로 표시
  Widget _buildIsoCard(
    String isoName,
    List<Map<String, dynamic>> revisions,
  ) {
    return Card(
      margin: const EdgeInsets.only(
        bottom: 6,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isoName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                // =================================================
                // 공사일보 버튼
                // =================================================

                if (SHOW_WELDING_FEATURES &&
                    weldingService.canAccessDailyReport)
                  OutlinedButton.icon(
                    onPressed: () {
                      _openWeldingDaily(
                        isoName,
                      );
                    },
                    icon: const Icon(
                      Icons.assignment,
                      size: 18,
                    ),
                    label: const Text(
                      '공사일보',
                    ),
                  ),
              ],
            ),

            const SizedBox(
              height: 6,
            ),

            // PDF가 없는 도면 (Welding Log에만 있음)
            if (revisions.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius:
                      BorderRadius.circular(6),
                ),
                child: Text(
                  'PDF 미등록 (Welding Log 도면)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: revisions.map(
                  (iso) => _buildRevisionButton(
                    isoName,
                    iso,
                  ),
                ).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevisionButton(
    String isoName,
    Map<String, dynamic> iso,
  ) {
    final revision =
        iso['revision']?.toString() ?? 'Rev.?';

    final modifiedDate =
        iso['modifiedDate']?.toString() ?? '';

    final isUploaded =
        iso['source'] == 'upload';

    final pdfPath =
        iso['path']?.toString() ?? '';

    final docId =
        iso['docId']?.toString() ?? '';

    final canOpen = isUploaded
        ? docId.isNotEmpty
        : pdfPath.isNotEmpty;

    final button = OutlinedButton(
      onPressed: !canOpen
          ? null
          : () {
              // 버튼 누를 때 한 번만 읽는다 (route가 다시 그려져도 재조회 X)
              final pdfBytes = isUploaded
                  ? isoUploadService.loadPdfBytes(
                      projectId: widget.projectId,
                      docId: docId,
                    )
                  : null;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      PDFViewerScreen(
                    pdfPath: pdfPath,
                    title: '$isoName - $revision',
                    pdfBytes: pdfBytes,
                  ),
                ),
              );
            },
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                revision,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isUploaded)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.cloud_done,
                    size: 14,
                  ),
                ),
            ],
          ),
          Text(
            modifiedDate,
            style: const TextStyle(
              fontSize: 11,
            ),
          ),
        ],
      ),
    );

    // 업로드한 ISO만 삭제 가능 (현장 admin 이상)
    if (!isUploaded || !_canManageIso) {
      return button;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        IconButton(
          tooltip: 'ISO 삭제',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.delete_outline,
            size: 18,
            color: Colors.red.shade400,
          ),
          onPressed: () => _deleteUploadedIso(
            isoName,
            iso,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // 공사일보 입력
  // =========================================================

  Future<void> _openWeldingDaily(
    String isoNo,
  ) async {
    final points =
        await weldingService.loadPointsForIso(
      projectId: widget.projectId,
      isoNo: isoNo,
    );

    if (!mounted) {
      return;
    }

    if (points.isEmpty) {
      _showMessage(
        '해당 ISO에 등록된 활성 Welding Point가 없습니다.',
      );

      return;
    }

    final selectedPoints = <String>{};

    DateTime workDate = DateTime.now();

    final commentController =
        TextEditingController();

    // =========================================================
    // 공사일보 용접사 목록 Scrollbar Controller
    // =========================================================

    final welderScrollController =
        ScrollController();

    // ---------------------------------------------------------
    // 현장에 등록된 용접사 조회
    // ---------------------------------------------------------

    final welders =
        await _loadProjectWelders();

    if (!mounted) {
      commentController.dispose();
      welderScrollController.dispose();
      return;
    }

    // pipefitter는 등록된 용접사가 없으면 작업할 수 없음.
    // admin / super_admin은 창을 열어서 바로 용접사를 추가할 수 있음.
    if (welders.isEmpty && !_isAdminLevel) {
      commentController.dispose();
      welderScrollController.dispose();

      await _showNoWeldersDialog();

      return;
    }

    final favoriteWelderIds =
        await _loadFavoriteWelderIds();

    String? selectedWelderId;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            final sortedWelders =
                List<Map<String, dynamic>>.from(
              welders,
            );

            // =====================================================
            // 즐겨찾기 우선
            // 그 다음 이름 가나다순
            // =====================================================

            sortedWelders.sort(
              (a, b) {
                final aUid =
                    a['userUid']?.toString() ?? '';

                final bUid =
                    b['userUid']?.toString() ?? '';

                final aFavorite =
                    favoriteWelderIds.contains(
                  aUid,
                );

                final bFavorite =
                    favoriteWelderIds.contains(
                  bUid,
                );

                if (aFavorite &&
                    !bFavorite) {
                  return -1;
                }

                if (!aFavorite &&
                    bFavorite) {
                  return 1;
                }

                final nameA =
                    (a['name'] ?? '')
                        .toString();

                final nameB =
                    (b['name'] ?? '')
                        .toString();

                final nameCompare =
                    nameA.compareTo(nameB);

                if (nameCompare != 0) {
                  return nameCompare;
                }

                return (a['welderNo'] ?? '')
                    .toString()
                    .toLowerCase()
                    .compareTo(
                      (b['welderNo'] ?? '')
                          .toString()
                          .toLowerCase(),
                    );
              },
            );

            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '공사일보 작업 등록',
                    ),
                  ),

                  // ===================================================
                  // Admin / Super Admin만 용접사 추가 가능
                  // ===================================================

                  if (_isAdminLevel)
                    TextButton.icon(
                      onPressed: () async {
                        final added =
                            await _showAddWelderDialog();

                        if (!added) {
                          return;
                        }

                        final refreshed =
                            await _loadProjectWelders();

                        if (!mounted) {
                          return;
                        }

                        setDialogState(() {
                          welders
                            ..clear()
                            ..addAll(
                              refreshed,
                            );

                          // 새로 추가한 경우 기존 선택은 유지하지 않음.
                          if (selectedWelderId !=
                              null) {
                            final exists =
                                welders.any(
                              (welder) =>
                                  welder[
                                          'userUid']
                                      ?.toString() ==
                                  selectedWelderId,
                            );

                            if (!exists) {
                              selectedWelderId =
                                  null;
                            }
                          }
                        });
                      },
                      icon: const Icon(
                        Icons.person_add,
                        size: 18,
                      ),
                      label: const Text(
                        '용접사 추가',
                      ),
                    ),
                ],
              ),

              content: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      // =================================================
                      // ISO
                      // =================================================

                      Text(
                        'ISO : $isoNo',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(
                        height: 15,
                      ),

                      // =================================================
                      // 작업일
                      // =================================================

                      Row(
                        children: [
                          const Text(
                            '작업일',
                            style:
                                TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),

                          const SizedBox(
                            width: 15,
                          ),

                          OutlinedButton.icon(
                            onPressed: () async {
                              final date =
                                  await showDatePicker(
                                context:
                                    context,
                                initialDate:
                                    workDate,
                                firstDate:
                                    DateTime(
                                  2020,
                                ),
                                lastDate:
                                    DateTime(
                                  2035,
                                ),
                                locale:
                                    const Locale(
                                  'ko',
                                  'KR',
                                ),
                              );

                              if (date ==
                                  null) {
                                return;
                              }

                              setDialogState(
                                () {
                                  workDate =
                                      date;
                                },
                              );
                            },
                            icon:
                                const Icon(
                              Icons
                                  .calendar_month,
                            ),
                            label:
                                Text(
                              _formatDate(
                                workDate,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 20,
                      ),

                      // =================================================
                      // Welding Point
                      // =================================================

                      const Text(
                        '작업 Point 선택',
                        style:
                            TextStyle(
                          fontWeight:
                              FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(
                        height: 6,
                      ),

                      Text(
                        '이미 FIELD Date가 입력된 Point는 선택할 수 없습니다.',
                        style:
                            TextStyle(
                          fontSize: 12,
                          color: Colors
                              .grey
                              .shade600,
                        ),
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            points.map(
                          (point) {
                            final pointNo =
                                point['pointNo']
                                        ?.toString() ??
                                    '';

                            final completed =
                                weldingService
                                    .isPointCompleted(
                              point,
                            );

                            final selected =
                                selectedPoints
                                    .contains(
                              pointNo,
                            );

                            return FilterChip(
                              label: Text(
                                completed
                                    ? 'Point $pointNo ✓'
                                    : 'Point $pointNo',
                              ),
                              selected:
                                  selected,
                              onSelected:
                                  completed
                                      ? null
                                      : (
                                          value,
                                        ) {
                                          setDialogState(
                                            () {
                                              if (value) {
                                                selectedPoints
                                                    .add(
                                                  pointNo,
                                                );
                                              } else {
                                                selectedPoints
                                                    .remove(
                                                  pointNo,
                                                );
                                              }
                                            },
                                          );
                                        },
                            );
                          },
                        ).toList(),
                      ),

                      const SizedBox(
                        height: 15,
                      ),

                      Container(
                        width:
                            double.infinity,
                        padding:
                            const EdgeInsets
                                .all(
                          12,
                        ),
                        decoration:
                            BoxDecoration(
                          color: Colors
                              .grey
                              .shade100,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            8,
                          ),
                        ),
                        child: Text(
                          '선택된 Point : '
                          '${selectedPoints.length}개\n'
                          '예상 D/I : '
                          '${_calculateSelectedDI(
                            points,
                            selectedPoints,
                          ).toStringAsFixed(2)}',
                        ),
                      ),

                      const SizedBox(
                        height: 22,
                      ),

                      // =================================================
                      // 용접사
                      // =================================================

                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '용접사',
                              style:
                                  TextStyle(
                                fontWeight:
                                    FontWeight
                                        .bold,
                                fontSize: 16,
                              ),
                            ),
                          ),

                          Text(
                            '${sortedWelders.length}명',
                            style:
                                TextStyle(
                              fontSize: 12,
                              color: Colors
                                  .grey
                                  .shade600,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      Text(
                        _isPipefitter
                            ? '⭐ 즐겨찾기 용접사가 위쪽에 표시됩니다.'
                            : '현장 용접사 목록입니다.',
                        style:
                            TextStyle(
                          fontSize: 12,
                          color: Colors
                              .grey
                              .shade600,
                        ),
                      ),

                      const SizedBox(
                        height: 10,
                      ),

                      // =================================================
                      // 용접사 목록
                      // =================================================

                      Container(
                        width:
                            double.infinity,
                        height: 280,
                        decoration:
                            BoxDecoration(
                          border:
                              Border.all(
                            color: Colors
                                .grey
                                .shade300,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            8,
                          ),
                        ),
                        child:
                            sortedWelders.isEmpty
                                ? const Center(
                                    child:
                                        Text(
                                      '등록된 용접사가 없습니다.',
                                    ),
                                  )
                                : Scrollbar(
                                    controller:
                                        welderScrollController,
                                    thumbVisibility:
                                        true,
                                    interactive:
                                        true,
                                    child:
                                        ListView.separated(
                                      controller:
                                          welderScrollController,
                                      padding:
                                          const EdgeInsets
                                              .symmetric(
                                        vertical:
                                            4,
                                      ),
                                      itemCount:
                                          sortedWelders
                                              .length,
                                      separatorBuilder:
                                          (
                                        context,
                                        index,
                                      ) =>
                                              const Divider(
                                        height:
                                            1,
                                      ),
                                      itemBuilder:
                                          (
                                        context,
                                        index,
                                      ) {
                                        final welder =
                                            sortedWelders[
                                                index];

                                        final welderUid =
                                            welder[
                                                        'userUid']
                                                    ?.toString() ??
                                                '';

                                        final welderNo =
                                            welder[
                                                        'welderNo']
                                                    ?.toString() ??
                                                '';

                                        final welderName =
                                            welder[
                                                        'name']
                                                    ?.toString() ??
                                                '';

                                        final phone =
                                            welder[
                                                        'phone']
                                                    ?.toString() ??
                                                '';

                                        final isFavorite =
                                            favoriteWelderIds
                                                .contains(
                                          welderUid,
                                        );

                                        final isSelected =
                                            selectedWelderId ==
                                                welderUid;

                                        return ListTile(
                                          dense:
                                              true,
                                          selected:
                                              isSelected,
                                          leading:
                                              CircleAvatar(
                                            radius:
                                                18,
                                            child:
                                                Text(
                                              welderNo.isEmpty
                                                  ? '?'
                                                  : welderNo.substring(
                                                      0,
                                                      welderNo.length > 3
                                                          ? 3
                                                          : welderNo.length,
                                                    ),
                                              style:
                                                  const TextStyle(
                                                fontSize:
                                                    10,
                                              ),
                                            ),
                                          ),
                                          title:
                                              Text(
                                            welderName.isEmpty
                                                ? '이름 없음'
                                                : welderName,
                                            style:
                                                const TextStyle(
                                              fontWeight:
                                                  FontWeight.w600,
                                            ),
                                          ),
                                          subtitle:
                                              Text(
                                            '$welderNo${phone.isEmpty ? '' : '  ·  $phone'}',
                                          ),
                                          onTap:
                                              welderUid.isEmpty
                                                  ? null
                                                  : () {
                                                      setDialogState(
                                                        () {
                                                          selectedWelderId =
                                                              welderUid;
                                                        },
                                                      );
                                                    },
                                          trailing:
                                              Row(
                                            mainAxisSize:
                                                MainAxisSize.min,
                                            children: [
                                              if (isSelected)
                                                const Icon(
                                                  Icons
                                                      .check_circle,
                                                  color:
                                                      Colors.green,
                                                ),

                                              // ===================================
                                              // 즐겨찾기
                                              // pipefitter만 사용
                                              // ===================================

                                              if (_isPipefitter)
                                                IconButton(
                                                  tooltip:
                                                      isFavorite
                                                          ? '즐겨찾기 해제'
                                                          : '즐겨찾기',
                                                  icon:
                                                      Icon(
                                                    isFavorite
                                                        ? Icons.star
                                                        : Icons.star_border,
                                                  ),
                                                  onPressed:
                                                      welderUid.isEmpty
                                                          ? null
                                                          : () async {
                                                              final changed =
                                                                  await _toggleFavoriteWelder(
                                                                welderUid:
                                                                    welderUid,
                                                                isFavorite:
                                                                    isFavorite,
                                                              );

                                                              if (!changed) {
                                                                return;
                                                              }

                                                              setDialogState(
                                                                () {
                                                                  if (isFavorite) {
                                                                    favoriteWelderIds.remove(
                                                                      welderUid,
                                                                    );
                                                                  } else {
                                                                    favoriteWelderIds.add(
                                                                      welderUid,
                                                                    );
                                                                  }
                                                                },
                                                              );
                                                            },
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      // =================================================
                      // 선택된 용접사
                      // =================================================

                      if (selectedWelderId !=
                          null)
                        Builder(
                          builder:
                              (context) {
                            Map<String, dynamic>?
                                selected;

                            for (final welder
                                in welders) {
                              if (welder[
                                          'userUid']
                                      ?.toString() ==
                                  selectedWelderId) {
                                selected =
                                    welder;
                                break;
                              }
                            }

                            if (selected ==
                                null) {
                              return const SizedBox
                                  .shrink();
                            }

                            final selectedName =
                                selected[
                                            'name']
                                        ?.toString() ??
                                    '';

                            final selectedNo =
                                selected[
                                            'welderNo']
                                        ?.toString() ??
                                    '';

                            final selectedPhone =
                                selected[
                                            'phone']
                                        ?.toString() ??
                                    '';

                            return Container(
                              width:
                                  double.infinity,
                              padding:
                                  const EdgeInsets
                                      .all(
                                12,
                              ),
                              decoration:
                                  BoxDecoration(
                                border:
                                    Border.all(
                                  color:
                                      Colors
                                          .green,
                                ),
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons
                                        .person,
                                    color:
                                        Colors
                                            .green,
                                  ),
                                  const SizedBox(
                                    width: 10,
                                  ),
                                  Expanded(
                                    child: Text(
                                      '선택된 용접사 : '
                                      '$selectedNo '
                                      '($selectedName)'
                                      '${selectedPhone.isEmpty ? '' : ' · $selectedPhone'}',
                                      style:
                                          const TextStyle(
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                      const SizedBox(
                        height: 20,
                      ),

                      // =================================================
                      // Comment
                      // =================================================

                      TextField(
                        controller:
                            commentController,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'Comment',
                          hintText:
                              '작업 내용을 입력하세요.',
                          border:
                              OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child:
                      const Text('취소'),
                ),

                ElevatedButton.icon(
                  onPressed:
                      selectedPoints.isEmpty ||
                              selectedWelderId ==
                                  null
                          ? null
                          : () async {
                              Map<String, dynamic>?
                                  selectedWelder;

                              for (final welder
                                  in welders) {
                                if (welder[
                                            'userUid']
                                        ?.toString() ==
                                    selectedWelderId) {
                                  selectedWelder =
                                      welder;
                                  break;
                                }
                              }

                              if (selectedWelder ==
                                  null) {
                                _showMessage(
                                  '선택된 용접사 정보를 찾을 수 없습니다.',
                                );
                                return;
                              }

                              final welderUid =
                                  selectedWelder[
                                              'userUid']
                                          ?.toString() ??
                                      '';

                              final welderName =
                                  selectedWelder[
                                              'name']
                                          ?.toString() ??
                                      '';

                              final welderNo =
                                  selectedWelder[
                                              'welderNo']
                                          ?.toString() ??
                                      '';

                              if (welderUid.isEmpty ||
                                  welderName.isEmpty ||
                                  welderNo.isEmpty) {
                                _showMessage(
                                  '용접사 정보가 올바르지 않습니다.',
                                );
                                return;
                              }

                              final success =
                                  await weldingService
                                      .submitDailyReport(
                                projectId:
                                    widget.projectId,
                                isoNo:
                                    isoNo,
                                pointNos:
                                    selectedPoints
                                        .toList(),
                                workDate:
                                    workDate,
                                comment:
                                    commentController
                                        .text
                                        .trim(),
                                welderUid:
                                    welderUid,
                                welderName:
                                    welderName,
                                welderNo:
                                    welderNo,
                              );

                              if (!mounted) {
                                return;
                              }

                              Navigator.pop(
                                dialogContext,
                              );

                              if (success) {
                                _showMessage(
                                  '공사일보가 등록되었습니다.\n'
                                  'FIELD Date / FIELD D/I가 저장되었습니다.',
                                );
                              } else {
                                _showMessage(
                                  '처리할 수 있는 Point가 없습니다.',
                                );
                              }
                            },
                  icon: const Icon(
                    Icons.send,
                  ),
                  label: const Text(
                    '공사일보 제출',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    commentController.dispose();
    welderScrollController.dispose();
  }

  // =========================================================
  // 현재 프로젝트의 용접사 조회
  //
  // Firestore:
  //
  // projects/{projectId}/welders/{userUid}
  //
  // 문서:
  // {
  //   welderNo: "W-001"
  // }
  //
  // 이름/전화번호는 users/{userUid}에서 가져옴.
  // =========================================================

  Future<List<Map<String, dynamic>>>
      _loadProjectWelders() async {
    try {
      final snapshot = await _firestore
          .collection('projects')
          .doc(widget.projectId)
          .collection('welders')
          .get();

      final result =
          <Map<String, dynamic>>[];

      for (final welderDoc in snapshot.docs) {
        final welderData =
            welderDoc.data();

        final userUid =
            welderDoc.id;

        final welderNo =
            welderData['welderNo']
                    ?.toString()
                    .trim() ??
                '';

        if (welderNo.isEmpty) {
          continue;
        }

        final userDoc = await _firestore
            .collection('users')
            .doc(userUid)
            .get();

        if (!userDoc.exists) {
          continue;
        }

        final userData =
            userDoc.data();

        if (userData == null) {
          continue;
        }

        final status =
            userData['status']
                    ?.toString() ??
                '';

        final role =
            userData['role']
                    ?.toString() ??
                '';

        if (status != 'approved') {
          continue;
        }

        if (role != 'user') {
          continue;
        }

        result.add({
          'userUid': userUid,
          'welderNo': welderNo,
          'name':
              userData['name']
                      ?.toString() ??
                  '',
          'phone':
              userData['phone']
                      ?.toString() ??
                  '',
        });
      }

      // =========================================================
      // 이름 가나다순
      // =========================================================

      result.sort(
        (a, b) {
          final nameA =
              (a['name'] ?? '')
                  .toString();

          final nameB =
              (b['name'] ?? '')
                  .toString();

          final nameCompare =
              nameA.compareTo(nameB);

          if (nameCompare != 0) {
            return nameCompare;
          }

          return (a['welderNo'] ?? '')
              .toString()
              .compareTo(
                (b['welderNo'] ?? '')
                    .toString(),
              );
        },
      );

      return result;
    } catch (e) {
      debugPrint(
        '현장 용접사 조회 오류: $e',
      );

      return [];
    }
  }

  // =========================================================
  // pipefitter 개인 즐겨찾기 조회
  //
  // users/{현재UID}/favoriteWelders/{현장ID}__{용접사UID}
  // =========================================================

  Future<Set<String>>
      _loadFavoriteWelderIds() async {
    final user = _auth.currentUser;

    if (user == null ||
        !_isPipefitter) {
      return {};
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favoriteWelders')
          .where(
            'projectId',
            isEqualTo: widget.projectId,
          )
          .get();

      return snapshot.docs
          .map(
            (doc) =>
                doc.data()['welderUid']?.toString() ?? '',
          )
          .where(
            (uid) => uid.isNotEmpty,
          )
          .toSet();
    } catch (e) {
      debugPrint(
        '즐겨찾기 조회 오류: $e',
      );

      return {};
    }
  }

  // =========================================================
  // 즐겨찾기 ON / OFF
  // =========================================================

  Future<bool> _toggleFavoriteWelder({
    required String welderUid,
    required bool isFavorite,
  }) async {
    if (!_isPipefitter) {
      return false;
    }

    final user = _auth.currentUser;

    if (user == null) {
      _showMessage(
        '로그인 정보를 확인할 수 없습니다.',
      );

      return false;
    }

    try {
      final ref = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('favoriteWelders')
          // 현장별 즐겨찾기: 문서 ID = {현장ID}__{용접사UID}
          .doc('${widget.projectId}__$welderUid');

      if (isFavorite) {
        await ref.delete();
      } else {
        await ref.set({
          'projectId':
              widget.projectId,
          'projectName':
              widget.projectName,
          'welderUid':
              welderUid,
          'createdAt':
              FieldValue.serverTimestamp(),
        });
      }

      return true;
    } catch (e) {
      debugPrint(
        '즐겨찾기 변경 오류: $e',
      );

      _showMessage(
        '즐겨찾기 변경에 실패했습니다.',
      );

      return false;
    }
  }

  // =========================================================
  // 용접사 추가
  //
  // 1. 현재 현장의 approved user 조회
  // 2. role == user만 후보
  // 3. 이름 / 전화번호 검색
  // 4. 사용자 선택
  // 5. 용접사 번호 입력
  // 6. projects/{projectId}/welders/{userUid}
  //    에 welderNo만 저장
  // =========================================================

  Future<bool> _showAddWelderDialog() async {
    if (!_isAdminLevel) {
      return false;
    }

    // ---------------------------------------------------------
    // 현장 사용자 조회
    // ---------------------------------------------------------

    List<Map<String, dynamic>> users = [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .where(
            'projects',
            arrayContains: widget.projectId,
          )
          .get();

      for (final doc in snapshot.docs) {
        final data =
            Map<String, dynamic>.from(
          doc.data(),
        );

        final status =
            data['status']
                    ?.toString() ??
                '';

        final role =
            data['role']
                    ?.toString() ??
                '';

        // 승인된 일반 사용자만
        if (status != 'approved') {
          continue;
        }

        if (role != 'user') {
          continue;
        }

        data['uid'] = doc.id;

        users.add(data);
      }

      // -------------------------------------------------------
      // 이름 가나다순
      // -------------------------------------------------------

      users.sort(
        (a, b) {
          final nameA =
              (a['name'] ?? '')
                  .toString();

          final nameB =
              (b['name'] ?? '')
                  .toString();

          final result =
              nameA.compareTo(nameB);

          if (result != 0) {
            return result;
          }

          return (a['phone'] ?? '')
              .toString()
              .compareTo(
                (b['phone'] ?? '')
                    .toString(),
              );
        },
      );
    } catch (e) {
      debugPrint(
        '현장 사용자 조회 오류: $e',
      );

      _showMessage(
        '현장 사용자 목록을 불러오지 못했습니다.',
      );

      return false;
    }

    if (!mounted) {
      return false;
    }

    // ---------------------------------------------------------
    // 현재 이미 등록된 용접사 UID 조회
    // ---------------------------------------------------------

    final existingWelderIds =
        <String>{};

    try {
      final welderSnapshot =
          await _firestore
              .collection('projects')
              .doc(widget.projectId)
              .collection('welders')
              .get();

      for (final doc
          in welderSnapshot.docs) {
        existingWelderIds.add(
          doc.id,
        );
      }
    } catch (e) {
      debugPrint(
        '기존 용접사 UID 조회 오류: $e',
      );
    }

    String userSearchQuery = '';
    Map<String, dynamic>? selectedUser;

    final searchController =
        TextEditingController();

    // =========================================================
    // 용접사 선택창 Scrollbar Controller
    // =========================================================

    final welderUserScrollController =
        ScrollController();

    bool added = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            // ---------------------------------------------------
            // 검색
            // 이름 또는 전화번호
            // ---------------------------------------------------

            final query =
                userSearchQuery
                    .trim()
                    .toLowerCase();

            final normalizedQuery =
                query.replaceAll(
              RegExp(r'[\s-]'),
              '',
            );

            final filteredUsers =
                users.where(
              (user) {
                if (query.isEmpty) {
                  return true;
                }

                final name =
                    (user['name'] ?? '')
                        .toString()
                        .toLowerCase();

                final phone =
                    (user['phone'] ?? '')
                        .toString()
                        .toLowerCase();

                final normalizedPhone =
                    phone.replaceAll(
                  RegExp(r'[\s-]'),
                  '',
                );

                return name.contains(query) ||
                    phone.contains(query) ||
                    normalizedPhone.contains(
                      normalizedQuery,
                    );
              },
            ).toList();

            return AlertDialog(
              title: const Text(
                '용접사 선택',
              ),
              content: SizedBox(
                width: 600,
                height: 600,
                child: Column(
                  children: [
                    // ===========================================
                    // 검색창
                    // ===========================================

                    TextField(
                      controller:
                          searchController,
                      onChanged: (value) {
                        setDialogState(() {
                          userSearchQuery =
                              value;
                        });
                      },
                      decoration:
                          InputDecoration(
                        hintText:
                            '이름 또는 전화번호 검색',
                        prefixIcon:
                            const Icon(
                          Icons.search,
                        ),
                        suffixIcon:
                            userSearchQuery
                                    .isNotEmpty
                                ? IconButton(
                                    icon:
                                        const Icon(
                                      Icons.clear,
                                    ),
                                    onPressed:
                                        () {
                                      searchController
                                          .clear();

                                      setDialogState(
                                        () {
                                          userSearchQuery =
                                              '';
                                        },
                                      );
                                    },
                                  )
                                : null,
                        border:
                            OutlineInputBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    // ===========================================
                    // 안내
                    // ===========================================

                    Row(
                      children: [
                        Text(
                          '현장 사용자 ${filteredUsers.length}명',
                          style:
                              TextStyle(
                            fontSize: 13,
                            color: Colors
                                .grey
                                .shade700,
                          ),
                        ),
                        const Spacer(),
                        if (selectedUser !=
                            null)
                          Text(
                            '선택됨: '
                            '${selectedUser!['name'] ?? ''}',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                              color:
                                  Colors.green,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    // ===========================================
                    // 사용자 스크롤 목록
                    // ===========================================

                    Expanded(
                      child:
                          filteredUsers.isEmpty
                              ? const Center(
                                  child:
                                      Text(
                                    '검색 결과가 없습니다.',
                                  ),
                                )
                              : Container(
                                  decoration:
                                      BoxDecoration(
                                    border:
                                        Border.all(
                                      color: Colors
                                          .grey
                                          .shade300,
                                    ),
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                      8,
                                    ),
                                  ),
                                  child:
                                      Scrollbar(
                                    controller:
                                        welderUserScrollController,
                                    thumbVisibility:
                                        true,
                                    interactive:
                                        true,
                                    child:
                                        ListView
                                            .separated(
                                      controller:
                                          welderUserScrollController,
                                      padding:
                                          const EdgeInsets
                                              .symmetric(
                                        vertical:
                                            4,
                                      ),
                                      itemCount:
                                          filteredUsers
                                              .length,
                                      separatorBuilder:
                                          (
                                        context,
                                        index,
                                      ) =>
                                              const Divider(
                                        height:
                                            1,
                                      ),
                                      itemBuilder:
                                          (
                                        context,
                                        index,
                                      ) {
                                        final user =
                                            filteredUsers[
                                                index];

                                        final uid =
                                            user[
                                                        'uid']
                                                    ?.toString() ??
                                                '';

                                        final name =
                                            user[
                                                        'name']
                                                    ?.toString() ??
                                                '';

                                        final phone =
                                            user[
                                                        'phone']
                                                    ?.toString() ??
                                                '';

                                        final isSelected =
                                            selectedUser !=
                                                    null &&
                                                selectedUser![
                                                        'uid'] ==
                                                    uid;

                                        final alreadyWelder =
                                            existingWelderIds
                                                .contains(
                                          uid,
                                        );

                                        return ListTile(
                                          selected:
                                              isSelected,
                                          enabled:
                                              !alreadyWelder,
                                          leading:
                                              CircleAvatar(
                                            child:
                                                Text(
                                              name.isEmpty
                                                  ? '?'
                                                  : name.substring(
                                                      0,
                                                      1,
                                                    ),
                                            ),
                                          ),
                                          title:
                                              Row(
                                            children: [
                                              Expanded(
                                                child:
                                                    Text(
                                                  name.isEmpty
                                                      ? '이름 없음'
                                                      : name,
                                                  style:
                                                      const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              if (alreadyWelder)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal:
                                                        7,
                                                    vertical:
                                                        3,
                                                  ),
                                                  decoration:
                                                      BoxDecoration(
                                                    color:
                                                        Colors.green.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      5,
                                                    ),
                                                  ),
                                                  child:
                                                      Text(
                                                    '용접사 등록됨',
                                                    style:
                                                        TextStyle(
                                                      fontSize:
                                                          11,
                                                      color:
                                                          Colors.green.shade700,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          subtitle:
                                              Text(
                                            phone.isEmpty
                                                ? '전화번호 없음'
                                                : phone,
                                          ),
                                          trailing:
                                              isSelected
                                                  ? const Icon(
                                                      Icons
                                                          .check_circle,
                                                      color:
                                                          Colors.green,
                                                    )
                                                  : null,
                                          onTap:
                                              alreadyWelder
                                                  ? null
                                                  : () {
                                                      setDialogState(
                                                        () {
                                                          selectedUser =
                                                              user;
                                                        },
                                                      );
                                                    },
                                        );
                                      },
                                    ),
                                  ),
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child:
                      const Text('취소'),
                ),
                ElevatedButton.icon(
                  onPressed:
                      selectedUser ==
                              null
                          ? null
                          : () async {
                              final user =
                                  selectedUser!;

                              final uid =
                                  user['uid']
                                          ?.toString() ??
                                      '';

                              final name =
                                  user['name']
                                          ?.toString() ??
                                      '';

                              final phone =
                                  user['phone']
                                          ?.toString() ??
                                      '';

                              if (uid.isEmpty) {
                                _showMessage(
                                  '사용자 UID를 확인할 수 없습니다.',
                                );
                                return;
                              }

                              if (existingWelderIds
                                  .contains(
                                uid,
                              )) {
                                _showMessage(
                                  '이미 이 현장의 용접사로 등록되어 있습니다.',
                                );
                                return;
                              }

                              final welderNo =
                                  await _showWelderNoDialog(
                                userName:
                                    name,
                                phone:
                                    phone,
                              );

                              if (welderNo ==
                                  null) {
                                return;
                              }

                              final success =
                                  await _addWelder(
                                userUid:
                                    uid,
                                welderNo:
                                    welderNo,
                              );

                              if (!mounted) {
                                return;
                              }

                              if (success) {
                                added =
                                    true;

                                Navigator.pop(
                                  dialogContext,
                                );

                                _showMessage(
                                  '용접사가 추가되었습니다.',
                                );
                              }
                            },
                  icon: const Icon(
                    Icons.arrow_forward,
                  ),
                  label:
                      const Text('다음'),
                ),
              ],
            );
          },
        );
      },
    );

    welderUserScrollController.dispose();
    searchController.dispose();

    return added;
  }

  // =========================================================
  // 용접사 번호 입력
  // =========================================================

  Future<String?> _showWelderNoDialog({
    required String userName,
    required String phone,
  }) async {
    final controller =
        TextEditingController();

    String? result;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: const Text(
                '용접사 번호 지정',
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName.isEmpty
                          ? '이름 없음'
                          : userName,
                      style:
                          const TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    if (phone.isNotEmpty) ...[
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        phone,
                        style:
                            TextStyle(
                          color: Colors
                              .grey
                              .shade700,
                        ),
                      ),
                    ],

                    const SizedBox(
                      height: 18,
                    ),

                    TextField(
                      controller:
                          controller,
                      autofocus:
                          true,
                      decoration:
                          const InputDecoration(
                        labelText:
                            '용접사 번호',
                        hintText:
                            '예: W-001',
                        border:
                            OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving
                          ? null
                          : () {
                              Navigator.pop(
                                dialogContext,
                              );
                            },
                  child:
                      const Text('취소'),
                ),
                ElevatedButton(
                  onPressed:
                      saving
                          ? null
                          : () async {
                              final welderNo =
                                  controller
                                      .text
                                      .trim();

                              if (welderNo
                                  .isEmpty) {
                                _showMessage(
                                  '용접사 번호를 입력하세요.',
                                );
                                return;
                              }

                              setDialogState(
                                () {
                                  saving =
                                      true;
                                },
                              );

                              final duplicate =
                                  await _isWelderNoAlreadyUsed(
                                welderNo:
                                    welderNo,
                              );

                              if (!mounted) {
                                return;
                              }

                              if (duplicate) {
                                setDialogState(
                                  () {
                                    saving =
                                        false;
                                  },
                                );

                                _showMessage(
                                  '이미 사용 중인 용접사 번호입니다.',
                                );

                                return;
                              }

                              result =
                                  welderNo;

                              Navigator.pop(
                                dialogContext,
                              );
                            },
                  child:
                      saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : const Text(
                              '확인',
                            ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    return result;
  }

  // =========================================================
  // 용접사 번호 중복 검사
  //
  // 현재 프로젝트의 welders 전체를 확인.
  // 용접사는 많아야 수십 명 수준이므로 충분함.
  // =========================================================

  Future<bool> _isWelderNoAlreadyUsed({
    required String welderNo,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('projects')
          .doc(widget.projectId)
          .collection('welders')
          .get();

      for (final doc in snapshot.docs) {
        final data =
            doc.data();

        final existingNo =
            data['welderNo']
                    ?.toString()
                    .trim() ??
                '';

        if (existingNo.toLowerCase() ==
            welderNo.toLowerCase()) {
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint(
        '용접사 번호 중복 검사 오류: $e',
      );

      // 중복 검사 자체에 실패하면
      // 안전하게 저장을 막음.
      return true;
    }
  }

  // =========================================================
  // 용접사 추가 저장
  //
  // projects/{projectId}/welders/{userUid}
  //
  // {
  //   welderNo: "W-001"
  // }
  // =========================================================

  Future<bool> _addWelder({
    required String userUid,
    required String welderNo,
  }) async {
    try {
      if (userUid.isEmpty ||
          welderNo.isEmpty) {
        return false;
      }

      final welderRef = _firestore
          .collection('projects')
          .doc(widget.projectId)
          .collection('welders')
          .doc(userUid);

      // -------------------------------------------------------
      // 이 사용자가 이미 해당 프로젝트의 용접사인지 확인
      // -------------------------------------------------------

      final existing =
          await welderRef.get();

      if (existing.exists) {
        _showMessage(
          '이미 이 현장의 용접사로 등록되어 있습니다.',
        );

        return false;
      }

      // -------------------------------------------------------
      // 용접사 번호 중복 검사
      // -------------------------------------------------------

      final duplicate =
          await _isWelderNoAlreadyUsed(
        welderNo: welderNo,
      );

      if (duplicate) {
        _showMessage(
          '이미 사용 중인 용접사 번호입니다.',
        );

        return false;
      }

      // -------------------------------------------------------
      // 저장
      //
      // UID는 문서 ID.
      // 실제 필드는 welderNo 하나만.
      // -------------------------------------------------------

      await welderRef.set({
        'welderNo': welderNo,
      });

      return true;
    } catch (e) {
      debugPrint(
        '용접사 추가 오류: $e',
      );

      _showMessage(
        '용접사 추가에 실패했습니다.',
      );

      return false;
    }
  }

  // =========================================================
  // 용접사가 없는 경우
  // =========================================================

  Future<void> _showNoWeldersDialog() async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              const Text('용접사 없음'),
          content: const Text(
            '현재 현장에 등록된 용접사가 없습니다.\n\n'
            'Admin 이상 권한으로 용접사를 먼저 추가해주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                );
              },
              child:
                  const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  // =========================================================
  // 권한
  // =========================================================

  bool get _isPipefitter {
    return weldingService.currentRole ==
        'pipefitter';
  }

  bool get _isAdminLevel {
    return weldingService.currentRole ==
            'admin' ||
        weldingService.currentRole ==
            'super_admin';
  }

  // =========================================================
  // D/I 계산
  // =========================================================

  double _calculateSelectedDI(
    List<Map<String, dynamic>> points,
    Set<String> selected,
  ) {
    double total = 0;

    for (final point in points) {
      final pointNo =
          point['pointNo']?.toString();

      if (pointNo == null ||
          !selected.contains(pointNo)) {
        continue;
      }

      final value =
          point['originalDI'];

      if (value is num) {
        total += value.toDouble();
      } else {
        total +=
            double.tryParse(
                  value?.toString() ?? '',
                ) ??
                0;
      }
    }

    return total;
  }

  // =========================================================
  // PKG
  // =========================================================
  Widget buildPkgTab() {
    final files = getFilteredPkgFiles();

    return Column(
      children: [
        // =======================================================
        // Welding PKG Progress
        // =======================================================
        if (SHOW_WELDING_FEATURES &&
            weldingService.canAccessDailyReport)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Welding PKG 진행률',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '새로고침',
                          onPressed: isLoadingPkgProgress
                              ? null
                              : loadPkgProgress,
                          icon: isLoadingPkgProgress
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isLoadingPkgProgress)
                      const LinearProgressIndicator()
                    else if (pkgProgress.isEmpty)
                      const Text(
                        '등록된 Welding PKG 데이터가 없습니다.',
                        style: TextStyle(fontSize: 13),
                      )
                    else
                      ...pkgProgress.map(_buildPkgProgressRow),
                  ],
                ),
              ),
            ),
          ),

        // =======================================================
        // PKG 도면 목록
        // =======================================================
        Expanded(
          child: files.isEmpty
              ? Center(
                  child: Text(
                    searchQuery.trim().isEmpty
                        ? '등록된 PKG가 없습니다.'
                        : '검색 결과가 없습니다.',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];

                    final fileName =
                        file['fileName']?.toString() ?? '';
                    final modifiedDate =
                        file['modifiedDate']?.toString() ?? '';
                    final pdfPath =
                        file['path']?.toString() ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf),
                        title: Text(
                          fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '최종 수정: $modifiedDate',
                        ),
                        onTap: pdfPath.isEmpty
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        PDFViewerScreen(
                                      pdfPath: pdfPath,
                                      title: fileName,
                                    ),
                                  ),
                                );
                              },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPkgProgressRow(
    Map<String, dynamic> item,
  ) {
    final pkgNo = item['pkgNo']?.toString() ?? '';
    final total = (item['total'] as num?)?.toInt() ?? 0;
    final completed = (item['completed'] as num?)?.toInt() ?? 0;
    final remaining = (item['remaining'] as num?)?.toInt() ?? 0;
    final progress = (item['progress'] as num?)?.toDouble() ?? 0.0;

    final normalizedProgress =
        (progress / 100.0).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  pkgNo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: normalizedProgress,
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 105,
                child: Text(
                  '$completed / $total  ${progress.toStringAsFixed(2)}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '잔여 $remaining',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // PLAN
  // =========================================================

  Widget buildPlanTab() {
    final files =
        getFilteredPlanFiles();

    if (files.isEmpty) {
      return Center(
        child: Text(
          searchQuery.trim().isEmpty
              ? '등록된 플랜도가 없습니다.'
              : '검색 결과가 없습니다.',
        ),
      );
    }

    return ListView.builder(
      padding:
          const EdgeInsets.all(20),
      itemCount: files.length,
      itemBuilder:
          (context, index) {
        final file = files[index];

        final fileName =
            file['fileName']
                    ?.toString() ??
                '';

        final modifiedDate =
            file['modifiedDate']
                    ?.toString() ??
                '';

        final extension =
            file['extension']
                    ?.toString()
                    .toUpperCase() ??
                '';

        return Card(
          margin:
              const EdgeInsets.only(
            bottom: 10,
          ),
          child: ListTile(
            leading: const Icon(
              Icons.architecture,
            ),
            title: Text(
              fileName,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            subtitle: Text(
              '$extension · 최종 수정: $modifiedDate',
            ),
            onTap: () {},
          ),
        );
      },
    );
  }

  // =========================================================
  // Utils
  // =========================================================

  String _formatDate(
    DateTime date,
  ) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // =========================================================
  // Build
  // =========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.projectName,
        ),
      ),
      body: isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : Column(
              children: [
                buildSearchBar(),

                TabBar(
                  controller:
                      tabController,
                  tabs: const [
                    Tab(
                      text: 'ISO',
                    ),
                    Tab(
                      text: 'PKG',
                    ),
                    Tab(
                      text: '플랜도',
                    ),
                  ],
                ),

                Expanded(
                  child: TabBarView(
                    controller:
                        tabController,
                    children: [
                      buildIsoTab(),
                      buildPkgTab(),
                      buildPlanTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}