// The providers section of a host's settings: the default model, then each
// provider with whether its key was found and its models, each with Make
// default. The host reports only whether a key is present; no widget here
// reads, shows or stores one.
//
// [ProviderList] draws a [ProviderSetup]; [ProviderSettings] loads it from a
// backend and runs Make default.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../composer/composer_parts.dart' show KitButton;
import '../status/status.dart';
import '../theme/theme.dart';

/// Draws [setup]. [onMakeDefault] takes `provider/model`; null shows the
/// list without the buttons (a host that cannot set the default).
///
/// [makingDefault] is the model being set: its button is disabled and says
/// so. [error] is the last failure, shown under the list.
class ProviderList extends StatelessWidget {
  /// Creates the list.
  const ProviderList({
    super.key,
    required this.setup,
    this.onMakeDefault,
    this.makingDefault,
    this.error,
  });

  /// The providers and the default model.
  final ProviderSetup setup;

  /// Makes `provider/model` the default model.
  final ValueChanged<String>? onMakeDefault;

  /// The `provider/model` being set as default.
  final String? makingDefault;

  /// The last failure, in words for the user.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final current = setup.defaultModel;
    final pending = setup.reloadNeeded && setup.main != setup.activeMain;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SettingsHeading('Models'),
        SettingsRow(
          label: 'Default model',
          description: setup.reloadNeeded
              ? 'The configuration changed and the host has not applied it. '
                    'New runs keep using this model until the host reloads.'
              : 'New runs in every chat use this model. A run in progress '
                    'keeps its own.',
          stack: true,
          trailing: Text(
            current ?? 'None set',
            key: const ValueKey('provider-default'),
            style: ts(
              theme.typeScale.ui,
              current == null ? theme.faint : theme.ink,
              mono: current != null,
            ),
          ),
        ),
        if (pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Saved as ${setup.main}.',
              key: const ValueKey('provider-saved'),
              style: ts(theme.typeScale.uiSmall, theme.muted),
            ),
          ),
        if (setup.providers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No providers are configured on this host. Add one to the '
              'host configuration, then reload it.',
              key: const ValueKey('provider-empty'),
              style: ts(theme.typeScale.ui, theme.muted),
            ),
          ),
        for (final provider in setup.providers)
          _Provider(
            key: ValueKey('provider-${provider.name}'),
            provider: provider,
            current: current,
            makingDefault: makingDefault,
            onMakeDefault: onMakeDefault,
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                key: const ValueKey('provider-error'),
                style: ts(theme.typeScale.ui, theme.dangerInk),
              ),
            ),
          ),
      ],
    );
  }
}

class _Provider extends StatelessWidget {
  const _Provider({
    super.key,
    required this.provider,
    required this.current,
    required this.makingDefault,
    required this.onMakeDefault,
  });

  final ProviderInfo provider;
  final String? current;
  final String? makingDefault;
  final ValueChanged<String>? onMakeDefault;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final needsKey = provider.keyEnv != null;
    final usable = provider.keyPresent || !needsKey;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                provider.name,
                style: ts(theme.typeScale.ui, theme.ink, weight: 700),
              ),
              Text(
                provider.kind,
                style: ts(theme.typeScale.uiSmall, theme.faint, mono: true),
              ),
              if (needsKey)
                StatusMark(
                  provider.keyPresent ? ChatStatus.done : ChatStatus.needsYou,
                  label: provider.keyPresent ? 'Key found' : 'Key missing',
                ),
            ],
          ),
          if (provider.baseUrl != null) ...[
            const SizedBox(height: 2),
            Text(
              provider.baseUrl!,
              style: ts(theme.typeScale.uiSmall, theme.faint, mono: true),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (!usable) ...[
            const SizedBox(height: 4),
            Text(
              'The host did not find ${provider.keyEnv}. Set it for the '
              'host and restart it to use this provider.',
              key: ValueKey('provider-key-${provider.name}'),
              style: ts(theme.typeScale.uiSmall, theme.muted),
            ),
          ],
          if (provider.models.isEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'This provider lists no models.',
              style: ts(theme.typeScale.uiSmall, theme.muted),
            ),
          ],
          for (final model in provider.models)
            _Model(
              key: ValueKey('model-${provider.qualify(model)}'),
              id: provider.qualify(model),
              label: model.id,
              isDefault: provider.qualify(model) == current,
              usable: usable,
              making: makingDefault == provider.qualify(model),
              busy: makingDefault != null,
              onMakeDefault: onMakeDefault,
            ),
        ],
      ),
    );
  }
}

class _Model extends StatelessWidget {
  const _Model({
    super.key,
    required this.id,
    required this.label,
    required this.isDefault,
    required this.usable,
    required this.making,
    required this.busy,
    required this.onMakeDefault,
  });

  final String id;
  final String label;
  final bool isDefault;
  final bool usable;
  final bool making;
  final bool busy;
  final ValueChanged<String>? onMakeDefault;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    final Widget? trailing = isDefault
        ? const StatusMark(ChatStatus.done, label: 'Default')
        : onMakeDefault == null
        ? null
        : KitButton(
            key: ValueKey('make-default-$id'),
            label: making ? 'Making default…' : 'Make default',
            semanticLabel: 'Make $id the default model',
            height: 28,
            fontSize: 12,
            onTap: !usable || busy ? null : () => onMakeDefault!(id),
          );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: ts(theme.typeScale.ui, theme.ink, mono: true),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing],
        ],
      ),
    );
  }
}

/// The providers section for a backend: loads the setup, offers Make default
/// when the backend can set it, and shows nothing without the `providers`
/// capability.
class ProviderSettings extends StatefulWidget {
  /// Creates the section.
  const ProviderSettings({super.key, required this.backend});

  /// Where the providers come from.
  final AgentBackend backend;

  @override
  State<ProviderSettings> createState() => _ProviderSettingsState();
}

class _ProviderSettingsState extends State<ProviderSettings> {
  ProviderSetup? _setup;
  String? _loadError;
  String? _makeError;
  String? _making;
  int _ticket = 0;

  bool get _supported =>
      widget.backend.capabilities.has(KitCapability.providers);

  @override
  void initState() {
    super.initState();
    if (_supported) _load();
  }

  @override
  void didUpdateWidget(ProviderSettings old) {
    super.didUpdateWidget(old);
    if (old.backend != widget.backend) {
      _setup = null;
      _loadError = null;
      _makeError = null;
      _making = null;
      if (_supported) _load();
    }
  }

  static String _describe(Object error) =>
      error is KitError ? error.message : 'Something went wrong.';

  Future<void> _load() async {
    final ticket = ++_ticket;
    final backend = widget.backend;
    setState(() => _loadError = null);
    try {
      final setup = await backend.listProviders();
      if (!mounted || ticket != _ticket) return;
      setState(() => _setup = setup);
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() => _loadError = _describe(error));
    }
  }

  Future<void> _makeDefault(String id) async {
    final backend = widget.backend;
    final ticket = ++_ticket;
    setState(() {
      _making = id;
      _makeError = null;
    });
    try {
      final setup = await backend.setDefaultModel(id);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _setup = setup;
        _making = null;
      });
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _making = null;
        _makeError = 'Could not make $id the default. ${_describe(error)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    final theme = context.bb;
    final setup = _setup;
    if (setup != null) {
      return ProviderList(
        setup: setup,
        onMakeDefault:
            widget.backend.capabilities.has(KitCapability.defaultModel)
            ? _makeDefault
            : null,
        makingDefault: _making,
        error: _makeError,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SettingsHeading('Models'),
        if (_loadError == null)
          Text('Loading providers…', style: ts(theme.typeScale.ui, theme.faint))
        else ...[
          Text(
            'Could not load the providers. $_loadError',
            key: const ValueKey('provider-load-error'),
            style: ts(theme.typeScale.ui, theme.dangerInk),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: KitButton(
              key: const ValueKey('provider-retry'),
              label: 'Try again',
              onTap: _load,
            ),
          ),
        ],
      ],
    );
  }
}
