import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../services/iso_upload_service.dart';

// =============================================================
// ISO 업로드 창
//
// 1) PDF / ZIP 파일을 끌어다 놓는다 (여러 번 놓아도 누적)
// 2) 파일 목록과 검사 결과 확인
//    - 파일명 끝 -REV1 형식이 아니면 제외
//    - ISO 목록에 없는 도면은 "강제 추가" 경고
// 3) [업로드] 눌러야 올라간다
//
// 반환: 업로드가 1건 이상 성공했으면 true
// =============================================================

Future<bool> showIsoUploadDialog({
  required BuildContext context,
  required String projectId,
  required Set<String> knownIsoNames,
  Set<String> existingRevisions = const {},
  String? userName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _IsoUploadDialog(
      projectId: projectId,
      knownIsoNames: knownIsoNames,
      existingRevisions: existingRevisions,
      userName: userName,
    ),
  );

  return result == true;
}

class _IsoUploadDialog extends StatefulWidget {
  final String projectId;
  final Set<String> knownIsoNames;
  final Set<String> existingRevisions;
  final String? userName;

  const _IsoUploadDialog({
    required this.projectId,
    required this.knownIsoNames,
    required this.existingRevisions,
    this.userName,
  });

  @override
  State<_IsoUploadDialog> createState() => _IsoUploadDialogState();
}

class _IsoUploadDialogState extends State<_IsoUploadDialog> {
  final IsoUploadService _service = IsoUploadService.instance;

  // 놓은 파일 원본 (ZIP 풀기 전)
  final List<({String name, Uint8List bytes})> _rawFiles = [];

  List<IsoUploadCandidate> _candidates = [];

  bool _dragging = false;
  bool _checking = false;
  bool _uploading = false;
  String _progress = '';
  IsoUploadResult? _result;

  int get _okCount => _candidates
      .where((c) => c.status == IsoCandidateStatus.ok)
      .length;

  int get _forceCount => _candidates
      .where((c) => c.status == IsoCandidateStatus.notInList)
      .length;

  int get _excludedCount =>
      _candidates.where((c) => !c.canUpload).length;

  int get _uploadCount => _okCount + _forceCount;

  // =========================================================
  // 파일 받기
  // =========================================================

  Future<void> _onDropped(DropDoneDetails detail) async {
    setState(() {
      _dragging = false;
    });

    final files = <({String name, Uint8List bytes})>[];

    for (final item in detail.files) {
      final lower = item.name.toLowerCase();

      // 폴더나 다른 파일은 무시
      if (!lower.endsWith('.pdf') && !lower.endsWith('.zip')) {
        continue;
      }

      try {
        files.add((
          name: item.name,
          bytes: await item.readAsBytes(),
        ));
      } catch (e) {
        debugPrint('드롭 파일 읽기 실패 ${item.name}: $e');
      }
    }

    await _addFiles(files);
  }

  Future<void> _pickFiles() async {
    final files = await _service.pickRawFiles();
    await _addFiles(files);
  }

  Future<void> _addFiles(
    List<({String name, Uint8List bytes})> files,
  ) async {
    if (files.isEmpty) {
      return;
    }

    setState(() {
      _checking = true;
      _rawFiles.addAll(files);
    });

    final candidates = await _service.checkFiles(
      projectId: widget.projectId,
      files: _service.expandZips(_rawFiles),
      knownIsoNames: widget.knownIsoNames,
      existingRevisions: widget.existingRevisions,
    );

    if (!mounted) return;

    setState(() {
      _candidates = candidates;
      _checking = false;
    });
  }

  void _clear() {
    setState(() {
      _rawFiles.clear();
      _candidates = [];
    });
  }

  // =========================================================
  // 업로드
  // =========================================================

  Future<void> _upload() async {
    if (_uploadCount == 0 || _uploading) {
      return;
    }

    // 목록에 없는 도면이 있으면 한 번 더 확인
    if (_forceCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange.shade700,
            size: 36,
          ),
          title: const Text('목록에 없는 도면 포함'),
          content: Text(
            'ISO 목록(Welding Log 도면)에 없는 도면 $_forceCount개가 있습니다.\n'
            '그대로 진행하면 목록에 강제로 추가됩니다.\n\n'
            '도면 번호가 맞는지 확인하셨나요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('다시 확인'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('강제 추가하고 업로드'),
            ),
          ],
        ),
      );

      if (ok != true) {
        return;
      }
    }

    setState(() {
      _uploading = true;
      _progress = '업로드 준비 중...';
    });

    final result = await _service.uploadCandidates(
      projectId: widget.projectId,
      candidates: _candidates,
      userName: widget.userName,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _progress = '업로드 중 $done / $total';
        });
      },
    );

    if (!mounted) return;

    setState(() {
      _uploading = false;
      _result = result;
    });
  }

  // =========================================================
  // 화면
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return AlertDialog(
      title: const Text('ISO 업로드'),
      content: SizedBox(
        width: 640,
        child: result != null
            ? _buildResult(result)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDropZone(),
                  const SizedBox(height: 12),
                  if (_checking)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_candidates.isNotEmpty) ...[
                    _buildCounts(),
                    const SizedBox(height: 8),
                    _buildList(),
                  ],
                  if (_uploading) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(minHeight: 3),
                    const SizedBox(height: 6),
                    Text(_progress),
                  ],
                ],
              ),
      ),
      actions: result != null
          ? [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  result.uploaded.isNotEmpty ||
                      result.replaced.isNotEmpty,
                ),
                child: const Text('닫기'),
              ),
            ]
          : [
              if (_candidates.isNotEmpty && !_uploading)
                TextButton(
                  onPressed: _clear,
                  child: const Text('목록 비우기'),
                ),
              TextButton(
                onPressed: _uploading
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton.icon(
                onPressed: _uploadCount == 0 || _uploading || _checking
                    ? null
                    : _upload,
                style: _forceCount > 0
                    ? FilledButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                      )
                    : null,
                icon: const Icon(Icons.cloud_upload),
                label: Text('업로드 ($_uploadCount개)'),
              ),
            ],
    );
  }

  Widget _buildDropZone() {
    final color = _dragging
        ? Theme.of(context).colorScheme.primary
        : Colors.grey.shade400;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDropped,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: _dragging
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
              : Colors.grey.shade50,
          border: Border.all(
            color: color,
            width: _dragging ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.file_download_outlined,
              size: 36,
              color: color,
            ),
            const SizedBox(height: 6),
            const Text(
              'PDF 또는 ZIP 파일을 여기에 끌어다 놓으세요',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              '파일명: 도면번호-REV0.pdf, -REV1.pdf ... · 같은 리비전 중복 불가 · 1MB 이하',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            TextButton(
              onPressed: _uploading ? null : _pickFiles,
              child: const Text(
                '또는 파일 선택',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounts() {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(
          '업로드 $_okCount개',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.green.shade700,
          ),
        ),
        if (_forceCount > 0)
          Text(
            '⚠ 목록에 없음(강제 추가) $_forceCount개',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade800,
            ),
          ),
        if (_excludedCount > 0)
          Text(
            '제외 $_excludedCount개',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red.shade400,
            ),
          ),
      ],
    );
  }

  Widget _buildList() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: _candidates.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            color: Colors.grey.shade200,
          ),
          itemBuilder: (context, index) {
            final c = _candidates[index];

            final Color color;
            final IconData icon;

            switch (c.status) {
              case IsoCandidateStatus.ok:
                color = Colors.green.shade700;
                icon = c.replaces ? Icons.sync : Icons.check_circle;
                break;
              case IsoCandidateStatus.notInList:
                color = Colors.orange.shade800;
                icon = Icons.warning_amber_rounded;
                break;
              default:
                color = Colors.red.shade400;
                icon = Icons.block;
            }

            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(icon, color: color, size: 20),
              title: Text(
                c.fileName,
                style: TextStyle(
                  fontSize: 13,
                  decoration: c.canUpload
                      ? null
                      : TextDecoration.lineThrough,
                ),
              ),
              subtitle: Text(
                c.canUpload
                    ? '${c.isoName} · ${c.revision} · ${c.statusText}'
                    : c.statusText,
                style: TextStyle(fontSize: 12, color: color),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildResult(IsoUploadResult result) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '신규 ${result.uploaded.length}개 · '
          '교체 ${result.replaced.length}개 · '
          '실패 ${result.failed.length}개',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
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
    );
  }
}

// =============================================================
// ISO 업로드 / 삭제 히스토리
//
// - ISO 검색: 도면 이름 / 파일명 일부 (여러 단어 = 모두 포함)
// - 날짜: 하루 또는 기간 선택 (그 기간만 서버에서 읽음)
// =============================================================

Future<void> showIsoHistoryDialog({
  required BuildContext context,
  required String projectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _IsoHistoryDialog(projectId: projectId),
  );
}

class _IsoHistoryDialog extends StatefulWidget {
  final String projectId;

  const _IsoHistoryDialog({required this.projectId});

  @override
  State<_IsoHistoryDialog> createState() => _IsoHistoryDialogState();
}

class _IsoHistoryDialogState extends State<_IsoHistoryDialog> {
  final TextEditingController _searchController =
      TextEditingController();

  DateTimeRange? _range;

  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await IsoUploadService.instance.loadHistory(
        widget.projectId,
        from: _range?.start,
        to: _range?.end,
      );

      if (!mounted) return;

      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
      helpText: '날짜 또는 기간 선택 (하루만 보려면 같은 날 두 번)',
    );

    if (picked == null) return;

    setState(() {
      _range = picked;
    });

    _load();
  }

  void _clearRange() {
    setState(() {
      _range = null;
    });

    _load();
  }

  List<Map<String, dynamic>> get _filtered {
    final keywords = _searchController.text
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((k) => k.isNotEmpty)
        .toList();

    if (keywords.isEmpty) {
      return _items;
    }

    return _items.where((item) {
      final text = '${item['fileName'] ?? ''} ${item['isoName'] ?? ''}'
          .toLowerCase();
      return keywords.every(text.contains);
    }).toList();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final range = _range;

    final rangeText = range == null
        ? '전체 기간 (최근 300건)'
        : range.start == range.end
            ? _fmtDate(range.start)
            : '${_fmtDate(range.start)} ~ ${_fmtDate(range.end)}';

    return AlertDialog(
      title: const Text('ISO 업로드 / 삭제 기록'),
      content: SizedBox(
        width: 760,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'ISO 검색 (예: 9073 / 9073 01)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            ),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(rangeText),
                ),
                if (range != null)
                  IconButton(
                    tooltip: '날짜 조건 지우기',
                    icon: const Icon(Icons.close),
                    onPressed: _clearRange,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${items.length}건',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            if (_loading)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _error != null
                  ? Text(
                      '불러오기 실패: $_error\n'
                      '(처음이면 Firestore 색인 생성 링크가 콘솔에 표시됩니다)',
                    )
                  : items.isEmpty && !_loading
                      ? const Center(child: Text('기록이 없습니다.'))
                      : SelectionArea(
                          child: ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              color: Colors.grey.shade200,
                            ),
                            itemBuilder: (context, index) =>
                                _buildItem(items[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final action = item['action']?.toString() ?? '';

    final (label, color) = switch (action) {
      'upload' => ('업로드', Colors.green.shade700),
      'replace' => ('교체', Colors.blue.shade700),
      'delete' => ('삭제', Colors.red.shade400),
      _ => (action, Colors.grey.shade700),
    };

    final at = item['at'];
    final atText = at is Timestamp ? _formatDateTime(at.toDate()) : '';

    return ListTile(
      dense: true,
      leading: Container(
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
      title: Text(
        item['fileName']?.toString() ?? '',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '$atText · ${item['by'] ?? ''}'
        '${item['notInList'] == true ? ' · 목록에 없던 도면(강제 추가)' : ''}',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

String _formatDateTime(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}';
}
