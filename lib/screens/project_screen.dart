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

class _ProjectScreenState extends State<ProjectScreen>
    with SingleTickerProviderStateMixin {
  // =========================================================
  // ISO
  // =========================================================

  List<Map<String, dynamic>> isoFiles = [];

  // =========================================================
  // PKG
  // =========================================================

  List<Map<String, dynamic>> pkgFiles = [];

  // =========================================================
  // PLAN
  // =========================================================

  List<Map<String, dynamic>> planFiles = [];

  // =========================================================
  // 공통
  // =========================================================

  bool isLoading = true;

  String searchQuery = '';

  final TextEditingController searchController =
      TextEditingController();

  late TabController tabController;

  @override
  void initState() {
    super.initState();

    tabController = TabController(
      length: 3,
      vsync: this,
    );

    loadMetadata();
  }

  @override
  void dispose() {
    searchController.dispose();
    tabController.dispose();

    super.dispose();
  }

  // =========================================================
  // Metadata 불러오기
  // =========================================================

  Future<void> loadMetadata() async {
    try {
      // -----------------------------------------------------
      // ISO
      // -----------------------------------------------------

      final isoJsonString = await rootBundle.loadString(
        'assets/iso_metadata.json',
      );

      final List<dynamic> isoData =
          json.decode(isoJsonString);

      final loadedIsoFiles = isoData
          .map(
            (item) => Map<String, dynamic>.from(item),
          )
          .toList();

      // -----------------------------------------------------
      // PKG
      // -----------------------------------------------------

      final pkgJsonString = await rootBundle.loadString(
        'assets/pkg_metadata.json',
      );

      final List<dynamic> pkgData =
          json.decode(pkgJsonString);

      final loadedPkgFiles = pkgData
          .map(
            (item) => Map<String, dynamic>.from(item),
          )
          .toList();

      // -----------------------------------------------------
      // PLAN
      // -----------------------------------------------------

      final planJsonString = await rootBundle.loadString(
        'assets/plan_metadata.json',
      );

      final List<dynamic> planData =
          json.decode(planJsonString);

      final loadedPlanFiles = planData
          .map(
            (item) => Map<String, dynamic>.from(item),
          )
          .toList();

      // -----------------------------------------------------
      // 정렬
      // -----------------------------------------------------

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

      setState(() {
        isLoading = false;
      });
    }
  }

  // =========================================================
  // ISO 그룹화
  // =========================================================

  Map<String, List<Map<String, dynamic>>> groupByIso() {
    final Map<String, List<Map<String, dynamic>>> grouped =
        {};

    for (final iso in isoFiles) {
      final isoName =
          iso['isoName']?.toString() ?? '';

      grouped.putIfAbsent(
        isoName,
        () => [],
      );

      grouped[isoName]!.add(iso);
    }

    return grouped;
  }

  // =========================================================
  // 검색 키워드 생성
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

  // =========================================================
  // ISO 검색
  // =========================================================

  Map<String, List<Map<String, dynamic>>> getFilteredIsos() {
    final grouped = groupByIso();

    final keywords = getSearchKeywords();

    if (keywords.isEmpty) {
      return grouped;
    }

    final Map<String, List<Map<String, dynamic>>>
        filtered = {};

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

  // =========================================================
  // PKG 검색
  // =========================================================

  List<Map<String, dynamic>> getFilteredPkgFiles() {
    final keywords = getSearchKeywords();

    if (keywords.isEmpty) {
      return pkgFiles;
    }

    return pkgFiles.where((file) {
      final fileName =
          file['fileName']
                  ?.toString()
                  .toLowerCase() ??
              '';

      return keywords.every(
        (keyword) => fileName.contains(keyword),
      );
    }).toList();
  }

  // =========================================================
  // PLAN 검색
  // =========================================================

  List<Map<String, dynamic>> getFilteredPlanFiles() {
    final keywords = getSearchKeywords();

    if (keywords.isEmpty) {
      return planFiles;
    }

    return planFiles.where((file) {
      final fileName =
          file['fileName']
                  ?.toString()
                  .toLowerCase() ??
              '';

      return keywords.every(
        (keyword) => fileName.contains(keyword),
      );
    }).toList();
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
            borderRadius: BorderRadius.circular(12),
          ),

          filled: true,
        ),
      ),
    );
  }

  // =========================================================
  // ISO 화면
  // =========================================================

  Widget buildIsoTab() {
    final filteredIsos =
        getFilteredIsos();

    if (filteredIsos.isEmpty) {
      return Center(
        child: Text(
          searchQuery.trim().isEmpty
              ? '등록된 ISO가 없습니다.'
              : '검색 결과가 없습니다.',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),

      children: filteredIsos.entries.map(
        (entry) {
          final isoName = entry.key;
          final revisions = entry.value;

          return Card(
            margin: const EdgeInsets.only(
              bottom: 15,
            ),

            child: Padding(
              padding: const EdgeInsets.all(16),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [
                  Text(
                    isoName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 12,
                  ),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,

                    children: revisions.map(
                      (iso) {
                        final revision =
                            iso['revision']
                                    ?.toString() ??
                                'Rev.?';

                        final modifiedDate =
                            iso['modifiedDate']
                                    ?.toString() ??
                                '';

                        final pdfPath =
                            iso['path']
                                    ?.toString() ??
                                '';

                        return OutlinedButton(
                          onPressed: pdfPath.isEmpty
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) =>
                                              PDFViewerScreen(
                                        pdfPath:
                                            pdfPath,
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
                                style:
                                    const TextStyle(
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
                      },
                    ).toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ).toList(),
    );
  }

  // =========================================================
  // PKG 화면
  // =========================================================

  Widget buildPkgTab() {
    final files =
        getFilteredPkgFiles();

    if (files.isEmpty) {
      return Center(
        child: Text(
          searchQuery.trim().isEmpty
              ? '등록된 PKG가 없습니다.'
              : '검색 결과가 없습니다.',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),

      itemCount: files.length,

      itemBuilder: (context, index) {
        final file = files[index];

        final fileName =
            file['fileName']
                    ?.toString() ??
                '';

        final modifiedDate =
            file['modifiedDate']
                    ?.toString() ??
                '';

        final pdfPath =
            file['path']
                    ?.toString() ??
                '';

        return Card(
          margin: const EdgeInsets.only(
            bottom: 10,
          ),

          child: ListTile(
            leading: const Icon(
              Icons.picture_as_pdf,
            ),

            title: Text(
              fileName,
              style: const TextStyle(
                fontWeight:
                    FontWeight.bold,
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
    );
  }

  // =========================================================
  // 플랜도 화면
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
      padding: const EdgeInsets.all(20),

      itemCount: files.length,

      itemBuilder: (context, index) {
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
          margin: const EdgeInsets.only(
            bottom: 10,
          ),

          child: ListTile(
            leading: const Icon(
              Icons.architecture,
            ),

            title: Text(
              fileName,
              style: const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            subtitle: Text(
              '$extension · 최종 수정: $modifiedDate',
            ),

            onTap: () {
              // CAD 뷰어는 추후 구현
            },
          ),
        );
      },
    );
  }

  // =========================================================
  // 전체 화면
  // =========================================================

  @override
  Widget build(BuildContext context) {
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
                // 검색창
                buildSearchBar(),

                // 탭
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

                // 탭 내용
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
