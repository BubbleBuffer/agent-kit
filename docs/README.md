# agent-kit docs

How the kit works now. Plans and decisions live in the owner's notes.

- [Package layout and pinning](package-layout.md): the workspace, what each package holds, where it came from, how consumers pin a tag and how to release.
- [agent_kit_core](agent-kit-core.md): chat view models, the backend port, the event reducer and the scripted fake backend (pure Dart).
- [Backend mapping](backend-mapping.md): each kit event and command against the BubblePaw SDK (layers 1 and 2) and Scratch's agent gateway, with the gaps.
- [agent_kit and the gallery](agent-kit.md): the Flutter widget package, `BbTheme` roles, size classes, `StatusMark`, the gallery app, how to add a widget with its golden and how to view the CI shots.
- [Icon and README assets](icon-and-readme-assets.md): how the icon, lockup and README shots are built and refreshed.

agent-kit is a dependency of BubblePaw Desktop (`agent_kit`, `agent_kit_core`, `agent_kit_bubblepaw`) and of Scratch (`agent_kit`, `agent_kit_core`, for its chat outline and dev pane). Both read it from their `pubspec.yaml`.

## Component sheets

One sheet per public widget, grouped by the folder under `packages/agent_kit/lib/src/`. Each has light and dark screenshots of its states, taken from the gallery's golden tests (`apps/gallery/test/component_shots_test.dart`), its parameters, the `BbTheme` roles it reads, size-class behaviour, accessibility and the tests that cover it. `shared/` holds internal helpers and has no sheets. To add one, see "Adding a widget" in [agent_kit and the gallery](agent-kit.md).

### theme

- [BbTheme](components/theme/BbTheme.md): The one `ThemeExtension` of the kit: colour roles, status styles, radii, motion, type scale and layout tokens, with `BbThemeScope` to install it.
- [SizeClassBuilder](components/theme/SizeClassBuilder.md): Measures its own width and gives its `builder` the `SizeClass` for that width, from the theme's thresholds; this sheet also covers `SizeClass` .

### status

- [StatusMark](components/status/StatusMark.md): The one widget that draws a status: a small mark and a label, in a dot form for list rows and meta lines, or a pill form for headers.

### transcript

- [ActivityGroupView](components/transcript/ActivityGroupView.md): One summary line for a run of agent work ("Searched 1× · Read 2 files · Ran 1 command · Worked 48s") that opens into evidence rows.
- [AssistantProse](components/transcript/AssistantProse.md): The assistant's message text, drawn by a `MarkdownRenderer`.
- [ChildQuestionRow](components/transcript/ChildQuestionRow.md): A question a child agent asked its parent agent, shown as a quiet inline row with the child's suggested options, its status.
- [CodeBlock](components/transcript/CodeBlock.md): A fenced code block: mono text on a `surface2` well that scrolls sideways.
- [DiffView](components/transcript/DiffView.md): A file diff: one row per line, added lines on the constructive tint, removed lines on the danger tint with the text struck through, context on the surface-2 well.
- [ExecOutput](components/transcript/ExecOutput.md): Tool output: a mono block clamped to 12 lines with a fade, and a footer with the size, the exit status, "Show all N lines" and "Open full output".
- [FileEditRow](components/transcript/FileEditRow.md): One file change: "Edited usage/mod.rs +N −N", with "Review diff", "Open" and "Undo" actions, and the diff opening under it.
- [PlanChecklist](components/transcript/PlanChecklist.md): The agent's plan as one line, "Plan 2/5", that opens into its steps.
- [ReturnLine](components/transcript/ReturnLine.md): The line that closes a child agent's work: "Map UsageState transitions returned", with a status pill and an Open action for the child's chat.
- [SystemLineView](components/transcript/SystemLineView.md): A system line: small, centred, faint text such as "Context compacted".
- [TranscriptList](components/transcript/TranscriptList.md): The scrolling column of a chat's transcript.
- [UserBubble](components/transcript/UserBubble.md): The user's message: context chips above a right-aligned text bubble, with an optional "Rewind from here" action.

### composer

- [AgentComposer](components/composer/AgentComposer.md): The message field and send bar at the foot of a chat.
- [ApprovalBar](components/composer/ApprovalBar.md): The bar above the composer that asks the user to approve or deny a tool call, with the sibling ApprovalKeyPane (the focus marker that decides which bar answers the keys).
- [QuestionAnswerLines](components/composer/QuestionAnswerLines.md): The resolved question as it reads in the transcript: one line per question, with the answer or "Skipped".
- [QuestionPrompt](components/composer/QuestionPrompt.md): The card above the composer that asks the user one or more questions and sends the answers.
- [QueuedRow](components/composer/QueuedRow.md): One queued message above the composer, with Send now, Edit and Remove, and an inline edit field.

### chrome

- [ChatHeader](components/chrome/ChatHeader.md): The bar at the top of a chat: the session's tile and title, its status pill, the branch, the context meter, the workspace toggle and the session menu.
- [ContextMeter](components/chrome/ContextMeter.md): A bar and a percentage that show how much of the model's context window the chat uses.
- [CrewLedger](components/chrome/CrewLedger.md): A list of the child agents and background jobs, with their status and a Cancel action for running agents.
- [CrewStrip](components/chrome/CrewStrip.md): A horizontal strip of chips, one per child agent or background job, that opens them.
- [RailLayout](components/chrome/RailLayout.md): The layout that places the session rail beside the chat: a column at medium and expanded widths, a sliding screen at compact width.
- [SessionRail](components/chrome/SessionRail.md): The session list: the workspace header, the chats grouped under labelled headings, and a footer.
- [UsageByModel](components/chrome/UsageByModel.md): A list of the models used in a chat, with each model's share of the tokens and a total.

### context

- [CompactionMarker](components/context/CompactionMarker.md): One quiet line in the assistant turn where a compaction was applied, was running, or failed.
- [ContextMeterBar](components/context/ContextMeterBar.md): The context meter of the Context pane: the token count against the window, a stacked bar of the context's parts, and a legend.
- [ContextPane](components/context/ContextPane.md): The Context pane: what the model sees now, the original history and the compactions over time, under the context meter.

### history

- [HistoryBoundary](components/history/HistoryBoundary.md): The hairline where full messages begin, below the compacted history: an arrow, "Full messages from here" and the number of the first message shown in full.
- [HistoryChapterCard](components/history/HistoryChapterCard.md): A closed chapter of compacted history: a card whose face is the chapter summary, which opens to its episode cards.
- [HistoryCurrentChapter](components/history/HistoryCurrentChapter.md): The open chapter of compacted history: a plain group header over its episode cards.
- [HistoryEpisodeCard](components/history/HistoryEpisodeCard.md): One episode of compacted history: a header line, the title and a gist.
- [HistoryLegacyCard](components/history/HistoryLegacyCard.md): A summary from before chapters and episodes: the title (when there is one), the summary, the start and end times and the message count.

### outline

- [OutlineChapterCard](components/outline/OutlineChapterCard.md): A closed chapter in the outline: a folding card with the chapter's title, one line on its face (the decision, or a gist).
- [OutlineChapterHeading](components/outline/OutlineChapterHeading.md): The heading of a chapter whose messages show in the outline: an open chapter, or a closed one the reader has unfolded.
- [OutlineList](components/outline/OutlineList.md): The outlined transcript as a list: the rows of an `OutlineController`'s layout, drawn in an `AnchoredList`.
- [OutlineSectionDivider](components/outline/OutlineSectionDivider.md): A section's divider in the outline: a short coloured bar, the section title, a dashed rule and an optional menu button.
- [OutlineWhereStrip](components/outline/OutlineWhereStrip.md): The where-am-I strip over the outline: a dot in the chapter's colour, the chapter title, the section after a "›", and a "Contents ▾" label.

### workspace

- [AgentWorkspace](components/workspace/AgentWorkspace.md): The tiling pane area beside the chat: a split tree of panes with dividers, tabs, maximise and close on each pane, collapse to edge tabs, drag to dock.

### compositions

- [AgentChatPane](components/compositions/AgentChatPane.md): One chat on an `AgentBackend`, with its header, crew strip, transcript and dock (approvals, question, queued inputs, error line, composer).
- [AgentContextPane](components/compositions/AgentContextPane.md): The Context pane of one chat.
- [AgentWorkbench](components/compositions/AgentWorkbench.md): The whole agent app on one `AgentBackend`: the session rail, the chat pane, the crew ledger or strip, and an optional workspace beside the chat .

### providers

- [ProviderSettings](components/providers/ProviderSettings.md): The providers section of a host's settings, with the default model, each provider's key status and models, and Make default: `ProviderList` draws a `ProviderSetup`.
