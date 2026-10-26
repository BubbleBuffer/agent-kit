/// The backend port: what a host implements so the kit's widgets can run.
library;

import 'events.dart';
import 'models.dart';
import 'snapshot.dart';
import 'value.dart';

/// An optional backend feature. Widgets hide what a backend lacks.
enum KitCapability {
  /// `steer`: deliver a message into the running turn.
  steer,

  /// `editQueued` and `removeQueued`.
  queueEdit,

  /// `sendQueuedNow`: deliver a queued message now, as a steer.
  sendQueuedNow,

  /// Child agents in the crew, and `cancelChild`.
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

  /// `listModels` and `setModel`.
  models,

  /// `listProfiles` and `setProfile`.
  profiles,

  /// The plan checklist.
  plan,

  /// `resume` of an interrupted run.
  resume,
}

/// The set of [KitCapability] a backend declares.
final class KitCapabilities extends KitValue {
  /// Creates a capability set.
  KitCapabilities(Iterable<KitCapability> values)
    : values = Set.unmodifiable(values);

  /// Every capability.
  factory KitCapabilities.all() => KitCapabilities(KitCapability.values);

  /// No optional capability.
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

/// The port between the kit and a host's agent backend.
///
/// Reads follow snapshot-plus-events: [loadChat] returns a snapshot up to
/// sequence N, and [events] streams what follows N. A consumer folds the
/// events into the snapshot with `reduce`, and reloads on a `gap`
/// (`ChatFeed` does all of this).
///
/// Commands return futures that complete when the backend has accepted
/// the command, not when its effects are done: effects arrive as events.
/// A command fails with a [KitError]; one that needs a missing capability
/// fails with [KitUnsupported]. Rewind and fork change history in ways
/// the event vocabulary does not express, so after them the backend sends
/// a `gap` on the affected chat.
abstract interface class AgentBackend {
  /// The optional features this backend supports.
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

  /// Sets the model for the chat's next runs.
  Future<void> setModel(String chatId, String modelId);

  /// Sets the profile for the chat's next runs.
  Future<void> setProfile(String chatId, String profileId);
}
