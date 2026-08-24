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

    test('extracts package colon prefix', () {
      expect(
        extractPrefix('sidequest: add completion order numbers'),
        equals('sidequest:'),
      );
      expect(
        extractPrefix('docs: update README with new skill'),
        equals('docs:'),
      );
    });

    test('returns null when title has no recognizable prefix', () {
      expect(extractPrefix('retire "deslop"'), isNull);
      expect(extractPrefix('Just a plain title'), isNull);
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
      expect(markdown, contains('`feat(core):`'));
      expect(markdown, contains('`[core]`'));
    });
  });
}
