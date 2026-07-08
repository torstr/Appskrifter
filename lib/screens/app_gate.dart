import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import '../providers/service_providers.dart';
import 'auth/login_screen.dart';
import 'home_shell.dart';
import 'household/household_setup_screen.dart';

/// Styrer hvilken toppnivå-skjerm brukeren skal se, basert på innloggings-
/// og husholdningsstatus:
/// ikke innlogget -> logg inn -> opprett/bli med i husholdning -> hovedapp.
class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const _Splash(),
      error: (error, stack) => _ErrorScreen(message: '$error'),
      data: (user) {
        if (user == null) return const LoginScreen();

        final profileState = ref.watch(userProfileProvider);
        return profileState.when(
          loading: () => const _Splash(),
          error: (error, stack) => _ErrorScreen(message: '$error'),
          data: (profile) {
            if (profile == null) return const _Splash();
            final householdId = profile.householdId;
            if (householdId == null) {
              return _HouseholdEntryGate(uid: user.uid);
            }
            // Bekreft at profilens householdId faktisk har et tilhørende
            // medlemskap, ikke bare stol på feltet alene — det kan bli
            // stående «foreldreløst» hvis leaveHousehold ble avbrutt midt i
            // sine to sekvensielle skriv (se HouseholdService.leaveHousehold).
            final membership = ref.watch(
              householdMembershipVerifiedProvider((householdId: householdId, uid: user.uid)),
            );
            return membership.when(
              loading: () => const _Splash(),
              // Ved f.eks. en forbigående nettverksfeil: ikke lås brukeren
              // ute av hovedappen — la skjermene der vise sine egne feil.
              error: (error, stack) => const HomeShell(),
              data: (isMember) {
                if (!isMember) {
                  ref.read(householdServiceProvider).clearOrphanedHouseholdId(user.uid);
                  return const _Splash();
                }
                return const HomeShell();
              },
            );
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Vises når brukeren ikke har `householdId` på profilen. Sjekker først om
/// de allerede er godkjent som medlem et sted (medlemskapsdokument uten at
/// profilen er koblet), og fullfører i så fall «bli med»-flyten automatisk.
class _HouseholdEntryGate extends ConsumerStatefulWidget {
  const _HouseholdEntryGate({required this.uid});

  final String uid;

  @override
  ConsumerState<_HouseholdEntryGate> createState() => _HouseholdEntryGateState();
}

class _HouseholdEntryGateState extends ConsumerState<_HouseholdEntryGate> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _recoverApprovedMembership();
  }

  Future<void> _recoverApprovedMembership() async {
    try {
      final householdService = ref.read(householdServiceProvider);
      final householdId = await householdService.findMembershipHouseholdId(widget.uid);
      if (householdId != null) {
        await householdService.finalizeJoin(householdId, widget.uid);
      }
    } catch (_) {
      // Vis oppsettsskjermen — brukeren kan prøve igjen der.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const _Splash();
    return const HouseholdSetupScreen();
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Noe gikk galt: $message', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
