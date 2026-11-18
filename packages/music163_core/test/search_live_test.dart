// 真实接口验证：双平台 × 三个标签的搜索与「加载更多」翻页。
// 默认跳过，需要实网验证时运行：
//   flutter test --dart-define=LIVE_SEARCH_TEST=true test/search_live_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:music163_core/music163_core.dart';

void main() {
  test('双平台三标签搜索首屏与翻页真实可用', () async {
    final client = http.Client();
    final api = NeteaseApi(
      client: client,
      deviceId: '0123456789abcdef0123456789abcdef',
    );
    final qq = QqApi(client: client);
    final search = SearchController(MusicRepository(api, qqApi: qq));
    try {
      for (final platform in MusicPlatform.values) {
        for (final tab in SearchTab.values) {
          search.platform = platform;
          search.tab = tab;
          await search.search('周杰伦');
          final first = search.resultCount;
          // ignore: avoid_print
          print('${platform.label}/${tab.name}: 首屏=$first hasMore=${search.hasMore}');
          expect(search.error, isNull, reason: '${platform.label}/${tab.name} 搜索报错');
          expect(first, greaterThan(0), reason: '${platform.label}/${tab.name} 首屏为空');
          if (search.hasMore) {
            await search.loadMore();
            // ignore: avoid_print
            print('  加载更多后=${search.resultCount}');
            expect(
              search.resultCount,
              greaterThan(first),
              reason: '${platform.label}/${tab.name} 翻页没有拿到新数据',
            );
          }
        }
      }
    } finally {
      search.dispose();
      api.close();
      qq.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)),
      skip: !const bool.fromEnvironment('LIVE_SEARCH_TEST'));
}
