import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ============================================
  // Firebase
  // ============================================
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  // ============================================
  // 입력 컨트롤러
  // ============================================
  final TextEditingController _idController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  final TextEditingController _nameController =
      TextEditingController();

  final TextEditingController _phoneController =
      TextEditingController();

  // ============================================
  // 포커스
  // ============================================
  final FocusNode _idFocusNode =
      FocusNode();

  final FocusNode _passwordFocusNode =
      FocusNode();

  final FocusNode _nameFocusNode =
      FocusNode();

  final FocusNode _phoneFocusNode =
      FocusNode();

  // ============================================
  // 상태
  // ============================================
  bool _isSignUp = false;

  bool _obscurePassword = true;

  bool _isLoading = false;

  // ============================================
  // 프로젝트 목록
  // 회원가입 시 현장 선택에 사용
  // ============================================
  List<Map<String, dynamic>> _projects = [];

  String? _selectedProjectId;

  String? _selectedProjectName;

  bool _isLoadingProjects = true;

  // ============================================
  // 초기화
  // ============================================
  @override
  void initState() {
    super.initState();

    _loadProjects();
  }

  // ============================================
  // 종료
  // ============================================
  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();

    _idFocusNode.dispose();
    _passwordFocusNode.dispose();
    _nameFocusNode.dispose();
    _phoneFocusNode.dispose();

    super.dispose();
  }

  // ============================================
  // 활성화된 프로젝트 목록 불러오기
  //
  // 회원가입할 때 사용할 현장 목록
  //
  // active == true 인 현장만 표시
  // ============================================
  Future<void> _loadProjects() async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snapshot =
          await _firestore
              .collection('projects')
              .where(
                'active',
                isEqualTo: true,
              )
              .get();

      final List<Map<String, dynamic>> projects = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        projects.add({
          'id': doc.id,
          'name': data['name']?.toString() ?? doc.id,
        });
      }

      // ==========================================
      // 프로젝트 이름순 정렬
      // ==========================================
      projects.sort(
        (a, b) => a['name']
            .toString()
            .compareTo(
              b['name'].toString(),
            ),
      );

      if (!mounted) return;

      setState(() {
        _projects = projects;

        // ========================================
        // 첫 번째 현장을 자동 선택하지 않음
        //
        // 사용자가 직접 선택하도록 함
        // ========================================
        _selectedProjectId = null;

        _selectedProjectName = null;

        _isLoadingProjects = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingProjects = false;
      });

      _showMessage(
        '현장 목록을 불러오지 못했습니다.',
      );
    }
  }

  // ============================================
  // 로그인
  // ============================================
  Future<void> _login() async {
    final String email =
        _idController.text.trim();

    final String password =
        _passwordController.text;

    FocusScope.of(context).unfocus();

    // ==========================================
    // 입력값 확인
    // ==========================================
    if (email.isEmpty ||
        password.isEmpty) {
      _showMessage(
        '아이디와 비밀번호를 입력해주세요.',
      );

      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage(
        '올바른 이메일 주소를 입력해주세요.',
      );

      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // ==========================================
      // Firebase Authentication 로그인
      // ==========================================
      final UserCredential credential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user =
          credential.user;

      if (user == null) {
        _showMessage(
          '사용자 정보를 확인할 수 없습니다.',
        );

        return;
      }

      // ==========================================
      // Firestore 사용자 정보 확인
      // ==========================================
      final DocumentSnapshot<Map<String, dynamic>>
          userDoc =
          await _firestore
              .collection('users')
              .doc(user.uid)
              .get();

      // ==========================================
      // 사용자 문서가 없는 경우
      // ==========================================
      if (!userDoc.exists) {
        await _auth.signOut();

        _showMessage(
          '사용자 정보를 찾을 수 없습니다.\n'
          '관리자에게 문의해주세요.',
        );

        return;
      }

      final Map<String, dynamic>? data =
          userDoc.data();

      // ==========================================
      // 승인 상태 확인
      // ==========================================
      final String status =
          data?['status']?.toString() ??
              'pending';

      if (status != 'approved') {
        await _auth.signOut();

        _showMessage(
          '아직 관리자 승인이 완료되지 않았습니다.',
        );

        return;
      }

      // ==========================================
      // 로그인 성공
      //
      // 역할과 관계없이 전부 AdminScreen으로 이동
      //
      // AdminScreen에서
      // - super_admin
      // - project_admin
      // - user
      //
      // 각각에게 필요한 메뉴를 보여줌
      // ==========================================
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const AdminScreen(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          message =
              '아이디 또는 비밀번호가 올바르지 않습니다.';
          break;

        case 'invalid-email':
          message =
              '올바른 이메일 주소를 입력해주세요.';
          break;

        case 'user-disabled':
          message =
              '정지된 계정입니다.\n'
              '관리자에게 문의해주세요.';
          break;

        case 'too-many-requests':
          message =
              '로그인 시도가 너무 많습니다.\n'
              '잠시 후 다시 시도해주세요.';
          break;

        default:
          message =
              '로그인 중 오류가 발생했습니다.\n'
              '${e.message ?? ''}';
      }

      _showMessage(message);
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        '로그인 중 오류가 발생했습니다.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================
  // 회원가입
  // ============================================
  Future<void> _signUp() async {
    final String email =
        _idController.text.trim();

    final String password =
        _passwordController.text;

    final String name =
        _nameController.text.trim();

    final String phone =
        _phoneController.text.trim();

    FocusScope.of(context).unfocus();

    // ==========================================
    // 현장 선택 확인
    // ==========================================
    if (_selectedProjectId == null) {
      _showMessage(
        '현장을 선택해주세요.',
      );

      return;
    }

    // ==========================================
    // 입력값 확인
    // ==========================================
    if (email.isEmpty ||
        password.isEmpty ||
        name.isEmpty ||
        phone.isEmpty) {
      _showMessage(
        '아이디, 비밀번호, 이름, 전화번호를 '
        '모두 입력해주세요.',
      );

      return;
    }

    if (!_isValidEmail(email)) {
      _showMessage(
        '올바른 이메일 주소를 입력해주세요.',
      );

      return;
    }

    if (password.length < 6) {
      _showMessage(
        '비밀번호는 6자 이상 입력해주세요.',
      );

      return;
    }

    if (!_isValidPhone(phone)) {
      _showMessage(
        '올바른 전화번호를 입력해주세요.',
      );

      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // ==========================================
      // Firebase Authentication 계정 생성
      // ==========================================
      final UserCredential credential =
          await _auth
              .createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user =
          credential.user;

      if (user == null) {
        _showMessage(
          '회원가입에 실패했습니다.',
        );

        return;
      }

      // ==========================================
      // Firebase Auth 프로필 이름 저장
      // ==========================================
      await user.updateDisplayName(name);

      // ==========================================
      // Firestore 사용자 정보 저장
      // ==========================================
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set({
        // ========================================
        // 기본 사용자 정보
        // ========================================
        'email': email,
        'name': name,
        'phone': phone,

        // ========================================
        // 관리자 승인 전
        // ========================================
        'status': 'pending',

        // ========================================
        // 기본 역할
        // ========================================
        'role': 'user',

        // ========================================
        // 승인된 프로젝트
        //
        // 관리자 승인 후 여기에 프로젝트 ID가
        // 들어감
        // ========================================
        'projects': [],

        // ========================================
        // 가입 신청한 프로젝트
        //
        // 해당 프로젝트 관리자에게
        // 가입 신청을 보여줄 때 사용
        // ========================================
        'requestedProjectId':
            _selectedProjectId,

        'requestedProjectName':
            _selectedProjectName,

        // ========================================
        // 가입 시간
        // ========================================
        'createdAt':
            FieldValue.serverTimestamp(),
      });

      // ==========================================
      // 회원가입 직후 로그아웃
      // ==========================================
      await _auth.signOut();

      if (!mounted) return;

      _showMessage(
        '회원가입 신청이 완료되었습니다.\n'
        '관리자 승인 후 로그인할 수 있습니다.',
      );

      // ==========================================
      // 로그인 화면으로 전환
      // ==========================================
      setState(() {
        _isSignUp = false;

        _idController.text = email;

        _passwordController.clear();

        _nameController.clear();

        _phoneController.clear();

        _selectedProjectId = null;

        _selectedProjectName = null;

        _obscurePassword = true;
      });

      // ==========================================
      // 비밀번호 입력칸 포커스
      // ==========================================
      WidgetsBinding.instance
          .addPostFrameCallback((_) {
        if (mounted) {
          _passwordFocusNode.requestFocus();
        }
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message =
              '이미 가입된 아이디입니다.';
          break;

        case 'invalid-email':
          message =
              '올바른 이메일 주소를 입력해주세요.';
          break;

        case 'weak-password':
          message =
              '비밀번호가 너무 간단합니다.';
          break;

        case 'operation-not-allowed':
          message =
              'Firebase에서 이메일/비밀번호 로그인이 '
              '활성화되어 있지 않습니다.';
          break;

        default:
          message =
              '회원가입 중 오류가 발생했습니다.\n'
              '${e.message ?? ''}';
      }

      _showMessage(message);
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        '회원가입 중 오류가 발생했습니다.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================
  // 이메일 형식 확인
  // ============================================
  bool _isValidEmail(String value) {
    return RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(value);
  }

  // ============================================
  // 전화번호 형식 확인
  // ============================================
  bool _isValidPhone(String value) {
    final String phone =
        value
            .replaceAll('-', '')
            .replaceAll(' ', '');

    return RegExp(
      r'^01[0-9]\d{7,8}$',
    ).hasMatch(phone);
  }

  // ============================================
  // 로그인 / 회원가입 전환
  // ============================================
  void _toggleMode() {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSignUp = !_isSignUp;

      _idController.clear();

      _passwordController.clear();

      _nameController.clear();

      _phoneController.clear();

      _selectedProjectId = null;

      _selectedProjectName = null;

      _obscurePassword = true;
    });

    // ==========================================
    // 회원가입 화면으로 들어갈 때
    // 프로젝트 목록이 아직 로딩 중이면
    // 그대로 기다림
    // ==========================================

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (mounted) {
        _idFocusNode.requestFocus();
      }
    });
  }

  // ============================================
  // 메시지
  // ============================================
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        duration:
            const Duration(seconds: 3),
      ),
    );
  }

  // ============================================
  // UI
  // ============================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(20),

          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,

            children: [

              // ==================================
              // 로고
              // ==================================
              const Text(
                'ISONow',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              // ==================================
              // 현재 화면
              // ==================================
              Text(
                _isSignUp
                    ? '회원가입'
                    : '로그인',

                style: const TextStyle(
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(height: 35),

              // ==================================
              // 회원가입일 때만 현장 선택
              // ==================================
              if (_isSignUp) ...[
                SizedBox(
                  width: 300,

                  child:
                      DropdownButtonFormField<
                          String>(
                    value:
                        _selectedProjectId,

                    isExpanded: true,

                    decoration:
                        const InputDecoration(
                      labelText: '현장',

                      border:
                          OutlineInputBorder(),

                      prefixIcon:
                          Icon(
                        Icons.business,
                      ),
                    ),

                    hint: const Text(
                      '현장을 선택해주세요',
                    ),

                    items:
                        _projects.map(
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
                        (_isLoading ||
                                _isLoadingProjects)
                            ? null
                            : (value) {
                                if (value ==
                                    null) {
                                  return;
                                }

                                final selected =
                                    _projects
                                        .firstWhere(
                                  (project) =>
                                      project['id']
                                          .toString() ==
                                      value,
                                );

                                setState(() {
                                  _selectedProjectId =
                                      value;

                                  _selectedProjectName =
                                      selected[
                                              'name']
                                          .toString();
                                });
                              },
                  ),
                ),

                const SizedBox(height: 20),
              ],

              // ==================================
              // 아이디
              // ==================================
              SizedBox(
                width: 300,

                child: TextField(
                  controller:
                      _idController,

                  focusNode:
                      _idFocusNode,

                  keyboardType:
                      TextInputType.emailAddress,

                  textInputAction:
                      TextInputAction.next,

                  enabled:
                      !_isLoading,

                  onSubmitted: (_) {
                    _passwordFocusNode
                        .requestFocus();
                  },

                  decoration:
                      const InputDecoration(
                    labelText:
                        '아이디 (이메일)',

                    hintText:
                        'example@email.com',

                    border:
                        OutlineInputBorder(),

                    prefixIcon:
                        Icon(
                      Icons.person,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ==================================
              // 비밀번호
              // ==================================
              SizedBox(
                width: 300,

                child: TextField(
                  controller:
                      _passwordController,

                  focusNode:
                      _passwordFocusNode,

                  obscureText:
                      _obscurePassword,

                  textInputAction:
                      _isSignUp
                          ? TextInputAction.next
                          : TextInputAction.done,

                  enabled:
                      !_isLoading,

                  onSubmitted: (_) {
                    if (_isSignUp) {
                      _nameFocusNode
                          .requestFocus();
                    } else {
                      _login();
                    }
                  },

                  decoration:
                      InputDecoration(
                    labelText:
                        '비밀번호',

                    border:
                        const OutlineInputBorder(),

                    prefixIcon:
                        const Icon(
                      Icons.lock,
                    ),

                    suffixIcon:
                        IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons
                                .visibility_off
                            : Icons
                                .visibility,
                      ),

                      onPressed:
                          _isLoading
                              ? null
                              : () {
                                  setState(() {
                                    _obscurePassword =
                                        !_obscurePassword;
                                  });
                                },
                    ),
                  ),
                ),
              ),

              // ==================================
              // 회원가입 추가 입력
              // ==================================
              if (_isSignUp) ...[
                const SizedBox(height: 20),

                // ================================
                // 이름
                // ================================
                SizedBox(
                  width: 300,

                  child: TextField(
                    controller:
                        _nameController,

                    focusNode:
                        _nameFocusNode,

                    textInputAction:
                        TextInputAction.next,

                    enabled:
                        !_isLoading,

                    onSubmitted: (_) {
                      _phoneFocusNode
                          .requestFocus();
                    },

                    decoration:
                        const InputDecoration(
                      labelText: '실명',

                      border:
                          OutlineInputBorder(),

                      prefixIcon:
                          Icon(
                        Icons.badge,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ================================
                // 전화번호
                // ================================
                SizedBox(
                  width: 300,

                  child: TextField(
                    controller:
                        _phoneController,

                    focusNode:
                        _phoneFocusNode,

                    keyboardType:
                        TextInputType.phone,

                    textInputAction:
                        TextInputAction.done,

                    enabled:
                        !_isLoading,

                    onSubmitted: (_) {
                      _signUp();
                    },

                    decoration:
                        const InputDecoration(
                      labelText:
                          '전화번호',

                      hintText:
                          '010-1234-5678',

                      border:
                          OutlineInputBorder(),

                      prefixIcon:
                          Icon(
                        Icons.phone,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 30),

              // ==================================
              // 로그인 / 회원가입 버튼
              // ==================================
              SizedBox(
                width: 300,
                height: 50,

                child:
                    ElevatedButton(
                  onPressed:
                      _isLoading ||
                              (_isSignUp &&
                                  _isLoadingProjects)
                          ? null
                          : (_isSignUp
                              ? _signUp
                              : _login),

                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,

                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isSignUp
                              ? '회원가입'
                              : '로그인',

                          style:
                              const TextStyle(
                            fontSize: 16,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 15),

              // ==================================
              // 로그인 / 회원가입 전환
              // ==================================
              TextButton(
                onPressed:
                    _isLoading
                        ? null
                        : _toggleMode,

                child: Text(
                  _isSignUp
                      ? '이미 계정이 있으신가요? 로그인'
                      : '계정이 없으신가요? 회원가입',
                ),
              ),

              const SizedBox(height: 20),

              // ==================================
              // 회원가입 안내
              // ==================================
              if (_isSignUp)
                const SizedBox(
                  width: 300,

                  child: Text(
                    '현장을 선택하여 가입 신청하면\n'
                    '해당 현장 관리자의 승인 후 '
                    '로그인할 수 있습니다.',

                    textAlign:
                        TextAlign.center,

                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ),

              // ==================================
              // 현장 목록 로딩
              // ==================================
              if (_isSignUp &&
                  _isLoadingProjects)
                const Padding(
                  padding:
                      EdgeInsets.only(
                    top: 15,
                  ),

                  child: Text(
                    '현장 목록을 불러오는 중...',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ),

              // ==================================
              // 활성화된 현장이 없는 경우
              // ==================================
              if (_isSignUp &&
                  !_isLoadingProjects &&
                  _projects.isEmpty)
                const Padding(
                  padding:
                      EdgeInsets.only(
                    top: 15,
                  ),

                  child: Text(
                    '현재 가입 가능한 현장이 없습니다.',
                    textAlign:
                        TextAlign.center,

                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}