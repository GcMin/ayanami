import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' hide Padding, State;
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(AyanamiApp(state: state));
}

class MangaFixture {
  const MangaFixture({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.author,
    required this.tags,
    required this.accent,
    required this.chapters,
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String author;
  final List<String> tags;
  final Color accent;
  final List<ChapterFixture> chapters;
}

class ChapterFixture {
  const ChapterFixture({
    required this.id,
    required this.mangaId,
    required this.title,
    required this.number,
    required this.pageCount,
  });

  final String id;
  final String mangaId;
  final String title;
  final String number;
  final int pageCount;
}

enum ReadingDirection { vertical, webtoon, leftToRight, rightToLeft }

enum ReaderScaleMode {
  originalSize,
  fitWidth,
  fitHeight,
  fitScreen,
  smartFit,
}

/// M0/M2 的固定内容适配器。后续接入源运行时时只替换这一层。
class FixtureContentSource {
  static final List<MangaFixture> mangas = [
    MangaFixture(
      id: 'fixture-ayanami',
      title: '绫波档案：潮汐回声',
      subtitle: 'Ayanami Archive',
      description: '一座被海雾包围的城市里，少女绫波在旧车站发现了一段会回应未来的录音。',
      author: 'Ayanami Fixture Studio',
      tags: ['科幻', '悬疑', '短篇'],
      accent: Color(0xff7c6cff),
      chapters: [
        ChapterFixture(
          id: 'ayanami-01',
          mangaId: 'fixture-ayanami',
          title: '潮汐开始的地方',
          number: '01',
          pageCount: 7,
        ),
        ChapterFixture(
          id: 'ayanami-02',
          mangaId: 'fixture-ayanami',
          title: '回声穿过月台',
          number: '02',
          pageCount: 8,
        ),
        ChapterFixture(
          id: 'ayanami-03',
          mangaId: 'fixture-ayanami',
          title: '没有终点的列车',
          number: '03',
          pageCount: 6,
        ),
      ],
    ),
    MangaFixture(
      id: 'fixture-night',
      title: '夜航灯塔',
      subtitle: 'Night Beacon',
      description: '灯塔守夜人每晚记录星光，直到某一天海面亮起了不属于这个世界的航标。',
      author: 'Ayanami Fixture Studio',
      tags: ['治愈', '奇幻', '连载'],
      accent: Color(0xff1bb7a7),
      chapters: [
        ChapterFixture(
          id: 'night-01',
          mangaId: 'fixture-night',
          title: '守夜人的第一盏灯',
          number: '01',
          pageCount: 6,
        ),
        ChapterFixture(
          id: 'night-02',
          mangaId: 'fixture-night',
          title: '海面上的星图',
          number: '02',
          pageCount: 7,
        ),
      ],
    ),
    MangaFixture(
      id: 'fixture-cafe',
      title: '星期八的咖啡馆',
      subtitle: 'Cafe on Day Eight',
      description: '如果一周有第八天，咖啡馆老板会把这一天留给那些还没说出口的话。',
      author: 'Ayanami Fixture Studio',
      tags: ['日常', '单元剧', '轻喜剧'],
      accent: Color(0xffe78d58),
      chapters: [
        ChapterFixture(
          id: 'cafe-01',
          mangaId: 'fixture-cafe',
          title: '请给我一杯星期八',
          number: '01',
          pageCount: 5,
        ),
        ChapterFixture(
          id: 'cafe-02',
          mangaId: 'fixture-cafe',
          title: '迟到的客人',
          number: '02',
          pageCount: 6,
        ),
      ],
    ),
  ];

  static MangaFixture byId(String id) =>
      mangas.firstWhere((manga) => manga.id == id);

  static List<MangaFixture> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return mangas;
    return mangas.where((manga) {
      return '${manga.title} ${manga.subtitle} ${manga.tags.join(' ')}'
          .toLowerCase()
          .contains(normalized);
    }).toList();
  }
}

class ManwaSearchResult {
  const ManwaSearchResult({
    required this.id,
    required this.title,
    required this.url,
    required this.coverUrl,
    required this.subtitle,
    this.requestId = '',
    this.sourceId = 'com.ayanami.source.manwa',
    this.sourceVersion = '0.1.0',
    this.resultKey = '',
  });

  final String id;
  final String title;
  final String url;
  final String coverUrl;
  final String subtitle;
  final String requestId;
  final String sourceId;
  final String sourceVersion;
  final String resultKey;

  ManwaSearchResult copyWith({String? requestId, String? resultKey}) =>
      ManwaSearchResult(
        id: id,
        title: title,
        url: url,
        coverUrl: coverUrl,
        subtitle: subtitle,
        requestId: requestId ?? this.requestId,
        sourceId: sourceId,
        sourceVersion: sourceVersion,
        resultKey: resultKey ?? this.resultKey,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'coverUrl': coverUrl,
        'subtitle': subtitle,
        'sourceId': sourceId,
        'sourceVersion': sourceVersion,
      };

  factory ManwaSearchResult.fromJson(Map<String, dynamic> json) =>
      ManwaSearchResult(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        url: '${json['url'] ?? ''}',
        coverUrl: '${json['coverUrl'] ?? ''}',
        subtitle: '${json['subtitle'] ?? ''}',
        sourceId: '${json['sourceId'] ?? 'com.ayanami.source.manwa'}',
        sourceVersion: '${json['sourceVersion'] ?? '0.1.0'}',
      );
}

class DiscoverySearchRequest {
  const DiscoverySearchRequest({
    required this.requestId,
    required this.keyword,
    required this.sourceIds,
  });
  final String requestId;
  final String keyword;
  final List<String> sourceIds;
}

class MangaDetailsRoute {
  const MangaDetailsRoute({
    required this.sourceId,
    required this.sourceVersion,
    required this.sourceMangaId,
    required this.mangaRefSnapshot,
  });
  final String sourceId;
  final String sourceVersion;
  final String sourceMangaId;
  final ManwaSearchResult mangaRefSnapshot;
}

class ManwaChapter {
  const ManwaChapter({
    required this.id,
    required this.mangaId,
    required this.title,
    required this.url,
    required this.chapterNumber,
  });
  final String id;
  final String mangaId;
  final String title;
  final String url;
  final String chapterNumber;

  Map<String, dynamic> toJson() => {
        'id': id,
        'mangaId': mangaId,
        'title': title,
        'url': url,
        'chapterNumber': chapterNumber,
      };

  factory ManwaChapter.fromJson(Map<String, dynamic> json) => ManwaChapter(
        id: '${json['id'] ?? ''}',
        mangaId: '${json['mangaId'] ?? ''}',
        title: '${json['title'] ?? ''}',
        url: '${json['url'] ?? ''}',
        chapterNumber: '${json['chapterNumber'] ?? ''}',
      );
}

class ManwaChapterContent {
  const ManwaChapterContent({
    required this.chapter,
    required this.pageUrls,
    this.cachedPagePaths = const [],
    this.cacheError,
  });

  final ManwaChapter chapter;
  final List<String> pageUrls;
  final List<String?> cachedPagePaths;
  final String? cacheError;
}

class ChapterCacheRecord {
  const ChapterCacheRecord({required this.pageUrls, required this.paths});

  final List<String> pageUrls;
  final List<String?> paths;
}

class ManwaDetails {
  const ManwaDetails({
    required this.id,
    required this.title,
    required this.url,
    required this.coverUrl,
    required this.alternativeTitles,
    required this.authors,
    required this.description,
    required this.status,
    required this.latestChapter,
    this.chapters = const [],
    this.chaptersError,
  });

  final String id;
  final String title;
  final String url;
  final String coverUrl;
  final List<String> alternativeTitles;
  final List<String> authors;
  final String description;
  final String status;
  final String latestChapter;
  final List<ManwaChapter> chapters;
  final String? chaptersError;

  ManwaDetails copyWith({
    List<ManwaChapter>? chapters,
    String? chaptersError,
  }) => ManwaDetails(
    id: id,
    title: title,
    url: url,
    coverUrl: coverUrl,
    alternativeTitles: alternativeTitles,
    authors: authors,
    description: description,
    status: status,
    latestChapter: latestChapter,
    chapters: chapters ?? this.chapters,
    chaptersError: chaptersError,
  );
}

/// 受限 JS 源适配器：JS 只生成请求描述和解析结果，网络由宿主执行。
class ManwaSourceService {
  static const allowedHosts = {'manwa.me', 'manwaqb.cc', 'mwappimgs.cc'};
  JavascriptRuntime? _runtime;
  bool _loaded = false;

  Future<void> prepare() async {
    if (_loaded) return;
    _runtime = getJavascriptRuntime(xhr: false);
    final source = await rootBundle.loadString('assets/sources/manwa.js');
    final result = _runtime!.evaluate(source, sourceUrl: 'manwa.js');
    if (result.isError) throw StateError('漫蛙 JS 源加载失败');
    _loaded = true;
  }

  Future<dynamic> _call(String functionName, Map<String, dynamic> input) async {
    await prepare();
    final argument = jsonEncode(input);
    final result = _runtime!.evaluate(
      'JSON.stringify($functionName($argument))',
    );
    if (result.isError) throw StateError('漫蛙 JS 源调用失败：$functionName');
    return jsonDecode(result.stringResult);
  }

  Future<String> _request(Map<String, dynamic> request) async {
    final path = request['path'] as String?;
    if (path == null || !path.startsWith('/')) throw StateError('漫蛙源返回了非法路径');
    final query =
        (request['query'] as Map?)?.map(
          (key, value) => MapEntry('$key', '$value'),
        ) ??
        <String, String>{};
    final uri = Uri.https('manwaqb.cc', path, query);
    final response = await http.get(
      uri,
      headers: const {'User-Agent': 'Ayanami/0.1 (source runtime)'},
    );
    final finalHost = response.request?.url.host;
    if (finalHost == null || !allowedHosts.contains(finalHost)) {
      throw StateError('漫蛙源重定向到未声明域名');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('漫蛙源请求失败：HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<List<ManwaSearchResult>> search(String keyword) async {
    final request = await _call('search', {'keyword': keyword});
    final html = await _request(Map<String, dynamic>.from(request as Map));
    final parsed = await _call('parseSearch', {'response': html});
    final items = (parsed['items'] as List? ?? const []);
    return items.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return ManwaSearchResult(
        id: '${map['id']}',
        title: '${map['title'] ?? '未命名漫画'}',
        url: '${map['url'] ?? ''}',
        coverUrl: '${map['coverUrl'] ?? ''}',
        subtitle: '${map['subtitle'] ?? ''}',
      );
    }).toList();
  }

  Future<ManwaDetails> getDetails(ManwaSearchResult ref) async {
    final request = await _call('getMangaDetails', {
      'id': ref.id,
      'title': ref.title,
      'url': ref.url,
    });
    final html = await _request(Map<String, dynamic>.from(request as Map));
    final parsed = await _call('parseDetails', {
      'response': html,
      'id': ref.id,
    });
    return ManwaDetails(
      id: '${parsed['id'] ?? ref.id}',
      title: '${parsed['title'] ?? ref.title}',
      url: '${parsed['url'] ?? ref.url}',
      coverUrl: '${parsed['coverUrl'] ?? ref.coverUrl}',
      alternativeTitles: [
        for (final item in (parsed['alternativeTitles'] as List? ?? const []))
          '$item',
      ],
      authors: [
        for (final item in (parsed['authors'] as List? ?? const [])) '$item',
      ],
      description: '${parsed['description'] ?? ''}',
      status: '${parsed['status'] ?? 'unknown'}',
      latestChapter: '${parsed['latestChapter'] ?? ''}',
    );
  }

  Future<List<ManwaChapter>> getChapters(ManwaDetails details) async {
    final request = await _call('getChapters', {
      'id': details.id,
      'title': details.title,
      'url': details.url,
    });
    final html = await _request(Map<String, dynamic>.from(request as Map));
    final parsed = await _call('parseChapters', {
      'response': html,
      'mangaId': details.id,
    });
    final items = (parsed as List? ?? const []);
    return items.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return ManwaChapter(
        id: '${map['id']}',
        mangaId: '${map['mangaId'] ?? details.id}',
        title: '${map['title'] ?? '未命名章节'}',
        url: '${map['url'] ?? ''}',
        chapterNumber: '${map['chapterNumber'] ?? ''}',
      );
    }).toList();
  }

  Future<List<String>> getChapterPages(ManwaChapter chapter) async {
    final request = await _call('getChapterPages', {
      'id': chapter.id,
      'mangaId': chapter.mangaId,
      'title': chapter.title,
      'url': chapter.url,
    });
    final html = await _request(Map<String, dynamic>.from(request as Map));
    final parsed = await _call('parseChapterPages', {
      'response': html,
      'chapterId': chapter.id,
    });
    final items = (parsed as List? ?? const []);
    return items
        .map((item) => '${Map<String, dynamic>.from(item as Map)['url'] ?? ''}')
        .where((url) => url.isNotEmpty)
        .toList();
  }

  Future<ManwaDetails> loadDetailsAndChapters(ManwaSearchResult ref) async {
    final details = await getDetails(ref);
    try {
      return details.copyWith(chapters: await getChapters(details));
    } catch (error) {
      return details.copyWith(chaptersError: '$error');
    }
  }
}

class ManwaChapterCache {
  static const allowedHosts = {'mwappimgs.cc', 'manwaqb.cc', 'manwa.me'};

  Future<Directory> _chapterDirectory(String chapterId) async {
    final root = await getApplicationDocumentsDirectory();
    final safeId = chapterId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return Directory('${root.path}/chapter_cache/manwa/$safeId');
  }

  Future<String?> cacheCover(String coverId, String url) async {
    final root = await getApplicationDocumentsDirectory();
    final safeId = coverId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final directory = Directory('${root.path}/cache/images/covers/manwa');
    final file = File('${directory.path}/$safeId.img');
    if (await file.exists() && await file.length() > 0) return file.path;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || !allowedHosts.contains(uri.host)) {
      return null;
    }
    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'Ayanami/0.1 (cover cache)',
        'Referer': 'https://manwaqb.cc/',
      },
    );
    final finalHost = response.request?.url.host;
    if (response.statusCode < 200 || response.statusCode >= 300 ||
        finalHost == null || !allowedHosts.contains(finalHost)) {
      return null;
    }
    final bytes = ManwaImageCodec.decode(response.bodyBytes);
    await directory.create(recursive: true);
    final temp = File('${file.path}.part');
    await temp.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
    return file.path;
  }

  Future<ChapterCacheRecord?> read(String chapterId) async {
    final directory = await _chapterDirectory(chapterId);
    final manifest = File('${directory.path}/manifest.json');
    if (!await manifest.exists()) return null;
    try {
      final data = jsonDecode(await manifest.readAsString());
      final urls = [for (final url in (data['urls'] as List? ?? const [])) '$url'];
      final paths = [
        for (final path in (data['paths'] as List? ?? const []))
          path == null ? null : '$path',
      ];
      if (urls.isEmpty || urls.length != paths.length) return null;
      for (var index = 0; index < paths.length; index++) {
        final path = paths[index];
        if (path != null && !await File(path).exists()) paths[index] = null;
      }
      return ChapterCacheRecord(pageUrls: urls, paths: paths);
    } catch (_) {
      return null;
    }
  }

  Future<ChapterCacheRecord> cache(
    String chapterId,
    List<String> pageUrls,
  ) async {
    final existing = await read(chapterId);
    if (existing != null &&
        _sameUrls(existing.pageUrls, pageUrls) &&
        existing.paths.every((path) => path != null)) {
      return existing;
    }
    final directory = await _chapterDirectory(chapterId);
    final temp = Directory('${directory.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
    await temp.create(recursive: true);
    try {
      final paths = <String?>[];
      for (var index = 0; index < pageUrls.length; index++) {
        final uri = Uri.tryParse(pageUrls[index]);
        if (uri == null || uri.scheme != 'https' || !allowedHosts.contains(uri.host)) {
          throw StateError('章节图片域名未声明：${pageUrls[index]}');
        }
        final response = await http.get(
          uri,
          headers: const {
            'User-Agent': 'Ayanami/0.1 (chapter cache)',
            'Referer': 'https://manwaqb.cc/',
          },
        );
        final finalHost = response.request?.url.host;
        if (response.statusCode < 200 || response.statusCode >= 300 ||
            finalHost == null || !allowedHosts.contains(finalHost)) {
          throw StateError('章节图片请求失败：HTTP ${response.statusCode}');
        }
        final file = File('${temp.path}/page_${index.toString().padLeft(4, '0')}.img');
        await file.writeAsBytes(
          ManwaImageCodec.decode(response.bodyBytes),
          flush: true,
        );
        paths.add('${directory.path}/${file.uri.pathSegments.last}');
      }
      final manifest = File('${temp.path}/manifest.json');
      await manifest.writeAsString(
        jsonEncode({'urls': pageUrls, 'paths': paths}),
        flush: true,
      );
      if (await directory.exists()) await directory.delete(recursive: true);
      await temp.rename(directory.path);
      return ChapterCacheRecord(pageUrls: pageUrls, paths: paths);
    } catch (_) {
      if (await temp.exists()) await temp.delete(recursive: true);
      rethrow;
    }
  }

  Future<ChapterCacheRecord> cachePages(
    String chapterId,
    List<String> pageUrls,
    Iterable<int> indexes,
  ) async {
    final existing = await read(chapterId);
    final paths = _sameUrls(existing?.pageUrls ?? const [], pageUrls)
        ? [...existing!.paths]
        : List<String?>.filled(pageUrls.length, null);
    final directory = await _chapterDirectory(chapterId);
    await directory.create(recursive: true);
    for (final index in indexes) {
      if (index < 0 || index >= pageUrls.length || paths[index] != null) {
        continue;
      }
      final response = await _downloadImage(pageUrls[index]);
      final file = File(
        '${directory.path}/page_${index.toString().padLeft(4, '0')}.img',
      );
      final temp = File('${file.path}.part');
      await temp.writeAsBytes(ManwaImageCodec.decode(response.bodyBytes), flush: true);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
      paths[index] = file.path;
      await _writeManifest(directory, pageUrls, paths);
    }
    return ChapterCacheRecord(pageUrls: pageUrls, paths: paths);
  }

  Future<List<String>> downloadChapter(
    String chapterId,
    List<String> pageUrls,
  ) async {
    final cached = await cache(chapterId, pageUrls);
    final root = await getApplicationDocumentsDirectory();
    final safeId = chapterId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final directory = Directory('${root.path}/manga/manwa/$safeId/pages');
    await directory.create(recursive: true);
    final paths = <String>[];
    for (var index = 0; index < cached.paths.length; index++) {
      final sourcePath = cached.paths[index];
      if (sourcePath == null) throw StateError('章节存在未完成缓存页面');
      final destination = File(
        '${directory.path}/${index.toString().padLeft(6, '0')}.img',
      );
      if (!await destination.exists()) {
        await File(sourcePath).copy(destination.path);
      }
      paths.add(destination.path);
    }
    await File('${directory.parent.path}/chapter.json').writeAsString(
      jsonEncode({'chapterId': chapterId, 'urls': pageUrls, 'paths': paths}),
      flush: true,
    );
    return paths;
  }

  Future<http.Response> _downloadImage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || !allowedHosts.contains(uri.host)) {
      throw StateError('章节图片域名未声明：$url');
    }
    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'Ayanami/0.1 (chapter cache)',
        'Referer': 'https://manwaqb.cc/',
      },
    );
    final finalHost = response.request?.url.host;
    if (response.statusCode < 200 || response.statusCode >= 300 ||
        finalHost == null || !allowedHosts.contains(finalHost)) {
      throw StateError('章节图片请求失败：HTTP ${response.statusCode}');
    }
    return response;
  }

  Future<void> _writeManifest(
    Directory directory,
    List<String> urls,
    List<String?> paths,
  ) async {
    await File('${directory.path}/manifest.json').writeAsString(
      jsonEncode({'urls': urls, 'paths': paths}),
      flush: true,
    );
  }

  bool _sameUrls(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class ManwaImageCodec {
  static final Uint8List _key = Uint8List.fromList(
    utf8.encode('my2ecret782ecret'),
  );

  static Uint8List decode(List<int> bytes) {
    final input = Uint8List.fromList(bytes);
    if (_looksLikeImage(input)) return input;
    if (input.length < 16 || input.length % 16 != 0) {
      throw const FormatException('漫蛙图片数据长度无效');
    }
    final cipher = CBCBlockCipher(AESEngine())
      ..init(
        false,
        ParametersWithIV<KeyParameter>(KeyParameter(_key), _key),
      );
    final output = Uint8List(input.length);
    for (var offset = 0; offset < input.length; offset += cipher.blockSize) {
      cipher.processBlock(input, offset, output, offset);
    }
    final padding = output.last;
    if (padding < 1 || padding > cipher.blockSize) {
      throw const FormatException('漫蛙图片解密填充无效');
    }
    for (var index = output.length - padding; index < output.length; index++) {
      if (output[index] != padding) {
        throw const FormatException('漫蛙图片解密校验失败');
      }
    }
    final decoded = Uint8List.sublistView(output, 0, output.length - padding);
    if (!_looksLikeImage(decoded)) {
      throw const FormatException('漫蛙图片解密结果无效');
    }
    return decoded;
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return true;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }
}

class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;
  final ManwaSourceService manwaSource = ManwaSourceService();
  final ManwaChapterCache manwaChapterCache = ManwaChapterCache();
  final Set<String> libraryIds = <String>{};
  final Set<String> downloadedChapterIds = <String>{};
  final Set<String> downloadingChapterIds = <String>{};
  final Map<String, double> downloadProgress = <String, double>{};
  final Map<String, ManwaChapter> downloadedManwaChapters =
      <String, ManwaChapter>{};
  final Set<String> downloadingManwaChapterIds = <String>{};
  final Map<String, double> manwaDownloadProgress = <String, double>{};
  final Map<String, ManwaSearchResult> remoteLibrary =
      <String, ManwaSearchResult>{};
  final Set<String> _preloadingPageKeys = <String>{};
  final Map<String, int> readingProgress = <String, int>{};
  bool manwaInstalled = false;
  bool manwaEnabled = false;
  bool autoCacheChapter = true;
  ReadingDirection readerDirection = ReadingDirection.vertical;
  ReaderScaleMode readerScaleMode = ReaderScaleMode.fitWidth;
  bool remoteSearching = false;
  List<ManwaSearchResult> remoteResults = const [];
  String? remoteSearchError;
  String? activeSearchRequestId;
  int searchSequence = 0;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    manwaInstalled = _prefs.getBool('source_manwa_installed') ?? false;
    manwaEnabled = _prefs.getBool('source_manwa_enabled') ?? manwaInstalled;
    autoCacheChapter = _prefs.getBool('auto_cache_chapter') ?? true;
    readerDirection = _readingDirectionFromString(
      _prefs.getString('reader_direction'),
    );
    readerScaleMode = _readerScaleFromString(
      _prefs.getString('reader_scale_mode'),
    );
    libraryIds.addAll(_prefs.getStringList('library_ids') ?? const []);
    downloadedChapterIds.addAll(
      _prefs.getStringList('downloaded_chapters') ?? const [],
    );
    for (final raw in _prefs.getStringList('library_remote') ?? const []) {
      try {
        final result = ManwaSearchResult.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        remoteLibrary[result.id] = result;
      } catch (_) {}
    }
    for (final raw in _prefs.getStringList('downloaded_manwa_chapters') ??
        const []) {
      try {
        final chapter = ManwaChapter.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        downloadedManwaChapters[chapter.id] = chapter;
      } catch (_) {}
    }
    for (final manga in FixtureContentSource.mangas) {
      for (final chapter in manga.chapters) {
        final page = _prefs.getInt('progress_${chapter.id}');
        if (page != null) readingProgress[chapter.id] = page;
        final persistedState = _prefs.getString('download_state_${chapter.id}');
        if (persistedState == 'downloading' &&
            !downloadedChapterIds.contains(chapter.id)) {
          downloadingChapterIds.add(chapter.id);
          downloadProgress[chapter.id] =
              _prefs.getDouble('download_progress_${chapter.id}') ?? 0;
          unawaited(_resumeDownload(chapter));
        }
      }
    }
  }

  Future<void> installManwaSource() async {
    await manwaSource.prepare();
    manwaInstalled = true;
    manwaEnabled = true;
    await _prefs.setBool('source_manwa_installed', true);
    await _prefs.setBool('source_manwa_enabled', true);
    notifyListeners();
  }

  Future<void> setManwaEnabled(bool enabled) async {
    if (!manwaInstalled) return;
    manwaEnabled = enabled;
    await _prefs.setBool('source_manwa_enabled', enabled);
    if (!enabled) activeSearchRequestId = null;
    notifyListeners();
  }

  Future<void> setAutoCacheChapter(bool enabled) async {
    autoCacheChapter = enabled;
    await _prefs.setBool('auto_cache_chapter', enabled);
    notifyListeners();
  }

  Future<void> setReaderDirection(ReadingDirection direction) async {
    readerDirection = direction;
    await _prefs.setString('reader_direction', direction.name);
    notifyListeners();
  }

  Future<void> setReaderScaleMode(ReaderScaleMode mode) async {
    readerScaleMode = mode;
    await _prefs.setString('reader_scale_mode', mode.name);
    notifyListeners();
  }


  ReadingDirection _readingDirectionFromString(String? value) =>
      ReadingDirection.values.firstWhere(
        (item) => item.name == value,
        orElse: () => ReadingDirection.vertical,
      );

  ReaderScaleMode _readerScaleFromString(String? value) =>
      ReaderScaleMode.values.firstWhere(
        (item) => item.name == value,
        orElse: () => ReaderScaleMode.fitWidth,
      );

  Future<String?> cacheManwaCover(String id, String url) =>
      manwaChapterCache.cacheCover(id, url);

  bool isRemoteInLibrary(String mangaId) => remoteLibrary.containsKey(mangaId);

  Future<void> toggleRemoteLibrary(ManwaSearchResult result) async {
    if (remoteLibrary.remove(result.id) == null) {
      remoteLibrary[result.id] = result;
    }
    await _prefs.setStringList(
      'library_remote',
      remoteLibrary.values.map((item) => jsonEncode(item.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> searchManwa(String keyword) async {
    final normalized = keyword.trim();
    if (normalized.isEmpty) return;
    if (!manwaInstalled || !manwaEnabled) {
      remoteSearchError = '漫蛙 JS 源未安装或未启用';
      remoteResults = const [];
      notifyListeners();
      return;
    }
    final request = DiscoverySearchRequest(
      requestId:
          'discovery-${DateTime.now().microsecondsSinceEpoch}-${++searchSequence}',
      keyword: normalized.length > 128
          ? normalized.substring(0, 128)
          : normalized,
      sourceIds: const ['com.ayanami.source.manwa'],
    );
    activeSearchRequestId = request.requestId;
    remoteSearching = true;
    remoteSearchError = null;
    remoteResults = const [];
    notifyListeners();
    try {
      final results = await manwaSource.search(request.keyword);
      if (activeSearchRequestId != request.requestId) return;
      remoteResults = results
          .map(
            (result) => result.copyWith(
              requestId: request.requestId,
              resultKey: '${result.sourceId}:${result.id}',
            ),
          )
          .toList();
    } catch (error) {
      if (activeSearchRequestId != request.requestId) return;
      remoteResults = const [];
      remoteSearchError = error.toString().replaceFirst('Bad state: ', '');
    } finally {
      if (activeSearchRequestId == request.requestId) {
        remoteSearching = false;
        notifyListeners();
      }
    }
  }

  void clearRemoteSearch() {
    remoteResults = const [];
    remoteSearchError = null;
    remoteSearching = false;
    activeSearchRequestId = null;
    notifyListeners();
  }

  Future<ManwaDetails> loadManwaDetails(ManwaSearchResult result) {
    if (!manwaInstalled ||
        !manwaEnabled ||
        result.sourceId != 'com.ayanami.source.manwa') {
      throw StateError('该结果来源已禁用或不可用');
    }
    final route = MangaDetailsRoute(
      sourceId: result.sourceId,
      sourceVersion: result.sourceVersion,
      sourceMangaId: result.id,
      mangaRefSnapshot: result,
    );
    return manwaSource.loadDetailsAndChapters(route.mangaRefSnapshot);
  }

  Future<ManwaChapterContent> loadManwaChapter(ManwaChapter chapter) async {
    final cached = await manwaChapterCache.read(chapter.id);
    try {
      final pageUrls = await manwaSource.getChapterPages(chapter);
      if (pageUrls.isEmpty) throw StateError('该章节没有可显示的漫画图片');
      return ManwaChapterContent(
        chapter: chapter,
        pageUrls: pageUrls,
        cachedPagePaths: cached != null && _sameUrls(cached.pageUrls, pageUrls)
            ? cached.paths
            : const [],
      );
    } catch (error) {
      if (cached != null) {
        return ManwaChapterContent(
          chapter: chapter,
          pageUrls: cached.pageUrls,
          cachedPagePaths: cached.paths,
          cacheError: '在线刷新失败，正在使用本地缓存：$error',
        );
      }
      rethrow;
    }
  }

  Future<void> preloadAllManwaPages(ManwaChapterContent content) async {
    if (!autoCacheChapter) return;
    final indexes = <int>[];
    for (var index = 0; index < content.pageUrls.length; index++) {
      if (_preloadingPageKeys.add('${content.chapter.id}:$index')) {
        indexes.add(index);
      }
    }
    if (indexes.isEmpty) return;
    try {
      await manwaChapterCache.cachePages(
        content.chapter.id,
        content.pageUrls,
        indexes,
      );
    } finally {
      for (final index in indexes) {
        _preloadingPageKeys.remove('${content.chapter.id}:$index');
      }
    }
  }

  bool isManwaChapterDownloaded(String chapterId) =>
      downloadedManwaChapters.containsKey(chapterId);

  Future<void> downloadManwaChapter(ManwaChapter chapter) async {
    if (isManwaChapterDownloaded(chapter.id) ||
        downloadingManwaChapterIds.contains(chapter.id)) {
      return;
    }
    downloadingManwaChapterIds.add(chapter.id);
    manwaDownloadProgress[chapter.id] = 0;
    notifyListeners();
    try {
      final pages = await manwaSource.getChapterPages(chapter);
      if (pages.isEmpty) throw StateError('该章节没有可下载图片');
      await manwaChapterCache.downloadChapter(chapter.id, pages);
      manwaDownloadProgress.remove(chapter.id);
      downloadingManwaChapterIds.remove(chapter.id);
      downloadedManwaChapters[chapter.id] = chapter;
      await _prefs.setStringList(
        'downloaded_manwa_chapters',
        downloadedManwaChapters.values
            .map((item) => jsonEncode(item.toJson()))
            .toList(),
      );
    } catch (_) {
      downloadingManwaChapterIds.remove(chapter.id);
      manwaDownloadProgress.remove(chapter.id);
    }
    notifyListeners();
  }

  void saveManwaProgress(ManwaChapter chapter, int page) {
    final key = 'progress_manwa_${chapter.id}';
    _prefs.setInt(key, page);
  }

  int manwaProgressFor(ManwaChapter chapter) =>
      _prefs.getInt('progress_manwa_${chapter.id}') ?? 0;

  bool _sameUrls(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void toggleLibrary(String mangaId) {
    if (!libraryIds.add(mangaId)) libraryIds.remove(mangaId);
    _prefs.setStringList('library_ids', libraryIds.toList());
    notifyListeners();
  }

  bool isInLibrary(String mangaId) => libraryIds.contains(mangaId);

  void saveProgress(ChapterFixture chapter, int page) {
    final safePage = page.clamp(0, chapter.pageCount - 1);
    readingProgress[chapter.id] = safePage;
    _prefs.setInt('progress_${chapter.id}', safePage);
    notifyListeners();
  }

  int progressFor(ChapterFixture chapter) => readingProgress[chapter.id] ?? 0;

  bool isDownloaded(ChapterFixture chapter) =>
      downloadedChapterIds.contains(chapter.id);

  Future<void> download(ChapterFixture chapter) async {
    if (isDownloaded(chapter) || downloadingChapterIds.contains(chapter.id)) {
      return;
    }
    downloadingChapterIds.add(chapter.id);
    downloadProgress[chapter.id] = 0;
    await _prefs.setString('download_state_${chapter.id}', 'downloading');
    notifyListeners();
    await _resumeDownload(chapter);
  }

  Future<void> _resumeDownload(ChapterFixture chapter) async {
    if (isDownloaded(chapter)) return;
    downloadingChapterIds.add(chapter.id);
    var current = downloadProgress[chapter.id] ?? 0;
    while (current < 1) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      current = (current + 0.2).clamp(0, 1);
      downloadProgress[chapter.id] = current;
      await _prefs.setDouble('download_progress_${chapter.id}', current);
      notifyListeners();
    }
    downloadingChapterIds.remove(chapter.id);
    downloadProgress.remove(chapter.id);
    downloadedChapterIds.add(chapter.id);
    await _prefs.setStringList(
      'downloaded_chapters',
      downloadedChapterIds.toList(),
    );
    await _prefs.setString('download_state_${chapter.id}', 'completed');
    notifyListeners();
  }

  Future<void> removeDownload(ChapterFixture chapter) async {
    downloadedChapterIds.remove(chapter.id);
    downloadingChapterIds.remove(chapter.id);
    downloadProgress.remove(chapter.id);
    await _prefs.setStringList(
      'downloaded_chapters',
      downloadedChapterIds.toList(),
    );
    await _prefs.remove('download_state_${chapter.id}');
    await _prefs.remove('download_progress_${chapter.id}');
    notifyListeners();
  }
}

class AyanamiApp extends StatelessWidget {
  const AyanamiApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Ayanami',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff7566ee),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xfff8f7fc),
            cardTheme: const CardThemeData(
              margin: EdgeInsets.zero,
              elevation: 0,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          home: HomeShell(state: state),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});
  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    const titles = ['发现', '书架', '下载', '设置'];
    final pages = [
      DiscoverPage(state: widget.state),
      LibraryPage(state: widget.state),
      DownloadsPage(state: widget.state),
      SettingsPage(state: widget.state),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SourceManagementPage(state: widget.state),
              ),
            ),
            icon: const Icon(Icons.extension_outlined),
            label: const Text('JS 源'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => setState(() => selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '发现',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: '下载',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.state});
  final AppState state;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final controller = TextEditingController();
  Timer? searchDebounce;
  String query = '';

  @override
  void dispose() {
    searchDebounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = FixtureContentSource.search(query);
    final showFixtureResults = query.trim().isEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        TextField(
          controller: controller,
          onChanged: (value) {
            setState(() => query = value);
            searchDebounce?.cancel();
            if (value.trim().isNotEmpty && widget.state.manwaInstalled) {
              searchDebounce = Timer(
                const Duration(milliseconds: 650),
                () => widget.state.searchManwa(value),
              );
            } else if (value.trim().isEmpty) {
              widget.state.clearRemoteSearch();
            }
          },
          onSubmitted: widget.state.manwaInstalled
              ? widget.state.searchManwa
              : null,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: widget.state.manwaInstalled
                ? '搜索已安装的 JS 源'
                : '搜索测试漫画、作者或标签',
            suffixIcon: IconButton(
              tooltip: '搜索',
              onPressed: query.trim().isEmpty
                  ? null
                  : () => widget.state.searchManwa(query),
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _SectionTitle(
          title: showFixtureResults ? '本地测试内容' : '漫蛙搜索结果',
          trailing: showFixtureResults ? 'fixture' : 'com.ayanami.source.manwa',
        ),
        if (showFixtureResults) ...[
          const SizedBox(height: 12),
          _FeaturedManga(
            manga: FixtureContentSource.mangas.first,
            onTap: () => _openDetail(FixtureContentSource.mangas.first),
          ),
          const SizedBox(height: 24),
        ],
        if (!showFixtureResults && !widget.state.manwaInstalled)
          _InstallSourcePrompt(onInstall: () => _openSourceManager(context))
        else if (!showFixtureResults && widget.state.remoteSearching)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!showFixtureResults && widget.state.remoteSearchError != null)
          _SourceError(
            message: widget.state.remoteSearchError!,
            onRetry: () => widget.state.searchManwa(query),
          )
        else if (!showFixtureResults && widget.state.remoteResults.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('漫蛙没有匹配结果')),
          )
        else if (showFixtureResults && results.isNotEmpty)
          ...results.map(
            (manga) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MangaListTile(
                manga: manga,
                state: widget.state,
                onTap: () => _openDetail(manga),
              ),
            ),
          ),
        if (!showFixtureResults)
          ...widget.state.remoteResults.map(
            (result) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ManwaListTile(
                result: result,
                state: widget.state,
                onTap: () => _openRemoteDetail(result),
              ),
            ),
          ),
        if (showFixtureResults) ...[
          const SizedBox(height: 12),
          const _FixtureNotice(),
          const SizedBox(height: 12),
          _InstalledSourceCard(
            state: widget.state,
            onTap: () => _openSourceManager(context),
          ),
        ],
      ],
    );
  }

  void _openDetail(MangaFixture manga) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MangaDetailPage(manga: manga, state: widget.state),
      ),
    );
  }

  void _openRemoteDetail(ManwaSearchResult result) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManwaDetailPage(result: result, state: widget.state),
      ),
    );
  }

  void _openSourceManager(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SourceManagementPage(state: widget.state),
      ),
    );
  }
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.state});
  final AppState state;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final Set<String> selected = <String>{};
  bool selecting = false;

  String _remoteKey(ManwaSearchResult result) =>
      'remote:${result.sourceId}:${result.id}';

  String _fixtureKey(MangaFixture manga) => 'fixture:${manga.id}';

  void _toggle(String key) {
    setState(() {
      if (!selected.add(key)) selected.remove(key);
    });
  }

  Future<void> _downloadSelected(
    BuildContext context,
    List<ManwaSearchResult> remoteMangas,
    List<MangaFixture> mangas,
  ) async {
    final selectedRemote = remoteMangas
        .where((item) => selected.contains(_remoteKey(item)))
        .toList();
    final selectedFixtures =
        mangas.where((item) => selected.contains(_fixtureKey(item))).toList();
    if (selectedRemote.isEmpty && selectedFixtures.isEmpty) return;
    for (final manga in selectedFixtures) {
      for (final chapter in manga.chapters) {
        if (!widget.state.isDownloaded(chapter)) {
          await widget.state.download(chapter);
        }
      }
    }
    for (final result in selectedRemote) {
      try {
        final details = await widget.state.loadManwaDetails(result);
        for (final chapter in details.chapters) {
          await widget.state.downloadManwaChapter(chapter);
        }
      } catch (_) {}
    }
    if (!context.mounted) return;
    setState(() {
      selecting = false;
      selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已创建所选漫画的章节下载任务')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mangas = FixtureContentSource.mangas
        .where((manga) => widget.state.isInLibrary(manga.id))
        .toList();
    final remoteMangas = widget.state.remoteLibrary.values.toList();
    if (mangas.isEmpty && remoteMangas.isEmpty) {
      return const _EmptyState(
        icon: Icons.bookmark_border,
        title: '书架还是空的',
        message: '在漫画详情页添加作品，它会出现在这里。',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Card(
          color: Colors.white,
          child: ListTile(
            leading: Icon(selecting ? Icons.close : Icons.checklist),
            title: Text(selecting ? '已选择 ${selected.length} 部漫画' : '批量选择'),
            trailing: selecting
                ? FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => _downloadSelected(
                            context,
                            remoteMangas,
                            mangas,
                          ),
                    child: const Text('下载'),
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => setState(() {
              selecting = !selecting;
              if (!selecting) selected.clear();
            }),
          ),
        ),
        const SizedBox(height: 12),
        ...remoteMangas.map(
          (result) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ManwaListTile(
              result: result,
              state: widget.state,
              onTap: () => selecting
                  ? _toggle(_remoteKey(result))
                  : Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ManwaDetailPage(result: result, state: widget.state),
                      ),
                    ),
            ),
          ),
        ),
        ...mangas.map(
          (manga) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MangaListTile(
              manga: manga,
              state: widget.state,
              onTap: () => selecting
                  ? _toggle(_fixtureKey(manga))
                  : Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            MangaDetailPage(manga: manga, state: widget.state),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final chapters = [
      for (final manga in FixtureContentSource.mangas)
        for (final chapter in manga.chapters)
          if (state.downloadedChapterIds.contains(chapter.id) ||
              state.downloadingChapterIds.contains(chapter.id))
            chapter,
    ];
    final remoteChapters = state.downloadedManwaChapters.values.toList();
    if (chapters.isEmpty && remoteChapters.isEmpty) {
      return const _EmptyState(
        icon: Icons.download_outlined,
        title: '暂无下载任务',
        message: '在漫画详情页下载章节，完成后可离线阅读。',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        for (final chapter in remoteChapters) ...[
          Card(
            color: Colors.white,
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.menu_book)),
              title: Text('漫蛙 · ${chapter.title}'),
              subtitle: const Text('已完成 · 可离线阅读'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ManwaChapterLoaderPage(
                    chapter: chapter,
                    state: state,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        ...chapters.map((chapter) {
          final manga = FixtureContentSource.byId(chapter.mangaId);
          final downloaded = state.isDownloaded(chapter);
          final progress = state.downloadProgress[chapter.id] ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              color: Colors.white,
              child: ListTile(
                leading: MangaCover(manga: manga, width: 48, height: 64),
                title: Text(
                  '${manga.title} · ${chapter.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  downloaded
                      ? '已完成 · 可离线阅读'
                      : '下载中 ${(progress * 100).round()}%',
                ),
                trailing: downloaded
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除下载',
                        onPressed: () => state.removeDownload(chapter),
                      )
                    : SizedBox(
                        width: 72,
                        child: LinearProgressIndicator(value: progress),
                      ),
                onTap: downloaded
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReaderPage(
                            manga: manga,
                            chapter: chapter,
                            state: state,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          );
        }),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Card(
          color: const Color(0xffece9ff),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.science_outlined, color: Color(0xff5b4bd8)),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '当前使用固定测试内容 + 漫蛙 JS 源\n远程源只访问其声明域名，搜索结果来自源脚本解析。',
                    style: TextStyle(height: 1.45, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionTitle(title: '阅读器', trailing: ''),
        ListTile(
          leading: Icon(Icons.view_agenda_outlined),
          title: const Text('阅读方向'),
          subtitle: Text(_directionLabel(state.readerDirection)),
          trailing: Icon(Icons.chevron_right),
          onTap: () => _chooseDirection(context, state),
        ),
        ListTile(
          leading: Icon(Icons.fit_screen_outlined),
          title: const Text('页面适配'),
          subtitle: Text(_scaleLabel(state.readerScaleMode)),
          trailing: Icon(Icons.chevron_right),
          onTap: () => _chooseScale(context, state),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.offline_bolt_outlined),
          title: const Text('当前章节全部页面预加载'),
          subtitle: Text(
            state.autoCacheChapter
                ? '打开章节后后台保存全部页面，缓存不等同于正式下载'
                : '仅在线加载，不自动保存章节页面',
          ),
          value: state.autoCacheChapter,
          onChanged: state.setAutoCacheChapter,
        ),
        const Divider(height: 26),
        const _SectionTitle(title: '数据与诊断', trailing: ''),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: const Text('本地状态'),
          subtitle: Text(
            '${state.libraryIds.length} 本收藏 · ${state.downloadedChapterIds.length} 个已下载章节',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('隐私'),
          subtitle: Text('没有账号、云同步或遥测；仅在用户搜索时访问已安装源'),
        ),
      ],
    );
  }
}

String _directionLabel(ReadingDirection direction) {
  switch (direction) {
    case ReadingDirection.vertical:
      return '纵向分页';
    case ReadingDirection.webtoon:
      return 'Webtoon 连续';
    case ReadingDirection.leftToRight:
      return '从左到右';
    case ReadingDirection.rightToLeft:
      return '从右到左';
  }
}

String _scaleLabel(ReaderScaleMode mode) {
  switch (mode) {
    case ReaderScaleMode.originalSize:
      return '原始尺寸';
    case ReaderScaleMode.fitWidth:
      return '适应宽度';
    case ReaderScaleMode.fitHeight:
      return '适应高度';
    case ReaderScaleMode.fitScreen:
      return '适应屏幕';
    case ReaderScaleMode.smartFit:
      return '智能适应';
  }
}

Future<void> _chooseDirection(BuildContext context, AppState state) async {
  final selected = await showModalBottomSheet<ReadingDirection>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: ReadingDirection.values
            .map(
              (item) => ListTile(
                title: Text(_directionLabel(item)),
                leading: Icon(
                  item == state.readerDirection
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onTap: () => Navigator.pop(context, item),
              ),
            )
            .toList(),
      ),
    ),
  );
  if (selected != null) await state.setReaderDirection(selected);
}

Future<void> _chooseScale(BuildContext context, AppState state) async {
  final selected = await showModalBottomSheet<ReaderScaleMode>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: ReaderScaleMode.values
            .map(
              (item) => ListTile(
                title: Text(_scaleLabel(item)),
                leading: Icon(
                  item == state.readerScaleMode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onTap: () => Navigator.pop(context, item),
              ),
            )
            .toList(),
      ),
    ),
  );
  if (selected != null) await state.setReaderScaleMode(selected);
}

class SourceManagementPage extends StatelessWidget {
  const SourceManagementPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JS 源管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.extension_outlined,
                        color: Color(0xff6457d8),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '漫蛙',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Chip(label: Text(state.manwaInstalled ? '已安装' : '未安装')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('com.ayanami.source.manwa · v0.1.0'),
                  const SizedBox(height: 8),
                  Text(
                    '搜索域名：manwa.me、manwaqb.cc\n图片域名：mwappimgs.cc\n权限：network\n签名：开发源，未签名',
                    style: TextStyle(color: Colors.black54, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  if (state.manwaInstalled)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用此源'),
                      subtitle: Text(
                        state.manwaEnabled ? '搜索时会调用该源' : '已禁用，不会发起新请求',
                      ),
                      value: state.manwaEnabled,
                      onChanged: state.setManwaEnabled,
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: state.manwaInstalled
                          ? null
                          : () async {
                              try {
                                await state.installManwaSource();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('漫蛙 JS 源安装成功'),
                                    ),
                                  );
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('安装失败：$error')),
                                  );
                                }
                              }
                            },
                      icon: Icon(
                        state.manwaInstalled
                            ? Icons.check
                            : Icons.install_mobile_outlined,
                      ),
                      label: Text(
                        state.manwaInstalled ? '已安装并启用' : '安装漫蛙 JS 源',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _FixtureNotice(),
        ],
      ),
    );
  }
}

class ManwaListTile extends StatelessWidget {
  const ManwaListTile({
    super.key,
    required this.result,
    required this.state,
    required this.onTap,
  });
  final ManwaSearchResult result;
  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _CachedRemoteCover(
                cacheKey: result.id,
                state: state,
                url: result.coverUrl,
                fallback: result.title,
                width: 76,
                height: 104,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      result.subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        height: 1.35,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      '漫蛙 · JS 源',
                      style: TextStyle(
                        color: Color(0xff6457d8),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class ManwaDetailPage extends StatelessWidget {
  const ManwaDetailPage({super.key, required this.result, required this.state});
  final ManwaSearchResult result;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('漫蛙漫画详情')),
      body: FutureBuilder<ManwaDetails>(
        future: state.loadManwaDetails(result),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _SourceError(message: '${snapshot.error}', onRetry: null);
          }
          final details = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CachedRemoteCover(
                    cacheKey: result.id,
                    state: state,
                    url: details.coverUrl,
                    fallback: details.title,
                    width: 122,
                    height: 172,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          details.title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          details.status == 'completed' ? '已完结' : '连载中',
                          style: const TextStyle(
                            color: Color(0xff6457d8),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (details.latestChapter.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('最新：${details.latestChapter}'),
                        ],
                        if (details.authors.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '作者：${details.authors.join('、')}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => state.toggleRemoteLibrary(result),
                  icon: Icon(
                    state.isRemoteInLibrary(result.id)
                        ? Icons.bookmark
                        : Icons.bookmark_add_outlined,
                  ),
                  label: Text(
                    state.isRemoteInLibrary(result.id) ? '已加入书架' : '添加到书架',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '章节',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (details.chaptersError != null)
                _SourceError(
                  message: '章节加载失败：${details.chaptersError}',
                  onRetry: null,
                )
              else if (details.chapters.isEmpty)
                const Text('该源暂未返回章节')
              else
                ...details.chapters
                    .map(
                      (chapter) => Card(
                        color: Colors.white,
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xffece9ff),
                            foregroundColor: const Color(0xff6457d8),
                            child: Text(
                              chapter.chapterNumber.isEmpty
                                  ? '话'
                                  : chapter.chapterNumber,
                            ),
                          ),
                          title: Text(chapter.title),
                          subtitle: Text(
                            state.isManwaChapterDownloaded(chapter.id)
                                ? '已下载，可离线阅读'
                                : '已由同一漫蛙 JS 源解析',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (state.downloadingManwaChapterIds
                                  .contains(chapter.id))
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                IconButton(
                                  tooltip: state.isManwaChapterDownloaded(
                                          chapter.id)
                                      ? '已下载'
                                      : '下载章节',
                                  onPressed: state.isManwaChapterDownloaded(
                                          chapter.id)
                                      ? null
                                      : () => state.downloadManwaChapter(chapter),
                                  icon: const Icon(Icons.download_outlined),
                                ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ManwaChapterLoaderPage(
                                chapter: chapter,
                                state: state,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 22),
              Text(
                '别名',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                details.alternativeTitles.isEmpty
                    ? '暂无'
                    : details.alternativeTitles.join('、'),
                style: TextStyle(color: Colors.grey.shade700, height: 1.5),
              ),
              const SizedBox(height: 22),
              Text(
                '简介',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                details.description.isEmpty ? '暂无简介' : details.description,
                style: TextStyle(color: Colors.grey.shade700, height: 1.55),
              ),
              const SizedBox(height: 22),
              Text(
                '来源信息',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '来源：漫蛙 JS 源\nID：${details.id}\n页面：${details.url}',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  height: 1.55,
                  fontSize: 12,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ManwaChapterLoaderPage extends StatelessWidget {
  const ManwaChapterLoaderPage({
    super.key,
    required this.chapter,
    required this.state,
  });

  final ManwaChapter chapter;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(chapter.title)),
      body: FutureBuilder<ManwaChapterContent>(
        future: state.loadManwaChapter(chapter),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    state.autoCacheChapter
                        ? '正在加载并预缓存当前章节全部页面…'
                        : '正在加载章节…',
                  ),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return _SourceError(message: '${snapshot.error}', onRetry: null);
          }
          return ManwaReaderPage(content: snapshot.data!, state: state);
        },
      ),
    );
  }
}

class ManwaReaderPage extends StatefulWidget {
  const ManwaReaderPage({
    super.key,
    required this.content,
    required this.state,
  });

  final ManwaChapterContent content;
  final AppState state;

  @override
  State<ManwaReaderPage> createState() => _ManwaReaderPageState();
}

class _ManwaReaderPageState extends State<ManwaReaderPage> {
  late final PageController controller;
  late int currentPage;
  late List<String?> cachedPagePaths;
  Timer? cacheRefreshTimer;

  @override
  void initState() {
    super.initState();
    final maxPage = widget.content.pageUrls.length - 1;
    currentPage = widget.state
        .manwaProgressFor(widget.content.chapter)
        .clamp(0, maxPage)
        .toInt();
    cachedPagePaths = [...widget.content.cachedPagePaths];
    controller = PageController(initialPage: currentPage);
    unawaited(_preloadAllAndRefresh());
    cacheRefreshTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_refreshCachePaths()),
    );
  }

  @override
  void dispose() {
    cacheRefreshTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cachedCount = cachedPagePaths
        .where((path) => path != null)
        .length;
    final horizontal = widget.state.readerDirection ==
            ReadingDirection.leftToRight ||
        widget.state.readerDirection == ReadingDirection.rightToLeft;
    final imageFit = _readerBoxFit(widget.state.readerScaleMode);
    return Scaffold(
      backgroundColor: const Color(0xff101014),
      appBar: AppBar(
        backgroundColor: const Color(0xff101014),
        foregroundColor: Colors.white,
        title: Text(
          widget.content.chapter.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '阅读设置',
            onSelected: (value) {
              switch (value) {
                case 'fitWidth':
                  widget.state.setReaderScaleMode(ReaderScaleMode.fitWidth);
                case 'fitHeight':
                  widget.state.setReaderScaleMode(ReaderScaleMode.fitHeight);
                case 'fitScreen':
                  widget.state.setReaderScaleMode(ReaderScaleMode.fitScreen);
                case 'originalSize':
                  widget.state.setReaderScaleMode(ReaderScaleMode.originalSize);
                case 'smartFit':
                  widget.state.setReaderScaleMode(ReaderScaleMode.smartFit);
                case 'vertical':
                  widget.state.setReaderDirection(ReadingDirection.vertical);
                case 'webtoon':
                  widget.state.setReaderDirection(ReadingDirection.webtoon);
                case 'leftToRight':
                  widget.state.setReaderDirection(ReadingDirection.leftToRight);
                case 'rightToLeft':
                  widget.state.setReaderDirection(ReadingDirection.rightToLeft);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'fitWidth', child: Text('适应宽度')),
              PopupMenuItem(value: 'fitHeight', child: Text('适应高度')),
              PopupMenuItem(value: 'fitScreen', child: Text('适应屏幕')),
              PopupMenuItem(value: 'smartFit', child: Text('智能适应')),
              PopupMenuItem(value: 'originalSize', child: Text('原始尺寸')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'vertical', child: Text('纵向分页')),
              PopupMenuItem(value: 'webtoon', child: Text('Webtoon 连续')),
              PopupMenuItem(value: 'leftToRight', child: Text('从左到右')),
              PopupMenuItem(value: 'rightToLeft', child: Text('从右到左')),
            ],
          ),
          Center(
            child: Text(
              '${currentPage + 1}/${widget.content.pageUrls.length}',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          if (widget.content.cacheError != null)
            MaterialBanner(
              content: Text('缓存提示：${widget.content.cacheError}'),
              actions: [
                TextButton(
                  onPressed: () => ScaffoldMessenger.of(context)
                      .hideCurrentMaterialBanner(),
                  child: const Text('知道了'),
                ),
              ],
            ),
          Expanded(
            child: PageView.builder(
              controller: controller,
              scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
              reverse: widget.state.readerDirection ==
                  ReadingDirection.rightToLeft,
              itemCount: widget.content.pageUrls.length,
              onPageChanged: (page) {
                setState(() => currentPage = page);
                widget.state.saveManwaProgress(widget.content.chapter, page);
                unawaited(_refreshCachePaths());
              },
              itemBuilder: (context, index) {
                final path = index < cachedPagePaths.length
                    ? cachedPagePaths[index]
                    : null;
                return InteractiveViewer(
                  minScale: .5,
                  maxScale: 4,
                  child: Center(
                    child: path == null
                        ? _RemoteMangaImage(
                            url: widget.content.pageUrls[index],
                            fit: imageFit,
                          )
                        : Image.file(
                            File(path),
                            fit: imageFit,
                            errorBuilder: (context, error, stackTrace) =>
                                const _ReaderImageError(),
                          ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: const Color(0xff17171d),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                cachedCount > 0
                    ? '已缓存 $cachedCount 页 · 上下滑动翻页'
                    : '在线阅读 · 上下滑动翻页',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _preloadAllAndRefresh() async {
    try {
      await widget.state.preloadAllManwaPages(widget.content);
    } catch (_) {}
    await _refreshCachePaths();
  }

  Future<void> _refreshCachePaths() async {
    final record = await widget.state.manwaChapterCache.read(
      widget.content.chapter.id,
    );
    if (!mounted || record == null) return;
    if (record.pageUrls.length != widget.content.pageUrls.length) return;
    final changed = record.paths.length != cachedPagePaths.length ||
        record.paths.asMap().entries.any(
          (entry) => entry.value != cachedPagePaths[entry.key],
        );
    if (changed) setState(() => cachedPagePaths = [...record.paths]);
    if (record.paths.length == record.paths.where((path) => path != null).length) {
      cacheRefreshTimer?.cancel();
    }
  }
}

class _ReaderImageError extends StatelessWidget {
  const _ReaderImageError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '漫画图片加载失败，请检查网络后重试。',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

BoxFit _readerBoxFit(ReaderScaleMode mode) {
  switch (mode) {
    case ReaderScaleMode.originalSize:
      return BoxFit.none;
    case ReaderScaleMode.fitWidth:
      return BoxFit.fitWidth;
    case ReaderScaleMode.fitHeight:
      return BoxFit.fitHeight;
    case ReaderScaleMode.fitScreen:
    case ReaderScaleMode.smartFit:
      return BoxFit.contain;
  }
}

class _RemoteMangaImage extends StatefulWidget {
  const _RemoteMangaImage({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  State<_RemoteMangaImage> createState() => _RemoteMangaImageState();
}

class _RemoteMangaImageState extends State<_RemoteMangaImage> {
  late Future<http.Response> request;

  @override
  void initState() {
    super.initState();
    request = http.get(
      Uri.parse(widget.url),
      headers: const {
        'User-Agent': 'Ayanami/0.1 (reader)',
        'Referer': 'https://manwaqb.cc/',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<http.Response>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final response = snapshot.data;
        if (snapshot.hasError || response == null || response.statusCode < 200 ||
            response.statusCode >= 300) {
          return const _ReaderImageError();
        }
        Uint8List imageBytes;
        try {
          imageBytes = ManwaImageCodec.decode(response.bodyBytes);
        } catch (_) {
          return const _ReaderImageError();
        }
        return Image.memory(
          imageBytes,
          fit: widget.fit,
          errorBuilder: (context, error, stackTrace) =>
              const _ReaderImageError(),
        );
      },
    );
  }
}

class _CachedRemoteCover extends StatefulWidget {
  const _CachedRemoteCover({
    required this.cacheKey,
    required this.state,
    required this.url,
    required this.fallback,
    required this.width,
    required this.height,
  });

  final String cacheKey;
  final AppState state;
  final String url;
  final String fallback;
  final double width;
  final double height;

  @override
  State<_CachedRemoteCover> createState() => _CachedRemoteCoverState();
}

class _CachedRemoteCoverState extends State<_CachedRemoteCover> {
  late Future<String?> cacheFuture;

  @override
  void initState() {
    super.initState();
    cacheFuture = widget.state.cacheManwaCover(widget.cacheKey, widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: cacheFuture,
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(
              File(path),
              width: widget.width,
              height: widget.height,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _RemoteCover(
                url: widget.url,
                fallback: widget.fallback,
                width: widget.width,
                height: widget.height,
              ),
            ),
          );
        }
        return _RemoteCover(
          url: widget.url,
          fallback: widget.fallback,
          width: widget.width,
          height: widget.height,
        );
      },
    );
  }
}

class _RemoteCover extends StatelessWidget {
  const _RemoteCover({
    required this.url,
    required this.fallback,
    required this.width,
    required this.height,
  });
  final String url;
  final String fallback;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
    width: width,
    height: height,
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xff8174df), Color(0xff2c2854)]),
    ),
    padding: const EdgeInsets.all(10),
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        fallback,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );
}

class _InstallSourcePrompt extends StatelessWidget {
  const _InstallSourcePrompt({required this.onInstall});
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xffece9ff),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '搜索需要先安装 JS 源',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            '安装漫蛙源后，输入关键词会由源脚本请求并解析漫蛙搜索页。',
            style: TextStyle(height: 1.45),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onInstall,
            icon: const Icon(Icons.extension_outlined),
            label: const Text('去安装漫蛙源'),
          ),
        ],
      ),
    ),
  );
}

class _SourceError extends StatelessWidget {
  const _SourceError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 42, color: Colors.orange),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700, height: 1.4),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ],
    ),
  );
}

class _InstalledSourceCard extends StatelessWidget {
  const _InstalledSourceCard({required this.state, required this.onTap});
  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    child: ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xffece9ff),
        child: Icon(Icons.extension_outlined, color: Color(0xff6457d8)),
      ),
      title: const Text(
        '漫蛙 JS 源',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        !state.manwaInstalled
            ? '未安装 · 点击安装并启用'
            : state.manwaEnabled
            ? '已安装并启用 · 搜索将使用 JS 源'
            : '已安装但已禁用 · 点击管理',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class MangaDetailPage extends StatelessWidget {
  const MangaDetailPage({super.key, required this.manga, required this.state});
  final MangaFixture manga;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('漫画详情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MangaCover(manga: manga, width: 122, height: 172),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manga.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      manga.subtitle,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: manga.tags
                          .map(
                            (tag) => Chip(
                              label: Text(tag),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => state.toggleLibrary(manga.id),
                  icon: Icon(
                    state.isInLibrary(manga.id)
                        ? Icons.bookmark
                        : Icons.bookmark_add_outlined,
                  ),
                  label: Text(state.isInLibrary(manga.id) ? '已在书架' : '加入书架'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _openFirstChapter(context),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('开始阅读'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '简介',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            manga.description,
            style: TextStyle(color: Colors.grey.shade700, height: 1.55),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '章节',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                '${manga.chapters.length} 章 · 本地测试源',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...manga.chapters.map(
            (chapter) =>
                _ChapterTile(manga: manga, chapter: chapter, state: state),
          ),
        ],
      ),
    );
  }

  void _openFirstChapter(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          manga: manga,
          chapter: manga.chapters.first,
          state: state,
        ),
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.manga,
    required this.chapter,
    required this.state,
  });
  final MangaFixture manga;
  final ChapterFixture chapter;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final page = state.progressFor(chapter);
    final downloaded = state.isDownloaded(chapter);
    final downloading = state.downloadingChapterIds.contains(chapter.id);
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          '第 ${chapter.number} 话  ${chapter.title}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          downloaded
              ? '已下载 · ${page + 1}/${chapter.pageCount} 页'
              : '固定测试源 · ${chapter.pageCount} 页',
        ),
        leading: CircleAvatar(
          backgroundColor: manga.accent.withValues(alpha: .14),
          foregroundColor: manga.accent,
          child: Text(chapter.number),
        ),
        trailing: downloading
            ? SizedBox(
                width: 64,
                child: LinearProgressIndicator(
                  value: state.downloadProgress[chapter.id] ?? 0,
                ),
              )
            : IconButton(
                icon: Icon(
                  downloaded ? Icons.download_done : Icons.download_outlined,
                ),
                tooltip: downloaded ? '已下载' : '下载章节',
                onPressed: downloaded ? null : () => state.download(chapter),
              ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ReaderPage(manga: manga, chapter: chapter, state: state),
          ),
        ),
      ),
    );
  }
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.manga,
    required this.chapter,
    required this.state,
  });
  final MangaFixture manga;
  final ChapterFixture chapter;
  final AppState state;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final PageController controller;
  late int currentPage;

  @override
  void initState() {
    super.initState();
    currentPage = widget.state.progressFor(widget.chapter);
    controller = PageController(initialPage: currentPage);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff101014),
      appBar: AppBar(
        backgroundColor: const Color(0xff101014),
        foregroundColor: Colors.white,
        title: Text(
          '${widget.manga.title} · ${widget.chapter.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Center(
            child: Text(
              '${currentPage + 1}/${widget.chapter.pageCount}',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: PageView.builder(
        controller: controller,
        scrollDirection: Axis.vertical,
        itemCount: widget.chapter.pageCount,
        onPageChanged: (page) {
          setState(() => currentPage = page);
          widget.state.saveProgress(widget.chapter, page);
        },
        itemBuilder: (context, index) => InteractiveViewer(
          minScale: .5,
          maxScale: 4,
          child: Center(
            child: ComicPageArtwork(
              manga: widget.manga,
              chapter: widget.chapter,
              pageIndex: index,
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: const Color(0xff17171d),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                tooltip: '上一页',
                onPressed: currentPage == 0
                    ? null
                    : () => controller.previousPage(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                      ),
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              Expanded(
                child: Text(
                  '向上/向下滑动翻页 · 进度会自动保存在本地',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .65),
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                color: Colors.white,
                tooltip: '下一页',
                onPressed: currentPage == widget.chapter.pageCount - 1
                    ? null
                    : () => controller.nextPage(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                      ),
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ComicPageArtwork extends StatelessWidget {
  const ComicPageArtwork({
    super.key,
    required this.manga,
    required this.chapter,
    required this.pageIndex,
  });
  final MangaFixture manga;
  final ChapterFixture chapter;
  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: .70,
      child: CustomPaint(
        painter: ComicPainter(
          accent: manga.accent,
          pageIndex: pageIndex,
          title: manga.title,
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AYANAMI / FIXTURE',
                style: TextStyle(
                  color: manga.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                pageIndex == 0 ? chapter.title : 'PAGE ${pageIndex + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '这是用于验证阅读器的本地测试页。\n未来这里将由固定源返回的图片替换。',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .72),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ComicPainter extends CustomPainter {
  const ComicPainter({
    required this.accent,
    required this.pageIndex,
    required this.title,
  });
  final Color accent;
  final int pageIndex;
  final String title;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..color = Color.lerp(
        const Color(0xff252531),
        const Color(0xff111118),
        (pageIndex % 4) / 3,
      )!;
    canvas.drawRect(Offset.zero & size, background);
    final grid = Paint()
      ..color = accent.withValues(alpha: .14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final orb = Paint()
      ..shader =
          RadialGradient(
            colors: [
              accent.withValues(alpha: .72),
              accent.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * .7, size.height * .32),
              radius: size.width * .55,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * .7, size.height * .32),
      size.width * .55,
      orb,
    );
    final panel = Paint()..color = Colors.white.withValues(alpha: .06);
    final inset = size.width * .08;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height * .45),
        const Radius.circular(18),
      ),
      panel,
    );
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .24)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(inset * 2, size.height * .63),
      Offset(size.width - inset * 2, size.height * .63),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant ComicPainter oldDelegate) =>
      oldDelegate.pageIndex != pageIndex || oldDelegate.accent != accent;
}

class MangaListTile extends StatelessWidget {
  const MangaListTile({
    super.key,
    required this.manga,
    required this.state,
    required this.onTap,
  });
  final MangaFixture manga;
  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              MangaCover(manga: manga, width: 76, height: 104),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      manga.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      manga.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        height: 1.35,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Text(
                          'fixture',
                          style: TextStyle(
                            color: manga.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${manga.chapters.length} 章',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                          ),
                        ),
                        if (state.isInLibrary(manga.id)) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.bookmark,
                            size: 14,
                            color: Color(0xff7566ee),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class MangaCover extends StatelessWidget {
  const MangaCover({
    super.key,
    required this.manga,
    required this.width,
    required this.height,
  });
  final MangaFixture manga;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              manga.accent,
              Color.lerp(manga.accent, Colors.black, .72)!,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -20,
              child: Icon(
                Icons.circle,
                size: width * 1.2,
                color: Colors.white.withValues(alpha: .08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AYANAMI',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontSize: 8,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    manga.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedManga extends StatelessWidget {
  const _FeaturedManga({required this.manga, required this.onTap});
  final MangaFixture manga;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xff221e42),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日推荐',
                      style: TextStyle(
                        color: manga.accent.withValues(alpha: .95),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      manga.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '打开第一章，体验固定源阅读闭环',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              MangaCover(manga: manga, width: 82, height: 114),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.trailing});
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        if (trailing.isNotEmpty)
          Text(
            trailing,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
      ],
    );
  }
}

class _FixtureNotice extends StatelessWidget {
  const _FixtureNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffefedf8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xff6758d8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '这是项目内置的 fixture 测试源，不访问网络，也不执行漫画源 JS。',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: const Color(0xff8175d8)),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
