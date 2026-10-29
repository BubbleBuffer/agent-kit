/// The host's model providers and its default model.
library;

import 'value.dart';

/// One model a provider offers.
final class ProviderModel extends KitValue {
  /// Creates a model.
  const ProviderModel({required this.id});

  /// Reads a model from JSON.
  factory ProviderModel.fromJson(Json j) => ProviderModel(id: j.str('id'));

  /// The model's own id, without the provider.
  final String id;

  @override
  Json toJson() => {'id': id};
}

/// A configured model provider. It never carries a key: [keyPresent] says
/// only whether the host found one.
final class ProviderInfo extends KitValue {
  /// Creates a provider.
  ProviderInfo({
    required this.name,
    required this.kind,
    this.baseUrl,
    this.keyEnv,
    this.keyPresent = false,
    List<ProviderModel> models = const [],
  }) : models = List.unmodifiable(models);

  /// Reads a provider from JSON.
  factory ProviderInfo.fromJson(Json j) => ProviderInfo(
    name: j.str('name'),
    kind: j.str('kind'),
    baseUrl: j.strOpt('baseUrl'),
    keyEnv: j.strOpt('keyEnv'),
    keyPresent: j.boolean('keyPresent'),
    models: j.listOf('models', ProviderModel.fromJson),
  );

  /// The provider's name, the part of a model id before the slash.
  final String name;

  /// The API family, such as `chat-completions`.
  final String kind;

  /// The endpoint, when the provider has one.
  final String? baseUrl;

  /// The name of the environment variable the host reads the key from: a
  /// name, never a value. Null when the provider needs no key.
  final String? keyEnv;

  /// Whether the host has the key it needs (always true without [keyEnv]).
  final bool keyPresent;

  /// The models the provider offers.
  final List<ProviderModel> models;

  /// The id `setDefaultModel` takes for [model]: `provider/model`.
  String qualify(ProviderModel model) => '$name/${model.id}';

  @override
  Json toJson() => compact({
    'name': name,
    'kind': kind,
    'baseUrl': baseUrl,
    'keyEnv': keyEnv,
    'keyPresent': keyPresent,
    'models': jsonList(models),
  });
}

/// The providers a host has configured and which model new runs use.
final class ProviderSetup extends KitValue {
  /// Creates a setup.
  ProviderSetup({
    this.main,
    this.activeMain,
    this.reloadNeeded = false,
    List<ProviderInfo> providers = const [],
  }) : providers = List.unmodifiable(providers);

  /// Reads a setup from JSON.
  factory ProviderSetup.fromJson(Json j) => ProviderSetup(
    main: j.strOpt('main'),
    activeMain: j.strOpt('activeMain'),
    reloadNeeded: j.boolean('reloadNeeded'),
    providers: j.listOf('providers', ProviderInfo.fromJson),
  );

  /// The default model as saved, `provider/model`.
  final String? main;

  /// The default model new runs use now. It differs from [main] while a
  /// saved change waits for the host to reload.
  final String? activeMain;

  /// Whether saved configuration differs from what the host applies.
  final bool reloadNeeded;

  /// The configured providers.
  final List<ProviderInfo> providers;

  /// The model new runs use: [activeMain], else [main].
  String? get defaultModel => activeMain ?? main;

  @override
  Json toJson() => compact({
    'main': main,
    'activeMain': activeMain,
    'reloadNeeded': reloadNeeded ? true : null,
    'providers': jsonList(providers),
  });
}
