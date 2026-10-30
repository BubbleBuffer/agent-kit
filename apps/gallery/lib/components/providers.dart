// Gallery entries of the providers group: the provider list as the settings
// section draws it, with a restart pending and without.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/widgets.dart';

ProviderSetup _setup({required bool reload}) => ProviderSetup(
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

class ProviderSpecimens extends StatelessWidget {
  const ProviderSpecimens({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    Widget boxed(double width, ProviderSetup setup) => Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        child: ColoredBox(
          color: t.surface,
          child: Padding(
            padding: EdgeInsets.all(t.spacing.lg),
            child: ProviderList(setup: setup, onMakeDefault: (_) {}),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        boxed(680, _setup(reload: false)),
        SizedBox(height: t.spacing.lg),
        boxed(680, _setup(reload: true)),
        SizedBox(height: t.spacing.lg),
        boxed(390, _setup(reload: false)),
      ],
    );
  }
}
