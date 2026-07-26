import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../models/household.dart';
import '../../models/shopping_list.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/shopping_lists_providers.dart';
import '../../services/device_settings_service.dart';
import '../../services/household_service.dart';
import '../../services/shopping_lists_service.dart';
import '../../widgets/list_color_swatch.dart';
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

  void _selectList(WidgetRef ref, String listId) {
    ref.read(selectedListIdProvider.notifier).select(listId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(currentHouseholdProvider).value;
    final profile = ref.watch(userProfileProvider).value;
    final isCreator = profile != null && household != null && household.createdBy == profile.uid;
    final lists = ref.watch(shoppingListsProvider).value ?? const <ShoppingList>[];
    final currentList = ref.watch(currentListProvider);

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
            const Divider(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Handlelister', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final list in lists)
              ListTile(
                leading: ListColorDot(color: list.color),
                title: Text(list.name),
                selected: currentList?.id == list.id,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentList?.id == list.id)
                      const Icon(Icons.check, color: Colors.green)
                    else
                      const SizedBox(width: 24),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Rediger liste',
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _EditListDialog(
                          householdId: household.id,
                          list: list,
                          canDelete: lists.length > 1,
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () => _selectList(ref, list.id),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Ny liste'),
              onTap: () => showDialog(
                context: context,
                builder: (_) => _CreateListDialog(householdId: household.id),
              ),
            ),
            if (currentList != null)
              ListTile(
                title: const Text('Standard antall personer å handle til'),
                subtitle: Text(
                  lists.length > 1
                      ? 'For «${currentList.name}». Brukes som forhåndsvalg når du legger en middag i planen.'
                      : 'Brukes som forhåndsvalg når du legger en middag i planen.',
                ),
                trailing: _ServingsStepper(
                  value: currentList.defaultServings,
                  onChanged: (v) => ref
                      .read(shoppingListsServiceProvider)
                      .updateDefaultServings(household.id, currentList.id, v),
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
              subtitle: Text(
                lists.length > 1
                    ? 'Varer «${currentList?.name}» alltid har i hyllen (salt, pepper …) — utelates fra handlelisten.'
                    : 'Varer dere alltid har i hyllen (salt, pepper …) — utelates fra handlelisten.',
              ),
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

/// Fargevalg gjenbrukt av opprett- og rediger-dialogen for handlelister.
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onChanged});

  final ListColor selected;
  final ValueChanged<ListColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final color in ListColor.values)
          ChoiceChip(
            avatar: ListColorDot(color: color),
            label: Text(color.displayName),
            selected: selected == color,
            onSelected: (_) => onChanged(color),
          ),
      ],
    );
  }
}

class _CreateListDialog extends ConsumerStatefulWidget {
  const _CreateListDialog({required this.householdId});

  final String householdId;

  @override
  ConsumerState<_CreateListDialog> createState() => _CreateListDialogState();
}

class _CreateListDialogState extends ConsumerState<_CreateListDialog> {
  final _nameController = TextEditingController();
  ListColor _color = ListColor.gronn;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final listId = await ref
          .read(shoppingListsServiceProvider)
          .createList(widget.householdId, name: name, color: _color);
      ref.read(selectedListIdProvider.notifier).select(listId);
      if (mounted) Navigator.of(context).pop();
    } on ShoppingListsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ny handleliste'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Navn (f.eks. «Hytta»)', border: OutlineInputBorder()),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          _ColorPicker(selected: _color, onChanged: (c) => setState(() => _color = c)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Avbryt')),
        FilledButton(onPressed: _saving ? null : _create, child: const Text('Opprett')),
      ],
    );
  }
}

class _EditListDialog extends ConsumerStatefulWidget {
  const _EditListDialog({required this.householdId, required this.list, required this.canDelete});

  final String householdId;
  final ShoppingList list;
  final bool canDelete;

  @override
  ConsumerState<_EditListDialog> createState() => _EditListDialogState();
}

class _EditListDialogState extends ConsumerState<_EditListDialog> {
  late final _nameController = TextEditingController(text: widget.list.name);
  late ListColor _color = widget.list.color;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final service = ref.read(shoppingListsServiceProvider);
    await service.renameList(widget.householdId, widget.list.id, name);
    if (_color != widget.list.color) {
      await service.updateColor(widget.householdId, widget.list.id, _color);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Slette handlelisten?'),
        content: Text(
          '«${widget.list.name}» og hele middagsplanen/handlelisten dens blir slettet. Dette kan ikke angres.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Slett')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(shoppingListsServiceProvider).deleteList(widget.householdId, widget.list.id);
      if (mounted) Navigator.of(context).pop();
    } on ShoppingListsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rediger handleliste'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Navn', border: OutlineInputBorder()),
            autofocus: true,
          ),
          const SizedBox(height: 16),
          _ColorPicker(selected: _color, onChanged: (c) => setState(() => _color = c)),
        ],
      ),
      actions: [
        if (widget.canDelete)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Slett'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Avbryt')),
        FilledButton(onPressed: _save, child: const Text('Lagre')),
      ],
    );
  }
}
