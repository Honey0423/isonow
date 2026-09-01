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
      final User? user = _auth.currentUser;

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

      final userData = userDoc.data();

      final String role =
          userData?['role']?.toString() ?? 'user';

      final String name =
          userData?['name']?.toString() ?? '';

      // ==========================================
      // 전체 활성 현장
      // ==========================================

      final snapshot = await _firestore
          .collection('projects')
          .where('active', isEqualTo: true)
          .get();

      final List<Map<String, dynamic>> allProjects = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        allProjects.add({
          'id': doc.id,
          'name': data['name']?.toString() ?? doc.id,
        });
      }

      // ==========================================
      // 권한에 따른 현장 필터링
      // ==========================================

      List<Map<String, dynamic>> filteredProjects = [];

      if (role == 'super_admin') {
        // ----------------------------------------
        // 슈퍼 어드민
        // → 모든 활성 현장
        // ----------------------------------------

        filteredProjects = allProjects;
      } else {
        // ----------------------------------------
        // admin / user
        // → users.projects에 등록된 현장
        // ----------------------------------------

        final dynamic userProjects =
            userData?['projects'];

        if (userProjects is List) {
          final List<String> projectIds =
              userProjects
                  .map((e) => e.toString())
                  .toList();

          filteredProjects =
              allProjects.where((project) {
            return projectIds.contains(
              project['id'].toString(),
            );
          }).toList();
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
  // 로그인 화면으로 이동
  //
  // 중요:
  // '/login' named route를 사용하지 않는다.
  // LoginScreen을 직접 생성한다.
  // ============================================

  void _goToLogin() {
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
      (route) => false,
    );
  }

  // ============================================
  // AdminScreen 뒤로가기
  //
  // AdminScreen에서는 뒤로가기 = 로그아웃
  // ============================================

  Future<void> _handleAdminBack() async {
    await _auth.signOut();

    if (!mounted) return;

    _goToLogin();
  }

  // ============================================
  // 메시지
  // ============================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ============================================
  // 화면
  // ============================================

  @override
  Widget build(BuildContext context) {
    final bool canManagePeople =
        _role == 'super_admin' ||
        _role == 'admin';

    return PopScope(
      // ==========================================
      // AdminScreen에서는 기본 뒤로가기를 막음
      //
      // 뒤로가기 버튼을 누르면
      // → 로그아웃
      // → LoginScreen
      // ==========================================

      canPop: false,

      onPopInvokedWithResult:
          (didPop, result) async {
        if (didPop) return;

        await _handleAdminBack();
      },

      child: Scaffold(
        appBar: AppBar(
          // ======================================
          // 왼쪽 위 뒤로가기 버튼
          // ======================================

          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
            ),

            tooltip: '뒤로가기',

            onPressed: () async {
              await _handleAdminBack();
            },
          ),

          title: const Text('ISONow'),
        ),

        body: Column(
          children: [

            // ======================================
            // 사용자 정보
            // ======================================

            Container(
              width: double.infinity,

              padding: const EdgeInsets.fromLTRB(
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
                      _role == 'super_admin'
                          ? Icons.admin_panel_settings
                          : _role == 'admin'
                              ? Icons.manage_accounts
                              : Icons.person,
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

                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          _getRoleName(),

                          style: TextStyle(
                            fontSize: 13,
                            color:
                                Colors.grey.shade600,
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

            if (canManagePeople)
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
  // 역할 이름
  // ============================================

  String _getRoleName() {
    switch (_role) {
      case 'super_admin':
        return '총괄 관리자';

      case 'admin':
        return '현장 관리자';

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
        padding: const EdgeInsets.symmetric(
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
      padding: const EdgeInsets.all(20),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          const Text(
            '현장 선택',

            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            _getProjectDescription(),

            style: TextStyle(
              color: Colors.grey.shade600,
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
        child: CircularProgressIndicator(),
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
              color: Colors.grey.shade400,
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

      itemBuilder: (context, index) {
        final project =
            _projects[index];

        final String projectId =
            project['id'].toString();

        final String projectName =
            project['name'].toString();

        return Card(
          margin: const EdgeInsets.only(
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

              decoration: BoxDecoration(
                color: Colors.grey.shade100,

                borderRadius:
                    BorderRadius.circular(12),
              ),

              child: Icon(
                Icons.business,
                color: Colors.grey.shade700,
              ),
            ),

            title: Text(
              projectName,

              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            subtitle: const Text(
              '현장 접속',
            ),

            trailing: const Icon(
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
  // 사람 관리 탭
  // ============================================

  Widget _buildPeopleTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
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

class _PeopleManagement extends StatefulWidget {
  final String role;

  final List<Map<String, dynamic>> projects;

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

  String? _selectedProjectId;

  String? _selectedProjectName;

  bool _isLoading = false;

  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();

    // 관리자에게 관리 가능한 현장이 하나 있으면
    // 첫 번째 현장을 자동 선택
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

  void _changeProject(String? projectId) {
    if (projectId == null) return;

    final project =
        widget.projects.firstWhere(
      (element) =>
          element['id'].toString() ==
          projectId,
    );

    setState(() {
      _selectedProjectId = projectId;

      _selectedProjectName =
          project['name'].toString();
    });

    _loadUsers();
  }

  // ============================================
  // 사용자 목록
  // ============================================

  Future<void> _loadUsers() async {
    if (_selectedProjectId == null) {
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

      final List<Map<String, dynamic>> users =
          [];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final String? requestedProjectId =
            data['requestedProjectId']
                ?.toString();

        final dynamic projects =
            data['projects'];

        bool belongsToProject = false;

        // ========================================
        // 이미 승인된 사용자
        // ========================================

        if (projects is List) {
          belongsToProject =
              projects
                  .map((e) => e.toString())
                  .contains(
                    _selectedProjectId,
                  );
        }

        // ========================================
        // 아직 승인 대기중인 사용자
        // ========================================

        final bool requestedThisProject =
            requestedProjectId ==
            _selectedProjectId;

        // ========================================
        // 둘 중 하나라도 해당하면 표시
        // ========================================

        if (belongsToProject ||
            requestedThisProject) {
          users.add({
            'uid': doc.id,
            'data': data,
          });
        }
      }

      // ========================================
      // 정렬
      //
      // 1. 승인 대기(pending)
      // 2. 권한
      //    super_admin → admin → user
      // 3. 같은 등급이면 이름 가나다순
      // ========================================

      users.sort((a, b) {
        final String aStatus =
            a['data']['status']?.toString() ?? 'pending';

        final String bStatus =
            b['data']['status']?.toString() ?? 'pending';

        final String aRole =
            a['data']['role']?.toString() ?? 'user';

        final String bRole =
            b['data']['role']?.toString() ?? 'user';

        final String aName =
            a['data']['name']?.toString() ?? '';

        final String bName =
            b['data']['name']?.toString() ?? '';

        // ======================================
        // 1. 승인 대기 우선
        // ======================================

        final int aStatusPriority =
            aStatus == 'pending' ? 0 : 1;

        final int bStatusPriority =
            bStatus == 'pending' ? 0 : 1;

        if (aStatusPriority != bStatusPriority) {
          return aStatusPriority.compareTo(
            bStatusPriority,
          );
        }

        // ======================================
        // 2. 권한 우선순위
        // ======================================

        int getRolePriority(String role) {
          switch (role) {
            case 'super_admin':
              return 0;

            case 'admin':
              return 1;

            default:
              return 2;
          }
        }

        final int aRolePriority =
            getRolePriority(aRole);

        final int bRolePriority =
            getRolePriority(bRole);

        if (aRolePriority != bRolePriority) {
          return aRolePriority.compareTo(
            bRolePriority,
          );
        }

        // ======================================
        // 3. 같은 상태 + 같은 권한이면
        //    이름 가나다순
        // ======================================

        return aName.compareTo(bName);
      });



      //
      if (!mounted) return;

      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
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
    if (_selectedProjectId == null) {
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

      _loadUsers();
    } catch (e) {
      widget.onMessage(
        '사용자 승인에 실패했습니다.',
      );
    }
  }

  // ============================================
  // 관리자 지정
  // ============================================

  Future<void> _makeAdmin(
    String uid,
  ) async {
    if (_selectedProjectId == null) {
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
      });

      widget.onMessage(
        '현장 관리자로 지정했습니다.',
      );

      _loadUsers();
    } catch (e) {
      widget.onMessage(
        '관리자 지정에 실패했습니다.',
      );
    }
  }

  // ============================================
  // 관리자 해제
  // ============================================

  Future<void> _removeAdmin(
    String uid,
  ) async {
    try {
      await widget.firestore
          .collection('users')
          .doc(uid)
          .update({
        'role': 'user',
      });

      widget.onMessage(
        '관리자 권한을 해제했습니다.',
      );

      _loadUsers();
    } catch (e) {
      widget.onMessage(
        '관리자 권한 해제에 실패했습니다.',
      );
    }
  }

  // ============================================
  // 화면
  // ============================================

  @override
  Widget build(BuildContext context) {
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
      padding: const EdgeInsets.all(20),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          const Text(
            '사람 관리',

            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            widget.role == 'super_admin'
                ? '현장 회원을 관리하고 관리자를 지정할 수 있습니다.'
                : '현장 회원가입 신청을 승인할 수 있습니다.',

            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 20),

          // ======================================
          // 현장 선택
          // ======================================

          DropdownButtonFormField<String>(
            value: _selectedProjectId,

            isExpanded: true,

            decoration:
                const InputDecoration(
              labelText: '관리할 현장',
              border: OutlineInputBorder(),
              prefixIcon:
                  Icon(Icons.business),
            ),

            items:
                widget.projects.map((project) {
              return DropdownMenuItem<String>(
                value:
                    project['id'].toString(),

                child: Text(
                  project['name'].toString(),
                ),
              );
            }).toList(),

            onChanged: _changeProject,
          ),

          const SizedBox(height: 20),

          // ======================================
          // 사용자 목록
          // ======================================

          Expanded(
            child: _buildUserList(),
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
        child: CircularProgressIndicator(),
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
              color: Colors.grey.shade400,
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

      itemBuilder: (context, index) {
        final user =
            _users[index];

        final String uid =
            user['uid'].toString();

        final Map<String, dynamic> data =
            Map<String, dynamic>.from(
          user['data'],
        );

        final String name =
            data['name']?.toString() ??
                '이름 없음';

        final String email =
            data['email']?.toString() ??
                '';

        final String phone =
            data['phone']?.toString() ??
                '';

        final String status =
            data['status']?.toString() ??
                'pending';

        final String role =
            data['role']?.toString() ??
                'user';

        return Card(
          margin: const EdgeInsets.only(
            bottom: 12,
          ),

          child: Padding(
            padding: const EdgeInsets.all(15),

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

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,

                        children: [

                          Row(
                            children: [

                              Text(
                                name,

                                style:
                                    const TextStyle(
                                  fontSize: 17,
                                  fontWeight:
                                      FontWeight.bold,
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

                const SizedBox(height: 12),

                // ==================================
                // 전화번호
                // ==================================

                if (phone.isNotEmpty)
                  Text(
                    '전화번호  $phone',

                    style: const TextStyle(
                      fontSize: 13,
                    ),
                  ),

                const SizedBox(height: 10),

                // ==================================
                // 역할
                // ==================================

                Text(
                  '권한  ${_getUserRoleName(role)}',

                  style: TextStyle(
                    fontSize: 13,
                    color:
                        Colors.grey.shade700,
                  ),
                ),

                const SizedBox(height: 12),

                // ==================================
                // 버튼
                // ==================================

                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.end,

                  children: [

                    // --------------------------------
                    // 승인 대기
                    // --------------------------------

                    if (status == 'pending')
                      ElevatedButton.icon(
                        onPressed: () {
                          _approveUser(uid);
                        },

                        icon: const Icon(
                          Icons.check,
                          size: 18,
                        ),

                        label: const Text(
                          '승인',
                        ),
                      ),

                    // --------------------------------
                    // 슈퍼 어드민만 관리자 지정 가능
                    // --------------------------------

                    if (widget.role ==
                            'super_admin' &&
                        role != 'admin' &&
                        role != 'super_admin')
                      const SizedBox(width: 8),

                    if (widget.role ==
                            'super_admin' &&
                        role != 'admin' &&
                        role != 'super_admin')
                      OutlinedButton.icon(
                        onPressed: () {
                          _makeAdmin(uid);
                        },

                        icon: const Icon(
                          Icons.admin_panel_settings,
                          size: 18,
                        ),

                        label: const Text(
                          '관리자 지정',
                        ),
                      ),

                    // --------------------------------
                    // 관리자 해제
                    // --------------------------------

                    if (widget.role ==
                            'super_admin' &&
                        role == 'admin')
                      OutlinedButton.icon(
                        onPressed: () {
                          _removeAdmin(uid);
                        },

                        icon: const Icon(
                          Icons.person_remove,
                          size: 18,
                        ),

                        label: const Text(
                          '관리자 해제',
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

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),

      decoration: BoxDecoration(
        color: status == 'approved'
            ? Colors.green.shade50
            : Colors.orange.shade50,

        borderRadius:
            BorderRadius.circular(20),
      ),

      child: Text(
        text,

        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,

          color: status == 'approved'
              ? Colors.green.shade700
              : Colors.orange.shade700,
        ),
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

      default:
        return '일반 사용자';
    }
  }
}