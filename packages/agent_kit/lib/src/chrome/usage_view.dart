// A small usage view: tokens by model, as the browser mock's "By model"
// card. agent_kit_core's `Usage` is per chat, not per model, so the host
// passes the per-model figures as [ModelUsage] values.

import 'package:agent_kit_core/agent_kit_core.dart' show Usage;
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'chrome_format.dart';

/// Tokens used on one model.
@immutable
class ModelUsage {
  const ModelUsage(this.model, this.tokens);

  final String model;
  final int tokens;
}

/// The "By model" card: each model's share of the tokens, largest first,
/// with models under 1% folded into "Other". [usage], when given with input
/// and output figures, adds the chat's token total under the rows.
class UsageByModel extends StatelessWidget {
  const UsageByModel({
    super.key,
    required this.models,
    this.usage,
    this.title = 'By model',
  });

  final List<ModelUsage> models;
  final Usage? usage;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final total = models.fold<int>(0, (sum, m) => sum + m.tokens);
    final sorted = [...models]..sort((a, b) => b.tokens.compareTo(a.tokens));
    final shown = <ModelUsage>[];
    var other = 0;
    for (final m in sorted) {
      if (total > 0 && m.tokens * 100 < total) {
        other += m.tokens;
      } else {
        shown.add(m);
      }
    }
    final input = usage?.inputTokens, output = usage?.outputTokens;
    final label = ts(theme.typeScale.ui, theme.ink, weight: 400);
    final figure = ts(theme.typeScale.ui, theme.muted, weight: 400);
    final faint = ts(theme.typeScale.ui, theme.faint, weight: 400);

    Widget row(String name, String share, TextStyle nameStyle, TextStyle end) =>
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: nameStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(share, style: end, maxLines: 1),
          ],
        );

    return Semantics(
      container: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: theme.radii.field,
          border: Border.all(color: theme.seam),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: ts(theme.typeScale.uiSmall, theme.muted)),
              if (total == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('No usage yet', style: faint),
                )
              else ...[
                for (final m in shown)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: row(
                      m.model,
                      '${(m.tokens * 100 / total).round()}%',
                      label,
                      figure,
                    ),
                  ),
                if (other > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: row('Other', '<1%', faint, faint),
                  ),
              ],
              if (input != null && output != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${formatTokens(input + output)} tokens',
                    style: ts(theme.typeScale.uiSmall, theme.faint),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
