import 'package:flutter/material.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ============================================
  // 임시 회원정보
  // 앱 실행 중에만 유지됨
  // ============================================
  final Map<String, Map<String, String>> _users = {};

  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  final FocusNode _idFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _nameFocusNode = FocusNode();

  bool _isSignUp = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _nameController.dispose();

    _idFocusNode.dispose();
    _passwordFocusNode.dispose();
    _nameFocusNode.dispose();

    super.dispose();
  }

  // ============================================
  // 로그인
  // ============================================
  void _login() {
    final id = _idController.text.trim();
    final password = _passwordController.text;

    FocusScope.of(context).unfocus();

    if (id.isEmpty || password.isEmpty) {
      _showMessage('아이디와 비밀번호를 입력해주세요.');
      return;
    }

    // 테스트 관리자 계정
    if (id == 'admin' && password == '1234') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const HomeScreen(),
        ),
      );
      return;
    }

    // 회원가입한 계정
    if (_users.containsKey(id) &&
        _users[id]!['password'] == password) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const HomeScreen(),
        ),
      );
      return;
    }

    _showMessage('아이디 또는 비밀번호가 올바르지 않습니다.');
  }

  // ============================================
  // 회원가입
  // ============================================
  void _signUp() {
    final id = _idController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    FocusScope.of(context).unfocus();

    if (id.isEmpty || password.isEmpty || name.isEmpty) {
      _showMessage('아이디, 비밀번호, 이름을 모두 입력해주세요.');
      return;
    }

    if (_users.containsKey(id) || id == 'admin') {
      _showMessage('이미 존재하는 아이디입니다.');
      return;
    }

    // 회원정보 저장
    _users[id] = {
      'password': password,
      'name': name,
    };

    _showMessage('회원가입이 완료되었습니다.');

    // 로그인 화면으로 이동
    setState(() {
      _isSignUp = false;

      _idController.text = id;
      _passwordController.clear();
      _nameController.clear();

      _obscurePassword = true;
    });

    // 로그인 화면의 비밀번호 입력칸에 자동 포커스
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _passwordFocusNode.requestFocus();
      }
    });
  }

  // ============================================
  // 로그인 / 회원가입 화면 전환
  // ============================================
  void _toggleMode() {
    FocusScope.of(context).unfocus();

    setState(() {
      _isSignUp = !_isSignUp;

      _idController.clear();
      _passwordController.clear();
      _nameController.clear();

      _obscurePassword = true;
    });

    // 화면 전환 후 아이디 칸에 포커스
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _idFocusNode.requestFocus();
      }
    });
  }

  // ============================================
  // 메시지
  // ============================================
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
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
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 로고
              const Text(
                'ISONow',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              // 현재 화면
              Text(
                _isSignUp ? '회원가입' : '로그인',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 40),

              // ========================================
              // 아이디
              // ========================================
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _idController,
                  focusNode: _idFocusNode,
                  textInputAction:
                      TextInputAction.next,
                  onSubmitted: (_) {
                    _passwordFocusNode.requestFocus();
                  },
                  decoration: const InputDecoration(
                    labelText: '아이디',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ========================================
              // 비밀번호
              // ========================================
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  obscureText: _obscurePassword,
                  textInputAction: _isSignUp
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onSubmitted: (_) {
                    if (_isSignUp) {
                      _nameFocusNode.requestFocus();
                    } else {
                      _login();
                    }
                  },
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    border: const OutlineInputBorder(),
                    prefixIcon:
                        const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword =
                              !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
              ),

              // ========================================
              // 이름
              // ========================================
              if (_isSignUp) ...[
                const SizedBox(height: 20),

                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    textInputAction:
                        TextInputAction.done,
                    onSubmitted: (_) {
                      _signUp();
                    },
                    decoration:
                        const InputDecoration(
                      labelText: '이름',
                      border: OutlineInputBorder(),
                      prefixIcon:
                          Icon(Icons.badge),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 30),

              // ========================================
              // 로그인 / 회원가입 버튼
              // ========================================
              SizedBox(
                width: 300,
                height: 50,
                child: ElevatedButton(
                  onPressed:
                      _isSignUp ? _signUp : _login,
                  child: Text(
                    _isSignUp
                        ? '회원가입'
                        : '로그인',
                    style: const TextStyle(
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // ========================================
              // 화면 전환
              // ========================================
              TextButton(
                onPressed: _toggleMode,
                child: Text(
                  _isSignUp
                      ? '이미 계정이 있으신가요? 로그인'
                      : '계정이 없으신가요? 회원가입',
                ),
              ),

              const SizedBox(height: 20),

              // 테스트 계정
              if (!_isSignUp)
                const Text(
                  '테스트 계정\nID: admin / PW: 1234',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}