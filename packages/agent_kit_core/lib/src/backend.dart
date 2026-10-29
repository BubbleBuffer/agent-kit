/// The backend port: what a host implements so the kit's widgets can run.
library;

import 'context.dart';
import 'events.dart';
import 'models.dart';
import 'providers.dart';
import 'snapshot.dart';
import 'value.dart';

/// A backend feature. An absent capability means its commands are unsupported
/// and must fail with [KitUnsupported]. Widgets gate the corresponding actions.
enum KitCapability {
  /// `steer`: deliver a message into the running turn.
  steer,

  /// `editQueued` and `removeQueued`.
  queueEdit,

  /// `sendQueuedNow`: deliver a queued message now, as a steer.
  sendQueuedNow,

  /// Child agents in the crew. The ledger offers Cancel on a running agent
  /// only when this is declared, because it needs `cancelChild`.
  children,

  /// Background jobs, and `cancelJob`.
  jobs,

  /// `rewind`.
  rewind,

  /// Questions to the user, and `answerQuestion`.
  questions,

  /// Reasoning text in thinking rows (without it, rows show only time).
  reasoningText,

  /// Chats in their own worktrees (`WorkspaceInfo.worktree`).
  worktrees,

  /// Token usage and the context meter.
  usage,

  /// `fork`.
  fork,

  /// `archive`.
  archive,

  /// `rename`.
  rename,

  /// `undoEdit`.
  editUndo,

  /// `listModels` and `setModel`. With [defaultModel], the model pick sets
  /// the host's default for every chat.
  models,

  /// `listProviders`: the host's providers and which model new runs use.
  providers,

  /// `setDefaultModel`: the model new runs use in every chat.
  defaultModel,

  /// `listProfiles` and `setProfile`.
  profiles,

  /// The plan checklist.
  plan,

  /// `resume` of an interrupted run.
  resume,

  /// The context view: `ChatSnapshot.context`, `loadContext`,
  /// `loadHistoryRange` and `loadSummary`.
  context,

  /// `answerChildQuestion`: the user answers a child agent's question in
  /// the parent's place. Needs engine support: a user message to a child in
  /// `waitingForAnswer`.
  answerChildQuestion,

  /// `send` and `followup`.
  send,

  /// `cancel`.
  cancel,

  /// `decideApproval`.
  approve,

  /// `createChat`.
  createChat,
}

/// The set of [KitCapability] a backend declares.
final class KitCapabilities extends KitValue {
  /// Creates a capability set.
  KitCapabilities(Iterable<KitCapability> values)
    : values = Set.unmodifiable(values);

  /// Every capability.
  factory KitCapabilities.all() => KitCapabilities(KitCapability.values);

  /// No capability, including commands that write to a chat.
  factory KitCapabilities.none() => KitCapabilities(const []);

  /// Reads capabilities from JSON; unknown names are skipped.
  factory KitCapabilities.fromJson(Json j) {
    final names = j.strings('capabilities').toSet();
    return KitCapabilities(
      KitCapability.values.where((c) => names.contains(c.name)),
    );
  }

  /// The declared capabilities.
  final Set<KitCapability> values;

  /// Whether [capability] is declared.
  bool has(KitCapability capability) => values.contains(capability);

  @override
  Json toJson() => {
    'capabilities': [
      for (final c in KitCapability.values)
        if (values.contains(c)) c.name,
    ],
  };
}

/// Input shapes and running-turn behaviour supported by a backend.
///
/// These declarations refine capabilities; they do not grant commands.
final class BackendConstraints extends KitValue {
  /// Creates constraints, copying [supportedQuestionKinds] into an immutable set.
  BackendConstraints({
    bool acceptsReferences = true,
    Iterable<QuestionKind> supportedQuestionKinds = QuestionKind.values,
    bool followUpWhileRunning = true,
  }) : this._(
         acceptsReferences,
         Set.unmodifiable(supportedQuestionKinds),
         followUpWhileRunning,
       );

  const BackendConstraints._(
    this.acceptsReferences,
    this.supportedQuestionKinds,
    this.followUpWhileRunning,
  );

  /// The behaviour existing backends had before constraints were declared.
  static const defaults = BackendConstraints._(true, {
    QuestionKind.pickOne,
    QuestionKind.pickAny,
    QuestionKind.text,
  }, true);

  /// Reads constraints from JSON, keeping defaults for absent fields.
  factory BackendConstraints.fromJson(Json j) => BackendConstraints(
    acceptsReferences: j.boolean('acceptsReferences', fallback: true),
    supportedQuestionKinds: j.containsKey('supportedQuestionKinds')
        ? QuestionKind.values.where(
            (kind) => j.strings('supportedQuestionKinds').contains(kind.name),
          )
        : QuestionKind.values,
    followUpWhileRunning: j.boolean('followUpWhileRunning', fallback: true),
  );

  /// Whether outgoing messages may carry [KitRef] references.
  final bool acceptsReferences;

  /// The question input kinds this backend can answer.
  final Set<QuestionKind> supportedQuestionKinds;

  /// Whether a message can be queued as a follow-up while a run is active.
  final bool followUpWhileRunning;

  @override
  Json toJson() => {
    'acceptsReferences': acceptsReferences,
    'supportedQuestionKinds': [
      for (final kind in QuestionKind.values)
        if (supportedQuestionKinds.contains(kind)) kind.name,
    ],
    'followUpWhileRunning': followUpWhileRunning,
  };
}

/// Optional declarations that refine a backend's input support.
///
/// Kept separate from [AgentBackend] so existing implementers remain valid.
abstract interface class BackendConstraintsProvider {
  /// The backend's supported input shapes and running-turn behaviour.
  BackendConstraints get constraints;
}

/// Supplies defaults for backends that do not declare constraints.
extension BackendConstraintAccess on AgentBackend {
  /// The backend's constraints, or the existing behaviour by default.
  BackendConstraints get constraints {
    final backend = this;
    return backend is BackendConstraintsProvider
        ? (backend as BackendConstraintsProvider).constraints
        : BackendConstraints.defaults;
  }
}

/// The user's answer to an approval request.
enum ApprovalChoice {
  /// Approve this call.
  approve,

  /// Approve this tool for the rest of the session.
  approveForSession,

  /// Deny, with an optional reason the agent sees.
  deny,
}

/// A decision on an approval: a [choice] and, for a denial, a [reason].
final class ApprovalDecision extends KitValue {
  const ApprovalDecision._(this.choice, [this.reason]);

  /// Approve this call.
  static const approve = ApprovalDecision._(ApprovalChoice.approve);

  /// Approve this tool for the session.
  static const approveForSession = ApprovalDecision._(
    ApprovalChoice.approveForSession,
  );

  /// Deny, optionally saying why.
  const ApprovalDecision.deny([String? reason])
    : this._(ApprovalChoice.deny, reason);

  /// What the user chose.
  final ApprovalChoice choice;

  /// The deny reason.
  final String? reason;

  @override
  Json toJson() => compact({'choice': choice.name, 'reason': reason});
}

/// What happened to a sent message.
enum SendDelivery {
  /// It started a new run.
  started,

  /// A run was active, so it was queued as a follow-up.
  queued,
}

/// The result of `send`.
final class SendResult extends KitValue {
  /// Creates a result.
  const SendResult({required this.delivery, this.inputId, this.runId});

  /// Started a run or queued.
  final SendDelivery delivery;

  /// The queued input's id, when queued.
  final String? inputId;

  /// The new run's id, when started.
  final String? runId;

  @override
  Json toJson() =>
      compact({'delivery': delivery.name, 'inputId': inputId, 'runId': runId});
}

/// A command failure. [message] is safe to show to the user: adapters map
/// host errors to one of the subtypes and never pass through secrets,
/// tokens, paths outside the workspace or raw provider responses.
sealed class KitError implements Exception {
  const KitError(this.message);

  /// A short, user-safe description.
  final String message;

  /// A stable code: `unsupported`, `notFound`, `busy`, `conflict`,
  /// `invalid`, `unavailable`, `denied` or `failed`.
  String get code;

  @override
  String toString() => 'KitError.$code: $message';
}

/// The backend lacks the capability the command needs.
final class KitUnsupported extends KitError {
  /// Creates the error.
  const KitUnsupported(this.capability, [String? message])
    : super(message ?? 'Not supported by this backend.');

  /// The missing capability.
  final KitCapability capability;

  @override
  String get code => 'unsupported';
}

/// The chat, approval, queued input or other target does not exist.
final class KitNotFound extends KitError {
  /// Creates the error.
  const KitNotFound([super.message = 'Not found.']);

  @override
  String get code => 'notFound';
}

/// The chat has an active run and the command needs it idle.
final class KitBusy extends KitError {
  /// Creates the error.
  const KitBusy([super.message = 'The chat is busy. Steer or queue instead.']);

  @override
  String get code => 'busy';
}

/// The target changed state first: an approval already decided, an input
/// already delivered, an edit no longer undoable.
final class KitConflict extends KitError {
  /// Creates the error.
  const KitConflict([super.message = 'That changed in the meantime.']);

  @override
  String get code => 'conflict';
}

/// The arguments are invalid, such as an empty message.
final class KitInvalid extends KitError {
  /// Creates the error.
  const KitInvalid([super.message = 'Invalid input.']);

  @override
  String get code => 'invalid';
}

/// The backend cannot be reached now; the command may be retried.
final class KitUnavailable extends KitError {
  /// Creates the error.
  const KitUnavailable([super.message = 'The agent host is unreachable.']);

  @override
  String get code => 'unavailable';
}

/// The user or device is not allowed to do this.
final class KitDenied extends KitError {
  /// Creates the error.
  const KitDenied([super.message = 'Not allowed.']);

  @override
  String get code => 'denied';
}

/// Any other failure, with a generic or adapter-written message.
final class KitFailed extends KitError {
  /// Creates the error.
  const KitFailed([super.message = 'Something went wrong.']);

  @override
  String get code => 'failed';
}

/// Read access to chats, without authority to issue write commands.
///
/// Reads follow snapshot-plus-events: [loadChat] returns a snapshot up to
/// sequence N, and [events] streams what follows N. A consumer folds the
/// events into the snapshot with `reduce`, and reloads on a `gap`
/// (`ChatFeed` does all of this).
abstract interface class ChatReader {
  /// The features this backend supports.
  KitCapabilities get capabilities;

  /// A page of chats, newest first, optionally filtered by [query].
  Future<ChatPage> listChats({String? cursor, String? query});

  /// The chat's snapshot as of its latest durable event.
  Future<ChatSnapshot> loadChat(String chatId);

  /// The chat's events after sequence [after], then live events, until the
  /// subscription is cancelled. Durable events after [after] are replayed
  /// first; if they are no longer available, the stream starts with a
  /// `gap`.
  Stream<KitEvent> events(String chatId, {required int after});

  /// The structure behind the chat's context view. Needs `context`.
  /// Summary texts may be left empty; [loadSummary] has the whole text.
  Future<ContextDetails> loadContext(String chatId);

  /// Original messages, [firstSeq] to [lastSeq] inclusive. Needs `context`.
  Future<HistoryPage> loadHistoryRange(
    String chatId,
    int firstSeq,
    int lastSeq,
  );

  /// One summary with its whole text. Needs `context`; fails with
  /// [KitNotFound] for an unknown id.
  Future<ContextSummary> loadSummary(String chatId, String summaryId);
}

/// The port between the kit and a host's agent backend.
///
/// Commands return futures that complete when the backend has accepted
/// the command, not when its effects are done: effects arrive as events.
/// A command fails with a [KitError]; one that needs a missing capability
/// fails with [KitUnsupported]. Rewind and fork change history in ways
/// the event vocabulary does not express, so after them the backend sends
/// a `gap` on the affected chat.
abstract interface class AgentBackend implements ChatReader {
  /// Creates an empty chat.
  Future<ChatSummary> createChat({String? title, String? workspace});

  /// Sends a message: starts a run, or queues a follow-up if one is active.
  Future<SendResult> send(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  });

  /// Queues a steer for the running turn; returns the queued input's id.
  Future<String> steer(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  });

  /// Queues a follow-up for after the run; returns the queued input's id.
  Future<String> followup(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  });

  /// Delivers a queued input now, as a steer.
  Future<void> sendQueuedNow(String chatId, String inputId);

  /// Replaces a queued input's text.
  Future<void> editQueued(String chatId, String inputId, String text);

  /// Removes a queued input without delivering it.
  Future<void> removeQueued(String chatId, String inputId);

  /// Cancels the active run; does nothing when idle.
  Future<void> cancel(String chatId);

  /// Resumes an interrupted run.
  Future<void> resume(String chatId);

  /// Decides a pending approval.
  Future<void> decideApproval(
    String chatId,
    String approvalId,
    ApprovalDecision decision,
  );

  /// Answers a pending question request. [answers] is keyed by item id and
  /// has an entry for every item; skipped items have `skipped: true`.
  Future<void> answerQuestion(
    String chatId,
    String questionId,
    Map<String, QuestionAnswer> answers,
  );

  /// Answers a child agent's pending question in the parent's place ("Answer
  /// yourself"); the parent is told the user answered. [text] is the whole
  /// answer. Needs the `answerChildQuestion` capability; fails with
  /// `KitNotFound` for an unknown question and `KitConflict` when it was
  /// answered already.
  Future<void> answerChildQuestion(
    String chatId,
    String childId,
    String questionId,
    String text,
  );

  /// Renames the chat.
  Future<void> rename(String chatId, String title);

  /// Archives or restores the chat.
  Future<void> archive(String chatId, {bool archived = true});

  /// Forks the chat, through [atItemId] when given; returns the new chat.
  Future<ChatSummary> fork(String chatId, {String? atItemId});

  /// Rewinds the chat to just before [toItemId] (a user message).
  Future<void> rewind(String chatId, String toItemId);

  /// Cancels a running child agent.
  Future<void> cancelChild(String chatId, String childId);

  /// Cancels a running background job.
  Future<void> cancelJob(String chatId, String jobId);

  /// Reverts a file edit.
  Future<void> undoEdit(String chatId, String editId);

  /// The models a chat can use.
  Future<List<KitChoice>> listModels();

  /// The profiles a chat can use.
  Future<List<KitChoice>> listProfiles();

  /// The host's providers and models, without keys. Needs `providers`.
  Future<ProviderSetup> listProviders();

  /// Makes [modelId] (`provider/model`) the model new runs use in every
  /// chat, and returns the host's setup afterwards. Needs `defaultModel`;
  /// fails with `KitInvalid` for an unknown provider or model and
  /// `KitConflict` when a later configuration layer overrides the setting.
  Future<ProviderSetup> setDefaultModel(String modelId);

  /// Sets the model for the chat's next runs.
  Future<void> setModel(String chatId, String modelId);

  /// Sets the profile for the chat's next runs.
  Future<void> setProfile(String chatId, String profileId);
}
