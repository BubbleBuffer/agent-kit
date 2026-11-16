// The crew strip (`.crew-strip` in the mockup's app.css): one chip per child
// agent and background job, each with a StatusMark and its tag, scrolling
// sideways when they do not fit. Medium widths and the docked pane show it
// instead of the ledger.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/kit_tokens.dart';
import '../theme/theme.dart';
import 'chrome_icons.dart';
import 'crew_text.dart';

/// The strip. [agents] come from `ChatSnapshot.children`, [jobs] from
/// `ChatSnapshot.jobs`. A chip's title is the agent's task or the job's first
/// two words; [agentTitle] and [jobTitle] give shorter names. [now] is the
/// clock for running times (the real time by default). It draws nothing when
/// there is nothing in the crew.
class CrewStrip extends StatelessWidget {
  const CrewStrip({
    super.key,
    this.agents = const [],
    this.jobs = const [],
    this.now,
    this.agentTitle,
    this.jobTitle,
    this.onOpenAgent,
    this.onOpenJob,
  });

  final List<ChildAgent> agents;
  final List<BackgroundJob> jobs;
  final DateTime? now;
  final String Function(ChildAgent agent)? agentTitle;
  final String Function(BackgroundJob job)? jobTitle;
  final ValueChanged<ChildAgent>? onOpenAgent;
  final ValueChanged<BackgroundJob>? onOpenJob;

  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty && jobs.isEmpty) return const SizedBox.shrink();
    final theme = context.bb;
    final clock = now ?? DateTime.now();
    final touch = theme.touch;
    final chips = <Widget>[
      for (final agent in agents)
        _CrewChip(
          key: ValueKey('crew-agent-${agent.id}'),
          glyph: glyphBot,
          title: agentTitle?.call(agent) ?? agent.task,
          mark: StatusMark.work(agent.state, label: agentTag(agent, clock)),
          height: touch ? ControlSize.xs : ControlSize.sm,
          onTap: onOpenAgent == null ? null : () => onOpenAgent!(agent),
        ),
      for (final job in jobs)
        _CrewChip(
          key: ValueKey('crew-job-${job.id}'),
          glyph: glyphTerminal,
          title: jobTitle?.call(job) ?? jobShortName(job),
          mark: StatusMark(jobStatus(job), label: jobTag(job, clock)),
          height: touch ? ControlSize.xs : ControlSize.sm,
          onTap: onOpenJob == null ? null : () => onOpenJob!(job),
        ),
    ];
    return Semantics(
      container: true,
      label: crewHeading(agents, jobs).label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.colors.borderSubtle)),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (touch ? ControlSize.md : ControlSize.xl).height,
          ),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.stylus,
                PointerDeviceKind.trackpad,
              },
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Row(spacing: Space.xs, children: chips),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrewChip extends StatelessWidget {
  const _CrewChip({
    super.key,
    required this.glyph,
    required this.title,
    required this.mark,
    required this.height,
    required this.onTap,
  });

  final LucideGlyph glyph;
  final String title;
  final Widget mark;
  final ControlSize height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return Hover(
      onTap: onTap,
      borderRadius: theme.radii.pill,
      hoverBackground: theme.hover,
      pressedBackground: theme.pressed,
      lift: 0,
      border: Border.all(color: theme.seam),
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      // Inside the hairline border; grows with the text size.
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height.height - 2 * Stroke.hair),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChromeIcon(
              glyph,
              size: IconSize.xs,
              color: theme.colors.iconSecondary,
            ),
            const Gap(Space.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: KitSizes.crewChipTitle,
              ),
              child: Text(
                title,
                style: ts(theme.typeScale.uiSmall, theme.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Gap(Space.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: KitSizes.crewChipMark,
              ),
              child: mark,
            ),
          ],
        ),
      ),
    );
  }
}
