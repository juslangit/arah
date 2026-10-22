// Lane guidance row under the turn banner: the best lane white, other usable
// lanes outlined, the rest grey (app study §S5).
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../routing/route_model.dart';

/// Valhalla lane direction bits.
IconData laneIcon(int dirs) {
  if (dirs & 256 != 0) return Icons.u_turn_right; // reverse, Malaysia turns right to U-turn
  if (dirs & 4 != 0) return Icons.turn_sharp_left;
  if (dirs & 8 != 0 && dirs & 2 == 0) return Icons.turn_left;
  if (dirs & 16 != 0) return Icons.turn_slight_left;
  if (dirs & 128 != 0) return Icons.turn_sharp_right;
  if (dirs & 64 != 0 && dirs & 2 == 0) return Icons.turn_right;
  if (dirs & 32 != 0) return Icons.turn_slight_right;
  return Icons.straight;
}

class LaneRow extends StatelessWidget {
  final List<Lane> lanes;
  const LaneRow({super.key, required this.lanes});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: ArahColors.brandDark, borderRadius: BorderRadius.circular(12)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lanes.length; i++) ...[
          if (i > 0) Container(width: 1, height: 30, color: Colors.white24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              laneIcon(lanes[i].directions),
              size: 30,
              color: lanes[i].active
                  ? Colors.white
                  : lanes[i].valid
                  ? Colors.white70
                  : Colors.white24,
            ),
          ),
        ],
      ],
    ),
  );
}
