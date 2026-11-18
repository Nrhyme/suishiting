// 真实接口验证：双平台歌手搜索 + 歌手歌曲 + 歌手专辑。
// 默认跳过，需要实网验证时运行：
//   flutter test --dart-define=LIVE_ARTIST_TEST=true test/artist_live_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:music163_core/music163_core.dart';

void main() {
  test('双平台歌手搜索、歌手歌曲与歌手专辑真实可用', () async {
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
            .searchArtistsFor(platform, '周杰伦')
            .timeout(const Duration(seconds: 30));
        // ignore: avoid_print
        print('[$label] 歌手搜索 ${page.artists.length}/${page.total} 位');
        expect(page.artists, isNotEmpty, reason: '$label 歌手搜索结果为空');
        final artist = page.artists.first;
        expect(artist.name, isNotEmpty);

        final songs = await repository
            .artistSongsFor(artist)
            .timeout(const Duration(seconds: 30));
        // ignore: avoid_print
        print('[$label] ${artist.name} 歌曲 ${songs.length} 首');
        expect(songs, isNotEmpty, reason: '$label 歌手歌曲为空');

        final albums = await repository
            .artistAlbumsFor(artist)
            .timeout(const Duration(seconds: 30));
        // ignore: avoid_print
        print('[$label] ${artist.name} 专辑 ${albums.length} 张');
        expect(albums, isNotEmpty, reason: '$label 歌手专辑为空');
        for (final album in albums) {
          if (album.platform == MusicPlatform.qq) {
            expect(album.mid, isNotNull);
          }
        }
      }
    } finally {
      api.close();
      qq.close();
    }
  }, timeout: const Timeout(Duration(minutes: 2)),
      skip: !const bool.fromEnvironment('LIVE_ARTIST_TEST'));
}
