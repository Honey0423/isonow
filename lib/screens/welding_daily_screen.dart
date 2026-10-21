import 'dart:async';

import 'package:flutter/material.dart';

import '../services/welding_test_service.dart';

class WeldingDailyScreen extends StatefulWidget {
  final String projectId;
  final String projectName;

  const WeldingDailyScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  State<WeldingDailyScreen> createState() =>
      _WeldingDailyScreenState();
}

class _WeldingDailyScreenState
    extends State<WeldingDailyScreen> {
  final WeldingTestService service =
      WeldingTestService.instance;

  int _selectedTab = 0;

  DateTime _selectedDate =
      DateTime.now();

  bool _isExcelWorking = false;

  final ScrollController
      _tableHorizontalController =
      ScrollController();

  // =========================================================
  // ISO(DWG_NAME) 검색 - Everything 방식
  //
  // 도면 이름 목록(weldingLogMeta 1건)에서 바로 걸러내고,
  // 맞는 도면이 30개 이하면 그 도면들의 Point만 불러온다.
  // =========================================================

  final TextEditingController _isoSearchController =
      TextEditingController();

  Timer? _isoSearchDebounce;

  List<String> _dwgNames = [];

  List<String> _matchedDwgNames = [];

  @override
  void initState() {
    super.initState();

    // 현장별 데이터 분리: 이 화면의 현장을 먼저 지정한다.
    service.setCurrentProject(
      projectId: widget.projectId,
      projectName: widget.projectName,
    );

    // 검색창은 새로 비어 있으므로 이전 검색 조건도 지운다.
    service.resetIsoNoSearch();

    service.addListener(
      _onDataChanged,
    );

    _load();
  }

  Future<void> _load() async {
    // 검색용 도면 이름 목록 (문서 1건)
    final names =
        await service.getWeldingDwgNames(
      widget.projectId,
    );

    if (mounted) {
      setState(() {
        _dwgNames = names;
      });
    }

    await service.loadWeldingLogs(
      widget.projectId,
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // =========================================================
  // ISO 검색
  // =========================================================

  List<String> _isoSearchKeywords(
    String value,
  ) {
    return value
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((k) => k.isNotEmpty)
        .toList();
  }

  // 검색어가 모두 들어간 도면 이름 (예: "9073" / "9073 01" / "air 9073")
  List<String> _matchDwgNames(
    String value,
  ) {
    final keywords = _isoSearchKeywords(value);

    if (keywords.isEmpty) {
      return [];
    }

    return _dwgNames.where((name) {
      final lower = name.toLowerCase();
      return keywords.every(lower.contains);
    }).toList();
  }

  void _onIsoSearchChanged(
    String value,
  ) {
    setState(() {
      _matchedDwgNames = _matchDwgNames(value);
    });

    _isoSearchDebounce?.cancel();

    _isoSearchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _runIsoSearch(value),
    );
  }

  Future<void> _runIsoSearch(
    String value,
  ) async {
    final keywords = _isoSearchKeywords(value);

    if (keywords.isEmpty) {
      await service.clearIsoNoSearch(
        widget.projectId,
      );
      return;
    }

    // 도면 목록이 없으면 (엑셀 재업로드 전) 입력값 그대로 정확히 검색
    if (_dwgNames.isEmpty) {
      await service.applyIsoNoSearch(
        projectId: widget.projectId,
        isoNos: [value.trim()],
      );
      return;
    }

    final matched = _matchDwgNames(value);

    // 너무 많으면 조회하지 않고 아래 목록에서 고르게 한다 (읽기 비용 방지)
    if (matched.length >
        WeldingTestService.maxIsoSearchNames) {
      return;
    }

    await service.applyIsoNoSearch(
      projectId: widget.projectId,
      isoNos: matched,
    );
  }

  void _selectDwgName(
    String name,
  ) {
    _isoSearchDebounce?.cancel();

    _isoSearchController.text = name;

    setState(() {
      _matchedDwgNames = [name];
    });

    service.applyIsoNoSearch(
      projectId: widget.projectId,
      isoNos: [name],
    );
  }

  void _clearIsoSearch() {
    _isoSearchDebounce?.cancel();
    _isoSearchController.clear();

    setState(() {
      _matchedDwgNames = [];
    });

    service.clearIsoNoSearch(
      widget.projectId,
    );
  }

  Widget _buildIsoSearch() {
    final text = _isoSearchController.text;
    final hasText = text.trim().isNotEmpty;
    final matchCount = _matchedDwgNames.length;
    final tooMany = matchCount >
        WeldingTestService.maxIsoSearchNames;

    String info;

    if (!hasText) {
      info = _dwgNames.isEmpty
          ? '도면 목록이 없어 DWG_NAME 전체를 정확히 입력해야 검색됩니다. (엑셀 재업로드 시 부분 검색 가능)'
          : '도면 ${_dwgNames.length}개 · 번호 일부만 입력해도 됩니다 (예: 9073, 9073 01)';
    } else if (_dwgNames.isEmpty) {
      info = '정확히 일치하는 DWG_NAME 검색';
    } else if (matchCount == 0) {
      info = '일치하는 도면이 없습니다.';
    } else if (tooMany) {
      info = '일치 도면 $matchCount개 · 30개 이하가 되도록 더 입력하거나 아래에서 선택하세요.';
    } else {
      info = '일치 도면 $matchCount개의 Point를 표시합니다.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _isoSearchController,
                onChanged: _onIsoSearchChanged,
                decoration: InputDecoration(
                  hintText: 'ISO 검색 (예: 9073 / 9073 01 / AIR 9073)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: hasText
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clearIsoSearch,
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 기존 상세 필터 (CODE / COMMODITY / Floor / Welder)
            OutlinedButton.icon(
              onPressed: _showFilterDialog,
              icon: const Icon(
                Icons.tune,
                size: 18,
              ),
              label: const Text('상세 필터'),
            ),
          ],
        ),

        const SizedBox(height: 6),

        Text(
          info,
          style: TextStyle(
            fontSize: 12,
            color: hasText && matchCount == 0 && _dwgNames.isNotEmpty
                ? Colors.red.shade400
                : Colors.grey.shade600,
          ),
        ),

        // 일치 도면 목록 (눌러서 하나만 보기)
        if (hasText && matchCount > 1)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(
              maxHeight: 96,
            ),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _matchedDwgNames
                    .take(200)
                    .map(
                      (name) => ActionChip(
                        label: Text(
                          name,
                          style: const TextStyle(fontSize: 11),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _selectDwgName(name),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _isoSearchDebounce?.cancel();
    _isoSearchController.dispose();
    _tableHorizontalController.dispose();

    service.removeListener(
      _onDataChanged,
    );

    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // =========================================================
  // 전체
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
      body: Column(
        children: [
          _buildTabBar(),

          Expanded(
            child:
                _selectedTab == 0
                    ? _buildWeldingLog()
                    : _buildDailyReport(),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 탭
  // =========================================================

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color:
                Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              index: 0,
              icon:
                  Icons.table_chart,
              title:
                  'Welding Log',
            ),
          ),
          Expanded(
            child: _buildTabButton(
              index: 1,
              icon:
                  Icons.calendar_month,
              title:
                  '공사일보',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String title,
  }) {
    final selected =
        _selectedTab == index;

    final primary =
        Theme.of(context)
            .colorScheme
            .primary;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab =
              index;
        });
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          vertical: 15,
        ),
        decoration:
            BoxDecoration(
          border:
              Border(
            bottom:
                BorderSide(
              color:
                  selected
                      ? primary
                      : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color:
                  selected
                      ? primary
                      : Colors.grey,
            ),
            const SizedBox(
              width: 7,
            ),
            Text(
              title,
              style:
                  TextStyle(
                fontWeight:
                    selected
                        ? FontWeight.bold
                        : FontWeight.normal,
                color:
                    selected
                        ? primary
                        : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // Welding Log 전체
  // =========================================================

  Widget _buildWeldingLog() {
    final logs =
        service.weldingLogs;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        // =====================================================
        // 상단 고정 영역
        // =====================================================

        _buildWeldingLogHeader(),

        // =====================================================
        // 로딩
        // =====================================================

        if (service.isLoadingLogs)
          const LinearProgressIndicator(
            minHeight: 2,
          ),

        // =====================================================
        // 데이터 없음
        // =====================================================

        if (!service.isLoadingLogs &&
            logs.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Icon(
                    Icons
                        .table_rows_outlined,
                    size: 60,
                    color:
                        Colors.grey.shade400,
                  ),
                  const SizedBox(
                    height: 15,
                  ),
                  Text(
                    service.hasWeldingLogFilter
                        ? '검색 결과가 없습니다.'
                        : '등록된 Welding Log가 없습니다.',
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    service.hasWeldingLogFilter
                        ? '필터 조건을 변경해보세요.'
                        : 'Excel 파일을 업로드하면\n'
                          'Firestore에 등록됩니다.',
                    textAlign:
                        TextAlign.center,
                    style:
                        TextStyle(
                      color:
                          Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          // ===================================================
          // 표
          // ===================================================
          Expanded(
            child: Column(
              children: [
                // 가로 스크롤바를 항상 표시해서
                // 오른쪽 컬럼도 마우스로 끌어서 볼 수 있게 한다.
                Expanded(
                  child: Scrollbar(
                    controller:
                        _tableHorizontalController,
                    thumbVisibility: true,
                    child:
                        SingleChildScrollView(
                      controller:
                          _tableHorizontalController,
                      scrollDirection:
                          Axis.horizontal,
                      child:
                          SingleChildScrollView(
                        child:
                            _buildWeldingTable(
                          logs,
                        ),
                      ),
                    ),
                  ),
                ),

                // =================================================
                // 페이지네이션
                // =================================================

                _buildPagination(),
              ],
            ),
          ),
      ],
    );
  }

  // =========================================================
  // Welding Log Header
  // =========================================================

  Widget _buildWeldingLogHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        18,
        20,
        12,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welding Log',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '용접 작업 현황',
                    ),
                  ],
                ),
              ),

              if (_isExcelWorking)
                const Padding(
                  padding:
                      EdgeInsets.only(right: 15),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                ),

              OutlinedButton.icon(
                onPressed:
                    _isExcelWorking ||
                            service.weldingLogs.isEmpty
                        ? null
                        : _exportExcel,
                icon: const Icon(
                  Icons.download,
                ),
                label: const Text(
                  'Excel 다운로드',
                ),
              ),

              const SizedBox(width: 8),

              FilledButton.icon(
                onPressed:
                    _isExcelWorking
                        ? null
                        : _importExcel,
                icon: const Icon(
                  Icons.upload_file,
                ),
                label: const Text(
                  'Excel 업로드',
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          // ===================================================
          // ISO 검색 + 상세 필터
          // ===================================================

          _buildIsoSearch(),

          const SizedBox(height: 8),

          Row(
            children: [
              Text(
                service.hasWeldingLogFilter
                    ? '검색 결과 · 현재 페이지 ${service.weldingLogs.length}개'
                    : '현재 페이지 ${service.weldingLogs.length}개 Point',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      Colors.grey.shade600,
                ),
              ),

              const Spacer(),

              Text(
                'Page ${service.currentWeldingLogPage}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================
  // Filter Dialog
  // =========================================================

  Future<void> _showFilterDialog() async {
    final codeController =
        TextEditingController(
      text: service.filterCode,
    );

    final commodityController =
        TextEditingController(
      text: service.filterCommodity,
    );

    final floorController =
        TextEditingController(
      text: service.filterFloor,
    );

    final isoController =
        TextEditingController(
      text: service.filterIsoNo,
    );

    final welderController =
        TextEditingController(
      text: service.filterWelderNo,
    );

    final result =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.filter_alt),
              SizedBox(width: 8),
              Text('Welding Log 필터'),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                _buildFilterTextField(
                  controller:
                      codeController,
                  label: 'CODE',
                  hint: '예: N',
                ),

                const SizedBox(height: 12),

                _buildFilterTextField(
                  controller:
                      commodityController,
                  label: 'COMMODITY',
                  hint: '예: CDA(IA)',
                ),

                const SizedBox(height: 12),

                _buildFilterTextField(
                  controller:
                      floorController,
                  label: 'Floor',
                  hint: '예: 1F',
                ),

                const SizedBox(height: 12),

                _buildFilterTextField(
                  controller:
                      isoController,
                  label: 'DWG_NAME',
                  hint:
                      '예: 1F-15A-CDA(IA)-ST1-N-9011-01',
                ),

                const SizedBox(height: 12),

                _buildFilterTextField(
                  controller:
                      welderController,
                  label: 'Welder No.',
                  hint: '예: W-015',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(
                  dialogContext,
                ).pop(false);

                await service
                    .clearWeldingLogFilters(
                  widget.projectId,
                );
              },
              child:
                  const Text('초기화'),
            ),

            FilledButton(
              onPressed: () async {
                Navigator.of(
                  dialogContext,
                ).pop(true);

                await service
                    .applyWeldingLogFilters(
                  projectId:
                      widget.projectId,
                  code:
                      codeController.text,
                  commodity:
                      commodityController.text,
                  floor:
                      floorController.text,
                  isoNo:
                      isoController.text,
                  welderNo:
                      welderController.text,
                );
              },
              child:
                  const Text('검색'),
            ),
          ],
        );
      },
    );

    codeController.dispose();
    commodityController.dispose();
    floorController.dispose();
    isoController.dispose();
    welderController.dispose();

    if (result == true &&
        mounted) {
      setState(() {});
    }
  }

  Widget _buildFilterTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller:
          controller,
      decoration:
          InputDecoration(
        labelText:
            label,
        hintText:
            hint,
        border:
            const OutlineInputBorder(),
        isDense:
            true,
      ),
    );
  }

  // =========================================================
  // 페이지네이션
  // =========================================================

  Widget _buildPagination() {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 10,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.white,
        border:
            Border(
          top:
              BorderSide(
            color:
                Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed:
                service.hasPreviousWeldingLogPage &&
                        !service.isLoadingLogs
                    ? () async {
                        await service
                            .previousWeldingLogPage();
                      }
                    : null,
            icon:
                const Icon(
              Icons.chevron_left,
            ),
            label:
                const Text(
              '이전',
            ),
          ),

          const SizedBox(
            width: 18,
          ),

          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 9,
            ),
            decoration:
                BoxDecoration(
              color:
                  Colors.grey.shade100,
              borderRadius:
                  BorderRadius.circular(
                8,
              ),
            ),
            child:
                Text(
              'Page ${service.currentWeldingLogPage}',
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(
            width: 18,
          ),

          OutlinedButton.icon(
            onPressed:
                service.hasNextWeldingLogPage &&
                        !service.isLoadingLogs
                    ? () async {
                        await service
                            .nextWeldingLogPage();
                      }
                    : null,
            icon:
                const Icon(
              Icons.chevron_right,
            ),
            label:
                const Text(
              '다음',
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // Excel Export
  // =========================================================

  Future<void> _exportExcel() async {
    setState(() {
      _isExcelWorking =
          true;
    });

    try {
      await service.exportExcel(
        widget.projectId,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Welding Log Excel을 저장했습니다.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Excel 다운로드 실패\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExcelWorking =
              false;
        });
      }
    }
  }

  // =========================================================
  // Excel Import
  // =========================================================

  Future<void> _importExcel() async {
    setState(() {
      _isExcelWorking =
          true;
    });

    try {
      final result =
          await service.importExcel(
        widget.projectId,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Excel 업로드 완료\n'
        '신규 ${result['inserted']}개 · '
        '수정 ${result['updated']}개 · '
        '변경없음 ${result['unchanged'] ?? 0}개 · '
        '비활성 ${result['deactivated']}개'
        '${(result['duplicated'] ?? 0) > 0 ? '\n중복 DWG_NAME+Point ${result['duplicated']}개 (순번 붙여 저장)' : ''}',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Excel 업로드 실패\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExcelWorking =
              false;
        });
      }
    }
  }

  // =========================================================
  // Welding Table
  // =========================================================

  Widget _buildWeldingTable(
    List<Map<String, dynamic>> logs,
  ) {
    // 컬럼이 27개라 글자/간격을 작게 해서 한 화면에 최대한 보이게 한다.
    return DataTable(
      headingRowHeight: 34,

      dataRowMinHeight: 28,

      dataRowMaxHeight: 28,

      columnSpacing: 12,

      horizontalMargin: 10,

      headingTextStyle:
          const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),

      dataTextStyle:
          const TextStyle(
        fontSize: 11,
        color: Colors.black87,
      ),

      columns: [
        for (final column in _weldingLogColumns)
          DataColumn(
            label: Text(column.label),
            numeric: column.numeric,
          ),
      ],

      rows: logs.map(
        (log) {
          final completed =
              service.isPointCompleted(
            log,
          );

          return DataRow(
            cells: [
              for (final column in _weldingLogColumns)
                DataCell(
                  column.field == 'fieldDate'
                      ? Row(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Text(
                              _cellText(
                                log,
                                column,
                              ),
                            ),
                            if (completed)
                              const Padding(
                                padding:
                                    EdgeInsets.only(
                                  left: 4,
                                ),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 13,
                                  color: Colors.green,
                                ),
                              ),
                          ],
                        )
                      : Text(
                          _cellText(
                            log,
                            column,
                          ),
                        ),
                ),
            ],
          );
        },
      ).toList(),
    );
  }

  // =========================================================
  // Welding Log 컬럼 (WeldingLog Total 형식 + 작업 진행)
  //
  // label = Excel Header 이름 그대로
  // field = Firestore 필드
  // =========================================================

  static const List<_LogColumn> _weldingLogColumns = [
    _LogColumn('NO', 'no'),
    _LogColumn('DWG_NAME', 'isoNo'),
    _LogColumn('Floor', 'floor'),
    _LogColumn('CODE', 'code'),
    _LogColumn('COMMODITY', 'commodity'),
    _LogColumn('JOB_NO', 'jobNo'),
    _LogColumn('DESIGN_PRESS', 'designPress'),
    _LogColumn('DESIGN_TEMP', 'designTemp'),
    _LogColumn('OPER_PRESS', 'operPress'),
    _LogColumn('OPER_TEMP', 'operTemp'),
    _LogColumn('P&ID', 'pAndId'),
    _LogColumn('REF. PLAN DWG.', 'refPlanDwg'),
    _LogColumn('ISO NO', 'lineIsoNo'),
    _LogColumn('SHEETNo.1', 'sheetNo'),
    _LogColumn('SHEETNo.2', 'sheetNo2'),
    _LogColumn('PointNo.', 'pointNo'),
    _LogColumn('OriginalD/I', 'size', numeric: true),
    _LogColumn('D/I', 'originalDI', numeric: true, isDI: true),
    _LogColumn('Class', 'class'),
    _LogColumn('Metal/Non-Metal', 'material'),
    _LogColumn('System1', 'system1'),
    _LogColumn('System2', 'system2'),
    _LogColumn('WELDER', 'welderNo', dashIfEmpty: true),
    _LogColumn('SHOP DATE', 'shopDate', dashIfEmpty: true),
    _LogColumn('SHOP D/I', 'shopDI', numeric: true, isDI: true),
    _LogColumn('FIELD DATE', 'fieldDate', dashIfEmpty: true),
    _LogColumn('FIELD D/I', 'fieldDI', numeric: true, isDI: true),
  ];

  String _cellText(
    Map<String, dynamic> log,
    _LogColumn column,
  ) {
    final value = log[column.field];

    if (column.isDI) {
      return _formatDI(value);
    }

    final text = value?.toString() ?? '';

    if (text.trim().isEmpty &&
        column.dashIfEmpty) {
      return '-';
    }

    return text;
  }

  // =========================================================
  // 공사일보
  // =========================================================

  Widget _buildDailyReport() {
    final reports =
        service.getReportsByDate(
      _selectedDate,
    );

    if (reports.isEmpty) {
      return Column(
        children: [
          _buildDateHeader(),
          const Expanded(
            child:
                Center(
              child:
                  Text(
                '해당 날짜의 공사일보가 없습니다.',
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        _buildDateHeader(),

        Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 20,
          ),
          child:
              Text(
            '${_formatDate(_selectedDate)} 작업 내역',
            style:
                const TextStyle(
              fontSize: 20,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(
          height: 10,
        ),

        Expanded(
          child:
              ListView(
            padding:
                const EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20,
            ),
            children:
                reports.map(
              _buildReportCard,
            ).toList(),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // 날짜 Header
  // =========================================================

  Widget _buildDateHeader() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        20,
        20,
        20,
        10,
      ),
      child:
          Row(
        children: [
          const Expanded(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '공사일보',
                  style:
                      TextStyle(
                    fontSize: 26,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                SizedBox(
                  height: 5,
                ),
                Text(
                  '용접 작업 내역',
                ),
              ],
            ),
          ),

          OutlinedButton.icon(
            onPressed:
                _selectDate,
            icon:
                const Icon(
              Icons.calendar_month,
            ),
            label:
                Text(
              _formatDate(
                _selectedDate,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // 공사일보 카드
  // =========================================================

  Widget _buildReportCard(
    Map<String, dynamic> report,
  ) {
    final welderNo =
        report['welderNo']
                ?.toString() ??
            '';

    final welderName =
        report['welderName']
                ?.toString() ??
            '';

    final isoNo =
        report['isoNo']
                ?.toString() ??
            '';

    final pointCount =
        report['pointCount'] ??
            0;

    final di =
        _toDouble(
      report['di'],
    );

    final comment =
        report['comment']
                ?.toString() ??
            '';

    final List<dynamic>
        pointNos =
        report['pointNos'] ??
            [];

    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      child:
          Padding(
        padding:
            const EdgeInsets.all(
          18,
        ),
        child:
            Column(
          crossAxisAlignment:
              CrossAxisAlignment
                  .start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  child:
                      Icon(
                    Icons.person,
                  ),
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child:
                      Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        '$welderNo ($welderName)',
                        style:
                            const TextStyle(
                          fontSize:
                              17,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        isoNo,
                        style:
                            TextStyle(
                          fontSize:
                              13,
                          color:
                              Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        Colors.green.shade50,
                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                  ),
                  child:
                      Text(
                    '등록 완료',
                    style:
                        TextStyle(
                      fontSize:
                          12,
                      fontWeight:
                          FontWeight.bold,
                      color:
                          Colors.green.shade700,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 15,
            ),

            Row(
              children: [
                Expanded(
                  child:
                      _InfoBox(
                    title:
                        '작업 Point',
                    value:
                        '$pointCount Point',
                  ),
                ),

                const SizedBox(
                  width: 10,
                ),

                Expanded(
                  child:
                      _InfoBox(
                    title:
                        'D/I',
                    value:
                        '${di.toStringAsFixed(2)} D/I',
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 12,
            ),

            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  pointNos.map(
                (point) {
                  return Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal:
                          9,
                      vertical:
                          5,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          Colors.grey.shade100,
                      borderRadius:
                          BorderRadius
                              .circular(
                        6,
                      ),
                    ),
                    child:
                        Text(
                      'P$point',
                      style:
                          const TextStyle(
                        fontSize:
                            12,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  );
                },
              ).toList(),
            ),

            if (comment
                .trim()
                .isNotEmpty) ...[
              const SizedBox(
                height: 12,
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
                  color:
                      Colors.grey.shade100,
                  borderRadius:
                      BorderRadius.circular(
                    8,
                  ),
                ),
                child:
                    Text(
                  'Comment  $comment',
                  style:
                      const TextStyle(
                    fontSize:
                        13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // =========================================================
  // 날짜 선택
  // =========================================================

  Future<void> _selectDate() async {
    final date =
        await showDatePicker(
      context:
          context,
      initialDate:
          _selectedDate,
      firstDate:
          DateTime(2020),
      lastDate:
          DateTime(2035),
      locale:
          const Locale(
        'ko',
        'KR',
      ),
    );

    if (date == null) {
      return;
    }

    setState(() {
      _selectedDate =
          date;
    });
  }

  String _formatDate(
    DateTime date,
  ) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  double _toDouble(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ??
              '',
        ) ??
        0.0;
  }

  String _formatDI(
    dynamic value,
  ) {
    return _toDouble(
      value,
    ).toStringAsFixed(
      2,
    );
  }

  void _showMessage(
    String message,
  ) {
    ScaffoldMessenger.of(
      context,
    ).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content:
            Text(message),
      ),
    );
  }
}

// ============================================================
// Info Box
// ============================================================

class _InfoBox
    extends StatelessWidget {
  final String title;
  final String value;

  const _InfoBox({
    required this.title,
    required this.value,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(
        12,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.grey.shade100,
        borderRadius:
            BorderRadius.circular(
          8,
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                TextStyle(
              fontSize:
                  11,
              color:
                  Colors.grey.shade600,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            value,
            style:
                const TextStyle(
              fontSize:
                  15,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// Welding Log 컬럼 정의
// =============================================================

class _LogColumn {
  final String label;
  final String field;
  final bool numeric;
  final bool isDI;
  final bool dashIfEmpty;

  const _LogColumn(
    this.label,
    this.field, {
    this.numeric = false,
    this.isDI = false,
    this.dashIfEmpty = false,
  });
}
