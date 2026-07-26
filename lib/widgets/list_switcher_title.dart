import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/shopping_list.dart';
import '../providers/shopping_lists_providers.dart';
import 'list_color_swatch.dart';

/// Bakgrunnstone som signaliserer hvilken handleliste man jobber med — kun
/// synlig når husholdningen faktisk har mer enn én liste, se
/// «Ingen synlig endring før man aktivt oppretter liste nr. 2» i CLAUDE.md.
Color? currentListTintColor(WidgetRef ref) {
  final lists = ref.watch(shoppingListsProvider).value ?? const <ShoppingList>[];
  final current = ref.watch(currentListProvider);
  if (lists.length <= 1 || current == null) return null;
  return current.color.materialColor.withValues(alpha: 0.08);
}

/// AppBar-tittel som viser navnet/fargen på gjeldende handleliste og lar
/// brukeren bytte, men kun når det finnes mer enn én liste — ellers vises
/// bare [title] uendret, akkurat som før flere-lister-funksjonen fantes.
class ListSwitcherTitle extends ConsumerWidget {
  const ListSwitcherTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(shoppingListsProvider).value ?? const <ShoppingList>[];
    final current = ref.watch(currentListProvider);
    if (lists.length <= 1 || current == null) {
      return Text(title);
    }
    return InkWell(
      onTap: () => _showListPicker(context, ref, lists, current),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          const SizedBox(width: 10),
          ListColorDot(color: current.color),
          const SizedBox(width: 6),
          Flexible(child: Text(current.name, overflow: TextOverflow.ellipsis)),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }

  void _showListPicker(
    BuildContext context,
    WidgetRef ref,
    List<ShoppingList> lists,
    ShoppingList current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final list in lists)
              ListTile(
                leading: ListColorDot(color: list.color),
                title: Text(list.name),
                trailing: list.id == current.id ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.of(context).pop();
                  ref.read(selectedListIdProvider.notifier).select(list.id);
                },
              ),
          ],
        ),
      ),
    );
  }
}
