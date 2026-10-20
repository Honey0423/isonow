import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'daily_work_report_screen.dart';
import 'project_screen.dart';
import 'welding_daily_screen.dart';

class HomeScreen extends StatefulWidget {
  final String projectId;
  final String projectName;

  const HomeScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  // =========================================================
  // 공사일보 기능 표시 여부
  //
  // true  = 공사일보 메뉴 표시
  // false = 공사일보 메뉴 숨김
  //
  // SK 보고용으로 숨길 때는 false
  // 평소 사용할 때는 true
  //
  // 기능/화면/Firestore 코드는 삭제하지 않습니다.
  // =========================================================
  static const bool SHOW_DAILY_REPORT = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  String _role = 'user';

  // 승인된 현장 ID 목록 (users.projects)
  List<String> _projects = [];

  bool _isLoadingRole = true;

  @override
  void initState() {
    super.initState();

    _loadUserRole();
  }

  // =========================================================
  // 현재 사용자 Role 불러오기
  // =========================================================

  Future<void> _loadUserRole() async {
    try {
      final User? user = _auth.currentUser;

      if (user == null) {
        if (!mounted) {
          return;
        }

        setState(() {
          _role = 'user';
          _isLoadingRole = false;
        });

        return;
      }

      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) {
        return;
      }

      if (doc.exists) {
        final data = doc.data();

        setState(() {
          _role =
              data?['role']?.toString() ?? 'user';

          final projects = data?['projects'];
          _projects = projects is List
              ? projects.map((e) => e.toString()).toList()
              : [];

          _isLoadingRole = false;
        });
      } else {
        setState(() {
          _role = 'user';
          _isLoadingRole = false;
        });
      }
    } catch (e) {
      debugPrint(
        '사용자 Role 불러오기 실패: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _role = 'user';
        _isLoadingRole = false;
      });
    }
  }

  // =========================================================
  // 이 현장의 admin 이상
  //
  // super_admin: 모든 현장
  // admin: 이 현장이 승인된 경우만
  // =========================================================

  bool get _isSiteAdmin {
    if (_role == 'super_admin') {
      return true;
    }

    return _role == 'admin' &&
        _projects.contains(widget.projectId);
  }

  void _openDailyWorkReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DailyWorkReportScreen(
          projectId: widget.projectId,
          projectName: widget.projectName,
        ),
      ),
    );
  }

  // =========================================================
  // 공사일보 화면
  // =========================================================

  void _openWeldingDaily() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WeldingDailyScreen(
          projectId: widget.projectId,
          projectName: widget.projectName,
        ),
      ),
    );
  }

  // =========================================================
  // 화면
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.projectName,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ===================================================
          // Project 이름
          // ===================================================

          Text(
            widget.projectName,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(
            height: 25,
          ),

          // ===================================================
          // 도면
          // ===================================================

          _MenuCard(
            icon: Icons.architecture,
            title: '도면',
            description:
                'ISO · P&ID · Plan DWG · ...',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProjectScreen(
                    projectId:
                        widget.projectId,
                    projectName:
                        widget.projectName,
                  ),
                ),
              );
            },
          ),

          // ===================================================
          // 안전
          // ===================================================

          _MenuCard(
            icon: Icons.health_and_safety,
            title: '안전',
            description:
                '금일 안전 주요 사항',
            onTap: () {},
          ),

          // ===================================================
          // 품질
          // ===================================================

          _MenuCard(
            icon: Icons.fact_check,
            title: '품질',
            description:
                'Punch List',
            onTap: () {},
          ),

          // ===================================================
          // 자재
          // ===================================================

          _MenuCard(
            icon: Icons.inventory_2,
            title: '자재',
            description:
                '자재 발주 및 현황',
            onTap: () {},
          ),

          // ===================================================
          // 현장 공정률 & 공사일보
          //
          // SHOW_DAILY_REPORT == true
          // 그리고
          // super_admin / admin
          //
          // 일 때만 표시
          //
          // false로 바꾸면 모든 사용자에게 숨겨짐.
          // pipefitter 역시 표시되지 않음.
          // ===================================================

          if (SHOW_DAILY_REPORT &&
              !_isLoadingRole &&
              _isSiteAdmin) ...[
            const SizedBox(
              height: 10,
            ),

            // ===================================================
            // 물량 집계 (일간/주간/월간) - 현장 admin 이상
            // ===================================================

            _MenuCard(
              icon: Icons.event_note,
              title: '물량 집계',
              description:
                  '일간 · 주간 · 월간 용접 물량 (Point · D/I · 용접사별) · 달력',
              onTap: _openDailyWorkReport,
            ),

            _MenuCard(
              icon: Icons.engineering,
              title:
                  '현장 공정률 & 공사일보',
              description:
                  '용접 공정률 · 공사일보 확인 · 작업 관리 · Excel 내보내기',
              onTap:
                  _openWeldingDaily,
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================
// 메뉴 카드
// =============================================================

class _MenuCard extends StatelessWidget {
  final IconData icon;

  final String title;

  final String description;

  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(
        bottom: 15,
      ),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(12),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 22,
          ),
          child: Row(
            children: [
              // =================================================
              // 아이콘
              // =================================================

              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color:
                      Colors.grey.shade100,
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color:
                      Colors.grey.shade700,
                ),
              ),

              const SizedBox(
                width: 18,
              ),

              // =================================================
              // 제목 + 설명
              // =================================================

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                          const TextStyle(
                        fontSize: 20,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // =================================================
              // 화살표
              // =================================================

              Icon(
                Icons.chevron_right,
                color:
                    Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}