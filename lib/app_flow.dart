import 'package:flutter/material.dart';

import 'aws_waste_repository.dart';
import 'home_dashboard.dart';
import 'app_preferences.dart';

class EcoSortFlow extends StatefulWidget {
  const EcoSortFlow({super.key, required this.repository});

  final WasteRepository repository;

  @override
  State<EcoSortFlow> createState() => _EcoSortFlowState();
}

class _EcoSortFlowState extends State<EcoSortFlow> {
  _AppStage _stage = _AppStage.welcome;

  @override
  Widget build(BuildContext context) => switch (_stage) {
    _AppStage.welcome => WelcomeScreen(
      onGetStarted: () => setState(
        () => _stage = appPreferences.session
            ? _AppStage.dashboard
            : _AppStage.login,
      ),
    ),
    _AppStage.login => LoginScreen(
      onSignedIn: () async {
        await appPreferences.setSession(true);
        if (mounted) setState(() => _stage = _AppStage.dashboard);
      },
    ),
    _AppStage.dashboard => HomeDashboard(
      repository: widget.repository,
      onLogout: () async {
        await appPreferences.setSession(false);
        if (mounted) setState(() => _stage = _AppStage.login);
      },
    ),
  };
}

enum _AppStage { welcome, login, dashboard }

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D5137), Color(0xFF12613E), Color(0xFF249653)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(30, 28, 30, 34),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 62,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Spacer(flex: 2),
                      Center(child: _EcoMark(size: 170, light: true)),
                      Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(
                          'Powered by AI and machine learning',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(height: 28),
                      Text(
                        'AIML Driven\nWaste Intelligence\nSystem',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.8,
                        ),
                      ),
                      SizedBox(height: 18),
                      Text(
                        'Smart bins that see, sort and report every item, so waste becomes data.',
                        style: TextStyle(
                          color: Color(0xFFD6E8DD),
                          fontSize: 17,
                          height: 1.45,
                        ),
                      ),
                      Spacer(flex: 2),
                      FilledButton(
                        key: Key('get_started_button'),
                        onPressed: onGetStarted,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.lime,
                          minimumSize: Size.fromHeight(68),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(36),
                          ),
                        ),
                        child: FittedBox(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Get started',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(width: 34),
                              Icon(Icons.arrow_forward_rounded, size: 30),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) widget.onSignedIn();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(28, 50, 28, 30),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _EcoMark(size: 110),
              SizedBox(height: 22),
              Text(
                'EcoSort AI',
                style: TextStyle(
                  fontSize: 35,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Smart waste intelligence system',
                style: TextStyle(fontSize: 16, color: AppColors.muted),
              ),
              SizedBox(height: 42),
              Container(
                padding: EdgeInsets.all(24),
                decoration: _loginCard(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Local device sign-in to monitor your smart bin',
                      style: TextStyle(color: AppColors.muted, fontSize: 15),
                    ),
                    SizedBox(height: 28),
                    Text(
                      'Email',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _fieldDecoration('name@example.com'),
                      validator: (v) => (v ?? '').contains('@')
                          ? null
                          : 'Enter a valid email',
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Password',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      decoration: _fieldDecoration('Password').copyWith(
                        suffixIcon: TextButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          child: Text(_obscurePassword ? 'Show' : 'Hide'),
                        ),
                      ),
                      validator: (v) => (v ?? '').length >= 4
                          ? null
                          : 'Use at least 4 characters',
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Password recovery will be available after authentication is connected.',
                            ),
                          ),
                        ),
                        child: Text('Forgot password?'),
                      ),
                    ),
                    SizedBox(height: 8),
                    FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      child: Text(
                        'Sign in',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Google sign-in is not connected yet. Use the local device sign-in.',
                          ),
                        ),
                      ),
                      icon: Icon(Icons.g_mobiledata_rounded, size: 28),
                      label: Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.fromHeight(54),
                        side: BorderSide(color: AppColors.cardBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
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
    ),
  );
}

class _EcoMark extends StatelessWidget {
  const _EcoMark({required this.size, this.light = false});
  final double size;
  final bool light;
  @override
  Widget build(BuildContext context) => Container(
    height: size,
    width: size,
    decoration: BoxDecoration(
      color: light ? Color(0xFF2EAA58) : AppColors.green,
      borderRadius: BorderRadius.circular(size * .25),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .13),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: size * .55,
        ),
        Positioned(
          top: size * .16,
          right: size * .16,
          child: Icon(
            Icons.energy_savings_leaf_rounded,
            color: Color(0xFFDDF4D9),
            size: size * .24,
          ),
        ),
      ],
    ),
  );
}

InputDecoration _fieldDecoration(String hint) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: AppColors.cardDeep,
  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 17),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: AppColors.cardBorder),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: AppColors.cardBorder),
  ),
);

BoxDecoration _loginCard() => BoxDecoration(
  color: AppColors.card,
  borderRadius: BorderRadius.circular(28),
  border: Border.all(color: AppColors.cardBorder),
  boxShadow: [
    BoxShadow(color: Color(0x12000000), blurRadius: 25, offset: Offset(0, 10)),
  ],
);
