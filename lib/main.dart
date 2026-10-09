import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/login_page.dart';
import 'features/reader/presentation/pages/home_page.dart';
import 'features/update/update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase before running the app. 
  // IMPORTANT: Replace these with your actual Supabase project URL and anon key.
  await Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL', 
      defaultValue: 'https://tijothriztjcasnvcxjr.supabase.co'
    ),
    anonKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY', 
      defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRpam90aHJpenRqY2FzbnZjeGpyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEwODk5NTYsImV4cCI6MjEwNjY2NTk1Nn0.Wg9Gd0LsMmQAx8GVz6wZC9Payd0lSteHzweKXzTFmhI'
    ),
  );

  runApp(const DigitalPothGulaApp());
}

class DigitalPothGulaApp extends StatelessWidget {
  const DigitalPothGulaApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital පොත් පියස',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AuthGuard(),
    );
  }
}

class AuthGuard extends StatefulWidget {
  const AuthGuard({super.key});

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuth();
    });
  }

  Future<void> _checkAuth() async {
    final isMandatoryUpdate = await UpdateService.checkForUpdates(context);
    if (isMandatoryUpdate) {
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginPage()));
      }
      return;
    }

    final LocalAuthentication auth = LocalAuthentication();
    bool authenticated = false;
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (canAuthenticate) {
        authenticated = await auth.authenticate(
          localizedReason: 'Please authenticate to access your books',
        );
      } else {
        authenticated = true;
      }
    } on PlatformException catch (e) {
      debugPrint('Error using biometrics: $e');
    }

    if (mounted) {
      if (authenticated) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomePage()));
      } else {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginPage()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
