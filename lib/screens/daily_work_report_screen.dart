import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// =============================================================
// 물량 집계 (일간 / 주간 / 월간)
//
// ISO 탭에서 입력한 공사일보(weldingDailyReports)를
// 기간별로 모아 총 수량을 보여주고, 달력에 날짜별 수량을 표시한다.
//
// - 현장 admin 이상만 진입 (HomeScreen에서 메뉴 노출 제어)
// - 읽기: 보고 있는 달(+주간이 걸친 달)만 한 번에 읽고,
//   그 범위 안에서 이동하면 다시 읽지 않는다.
//
// weldingDailyReports 문서:
//   projectId, isoNo, welderUid, welderNo, welderName,
//   pointNos[], pointCount, di, date('yyyy-MM-dd'), comment
// =============================================================

enum _PeriodMode { day, week, month }

class DailyWorkReportScreen extends StatefulWidget {
  final String projectId;
  final String projectName;

  const DailyWorkReportScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  State<DailyWorkReportScreen> createState() =>
      _DailyWorkReportScreenState();
}

class _DailyWorkReportScreenState
    extends State<DailyWorkReportScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  _PeriodMode _mode = _PeriodMode.day;

  DateTime _selectedDate = _dateOnly(DateTime.now());

  // 달력에 보이는 달 (달력 ◀ ▶로 따로 넘길 수 있음)
  DateTime _calendarMonth = _monthStart(DateTime.now());

  // 읽어둔 달 ('yyyy-MM')과 달별 데이터
  final Set<String> _loadedMonths = {};
  final Map<String, List<Map<String, dynamic>>> _reportsByMonth = {};

  List<Map<String, dynamic>> _reports = [];

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ensureLoaded();
  }

  // =========================================================
  // 날짜 유틸
  // =========================================================

  static DateTime _dateOnly(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static DateTime get _today => _dateOnly(DateTime.now());

  static String _fmt(DateTime d) =>
      '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _fmtShort(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static const List<String> _weekdays = [
    '월', '화', '수', '목', '금', '토', '일',
  ];

  String _fmtWithDay(DateTime d) =>
      '${_fmt(d)} (${_weekdays[d.weekday - 1]})';

  static DateTime _monthStart(DateTime d) =>
      DateTime(d.year, d.month, 1);

  static DateTime _monthEnd(DateTime d) =>
      DateTime(d.year, d.month + 1, 0);

  // 주: 월요일 ~ 일요일
  static DateTime _weekStart(DateTime d) =>
      _dateOnly(d).subtract(Duration(days: d.weekday - 1));

  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  DateTime get _periodStart {
    switch (_mode) {
      case _PeriodMode.day:
        return _selectedDate;
      case _PeriodMode.week:
        return _weekStart(_selectedDate);
      case _PeriodMode.month:
        return _monthStart(_selectedDate);
    }
  }

  DateTime get _periodEnd {
    switch (_mode) {
      case _PeriodMode.day:
        return _selectedDate;
      case _PeriodMode.week:
        return _addDays(_weekStart(_selectedDate), 6);
      case _PeriodMode.month:
        return _monthEnd(_selectedDate);
    }
  }

  String get _periodLabel {
    switch (_mode) {
      case _PeriodMode.day:
        return _fmtWithDay(_selectedDate);
      case _PeriodMode.week:
        final start = _periodStart;
        final end = _periodEnd;
        // 주차: 그 주 목요일이 속한 달 기준
        final thursday = _addDays(start, 3);
        final weekOfMonth =
            ((thursday.day - 1) ~/ 7) + 1;
        return '${thursday.month}월 $weekOfMonth주차 · '
            '${_fmtShort(start)}(월) ~ ${_fmtShort(end)}(일)';
      case _PeriodMode.month:
        return '${_selectedDate.year}년 ${_selectedDate.month}월';
    }
  }

  bool get _canGoNext {
    final today = _today;

    switch (_mode) {
      case _PeriodMode.day:
        return _selectedDate.isBefore(today);
      case _PeriodMode.week:
        return _periodEnd.isBefore(today);
      case _PeriodMode.month:
        return _periodEnd.isBefore(today);
    }
  }

  // =========================================================
  // 데이터
  //
  // 달력에 표시하는 달 + 선택 기간을 모두 덮는 범위를 읽는다.
  // =========================================================

  // 달 단위로 읽어서 모아둔다. 이미 읽은 달은 다시 읽지 않는다.
  Future<void> _ensureLoaded({
    bool force = false,
  }) async {
    final months = <DateTime>{
      _monthStart(_periodStart),
      _monthStart(_periodEnd),
      _calendarMonth,
    };

    if (force) {
      _loadedMonths.clear();
      _reportsByMonth.clear();
    }

    final missing = months
        .where((m) => !_loadedMonths.contains(_monthKey(m)))
        .toList();

    if (missing.isEmpty) {
      if (force) setState(_rebuildReports);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      for (final month in missing) {
        final snapshot = await _firestore
            .collection('weldingDailyReports')
            .where(
              'projectId',
              isEqualTo: widget.projectId,
            )
            .where(
              'date',
              isGreaterThanOrEqualTo: _fmt(month),
            )
            .where(
              'date',
              isLessThanOrEqualTo: _fmt(_monthEnd(month)),
            )
            .get();

        _reportsByMonth[_monthKey(month)] = snapshot.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList();
        _loadedMonths.add(_monthKey(month));
      }

      if (!mounted) return;

      setState(() {
        _rebuildReports();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('물량 집계 불러오기 실패: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  void _rebuildReports() {
    _reports = _reportsByMonth.values
        .expand((list) => list)
        .toList();
  }

  void _setSelected(DateTime date, {_PeriodMode? mode}) {
    final today = _today;

    setState(() {
      _selectedDate = date.isAfter(today) ? today : _dateOnly(date);
      _calendarMonth = _monthStart(_selectedDate);
      if (mode != null) _mode = mode;
    });

    _ensureLoaded();
  }

  void _move(int step) {
    if (step > 0 && !_canGoNext) {
      return;
    }

    switch (_mode) {
      case _PeriodMode.day:
        _setSelected(_addDays(_selectedDate, step));
        break;
      case _PeriodMode.week:
        _setSelected(_addDays(_selectedDate, step * 7));
        break;
      case _PeriodMode.month:
        final target = DateTime(
          _selectedDate.year,
          _selectedDate.month + step,
          1,
        );
        // 이번 달로 오면 오늘, 지난 달이면 그 달 1일 기준
        _setSelected(
          step > 0 && _monthEnd(target).isAfter(_today)
              ? _today
              : target,
        );
        break;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: _today,
    );

    if (picked == null) return;

    _setSelected(picked);
  }

  // =========================================================
  // 집계
  // =========================================================

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  int _pointCount(Map<String, dynamic> r) {
    final count = r['pointCount'];
    if (count is num) return count.toInt();

    final points = r['pointNos'];
    return points is List ? points.length : 0;
  }

  String _fmtDI(double v) {
    return v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2);
  }

  List<Map<String, dynamic>> _reportsBetween(
    DateTime start,
    DateTime end,
  ) {
    final from = _fmt(start);
    final to = _fmt(end);

    return _reports.where((r) {
      final d = r['date']?.toString() ?? '';
      return d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
    }).toList();
  }

  // 날짜별 {points, di}
  Map<String, ({int points, double di})> get _byDate {
    final Map<String, ({int points, double di})> map = {};

    for (final r in _reports) {
      final key = r['date']?.toString() ?? '';
      final old = map[key] ?? (points: 0, di: 0.0);

      map[key] = (
        points: old.points + _pointCount(r),
        di: old.di + _toDouble(r['di']),
      );
    }

    return map;
  }

  List<_Group> _groupBy(
    List<Map<String, dynamic>> reports,
    String Function(Map<String, dynamic>) keyOf,
    String Function(Map<String, dynamic>) subOf,
  ) {
    final Map<String, _Group> map = {};

    for (final r in reports) {
      final key = keyOf(r);
      final group = map.putIfAbsent(key, () => _Group(key));

      group.points += _pointCount(r);
      group.di += _toDouble(r['di']);

      final sub = subOf(r);
      if (sub.isNotEmpty) group.subs.add(sub);
    }

    return map.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  // =========================================================
  // 화면
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final periodReports =
        _reportsBetween(_periodStart, _periodEnd);

    final totalPoints = periodReports.fold<int>(
      0,
      (sum, r) => sum + _pointCount(r),
    );

    final totalDI = periodReports.fold<double>(
      0,
      (sum, r) => sum + _toDouble(r['di']),
    );

    final workDays = periodReports
        .map((r) => r['date']?.toString() ?? '')
        .toSet()
        .length;

    final byWelder = _groupBy(
      periodReports,
      (r) {
        final no = r['welderNo']?.toString() ?? '';
        final name = r['welderName']?.toString() ?? '';
        return name.isEmpty ? no : '$no  $name';
      },
      (r) => r['isoNo']?.toString() ?? '',
    );

    // 작업한 ISO 수 (요약 카드용)
    final isoCount = periodReports
        .map((r) => r['isoNo']?.toString() ?? '')
        .where((iso) => iso.isNotEmpty)
        .toSet()
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('물량 집계 · ${widget.projectName}'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: () => _ensureLoaded(force: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // ---------------------------------------------------
          // 일간 / 주간 / 월간
          // ---------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<_PeriodMode>(
              segments: const [
                ButtonSegment(
                  value: _PeriodMode.day,
                  label: Text('일간'),
                  icon: Icon(Icons.today),
                ),
                ButtonSegment(
                  value: _PeriodMode.week,
                  label: Text('주간'),
                  icon: Icon(Icons.view_week),
                ),
                ButtonSegment(
                  value: _PeriodMode.month,
                  label: Text('월간'),
                  icon: Icon(Icons.calendar_month),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) {
                _setSelected(_selectedDate, mode: value.first);
              },
            ),
          ),

          // ---------------------------------------------------
          // 기간 이동
          // ---------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: '이전',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _move(-1),
                ),
                Flexible(
                  child: TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _periodLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '다음',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _canGoNext ? () => _move(1) : null,
                ),
                if (_selectedDate != _today)
                  TextButton(
                    onPressed: () => _setSelected(_today),
                    child: const Text('오늘'),
                  ),
              ],
            ),
          ),

          if (_isLoading)
            const LinearProgressIndicator(minHeight: 2),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '불러오기 실패: $_error\n'
                '(처음이면 Firestore 색인 생성 링크가 콘솔에 표시됩니다)',
                style: TextStyle(color: Colors.red.shade400),
              ),
            ),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1000;

                final main = ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _buildSummary(
                      totalPoints: totalPoints,
                      totalDI: totalDI,
                      isoCount: isoCount,
                      welderCount: byWelder.length,
                      workDays: workDays,
                    ),

                    const SizedBox(height: 16),

                    if (!wide) ...[
                      _buildCalendar(),
                      const SizedBox(height: 16),
                    ],

                    if (periodReports.isEmpty && !_isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            '이 기간에 입력된 작업이 없습니다.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    else ...[
                      if (_mode != _PeriodMode.day) ...[
                        _buildSectionTitle('일자별', workDays),
                        _buildDailyTable(),
                        const SizedBox(height: 20),
                      ],

                      _buildSectionTitle('용접사별', byWelder.length),
                      _buildGroupTable(
                        firstHeader: '용접사',
                        subHeader: 'Line No.',
                        groups: byWelder,
                      ),

                      if (_mode == _PeriodMode.day) ...[
                        const SizedBox(height: 20),
                        _buildSectionTitle(
                          '입력 내역',
                          periodReports.length,
                        ),
                        ...periodReports.map(_buildReportTile),
                      ],
                    ],
                  ],
                );

                if (!wide) {
                  return main;
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    SizedBox(
                      width: 380,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(0, 8, 16, 24),
                        children: [_buildCalendar()],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary({
    required int totalPoints,
    required double totalDI,
    required int isoCount,
    required int welderCount,
    required int workDays,
  }) {
    Widget tile(String label, String value, IconData icon) {
      return Expanded(
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile('용접 Point', '$totalPoints', Icons.adjust),
        tile('D/I 합계', _fmtDI(totalDI), Icons.straighten),
        tile('ISO', '$isoCount', Icons.description_outlined),
        tile('용접사', '$welderCount', Icons.engineering),
        if (_mode != _PeriodMode.day)
          tile('작업일', '$workDays일', Icons.event_available),
      ],
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        '$title ($count)',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  static const TextStyle _headStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
  );

  static const TextStyle _cellStyle = TextStyle(
    fontSize: 12,
    color: Colors.black87,
  );

  DataTable _compactTable({
    required List<DataColumn> columns,
    required List<DataRow> rows,
  }) {
    return DataTable(
      // 행 클릭(일자별 → 일간 이동)에 체크박스 표시 안 함
      showCheckboxColumn: false,
      headingRowHeight: 34,
      dataRowMinHeight: 30,
      dataRowMaxHeight: 30,
      columnSpacing: 20,
      horizontalMargin: 12,
      headingTextStyle: _headStyle,
      dataTextStyle: _cellStyle,
      columns: columns,
      rows: rows,
    );
  }

  DataRow _totalRow(int points, double di, int extraCells) {
    return DataRow(
      color: WidgetStatePropertyAll(Colors.grey.shade100),
      cells: [
        const DataCell(Text('합계', style: _headStyle)),
        DataCell(Text('$points', style: _headStyle)),
        DataCell(Text(_fmtDI(di), style: _headStyle)),
        for (int i = 0; i < extraCells; i++)
          const DataCell(Text('')),
      ],
    );
  }

  // 주간 / 월간: 날짜별 합계 (누르면 그날 일간으로)
  Widget _buildDailyTable() {
    final byDate = _byDate;
    final rows = <DataRow>[];

    int sumPoints = 0;
    double sumDI = 0;

    for (var d = _periodStart;
        !d.isAfter(_periodEnd);
        d = _addDays(d, 1)) {
      final value = byDate[_fmt(d)];

      if (value == null) {
        continue;
      }

      sumPoints += value.points;
      sumDI += value.di;

      final day = d;

      rows.add(
        DataRow(
          onSelectChanged: (_) =>
              _setSelected(day, mode: _PeriodMode.day),
          cells: [
            DataCell(Text(_fmtWithDay(day))),
            DataCell(Text('${value.points}')),
            DataCell(Text(_fmtDI(value.di))),
          ],
        ),
      );
    }

    rows.add(_totalRow(sumPoints, sumDI, 0));

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _compactTable(
          columns: const [
            DataColumn(label: Text('날짜')),
            DataColumn(label: Text('Point'), numeric: true),
            DataColumn(label: Text('D/I'), numeric: true),
          ],
          rows: rows,
        ),
      ),
    );
  }

  Widget _buildGroupTable({
    required String firstHeader,
    required String subHeader,
    required List<_Group> groups,
  }) {
    final totalPoints =
        groups.fold<int>(0, (s, g) => s + g.points);
    final totalDI =
        groups.fold<double>(0, (s, g) => s + g.di);

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _compactTable(
          columns: [
            DataColumn(label: Text(firstHeader)),
            const DataColumn(label: Text('Point'), numeric: true),
            const DataColumn(label: Text('D/I'), numeric: true),
            DataColumn(label: Text(subHeader)),
          ],
          rows: [
            ...groups.map(
              (g) => DataRow(
                cells: [
                  DataCell(Text(g.key.isEmpty ? '-' : g.key)),
                  DataCell(Text('${g.points}')),
                  DataCell(Text(_fmtDI(g.di))),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        (g.subs.toList()..sort()).join(', '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _totalRow(totalPoints, totalDI, 1),
          ],
        ),
      ),
    );
  }

  Widget _buildReportTile(Map<String, dynamic> r) {
    final points = r['pointNos'];
    final pointText =
        points is List ? points.join(', ') : '';
    final comment = r['comment']?.toString().trim() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(
          r['isoNo']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${r['welderNo'] ?? ''} ${r['welderName'] ?? ''}'
          ' · Point $pointText'
          '${comment.isEmpty ? '' : '\n$comment'}',
        ),
        trailing: Text(
          '${_pointCount(r)}P · ${_fmtDI(_toDouble(r['di']))}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _moveCalendar(int months) {
    final target = DateTime(
      _calendarMonth.year,
      _calendarMonth.month + months,
      1,
    );

    if (target.isAfter(_today)) {
      return;
    }

    setState(() {
      _calendarMonth = target;
    });

    _ensureLoaded();
  }

  // =========================================================
  // 달력 (선택한 날짜가 속한 달)
  //
  // 날짜마다 Point / D/I 표시, 선택 기간 강조.
  // 날짜를 누르면 그날 일간으로 이동.
  // =========================================================

  Widget _buildCalendar() {
    final byDate = _byDate;
    final monthStart = _calendarMonth;
    final monthEnd = _monthEnd(_calendarMonth);
    final gridStart = _weekStart(monthStart);
    final today = _today;

    final periodStart = _periodStart;
    final periodEnd = _periodEnd;

    final monthTotal = _reportsBetween(monthStart, monthEnd);
    final monthPoints =
        monthTotal.fold<int>(0, (s, r) => s + _pointCount(r));
    final monthDI =
        monthTotal.fold<double>(0, (s, r) => s + _toDouble(r['di']));

    final weeks = <Widget>[];

    for (var weekStart = gridStart;
        !weekStart.isAfter(monthEnd);
        weekStart = _addDays(weekStart, 7)) {
      final cells = <Widget>[];

      for (int i = 0; i < 7; i++) {
        final day = _addDays(weekStart, i);
        final inMonth = day.month == monthStart.month;
        final value = byDate[_fmt(day)];
        final inPeriod =
            !day.isBefore(periodStart) && !day.isAfter(periodEnd);
        final isFuture = day.isAfter(today);

        cells.add(
          Expanded(
            child: InkWell(
              onTap: !inMonth || isFuture
                  ? null
                  : () => _setSelected(day, mode: _PeriodMode.day),
              child: Container(
                height: 54,
                margin: const EdgeInsets.all(1),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: inPeriod && inMonth
                      ? Colors.blue.shade50
                      : null,
                  border: Border.all(
                    color: day == today
                        ? Colors.blue
                        : Colors.grey.shade200,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: !inMonth
                    ? null
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isFuture
                                  ? Colors.grey.shade400
                                  : day.weekday == DateTime.sunday
                                      ? Colors.red.shade400
                                      : day.weekday == DateTime.saturday
                                          ? Colors.blue.shade400
                                          : Colors.black87,
                            ),
                          ),
                          if (value != null) ...[
                            const Spacer(),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${value.points}P',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _fmtDI(value.di),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        );
      }

      weeks.add(Row(children: cells));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '지난달',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _moveCalendar(-1),
                ),
                Text(
                  '${monthStart.year}년 ${monthStart.month}월',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  tooltip: '다음달',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _monthStart(_today) == monthStart
                      ? null
                      : () => _moveCalendar(1),
                ),
                const Spacer(),
                Text(
                  '${monthPoints}P · D/I ${_fmtDI(monthDI)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (int i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Text(
                        _weekdays[i],
                        style: TextStyle(
                          fontSize: 11,
                          color: i == 6
                              ? Colors.red.shade400
                              : i == 5
                                  ? Colors.blue.shade400
                                  : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ...weeks,
          ],
        ),
      ),
    );
  }
}

class _Group {
  final String key;
  int points = 0;
  double di = 0;
  final Set<String> subs = {};

  _Group(this.key);
}
