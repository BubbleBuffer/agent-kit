// The crew ledger, the "Still running" column (`.ledger` and `.lg-*` in the
// mockup's app.css): a header with counts, then one entry per child agent
// (icon, task, mono activity line, status line) and per background job
// (terminal icon, mono command, detail line, status line; a danger edge bar
// when it failed).

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/theme.dart';
import 'chrome_button.dart' show chromeTooltip;
import 'chrome_format.dart';
import 'chrome_icons.dart';
import 'crew_text.dart';

/// The ledger. [agents] come from `ChatSnapshot.children`, [jobs] from
/// `ChatSnapshot.jobs`; [now] is the clock for running times.
class CrewLedger extends StatelessWidget {
  const CrewLedger({
    super.key,
    this.agents = const [],
    this.jobs = const [],
    this.now,
    this.onOpenAgent,
    this.onOpenJob,
  });

  final List<ChildAgent> agents;
  final List<BackgroundJob> jobs;
  final DateTime? now;
  final ValueChanged<ChildAgent>? onOpenAgent;
  final ValueChanged<BackgroundJob>? onOpenJob;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final clock = now ?? DateTime.now();
    return Semantics(
      container: true,
      label: 'Still running',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Still running',
                  style: ts(const TypeSpec(12, 16, 700), theme.muted),
                ),
                if (agents.isNotEmpty || jobs.isNotEmpty)
                  Text(
                    crewCounts(agents.length, jobs.length),
                    style: ts(const TypeSpec(12, 16, 500), theme.faint),
                  ),
              ],
            ),
          ),
          for (final agent in agents)
            _LedgerRow(
              key: ValueKey('ledger-agent-${agent.id}'),
              glyph: glyphBot,
              title: agent.task,
              detail: askingLine(agent) ?? agent.activity,
              detailTip: askingLine(agent),
              status: StatusMark.work(
                agent.state,
                label: agentLabel(agent, clock),
                detail:
                    agent.toolCalls > 0 &&
                        agent.state != WorkState.waitingForAnswer
                    ? plural(agent.toolCalls, 'call')
                    : null,
              ),
              onTap: onOpenAgent == null ? null : () => onOpenAgent!(agent),
            ),
          for (final job in jobs)
            _LedgerRow(
              key: ValueKey('ledger-job-${job.id}'),
              glyph: glyphTerminal,
              title: job.command,
              mono: true,
              failed: job.failed,
              detail: jobDetailLine(job, clock),
              status: StatusMark(
                jobStatus(job),
                label: jobLabel(job, clock),
                detail: job.summary,
              ),
              onTap: onOpenJob == null ? null : () => onOpenJob!(job),
            ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    super.key,
    required this.glyph,
    required this.title,
    required this.status,
    required this.onTap,
    this.detail,
    this.detailTip,
    this.mono = false,
    this.failed = false,
  });

  final LucideGlyph glyph;
  final String title;
  final String? detail;

  /// The full text for a truncated [detail], as a tooltip.
  final String? detailTip;
  final Widget status;
  final bool mono;
  final bool failed;
  final VoidCallback? onTap;

  Widget _detailText(BbTheme theme) => Text(
    detail!,
    style: ts(const TypeSpec(12, 16, 400), theme.faint, mono: true),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final titleStyle = mono
        ? ts(const TypeSpec(12.5, 18, 400), theme.ink, mono: true)
        : ts(theme.typeScale.ui, theme.ink, weight: 600);
    return Stack(
      children: [
        Hover(
          onTap: onTap,
          borderRadius: theme.radii.field,
          hoverBackground: theme.hover,
          pressedBackground: theme.pressed,
          lift: 0,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: ChromeIcon(glyph, color: theme.colors.iconSecondary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: titleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      detailTip == null
                          ? _detailText(theme)
                          : chromeTooltip(
                              context,
                              detailTip!,
                              _detailText(theme),
                            ),
                    ],
                    const SizedBox(height: 2),
                    status,
                  ],
                ),
              ),
            ],
          ),
        ),
        if (failed)
          Positioned(
            left: 0,
            top: 6,
            bottom: 6,
            width: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.dangerInk,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
