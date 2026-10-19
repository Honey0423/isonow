import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';
import 'login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  // ============================================
  // 사용자 정보
  // ============================================

  String _role = 'user';
  String _userName = '';

  // ============================================
  // 상태
  // ============================================

  bool _isLoading = true;

  int _selectedTab = 0;

  // ============================================
  // 현장
  // ============================================

  List<Map<String, dynamic>> _projects = [];

  // ============================================
  // 초기화
  // ============================================

  @override
  void initState() {
    super.initState();

    _loadUserAndProjects();
  }

  // ============================================
  // 사용자 정보 + 현장 목록
  // ============================================

  Future<void> _loadUserAndProjects() async {
    try {
      final User? user =
          _auth.currentUser;

      if (user == null) {
        _goToLogin();
        return;
      }

      // ==========================================
      // 사용자 정보
      // ==========================================

      final userDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        await _auth.signOut();
        _goToLogin();
        return;
      }

      final userData =
          userDoc.data();

      final String role =
          userData?['role']?.toString() ??
              'user';

      final String name =
          userData?['name']?.toString() ??
              '';

      // ==========================================
      // 전체 활성 현장
      // ==========================================

      final snapshot = await _firestore
          .collection('projects')
          .where(
            'active',
            isEqualTo: true,
          )
          .get();

      final List<Map<String, dynamic>>
          allProjects = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        allProjects.add({
          'id': doc.id,
          'name':
              data['name']?.toString() ??
                  doc.id,
        });
      }

      // ==========================================
      // 권한에 따른 현장 필터링
      // ==========================================
      //
      // super_admin
      // → 모든 활성 현장
      //
      // admin / pipefitter / user
      // → users.projects에 승인된 현장만
      // ==========================================

      List<Map<String, dynamic>>
          filteredProjects = [];

      if (role == 'super_admin') {
        filteredProjects =
            allProjects;
      } else {
        final dynamic userProjects =
            userData?['projects'];

        if (userProjects is List) {
          final List<String>
              projectIds =
              userProjects
                  .map(
                    (e) => e.toString(),
                  )
                  .toList();

          filteredProjects =
              allProjects
                  .where(
                    (project) =>
                        projectIds.contains(
                      project['id']
                          .toString(),
                    ),
                  )
                  .toList();
        }
      }

      // ==========================================
      // 이름순 정렬
      // ==========================================

      filteredProjects.sort(
        (a, b) => a['name']
            .toString()
            .compareTo(
              b['name'].toString(),
            ),
      );

      if (!mounted) return;

      setState(() {
        _role = role;
        _userName = name;
        _projects = filteredProjects;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint(
        '사용자 / 현장 불러오기 오류: $e',
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        '정보를 불러오지 못했습니다.',
      );
    }
  }

  // ============================================
  // 현장 선택
  // ============================================

  void _selectProject(
    String projectId,
    String projectName,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(
          projectId: projectId,
          projectName: projectName,
        ),
      ),
    );
  }

  // ============================================
  // 로그인 화면
  // ============================================

  void _goToLogin() {
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const LoginScreen(),
      ),
      (route) => false,
    );
  }

  // ============================================
  // 로그아웃
  // ============================================

  Future<void> _handleAdminBack() async {
    await _auth.signOut();

    if (!mounted) return;

    _goToLogin();
  }

  // ============================================
  // 메시지
  // ============================================

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

  // ============================================
  // 현재 사용자가 사람 관리 가능한지
  // ============================================

  bool get _canManagePeople {
    return _role == 'super_admin' ||
        _role == 'admin';
  }

  // ============================================
  // 화면
  // ============================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult:
          (didPop, result) async {
        if (didPop) return;

        await _handleAdminBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
            ),
            tooltip: '로그아웃',
            onPressed: () async {
              await _handleAdminBack();
            },
          ),
          title: const Text(
            'ISONow',
          ),
        ),
        body: Column(
          children: [
            // ======================================
            // 사용자 정보
            // ======================================

            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.fromLTRB(
                20,
                15,
                20,
                15,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    child: Icon(
                      _getRoleIcon(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName.isEmpty
                              ? '사용자'
                              : _userName,
                          style:
                              const TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          _getRoleName(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors
                                .grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ======================================
            // 탭
            // ======================================

            if (_canManagePeople)
              _buildTabBar(),

            // ======================================
            // 내용
            // ======================================

            Expanded(
              child: _selectedTab == 0
                  ? _buildProjectTab()
                  : _buildPeopleTab(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // 역할 아이콘
  // ============================================

  IconData _getRoleIcon() {
    switch (_role) {
      case 'super_admin':
        return Icons.admin_panel_settings;

      case 'admin':
        return Icons.manage_accounts;

      case 'pipefitter':
        return Icons.plumbing;

      default:
        return Icons.person;
    }
  }

  // ============================================
  // 역할 이름
  // ============================================

  String _getRoleName() {
    switch (_role) {
      case 'super_admin':
        return '총괄 관리자';

      case 'admin':
        return '현장 관리자';

      case 'pipefitter':
        return '배관사';

      default:
        return '일반 사용자';
    }
  }

  // ============================================
  // 탭
  // ============================================

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              index: 0,
              icon: Icons.business,
              title: '현장',
            ),
          ),
          Expanded(
            child: _buildTabButton(
              index: 1,
              icon: Icons.people,
              title: '사람 관리',
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // 탭 버튼
  // ============================================

  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String title,
  }) {
    final bool selected =
        _selectedTab == index;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          vertical: 15,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected
                  ? Theme.of(context)
                      .colorScheme
                      .primary
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
              color: selected
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                  : Colors.grey,
            ),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                fontWeight: selected
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: selected
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                    : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // 현장 탭
  // ============================================

  Widget _buildProjectTab() {
    return Padding(
      padding:
          const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            '현장 선택',
            style: TextStyle(
              fontSize: 28,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getProjectDescription(),
            style: TextStyle(
              color:
                  Colors.grey.shade600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 25),
          Expanded(
            child: _buildProjectList(),
          ),
        ],
      ),
    );
  }

  // ============================================
  // 현장 설명
  // ============================================

  String _getProjectDescription() {
    switch (_role) {
      case 'super_admin':
        return '관리할 현장을 선택해주세요.';

      case 'admin':
        return '관리 권한이 있는 현장을 선택해주세요.';

      case 'pipefitter':
        return '접근 가능한 현장을 선택해주세요.';

      default:
        return '접근 가능한 현장을 선택해주세요.';
    }
  }

  // ============================================
  // 현장 목록
  // ============================================

  Widget _buildProjectList() {
    if (_isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons.business_outlined,
              size: 60,
              color:
                  Colors.grey.shade400,
            ),
            const SizedBox(height: 15),
            const Text(
              '접근 가능한 현장이 없습니다.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _projects.length,
      itemBuilder:
          (context, index) {
        final project =
            _projects[index];

        final String projectId =
            project['id'].toString();

        final String projectName =
            project['name'].toString();

        return Card(
          margin:
              const EdgeInsets.only(
            bottom: 12,
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            leading: Container(
              width: 48,
              height: 48,
              decoration:
                  BoxDecoration(
                color:
                    Colors.grey.shade100,
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
              ),
              child: Icon(
                Icons.business,
                color:
                    Colors.grey.shade700,
              ),
            ),
            title: Text(
              projectName,
              style:
                  const TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            subtitle:
                const Text(
              '현장 접속',
            ),
            trailing:
                const Icon(
              Icons.chevron_right,
            ),
            onTap: () {
              _selectProject(
                projectId,
                projectName,
              );
            },
          ),
        );
      },
    );
  }

  // ============================================
  // 사람 관리
  // ============================================

  Widget _buildPeopleTab() {
    if (_isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    return _PeopleManagement(
      role: _role,
      projects: _projects,
      firestore: _firestore,
      onMessage: _showMessage,
    );
  }
}

// ==================================================
// 사람 관리 화면
// ==================================================

class _PeopleManagement
    extends StatefulWidget {
  final String role;

  final List<Map<String, dynamic>>
      projects;

  final FirebaseFirestore firestore;

  final void Function(String message)
      onMessage;

  const _PeopleManagement({
    required this.role,
    required this.projects,
    required this.firestore,
    required this.onMessage,
  });

  @override
  State<_PeopleManagement> createState() =>
      _PeopleManagementState();
}

class _PeopleManagementState
    extends State<_PeopleManagement> {
  // ============================================
  // 선택된 현장
  // ============================================

  String? _selectedProjectId;

  String? _selectedProjectName;

  // ============================================
  // 상태
  // ============================================

  bool _isLoading = false;

  List<Map<String, dynamic>>
      _users = [];

  // ============================================
  // 초기화
  // ============================================

  @override
  void initState() {
    super.initState();

    if (widget.projects.isNotEmpty) {
      _selectedProjectId =
          widget.projects.first['id']
              .toString();

      _selectedProjectName =
          widget.projects.first['name']
              .toString();

      _loadUsers();
    }
  }

  // ============================================
  // 현장 변경
  // ============================================

  void _changeProject(
    String? projectId,
  ) {
    if (projectId == null) {
      return;
    }

    final project =
        widget.projects.firstWhere(
      (element) =>
          element['id'].toString() ==
          projectId,
    );

    setState(() {
      _selectedProjectId =
          projectId;

      _selectedProjectName =
          project['name'].toString();
    });

    _loadUsers();
  }

  // ============================================
  // 사용자 목록
  // ============================================

  Future<void> _loadUsers() async {
    if (_selectedProjectId ==
        null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final snapshot =
          await widget.firestore
              .collection('users')
              .get();

      final List<
              Map<String, dynamic>>
          users = [];

      for (final doc
          in snapshot.docs) {
        final data = doc.data();

        final String?
            requestedProjectId =
            data['requestedProjectId']
                ?.toString();

        final dynamic projects =
            data['projects'];

        bool belongsToProject =
            false;

        // ========================================
        // 이미 승인된 사용자
        // ========================================

        if (projects is List) {
          belongsToProject =
              projects
                  .map(
                    (e) =>
                        e.toString(),
                  )
                  .contains(
                    _selectedProjectId,
                  );
        }

        // ========================================
        // 승인 대기 사용자
        // ========================================

        final bool
            requestedThisProject =
            requestedProjectId ==
                _selectedProjectId;

        // ========================================
        // 해당 현장 사용자만 표시
        // ========================================

        if (belongsToProject ||
            requestedThisProject) {
          users.add({
            'uid': doc.id,
            'data': data,
          });
        }
      }

      // ==========================================
      // 정렬
      //
      // 1. 승인 대기
      // 2. 총괄 관리자
      // 3. 현장 관리자
      // 4. 배관사
      // 5. 일반 사용자
      // 6. 이름순
      // ==========================================

      users.sort((a, b) {
        final Map<String, dynamic>
            aData =
            Map<String, dynamic>.from(
          a['data'],
        );

        final Map<String, dynamic>
            bData =
            Map<String, dynamic>.from(
          b['data'],
        );

        final String aStatus =
            aData['status']
                    ?.toString() ??
                'pending';

        final String bStatus =
            bData['status']
                    ?.toString() ??
                'pending';

        final String aRole =
            aData['role']
                    ?.toString() ??
                'user';

        final String bRole =
            bData['role']
                    ?.toString() ??
                'user';

        final String aName =
            aData['name']
                    ?.toString() ??
                '';

        final String bName =
            bData['name']
                    ?.toString() ??
                '';

        // ======================================
        // 1. 승인 대기 우선
        // ======================================

        final int aStatusPriority =
            aStatus == 'pending'
                ? 0
                : 1;

        final int bStatusPriority =
            bStatus == 'pending'
                ? 0
                : 1;

        if (aStatusPriority !=
            bStatusPriority) {
          return aStatusPriority
              .compareTo(
            bStatusPriority,
          );
        }

        // ======================================
        // 2. 역할 우선순위
        // ======================================

        int getRolePriority(
          String role,
        ) {
          switch (role) {
            case 'super_admin':
              return 0;

            case 'admin':
              return 1;

            case 'pipefitter':
              return 2;

            default:
              return 3;
          }
        }

        final int aRolePriority =
            getRolePriority(
          aRole,
        );

        final int bRolePriority =
            getRolePriority(
          bRole,
        );

        if (aRolePriority !=
            bRolePriority) {
          return aRolePriority
              .compareTo(
            bRolePriority,
          );
        }

        // ======================================
        // 3. 같은 등급이면 이름순
        // ======================================

        return aName.compareTo(
          bName,
        );
      });

      if (!mounted) return;

      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint(
        '사용자 목록 불러오기 오류: $e',
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      widget.onMessage(
        '사용자 목록을 불러오지 못했습니다.',
      );
    }
  }

  // ============================================
  // 사용자 승인
  // ============================================

  Future<void> _approveUser(
    String uid,
  ) async {
    if (_selectedProjectId ==
        null) {
      return;
    }

    try {
      await widget.firestore
          .collection('users')
          .doc(uid)
          .update({
        'status': 'approved',
        'projects':
            FieldValue.arrayUnion([
          _selectedProjectId,
        ]),
      });

      widget.onMessage(
        '사용자를 승인했습니다.',
      );

      await _loadUsers();
    } catch (e) {
      debugPrint(
        '사용자 승인 오류: $e',
      );

      widget.onMessage(
        '사용자 승인에 실패했습니다.',
      );
    }
  }

  // ============================================
  // 관리자 지정
  //
  // super_admin만 가능
  //
  // role:
  // user / pipefitter
  // → admin
  // ============================================

  Future<void> _makeAdmin(
    String uid,
  ) async {
    if (_selectedProjectId ==
        null) {
      return;
    }

    if (widget.role !=
        'super_admin') {
      widget.onMessage(
        '총괄 관리자만 관리자를 지정할 수 있습니다.',
      );
      return;
    }

    try {
      await widget.firestore
          .collection('users')
          .doc(uid)
          .update({
        'role': 'admin',
        'status': 'approved',
        'projects':
            FieldValue.arrayUnion([
          _selectedProjectId,
        ]),

        // ======================================
        // 기존 구형 용접사 필드 제거
        // ======================================

        'isWelder':
            FieldValue.delete(),
        'welderNumber':
            FieldValue.delete(),
      });

      widget.onMessage(
        '현장 관리자로 지정했습니다.',
      );

      await _loadUsers();
    } catch (e) {
      debugPrint(
        '관리자 지정 오류: $e',
      );

      widget.onMessage(
        '관리자 지정에 실패했습니다.',
      );
    }
  }

  // ============================================
  // 관리자 해제
  //
  // super_admin만 가능
  //
  // admin → user
  // ============================================

  Future<void> _removeAdmin(
    String uid,
  ) async {
    if (widget.role !=
        'super_admin') {
      widget.onMessage(
        '총괄 관리자만 관리자 권한을 해제할 수 있습니다.',
      );
      return;
    }

    try {
      await widget.firestore
          .collection('users')
          .doc(uid)
          .update({
        'role': 'user',

        // ======================================
        // 기존 구형 용접사 필드 제거
        // ======================================

        'isWelder':
            FieldValue.delete(),
        'welderNumber':
            FieldValue.delete(),
      });

      widget.onMessage(
        '관리자 권한을 해제했습니다.',
      );

      await _loadUsers();
    } catch (e) {
      debugPrint(
        '관리자 해제 오류: $e',
      );

      widget.onMessage(
        '관리자 권한 해제에 실패했습니다.',
      );
    }
  }

  // ============================================
  // 배관사 지정
  //
  // super_admin / admin 가능
  //
  // role:
  // user → pipefitter
  //
  // 별도의 pipefitterNumber 없음
  // ============================================

  Future<void> _makePipefitter(
    String uid,
  ) async {
    if (_selectedProjectId ==
        null) {
      return;
    }

    if (widget.role !=
            'super_admin' &&
        widget.role != 'admin') {
      widget.onMessage(
        '배관사를 지정할 권한이 없습니다.',
      );
      return;
    }

    try {
      await widget.firestore
          .collection('users')
          .doc(uid)
          .update({
        'role': 'pipefitter',
        'status': 'approved',
        'projects':
            FieldValue.arrayUnion([
          _selectedProjectId,
        ]),

        // ======================================
        // 기존 구형 용접사 필드 제거
        // ======================================

        'isWelder':
            FieldValue.delete(),
        'welderNumber':
            FieldValue.delete(),
      });

      widget.onMessage(
        '배관사로 지정했습니다.',
      );

      await _loadUsers();
    } catch (e) {
      debugPrint(
        '배관사 지정 오류: $e',
      );

      widget.onMessage(
        '배관사 지정에 실패했습니다.',
      );
    }
  }

  // ============================================
  // 배관사 해제
  //
  // pipefitter → user
  // ============================================

  Future<void> _removePipefitter(
    String uid,
  ) async {
    if (widget.role !=
            'super_admin' &&
        widget.role != 'admin') {
      widget.onMessage(
        '배관사 권한을 해제할 권한이 없습니다.',
      );
      return;
    }

    try {
      await widget.firestore
          .collection('users')
          .doc(uid)
          .update({
        'role': 'user',

        // ======================================
        // 기존 구형 용접사 필드 제거
        // ======================================

        'isWelder':
            FieldValue.delete(),
        'welderNumber':
            FieldValue.delete(),
      });

      widget.onMessage(
        '배관사 권한을 해제했습니다.',
      );

      await _loadUsers();
    } catch (e) {
      debugPrint(
        '배관사 해제 오류: $e',
      );

      widget.onMessage(
        '배관사 해제에 실패했습니다.',
      );
    }
  }

  // ============================================
  // 화면
  // ============================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (widget.projects.isEmpty) {
      return const Center(
        child: Text(
          '관리할 현장이 없습니다.',
          style: TextStyle(
            color: Colors.grey,
          ),
        ),
      );
    }

    return Padding(
      padding:
          const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            '사람 관리',
            style: TextStyle(
              fontSize: 28,
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            widget.role ==
                    'super_admin'
                ? '현장 회원을 관리하고 관리자와 배관사를 지정할 수 있습니다.'
                : '현장 회원가입을 승인하고 배관사를 지정할 수 있습니다.',
            style: TextStyle(
              color:
                  Colors.grey.shade600,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 20),

          // ======================================
          // 현장 선택
          // ======================================

          DropdownButtonFormField<
              String>(
            initialValue:
                _selectedProjectId,

            isExpanded: true,

            decoration:
                const InputDecoration(
              labelText:
                  '관리할 현장',
              border:
                  OutlineInputBorder(),
              prefixIcon:
                  Icon(
                Icons.business,
              ),
            ),

            items:
                widget.projects.map(
              (project) {
                return DropdownMenuItem<
                    String>(
                  value:
                      project['id']
                          .toString(),
                  child: Text(
                    project['name']
                        .toString(),
                  ),
                );
              },
            ).toList(),

            onChanged:
                _changeProject,
          ),

          const SizedBox(height: 20),

          // ======================================
          // 사용자 목록
          // ======================================

          Expanded(
            child:
                _buildUserList(),
          ),
        ],
      ),
    );
  }

  // ============================================
  // 사용자 목록 UI
  // ============================================

  Widget _buildUserList() {
    if (_isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 60,
              color:
                  Colors.grey.shade400,
            ),

            const SizedBox(height: 15),

            const Text(
              '등록된 사용자가 없습니다.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _users.length,
      itemBuilder:
          (context, index) {
        final user =
            _users[index];

        final String uid =
            user['uid'].toString();

        final Map<String, dynamic>
            data =
            Map<String, dynamic>.from(
          user['data'],
        );

        final String name =
            data['name']
                    ?.toString() ??
                '이름 없음';

        final String email =
            data['email']
                    ?.toString() ??
                '';

        final String phone =
            data['phone']
                    ?.toString() ??
                '';

        final String status =
            data['status']
                    ?.toString() ??
                'pending';

        final String role =
            data['role']
                    ?.toString() ??
                'user';

        final bool isSuperAdmin =
            role == 'super_admin';

        final bool isAdmin =
            role == 'admin';

        final bool isPipefitter =
            role == 'pipefitter';

        final bool canAssignAdmin =
            widget.role ==
                'super_admin';

        final bool canAssignPipefitter =
            widget.role ==
                    'super_admin' ||
                widget.role == 'admin';

        return Card(
          margin:
              const EdgeInsets.only(
            bottom: 12,
          ),

          child: Padding(
            padding:
                const EdgeInsets.all(
              15,
            ),

            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                // ==================================
                // 이름 + 상태
                // ==================================

                Row(
                  children: [
                    CircleAvatar(
                      child: Text(
                        name.isNotEmpty
                            ? name[0]
                            : '?',
                      ),
                    ),

                    const SizedBox(
                      width: 12,
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child:
                                    Text(
                                  name,
                                  overflow:
                                      TextOverflow
                                          .ellipsis,
                                  style:
                                      const TextStyle(
                                    fontSize:
                                        17,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),
                              ),

                              const SizedBox(
                                width: 8,
                              ),

                              _buildStatusChip(
                                status,
                              ),
                            ],
                          ),

                          const SizedBox(
                            height: 4,
                          ),

                          Text(
                            email,
                            style:
                                TextStyle(
                              fontSize:
                                  13,
                              color: Colors
                                  .grey
                                  .shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 12,
                ),

                // ==================================
                // 전화번호
                // ==================================

                if (phone.isNotEmpty)
                  Text(
                    '전화번호  $phone',
                    style:
                        const TextStyle(
                      fontSize: 13,
                    ),
                  ),

                if (phone.isNotEmpty)
                  const SizedBox(
                    height: 10,
                  ),

                // ==================================
                // 권한
                // ==================================

                Row(
                  children: [
                    Text(
                      '권한  ${_getUserRoleName(role)}',
                      style:
                          TextStyle(
                        fontSize: 13,
                        color: Colors
                            .grey
                            .shade700,
                      ),
                    ),

                    if (isSuperAdmin) ...[
                      const SizedBox(
                        width: 8,
                      ),
                      _buildRoleChip(
                        text:
                            '총괄 관리자',
                        icon: Icons
                            .admin_panel_settings,
                      ),
                    ],

                    if (isAdmin) ...[
                      const SizedBox(
                        width: 8,
                      ),
                      _buildRoleChip(
                        text:
                            '현장 관리자',
                        icon: Icons
                            .manage_accounts,
                      ),
                    ],

                    if (isPipefitter) ...[
                      const SizedBox(
                        width: 8,
                      ),
                      _buildRoleChip(
                        text: '배관사',
                        icon:
                            Icons.plumbing,
                      ),
                    ],
                  ],
                ),

                const SizedBox(
                  height: 12,
                ),

                // ==================================
                // 버튼
                // ==================================

                Wrap(
                  alignment:
                      WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // --------------------------------
                    // 승인
                    // --------------------------------

                    if (status ==
                        'pending')
                      ElevatedButton.icon(
                        onPressed: () {
                          _approveUser(
                            uid,
                          );
                        },
                        icon:
                            const Icon(
                          Icons.check,
                          size: 18,
                        ),
                        label:
                            const Text(
                          '승인',
                        ),
                      ),

                    // --------------------------------
                    // 관리자 지정
                    //
                    // super_admin만
                    // --------------------------------

                    if (canAssignAdmin &&
                        role !=
                            'admin' &&
                        role !=
                            'super_admin')
                      OutlinedButton.icon(
                        onPressed: () {
                          _makeAdmin(
                            uid,
                          );
                        },
                        icon:
                            const Icon(
                          Icons
                              .admin_panel_settings,
                          size: 18,
                        ),
                        label:
                            const Text(
                          '관리자 지정',
                        ),
                      ),

                    // --------------------------------
                    // 관리자 해제
                    //
                    // super_admin만
                    // --------------------------------

                    if (canAssignAdmin &&
                        role ==
                            'admin')
                      OutlinedButton.icon(
                        onPressed: () {
                          _removeAdmin(
                            uid,
                          );
                        },
                        icon:
                            const Icon(
                          Icons
                              .person_remove,
                          size: 18,
                        ),
                        label:
                            const Text(
                          '관리자 해제',
                        ),
                      ),

                    // --------------------------------
                    // 배관사 지정
                    //
                    // super_admin / admin
                    // --------------------------------

                    if (canAssignPipefitter &&
                        role !=
                            'admin' &&
                        role !=
                            'super_admin' &&
                        !isPipefitter)
                      OutlinedButton.icon(
                        onPressed: () {
                          _makePipefitter(
                            uid,
                          );
                        },
                        icon:
                            const Icon(
                          Icons.plumbing,
                          size: 18,
                        ),
                        label:
                            const Text(
                          '배관사 지정',
                        ),
                      ),

                    // --------------------------------
                    // 배관사 해제
                    //
                    // super_admin / admin
                    // --------------------------------

                    if (canAssignPipefitter &&
                        isPipefitter)
                      OutlinedButton.icon(
                        onPressed: () {
                          _removePipefitter(
                            uid,
                          );
                        },
                        icon:
                            const Icon(
                          Icons
                              .person_remove_alt_1,
                          size: 18,
                        ),
                        label:
                            const Text(
                          '배관사 해제',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================
  // 상태 Chip
  // ============================================

  Widget _buildStatusChip(
    String status,
  ) {
    String text;

    switch (status) {
      case 'approved':
        text = '승인';
        break;

      case 'pending':
        text = '승인 대기';
        break;

      default:
        text = status;
    }

    final bool approved =
        status == 'approved';

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration:
          BoxDecoration(
        color: approved
            ? Colors.green.shade50
            : Colors.orange.shade50,
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight:
              FontWeight.bold,
          color: approved
              ? Colors.green.shade700
              : Colors.orange.shade700,
        ),
      ),
    );
  }

  // ============================================
  // 역할 Chip
  // ============================================

  Widget _buildRoleChip({
    required String text,
    required IconData icon,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.blue.shade50,
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color:
                Colors.blue.shade700,
          ),
          const SizedBox(
            width: 4,
          ),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  FontWeight.bold,
              color: Colors
                  .blue
                  .shade700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // 사용자 역할 이름
  // ============================================

  String _getUserRoleName(
    String role,
  ) {
    switch (role) {
      case 'super_admin':
        return '총괄 관리자';

      case 'admin':
        return '현장 관리자';

      case 'pipefitter':
        return '배관사';

      default:
        return '일반 사용자';
    }
  }
}