import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/household.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_providers.dart';
import '../../providers/service_providers.dart';
import '../../services/device_settings_service.dart';
import '../../services/household_service.dart';
import 'manual_item_history_screen.dart';
import 'staples_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _regenerateCode(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generere ny kode?'),
        content: const Text('Den gamle invitasjonskoden slutter å virke.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Generer')),
        ],
      ),
    );
    if (confirmed != true) return;
    final householdId = ref.read(currentHouseholdProvider).value?.id;
    if (householdId == null) return;
    try {
      await ref.read(householdServiceProvider).regenerateInviteCode(householdId);
    } on HouseholdException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Klarte ikke å generere ny kode: $e')));
      }
    }
  }

  Future<void> _copyCode(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Koden er kopiert.')));
    }
  }

  Future<void> _leaveHousehold(BuildContext context, WidgetRef ref, String householdId, String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forlate husholdningen?'),
        content: const Text(
          'Du mister tilgangen til husholdningens middagsplan, handleliste og eget oppskriftssett. '
          'Du kan bli med igjen senere med en invitasjonskode.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Forlat')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(householdServiceProvider).leaveHousehold(householdId, uid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Klarte ikke å forlate husholdningen: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(currentHouseholdProvider).value;
    final profile = ref.watch(userProfileProvider).value;
    final isCreator = profile != null && household != null && household.createdBy == profile.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Innstillinger')),
      body: ListView(
        children: [
          if (profile != null)
            ListTile(
              leading: profile.photoUrl != null ? CircleAvatar(backgroundImage: NetworkImage(profile.photoUrl!)) : const CircleAvatar(child: Icon(Icons.person)),
              title: Text(profile.displayName),
              subtitle: Text(profile.email),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Personlig', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            title: const Text('Hold skjermen på i (minutter)'),
            subtitle: const Text(
              'Brukes når du krysser av «Hold skjermen på» inne på en oppskrift. Gjelder kun denne enheten.',
            ),
            trailing: const _WakeLockMinutesStepper(),
          ),
          const Divider(),
          if (household != null) ...[
            ListTile(
              title: const Text('Husholdning'),
              subtitle: Text(household.name),
            ),
            ListTile(
              title: const Text('Invitasjonskode'),
              subtitle: Text(household.inviteCode, style: const TextStyle(fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.bold)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.copy), onPressed: () => _copyCode(context, household.inviteCode)),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: () => _regenerateCode(context, ref)),
                ],
              ),
            ),
            ListTile(
              title: const Text('Standard antall personer å handle til'),
              subtitle: const Text('Brukes som forhåndsvalg når du legger en middag i planen.'),
              trailing: _ServingsStepper(
                value: household.defaultServings,
                onChanged: (v) => ref.read(householdServiceProvider).updateDefaultServings(household.id, v),
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Medlemmer', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            _MembersList(household: household),
            if (isCreator) ...[
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Ventende forespørsler', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              _PendingRequestsList(householdId: household.id),
            ],
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Skjul oppskriftstyper som standard', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Gjelder oversiktene i Oppskrifter. Du kan fortsatt hente fram en skjult type via filter-knappen der.',
              ),
            ),
            for (final type in RecipeType.values)
              CheckboxListTile(
                title: Text(type.displayName),
                value: household.hiddenRecipeTypes.contains(type),
                onChanged: (checked) {
                  final updated = {...household.hiddenRecipeTypes};
                  if (checked ?? false) {
                    updated.add(type);
                  } else {
                    updated.remove(type);
                  }
                  ref.read(householdServiceProvider).updateHiddenRecipeTypes(household.id, updated);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Varehistorikk'),
              subtitle: const Text('Se, rediger eller fjern varer som foreslås i handlelisten.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ManualItemHistoryScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.kitchen_outlined),
              title: const Text('Standardvarer'),
              subtitle: const Text('Varer dere alltid har i hyllen (salt, pepper …) — utelates fra handlelisten.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StaplesScreen()),
              ),
            ),
            const Divider(),
            if (profile != null)
              ListTile(
                leading: const Icon(Icons.exit_to_app),
                title: const Text('Forlat husholdning'),
                onTap: () => _leaveHousehold(context, ref, household.id, profile.uid),
              ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logg ut'),
            onTap: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
    );
  }
}

class _MembersList extends ConsumerWidget {
  const _MembersList({required this.household});

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersState = ref.watch(householdMembersProvider);
    return membersState.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
      error: (e, st) => Padding(padding: const EdgeInsets.all(16), child: Text('Noe gikk galt: $e')),
      data: (members) => Column(
        children: [
          for (final member in members)
            ListTile(
              leading: member.photoUrl != null
                  ? CircleAvatar(backgroundImage: NetworkImage(member.photoUrl!))
                  : const CircleAvatar(child: Icon(Icons.person)),
              title: Text(member.displayName),
              subtitle: Text(member.email),
              trailing: member.uid == household.createdBy
                  ? const Chip(label: Text('Oppretter'), visualDensity: VisualDensity.compact)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _PendingRequestsList extends ConsumerWidget {
  const _PendingRequestsList({required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsState = ref.watch(pendingJoinRequestProfilesProvider);
    return requestsState.when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
      error: (e, st) => Padding(padding: const EdgeInsets.all(16), child: Text('Noe gikk galt: $e')),
      data: (requests) {
        if (requests.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Ingen ventende forespørsler.'),
          );
        }
        return Column(
          children: [
            for (final requester in requests) _PendingRequestTile(householdId: householdId, requester: requester),
          ],
        );
      },
    );
  }
}

class _PendingRequestTile extends ConsumerWidget {
  const _PendingRequestTile({required this.householdId, required this.requester});

  final String householdId;
  final UserProfile requester;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: requester.photoUrl != null
          ? CircleAvatar(backgroundImage: NetworkImage(requester.photoUrl!))
          : const CircleAvatar(child: Icon(Icons.person)),
      title: Text(requester.displayName),
      subtitle: Text(requester.email),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            tooltip: 'Godkjenn',
            onPressed: () => ref.read(householdServiceProvider).approveJoinRequest(householdId, requester.uid),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: 'Avvis',
            onPressed: () => ref.read(householdServiceProvider).rejectJoinRequest(householdId, requester.uid),
          ),
        ],
      ),
    );
  }
}

class _WakeLockMinutesStepper extends ConsumerWidget {
  const _WakeLockMinutesStepper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(wakeLockMinutesProvider).value ?? DeviceSettingsService.defaultWakeLockMinutes;

    Future<void> update(int value) async {
      await ref.read(deviceSettingsServiceProvider).setWakeLockMinutes(value);
      ref.invalidate(wakeLockMinutesProvider);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: minutes > 1 ? () => update(minutes - 1) : null,
        ),
        Text('$minutes'),
        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => update(minutes + 1)),
      ],
    );
  }
}

class _ServingsStepper extends StatelessWidget {
  const _ServingsStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: value > 1 ? () => onChanged(value - 1) : null),
        Text('$value'),
        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => onChanged(value + 1)),
      ],
    );
  }
}
