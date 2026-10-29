// Maps the host's redacted provider setup (`providers.list`,
// `roles.set_main`) to the kit's models. The wire carries `key_present` and
// the name of the key variable, never a key value, and only those are read.

import 'package:agent_kit_core/agent_kit_core.dart';

/// The kit's view of a `providers.list` or `roles.set_main` result.
ProviderSetup providerSetup(Json wire) {
  final providers = wire['providers'];
  return ProviderSetup(
    main: _string(wire['main']),
    activeMain: _string(wire['active_main']),
    reloadNeeded: wire['reload_needed'] == true,
    providers: [
      if (providers is List<Object?>)
        for (final entry in providers)
          if (entry is Map<String, Object?> && _string(entry['name']) != null)
            _provider(entry),
    ],
  );
}

ProviderInfo _provider(Json wire) {
  final models = wire['models'];
  return ProviderInfo(
    name: _string(wire['name'])!,
    kind: _string(wire['kind']) ?? 'unknown',
    baseUrl: _string(wire['base_url']),
    keyEnv: _string(wire['key_env']),
    keyPresent: wire['key_present'] == true,
    models: [
      if (models is List<Object?>)
        for (final model in models)
          if (model is Map<String, Object?> && _string(model['id']) != null)
            ProviderModel(id: _string(model['id'])!),
    ],
  );
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// The models of [setup] as the composer's choices, labelled
/// `provider/model` (the id the host takes). A provider that needs a key it
/// does not have is left out, since its runs would fail.
List<KitChoice> modelChoices(ProviderSetup setup) => [
  for (final provider in setup.providers)
    if (provider.keyPresent || provider.keyEnv == null)
      for (final model in provider.models)
        KitChoice(
          id: provider.qualify(model),
          label: provider.qualify(model),
          detail: provider.kind,
        ),
];
