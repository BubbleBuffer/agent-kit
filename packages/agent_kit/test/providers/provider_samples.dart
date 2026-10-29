// A provider setup for the providers tests and goldens: one provider that
// needs no key, one whose key was found, one whose key is missing.

import 'package:agent_kit_core/agent_kit_core.dart';

ProviderSetup sampleProviders({bool reload = false}) => ProviderSetup(
  main: reload ? 'openrouter/deepseek-v4.1-flash' : 'demo/scripted',
  activeMain: 'demo/scripted',
  reloadNeeded: reload,
  providers: [
    ProviderInfo(
      name: 'demo',
      kind: 'scripted',
      models: const [ProviderModel(id: 'scripted')],
    ),
    ProviderInfo(
      name: 'openrouter',
      kind: 'openai-compatible',
      baseUrl: 'https://openrouter.ai/api/v1',
      keyEnv: 'OPENROUTER_API_KEY',
      keyPresent: true,
      models: const [
        ProviderModel(id: 'deepseek-v4.1-flash'),
        ProviderModel(id: 'qwen3-coder'),
      ],
    ),
    ProviderInfo(
      name: 'anthropic',
      kind: 'anthropic',
      keyEnv: 'ANTHROPIC_API_KEY',
      models: const [ProviderModel(id: 'haiku-5.5')],
    ),
  ],
);
