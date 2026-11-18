// 真实接口验证：双平台专辑搜索 + 专辑曲目。
// 默认跳过，需要实网验证时运行：
//   flutter test --dart-define=LIVE_ALBUM_TEST=true test/album_live_test.dart
// 需要外网可访问网易云与 QQ 音乐接口。
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:music163_core/music163_core.dart';

void main() {
  test('双平台专辑搜索与专辑曲目真实可用', () async {
    final client = http.Client();
    final api = NeteaseApi(
      client: client,
      deviceId: '0123456789abcdef0123456789abcdef',
    );
    final qq = QqApi(client: client);
    final repository = MusicRepository(api, qqApi: qq);
    try {
      for (final platform in MusicPlatform.values) {
        final label = platform.label;
        final page = await repository
            .searchAlbumsFor(platform, '周杰伦')
            .timeout(const Duration(seconds: 30));
        // ignore: avoid_print
        print('[$label] 专辑搜索 ${page.albums.length}/${page.total} 张');
        expect(page.albums, isNotEmpty, reason: '$label 专辑搜索结果为空');
        final album = page.albums.first;
        expect(album.name, isNotEmpty);
        final songs = await repository
            .albumSongs(album)
            .timeout(const Duration(seconds: 30));
        // ignore: avoid_print
        print('[$label] 《${album.name}》共 ${songs.length} 首');
        expect(songs, isNotEmpty, reason: '$label 专辑曲目为空');
        for (final song in songs) {
          expect(song.mid != null || song.id != 0, isTrue);
        }
      }
    } finally {
      api.close();
      qq.close();
    }
  }, timeout: const Timeout(Duration(minutes: 2)),
      skip: !const bool.fromEnvironment('LIVE_ALBUM_TEST'));
}
