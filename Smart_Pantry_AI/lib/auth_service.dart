import 'package:firebase_auth/firebase_auth.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'screens.dart';
import 'storage_service.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<UserCredential> signUp({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<void> sendPasswordResetEmail({required String email}) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  static Future<void> signOut() => _auth.signOut();
}

class AuthGate extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AuthGate({
    super.key,
    required this.cameras,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _hasMigrated = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user != null && !_hasMigrated) {
          _hasMigrated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await StorageService.migrateLocalDataToFirestore();
          });
        }

        if (user == null) {
          _hasMigrated = false;
          return const AuthScreen();
        }

        return PantryPulseHomePage(cameras: widget.cameras);
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isSignUp = false;
  bool isLoading = false;
  String? errorMessage;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      if (isSignUp) {
        await AuthService.signUp(
          email: emailController.text,
          password: passwordController.text,
        );
      } else {
        await AuthService.signIn(
          email: emailController.text,
          password: passwordController.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          errorMessage = error.message ?? 'Authentication failed.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          errorMessage = 'Could not connect to Firebase.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> resetPassword() async {
    final resetEmailController = TextEditingController(text: emailController.text.trim());
    String? dialogError;
    var sending = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendResetEmail() async {
              final email = resetEmailController.text.trim();
              final isValidEmail = RegExp(
                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
              ).hasMatch(email);

              if (!isValidEmail) {
                setDialogState(() => dialogError = 'Enter a valid email address.');
                return;
              }

              setDialogState(() {
                sending = true;
                dialogError = null;
              });

              try {
                await AuthService.sendPasswordResetEmail(email: email);
                if (dialogContext.mounted && mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('Password reset link has been sent to your email.'),
                    ),
                  );
                }
              } on FirebaseAuthException catch (error) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    sending = false;
                    dialogError = _passwordResetError(error);
                  });
                }
              } catch (_) {
                if (dialogContext.mounted) {
                  setDialogState(() {
                    sending = false;
                    dialogError = 'Could not connect to Firebase.';
                  });
                }
              }
            }

            return AlertDialog(
              title: const Text('Forgot Password?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter your registered email address.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: resetEmailController,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      dialogError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: sending ? null : sendResetEmail,
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Link'),
                ),
              ],
            );
          },
        );
      },
    );

    resetEmailController.dispose();
  }

  String _passwordResetError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-not-found':
        return 'We could not find an account for this email.';
      case 'network-request-failed':
        return 'Check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Could not send the password reset email.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pantry Pulse')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                isSignUp ? 'Create your account' : 'Welcome back',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLoading ? null : submit,
                  child: Text(isSignUp ? 'SIGN UP' : 'LOG IN'),
                ),
              ),
              if (!isSignUp)
                TextButton(
                  onPressed: isLoading ? null : resetPassword,
                  child: const Text('Forgot password?'),
                ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => setState(() {
                          isSignUp = !isSignUp;
                          errorMessage = null;
                        }),
                child: Text(
                  isSignUp
                      ? 'Already have an account? Log in'
                      : 'New user? Create an account',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}