import 'dart:convert';
import 'package:test/test.dart';

import '../../skills/author-issue/lib/orient.dart';

void main() {
  group('extractPrefix unit tests', () {
    test('extracts bracketed subsystem prefix', () {
      expect(
        extractPrefix('[analyzer] Crash with NullPointer'),
        equals('[analyzer]'),
      );
      expect(
        extractPrefix('[pkg/foo] Bar failure on condition'),
        equals('[pkg/foo]'),
      );
    });

    test('extracts conventional commit prefix with scope', () {
      expect(
        extractPrefix('feat(sidequest): modernize CLI ergonomics'),
        equals('feat(sidequest):'),
      );
      expect(
        extractPrefix('fix(github-pr-triage): handle empty review array'),
        equals('fix(github-pr-triage):'),
      );
    });

    test('extracts package colon prefix and normalizes whitespace', () {
      expect(
        extractPrefix('sidequest: add completion order numbers'),
        equals('sidequest:'),
      );
      expect(extractPrefix('fix:   Windows line ending bug'), equals('fix:'));
      expect(
        extractPrefix('request/question: support custom flags'),
        equals('request/question:'),
      );
    });

    test('returns null when title has no recognizable prefix', () {
      expect(extractPrefix('retire "deslop"'), isNull);
      expect(extractPrefix('Just a plain title'), isNull);
    });
  });

  group('isBotAccount unit tests', () {
    test('identifies bot accounts correctly', () {
      expect(isBotAccount('dependabot[bot]'), isTrue);
      expect(isBotAccount('github-actions'), isTrue);
      expect(isBotAccount('app/github-actions'), isTrue);
      expect(isBotAccount('copilot-pull-request-reviewer'), isTrue);
      expect(isBotAccount('renovate-bot'), isTrue);
      expect(isBotAccount('alice'), isFalse);
      expect(isBotAccount('kevmoo'), isFalse);
    });
  });

  group('extractYamlFormFields unit tests', () {
    test('extracts id and label from GitHub issue form YAML', () {
      const yaml = '''
name: Feature request
description: Suggest an idea for this project
body:
  - type: input
    id: command
    attributes:
      label: Command
      description: The command you are running
  - type: textarea
    id: description
    attributes:
      label: Description
  - type: textarea
    id: reasoning
    attributes:
      label: Reasoning
''';
      final fields = extractYamlFormFields(yaml);
      expect(
        fields,
        equals([
          'command (Command)',
          'description (Description)',
          'reasoning (Reasoning)',
        ]),
      );
    });
  });

  group('OrientationGatherer with mock runner', () {
    test('gathers GitHub repository conventions and maintainers', () async {
      final mockRunner =
          (
            String command,
            List<String> args, {
            String? workingDirectory,
          }) async {
            if (command == 'gh' && args.contains('view')) {
              return jsonEncode({'nameWithOwner': 'octocat/Hello-World'});
            }
            if (command == 'gh' && args.contains('pr')) {
              return jsonEncode([
                {
                  'title': 'feat(core): initial implementation',
                  'author': {'login': 'alice'},
                  'reviews': [
                    {
                      'author': {'login': 'bob'},
                    },
                    {
                      'author': {'login': 'copilot-pull-request-reviewer'},
                    },
                  ],
                  'labels': [
                    {'name': 'enhancement'},
                  ],
                },
                {
                  'title': 'fix(core): resolve race condition',
                  'author': {'login': 'bob'},
                  'reviews': [],
                  'labels': [
                    {'name': 'bug'},
                  ],
                },
              ]);
            }
            if (command == 'gh' && args.contains('issue')) {
              return jsonEncode([
                {
                  'title': '[core] Race condition in event bus',
                  'author': {'login': 'alice'},
                  'labels': [
                    {'name': 'bug'},
                  ],
                },
                {
                  'title': '[docs] Missing setup guide',
                  'author': {'login': 'charlie'},
                  'labels': [
                    {'name': 'documentation'},
                  ],
                },
              ]);
            }
            throw Exception('Unexpected command: $command ${args.join(' ')}');
          };

      final gatherer = OrientationGatherer(runCmd: mockRunner);
      final orientation = await gatherer.gather(workingDirectory: '/tmp/repo');

      expect(orientation.environment, equals('GitHub'));
      expect(orientation.repoSlug, equals('octocat/Hello-World'));
      expect(orientation.maintainers, containsAll(['alice', 'bob']));
      expect(
        orientation.maintainers,
        isNot(contains('copilot-pull-request-reviewer')),
      );
      expect(orientation.commonIssuePrefixes, contains('[core]'));
      expect(orientation.commonPrPrefixes, contains('feat(core):'));
      expect(
        orientation.detectedLabels,
        containsAll(['bug', 'enhancement', 'documentation']),
      );

      final markdown = orientation.toMarkdown();
      expect(markdown, contains('octocat/Hello-World'));
      expect(markdown, contains('@alice'));
      expect(markdown, contains('@bob'));
      expect(markdown, isNot(contains('@copilot')));
      expect(markdown, contains('`feat(core):`'));
      expect(markdown, contains('`[core]`'));
    });

    test('gathers remote repository conventions via repo parameter', () async {
      final mockRunner =
          (
            String command,
            List<String> args, {
            String? workingDirectory,
          }) async {
            if (command == 'gh' &&
                args.contains('pr') &&
                args.contains('invertase/melos')) {
              return jsonEncode([
                {
                  'title': 'feat(version): support smart dependent versioning',
                  'author': {'login': 'dev_user'},
                  'reviews': [],
                  'labels': [],
                },
              ]);
            }
            if (command == 'gh' &&
                args.contains('issue') &&
                args.contains('invertase/melos')) {
              return jsonEncode([
                {
                  'title': 'request: avoid cascading releases',
                  'author': {'login': 'dev_user'},
                  'labels': [],
                },
              ]);
            }
            if (command == 'gh' && args.contains('api')) {
              return jsonEncode([
                {
                  'path': '.github/ISSUE_TEMPLATE/feature_request.yml',
                  'download_url': 'https://example.com/template.yml',
                },
              ]);
            }
            throw Exception('Unexpected command: $command ${args.join(' ')}');
          };

      final gatherer = OrientationGatherer(runCmd: mockRunner);
      final orientation = await gatherer.gather(repo: 'invertase/melos');

      expect(orientation.environment, equals('GitHub'));
      expect(orientation.repoSlug, equals('invertase/melos'));
      expect(orientation.maintainers, contains('dev_user'));
      expect(orientation.commonIssuePrefixes, contains('request:'));
      expect(orientation.commonPrPrefixes, contains('feat(version):'));
      expect(
        orientation.detectedTemplates,
        contains('.github/ISSUE_TEMPLATE/feature_request.yml'),
      );
    });
  });
}
