// Every maneuver of a route as a list (app study §S6).
import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../nav/phrases.dart';
import '../routing/route_model.dart';
import 'format.dart';
import 'map_kit.dart';

Future<void> showStepsSheet(BuildContext context, ArahRoute route, {int fromIndex = 0}) {
  final lang = context.appRead.lang;
  final steps = route.maneuvers.skip(fromIndex < 0 ? 0 : fromIndex).toList();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => ListView.separated(
        controller: scroll,
        itemCount: steps.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (_, i) {
          final m = steps[i];
          return ListTile(
            leading: Icon(turnIcon(m), size: 32),
            title: Text(bannerText(m, lang)),
            subtitle: m.lengthM > 0 && !isArrival(m.turn)
                ? Text([
                    fmtKm(m.lengthM),
                    if (m.toll) context.appRead.tr('Tol', 'Toll'),
                  ].join(' · '))
                : null,
          );
        },
      ),
    ),
  );
}
