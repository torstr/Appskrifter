import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/service_providers.dart';
import '../../services/household_service.dart';

/// Vises for en innlogget bruker som ikke er medlem av noen husholdning ennå.
/// Brukeren kan enten opprette en ny husholdning, eller sende en forespørsel
/// om å bli med i en eksisterende via en invitasjonskode — forespørselen må
/// godkjennes av husholdningens oppretter før man faktisk blir medlem.
class HouseholdSetupScreen extends ConsumerStatefulWidget {
  const HouseholdSetupScreen({super.key});

  @override
  ConsumerState<HouseholdSetupScreen> createState() => _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends ConsumerState<HouseholdSetupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _createNameController = TextEditingController();
  final _joinCodeController = TextEditingController();
  bool _loading = false;
  JoinRequestSubmitted? _pendingRequest;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _createNameController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _createHousehold() async {
    final name = _createNameController.text.trim();
    if (name.isEmpty) return;
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(householdServiceProvider).createHousehold(name, uid);
    } on HouseholdException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Klarte ikke å opprette husholdningen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitJoinRequest() async {
    final code = _joinCodeController.text.trim();
    if (code.isEmpty) return;
    final uid = ref.read(authStateProvider).value?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final result = await ref.read(householdServiceProvider).submitJoinRequest(code, uid);
      if (mounted) setState(() => _pendingRequest = result);
    } on HouseholdException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Klarte ikke å sende forespørselen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingRequest;
    if (pending != null) {
      return _WaitingForApprovalView(
        request: pending,
        onGiveUp: () => setState(() => _pendingRequest = null),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kom i gang'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Opprett husholdning'),
            Tab(text: 'Bli med via kode'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCreateTab(),
          _buildJoinTab(),
        ],
      ),
    );
  }

  Widget _buildCreateTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Opprett en ny husholdning. Du får en kode du kan dele med resten av familien.'),
          const SizedBox(height: 16),
          TextField(
            controller: _createNameController,
            decoration: const InputDecoration(
              labelText: 'Navn på husholdning',
              hintText: 'F.eks. «Familien Hansen»',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton(onPressed: _createHousehold, child: const Text('Opprett')),
        ],
      ),
    );
  }

  Widget _buildJoinTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Skriv inn invitasjonskoden du har fått fra et husholdningsmedlem. Husholdningens '
            'oppretter må godkjenne deg før du får tilgang.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _joinCodeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Invitasjonskode',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            FilledButton(onPressed: _submitJoinRequest, child: const Text('Send forespørsel')),
        ],
      ),
    );
  }
}

class _WaitingForApprovalView extends ConsumerStatefulWidget {
  const _WaitingForApprovalView({required this.request, required this.onGiveUp});

  final JoinRequestSubmitted request;
  final VoidCallback onGiveUp;

  @override
  ConsumerState<_WaitingForApprovalView> createState() => _WaitingForApprovalViewState();
}

class _WaitingForApprovalViewState extends ConsumerState<_WaitingForApprovalView> {
  bool _finalizeStarted = false;

  void _finalizeOnce(String uid, HouseholdService householdService) {
    if (_finalizeStarted) return;
    _finalizeStarted = true;
    householdService.finalizeJoin(widget.request.householdId, uid);
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authStateProvider).value?.uid;
    final householdService = ref.watch(householdServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Venter på godkjenning')),
      body: uid == null
          ? const SizedBox.shrink()
          : StreamBuilder<bool>(
              stream: householdService.isMemberStream(widget.request.householdId, uid),
              builder: (context, memberSnapshot) {
                final isMember = memberSnapshot.data ?? false;
                if (isMember) {
                  _finalizeOnce(uid, householdService);
                  return const Center(child: CircularProgressIndicator());
                }
                return StreamBuilder<bool>(
                  stream: householdService.joinRequestExistsStream(widget.request.householdId, uid),
                  builder: (context, requestSnapshot) {
                    final stillPending = requestSnapshot.data ?? true;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: stillPending
                              ? [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Venter på at oppretteren av «${widget.request.householdName}» skal godkjenne deg.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  TextButton(onPressed: widget.onGiveUp, child: const Text('Avbryt')),
                                ]
                              : [
                                  const Icon(Icons.block, size: 48),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Forespørselen om å bli med i «${widget.request.householdName}» ble ikke godkjent.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(onPressed: widget.onGiveUp, child: const Text('Tilbake')),
                                ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
