import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/service_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Innlogging feilet: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.restaurant_menu, size: 96, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('Appskrifter', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text(
                  'Middagsoppskrifter og handlelister for hele husholdningen',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                if (_loading)
                  const CircularProgressIndicator()
                else
                  FilledButton.icon(
                    onPressed: _signIn,
                    icon: const Icon(Icons.login),
                    label: const Text('Logg inn med Google'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
