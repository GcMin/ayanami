import 'package:flutter_test/flutter_test.dart';

import 'package:ayanami/main.dart';

void main() {
  test('fixture source returns all content and filters by title/tag', () {
    expect(FixtureContentSource.search(''), hasLength(3));
    expect(FixtureContentSource.search('潮汐').single.id, 'fixture-ayanami');
    expect(FixtureContentSource.search('治愈').single.id, 'fixture-night');
    expect(FixtureContentSource.search('不存在'), isEmpty);
  });

  test('fixture chapter identity is stable and page count is positive', () {
    final chapter = FixtureContentSource.byId('fixture-cafe').chapters.first;
    expect(chapter.id, 'cafe-01');
    expect(chapter.mangaId, 'fixture-cafe');
    expect(chapter.pageCount, greaterThan(0));
  });
}
