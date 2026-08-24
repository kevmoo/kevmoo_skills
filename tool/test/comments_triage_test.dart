import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import '../../skills/github-pr-triage/lib/github_cli.dart';

void main() {
  group('fetchPrGraphQLData tests', () {
    late Directory tempDir;
    late PrContext context;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('comments_triage_test_');
      context = PrContext(
        workingDir: tempDir.path,
        prNumber: '38',
        owner: 'dart-lang',
        repo: 'skills',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('extracts reviews, comments, and reviewThreads properly', () async {
      final mockGraphqlData = {
        'data': {
          'repository': {
            'pullRequest': {
              'comments': {
                'nodes': [
                  {
                    'databaseId': 1234567,
                    'author': {'login': 'alice'},
                    'body': 'This is a general conversation comment on the PR.',
                    'createdAt': '2026-08-24T06:00:00Z',
                    'url':
                        'https://github.com/dart-lang/skills/pull/38#issuecomment-1234567',
                  },
                ],
              },
              'reviews': {
                'nodes': [
                  {
                    'id': 'PRR_kwDORY_9Dc8AAAABKlLgCw',
                    'databaseId': 5005041675,
                    'author': {'login': 'bob'},
                    'body': '',
                    'state': 'COMMENTED',
                    'submittedAt': '2026-08-24T06:24:19Z',
                    'url':
                        'https://github.com/dart-lang/skills/pull/38#pullrequestreview-5005041675',
                  },
                  {
                    'id': 'PRR_kwDORY_9Dc8AAAABKlMYNQ',
                    'databaseId': 5005056053,
                    'author': {'login': 'kevmoo'},
                    'body':
                        'we should enable (at least) `dart analyze` and `dart format` for these files we\'ve added',
                    'state': 'COMMENTED',
                    'submittedAt': '2026-08-24T06:27:09Z',
                    'url':
                        'https://github.com/dart-lang/skills/pull/38#pullrequestreview-5005056053',
                  },
                ],
              },
              'reviewThreads': {
                'nodes': [
                  {
                    'id': 'PRRT_kwDORY_9Dc8AAAAB12345',
                    'isResolved': false,
                    'comments': {
                      'nodes': [
                        {
                          'databaseId': 9876543,
                          'author': {'login': 'charlie'},
                          'body': 'Please check this line.',
                          'path': 'lib/foo.dart',
                          'line': 42,
                          'originalLine': 42,
                          'createdAt': '2026-08-24T06:10:00Z',
                          'url':
                              'https://github.com/dart-lang/skills/pull/38#discussion_r9876543',
                        },
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      };

      final data = await fetchPrGraphQLData(
        context,
        runCommand: (command, args, {workingDirectory}) async {
          expect(command, equals('gh'));
          expect(args, contains('graphql'));
          return jsonEncode(mockGraphqlData);
        },
      );

      // Verify comments
      expect(data.comments, hasLength(1));
      final comment = data.comments.first;
      expect(comment.databaseId, equals('1234567'));
      expect(comment.author, equals('alice'));
      expect(
        comment.body,
        equals('This is a general conversation comment on the PR.'),
      );
      expect(comment.createdAt, equals('2026-08-24T06:00:00Z'));
      expect(
        comment.url,
        equals(
          'https://github.com/dart-lang/skills/pull/38#issuecomment-1234567',
        ),
      );

      // Verify reviews
      expect(data.reviews, hasLength(2));
      final emptyReview = data.reviews[0];
      expect(emptyReview.id, equals('PRR_kwDORY_9Dc8AAAABKlLgCw'));
      expect(emptyReview.databaseId, equals('5005041675'));
      expect(emptyReview.author, equals('bob'));
      expect(emptyReview.body, isEmpty);
      expect(emptyReview.state, equals('COMMENTED'));
      expect(emptyReview.submittedAt, equals('2026-08-24T06:24:19Z'));

      final substantiveReview = data.reviews[1];
      expect(substantiveReview.id, equals('PRR_kwDORY_9Dc8AAAABKlMYNQ'));
      expect(substantiveReview.databaseId, equals('5005056053'));
      expect(substantiveReview.author, equals('kevmoo'));
      expect(
        substantiveReview.body,
        equals(
          'we should enable (at least) `dart analyze` and `dart format` for these files we\'ve added',
        ),
      );
      expect(substantiveReview.state, equals('COMMENTED'));
      expect(
        substantiveReview.url,
        equals(
          'https://github.com/dart-lang/skills/pull/38#pullrequestreview-5005056053',
        ),
      );

      // Verify review threads
      expect(data.reviewThreads, hasLength(1));
      final thread = data.reviewThreads.first;
      expect(thread.id, equals('PRRT_kwDORY_9Dc8AAAAB12345'));
      expect(thread.isResolved, isFalse);
      expect(thread.comments, hasLength(1));
      expect(thread.comments.first.path, equals('lib/foo.dart'));
      expect(thread.comments.first.line, equals(42));
    });
  });
}
