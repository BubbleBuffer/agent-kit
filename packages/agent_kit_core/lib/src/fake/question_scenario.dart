/// A short script that ends with the mixed question request.
library;

import 'scripted_backend.dart';

/// The chat id of [mixedQuestionScript].
const questionChatId = 'stale-label';

/// The id of the request [mixedQuestionScript] asks.
const mixedQuestionId = 'qs1';

/// A chat that ends waiting on one request of three questions of different
/// kinds: pick one with descriptions and an "Other" row, pick any, and text
/// only. Status `needsYou`.
ChatScript mixedQuestionScript() => ChatScript(
  chatId: questionChatId,
  title: 'Stale quota figure',
  steps: [
    const ScriptStep(Duration.zero, {
      'kind': 'message.user',
      'itemId': 'u1',
      'text': 'Make the quota bar keep its last figure while we reconnect.',
    }),
    const ScriptStep(Duration.zero, {
      'kind': 'run.started',
      'runId': 'run-qs-1',
    }),
    const ScriptStep(Duration(seconds: 2), {
      'kind': 'question.asked',
      'question': {
        'id': mixedQuestionId,
        'items': [
          {
            'id': 'age',
            'header': 'Stale figure',
            'text': 'Should a stale quota figure show its age?',
            'kind': 'pickOne',
            'options': [
              {
                'label': 'Only on hover',
                'description': 'The bar dims; hovering shows the last update.',
              },
              {
                'label': 'Always',
                'description': 'A small age label sits next to the figure.',
              },
              {
                'label': 'Never',
                'description': 'Dimming alone marks it stale.',
              },
            ],
            'allowOther': true,
          },
          {
            'id': 'views',
            'header': 'Views',
            'text': 'Which views should keep the last known figure?',
            'kind': 'pickAny',
            'options': [
              {'label': 'Web quota bar'},
              {'label': 'Desktop tray'},
              {'label': 'CLI status line'},
            ],
            'allowOther': true,
          },
          {
            'id': 'label',
            'header': 'Label',
            'text': 'What should the stale label say?',
            'kind': 'text',
          },
        ],
      },
    }),
  ],
);
