// Golden crops of single widgets for the wiki's component sheets
// (docs/components/). Each shot renders a gallery scene exactly as the scene
// goldens do, then keeps the rectangle of one specimen (or a few), light and
// dark, as goldens/shots/<name>_<theme>.png. CI compares them like the other
// goldens; `docs/components/` copies the PNGs under stable names. A shot picks
// its specimen by widget type and position in the scene, so a change to a
// specimen list in the gallery moves the shots; re-render with
// `flutter test --update-goldens test/component_shots_test.dart`.

@Tags(['golden'])
library;

import 'dart:ui' as ui;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_gallery/gallery.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// One crop: the union of the rectangles of [pick]'s widgets, grown by [pad].
class _Shot {
  const _Shot(this.name, this.pick, {this.pad = 2});

  final String name;
  final List<Finder> Function() pick;
  final double pad;
}

/// A scene shot at [width] by [height], with the crops taken from it.
class _Sheet {
  const _Sheet(this.scene, this.width, this.height, this.shots);

  final GalleryScene scene;
  final double width;
  final double height;
  final List<_Shot> shots;
}

Finder _nth(Type type, int i) => find.byType(type).at(i);

List<Finder> Function() _one(Type type, int i) =>
    () => [_nth(type, i)];

List<Finder> Function() _range(Type type, int from, int to) =>
    () => [for (var i = from; i <= to; i++) _nth(type, i)];

final _sheets = <_Sheet>[
  _Sheet(GalleryScene.components, 1100, 30000, [
    // status
    _Shot('status_mark', _range(StatusMark, 0, 17)),
    // chrome
    _Shot('session_rail_column', _one(SessionRail, 0)),
    _Shot('session_rail_compact', _one(SessionRail, 1)),
    _Shot('rail_layout_hidden', _one(RailLayout, 1)),
    _Shot('chat_header_needs_you', _one(ChatHeader, 2)),
    _Shot('chat_header_running', _one(ChatHeader, 3)),
    _Shot('chat_header_failed', _one(ChatHeader, 4)),
    _Shot('chat_header_compact', _one(ChatHeader, 6)),
    _Shot('crew_strip_expanded', _one(CrewStrip, 1)),
    _Shot('crew_strip_compact', _one(CrewStrip, 2)),
    _Shot('crew_strip_asking_parent', _one(CrewStrip, 0)),
    _Shot('crew_ledger', _one(CrewLedger, 1)),
    _Shot('crew_ledger_asking_parent', _one(CrewLedger, 0)),
    _Shot('usage_by_model', _one(UsageByModel, 0)),
    _Shot('context_meter_states', _range(ContextMeter, 12, 15)),
    _Shot('context_meter_header', _range(ContextMeter, 0, 1)),
    // composer
    _Shot('agent_composer_idle', _one(AgentComposer, 0)),
    _Shot('agent_composer_steer', _one(AgentComposer, 1)),
    _Shot('agent_composer_queue', _one(AgentComposer, 2)),
    _Shot('agent_composer_phone', _one(AgentComposer, 4)),
    _Shot('approval_bar_expanded', _one(ApprovalBar, 0)),
    _Shot('approval_bar_medium', _one(ApprovalBar, 1)),
    _Shot('approval_bar_phone', _one(ApprovalBar, 2)),
    _Shot('approval_bar_deny', _one(ApprovalBar, 3)),
    _Shot('queued_row_wide', _one(QueuedRow, 0)),
    _Shot('queued_row_editing', _one(QueuedRow, 2)),
    _Shot('queued_row_phone', _one(QueuedRow, 3)),
    _Shot('question_prompt_pick_one', _one(QuestionPrompt, 0)),
    _Shot('question_prompt_pick_any', _one(QuestionPrompt, 1)),
    _Shot('question_prompt_text', _one(QuestionPrompt, 2)),
    _Shot('question_prompt_steps', _one(QuestionPrompt, 4)),
    _Shot('question_prompt_phone', _one(QuestionPrompt, 5)),
    _Shot('question_answer_lines', _one(QuestionAnswerLines, 0)),
    // context
    _Shot('context_meter_bar', _range(ContextMeterBar, 0, 1)),
    _Shot('compaction_marker', _range(CompactionMarker, 0, 2)),
    _Shot('context_pane_wide', _one(ContextPane, 0)),
    _Shot('context_pane_narrow', _one(ContextPane, 1)),
    _Shot('context_pane_summary', _one(ContextPane, 2)),
    _Shot('context_pane_history', _one(ContextPane, 3)),
    _Shot('context_pane_compactions', _one(ContextPane, 4)),
    // transcript
    _Shot('transcript_list', _one(TranscriptList, 0)),
    _Shot('jump_to_latest_button', _one(JumpToLatestButton, 0)),
    _Shot('user_bubble', _one(UserBubble, 0)),
    _Shot('assistant_prose', _one(AssistantProse, 1)),
    _Shot('code_block', _one(CodeBlock, 1)),
    _Shot(
      'system_notice_lines',
      () => [_nth(SystemLineView, 0), _nth(NoticeLineView, 4)],
    ),
    _Shot('activity_group_collapsed', _one(ActivityGroupView, 1)),
    _Shot('activity_group_open', _one(ActivityGroupView, 2)),
    _Shot('activity_group_running', _one(ActivityGroupView, 3)),
    _Shot('activity_group_mixed', _one(ActivityGroupView, 5)),
    _Shot('exec_output', _one(ExecOutput, 1)),
    _Shot('file_edit_row', _range(FileEditRow, 2, 4)),
    _Shot('diff_view', _one(DiffView, 1)),
    _Shot('plan_checklist', _range(PlanChecklist, 0, 1)),
    _Shot('return_line', _range(ReturnLine, 1, 2)),
    _Shot('interrupted_notice', _one(InterruptedNotice, 1)),
    _Shot('child_question_pending', _one(ChildQuestionRow, 0)),
    _Shot('child_question_composing', _one(ChildQuestionRow, 1)),
    _Shot('child_question_no_answer', _one(ChildQuestionRow, 2)),
    _Shot('child_question_answered', _one(ChildQuestionRow, 3)),
    _Shot('child_question_cancelled', _one(ChildQuestionRow, 5)),
    // workspace
    _Shot('agent_workspace_expanded', _one(AgentWorkspace, 0), pad: 13),
    _Shot('agent_workspace_collapsed', _one(AgentWorkspace, 1), pad: 13),
    _Shot('agent_workspace_maximised', _one(AgentWorkspace, 2), pad: 13),
    _Shot('agent_workspace_medium', _one(AgentWorkspace, 3), pad: 13),
    _Shot('agent_workspace_compact', _one(AgentWorkspace, 4), pad: 1),
    _Shot('agent_workspace_empty', _one(AgentWorkspace, 5), pad: 13),
    // providers
    _Shot('provider_list', _one(ProviderList, 0)),
    _Shot('provider_list_restart', _one(ProviderList, 1)),
    _Shot('provider_list_phone', _one(ProviderList, 2)),
  ]),
  _Sheet(GalleryScene.history, 1600, 2600, [
    _Shot('history_legacy_card', _one(HistoryLegacyCard, 0)),
    _Shot('history_chapter_card_closed', _one(HistoryChapterCard, 0)),
    _Shot('history_chapter_card_open', _one(HistoryChapterCard, 1)),
    _Shot('history_chapter_card_split', _range(HistoryChapterCard, 2, 3)),
    _Shot('history_episode_card_unlogged', _one(HistoryEpisodeCard, 0)),
    _Shot('history_episode_card_log', _one(HistoryEpisodeCard, 1)),
    _Shot('history_episode_card_messages', _one(HistoryEpisodeCard, 2)),
    _Shot('history_current_chapter', _one(HistoryCurrentChapter, 0)),
    _Shot('history_boundary', _one(HistoryBoundary, 0)),
  ]),
  _Sheet(GalleryScene.outline, 1600, 900, [
    _Shot(
      'outline_list',
      () => [_nth(OutlineChapterCard, 0), _nth(AssistantProse, 2)],
      pad: 8,
    ),
    _Shot('outline_chapter_card_sections', _one(OutlineChapterCard, 0)),
    _Shot('outline_chapter_card_plain', _one(OutlineChapterCard, 1)),
    _Shot('outline_chapter_heading', _one(OutlineChapterHeading, 0)),
    _Shot('outline_section_divider', _one(OutlineSectionDivider, 0)),
    _Shot('outline_where_strip', _one(OutlineWhereStrip, 0), pad: 0),
  ]),
  _Sheet(GalleryScene.outline, 390, 844, [
    _Shot('outline_list_compact', _one(OutlineList, 0), pad: 0),
  ]),
];

void main() {
  for (final sheet in _sheets) {
    for (final brightness in Brightness.values) {
      final label = '${sheet.scene.slug}_${sheet.width.round()}';
      testWidgets('shots $label ${brightness.name}', (tester) async {
        final controller = GalleryController();
        addTearDown(controller.dispose);
        await tester.runAsync(controller.start);
        tester.view.physicalSize = Size(sheet.width, sheet.height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = GlobalKey();
        await tester.pumpWidget(
          WidgetsApp(
            color: const Color(0xFF000000),
            debugShowCheckedModeBanner: false,
            builder: (context, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: RepaintBoundary(
                key: root,
                child: SceneFrame(
                  scene: sheet.scene,
                  controller: controller,
                  width: sheet.width,
                  brightness: brightness,
                  tall: sheet.scene == GalleryScene.components,
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final boundary =
            root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final bounds = Offset.zero & boundary.size;
        for (final shot in sheet.shots) {
          Rect? rect;
          for (final f in shot.pick()) {
            final r = tester.getRect(f);
            rect = rect == null ? r : rect.expandToInclude(r);
          }
          final crop = rect!.inflate(shot.pad).intersect(bounds);
          final image = await tester.runAsync<ui.Image>(
            () => (boundary.debugLayer! as OffsetLayer).toImage(crop),
          );
          await expectLater(
            image,
            matchesGoldenFile(
              'goldens/shots/${shot.name}_${brightness.name}.png',
            ),
          );
        }
      });
    }
  }
}
