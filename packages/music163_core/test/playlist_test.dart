import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music163_core/music163_core.dart';

class _MemoryStore implements CredentialStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

const _a = Song(id: 1, name: 'A类曲目', artists: '歌手甲', album: '专辑一');
const _b = Song(id: 2, name: 'B类曲目', artists: '歌手甲', album: '专辑一');
const _c = Song(id: 3, name: '歌手单曲', artists: '歌手甲', album: '专辑二');
const _qq = Song(
  id: 9,
  name: 'QQ曲目',
  artists: '歌手甲',
  album: '专辑三',
  platform: MusicPlatform.qq,
  mid: 'abc12345678901',
);

List<String> _keys(Iterable<Song> songs) => songs.map((s) => s.key).toList();

void main() {
  test('收藏是固定特殊歌单，与歌单体系共享存储', () async {
    final store = _MemoryStore();
    final library = LibraryController(store);
    await library.restore();

    final favorites = library.playlistById(LibraryController.favoritesPlaylistId);
    expect(favorites, isNotNull);
    expect(favorites!.isSpecial, isTrue);
    expect(library.rootPlaylists.first.id, LibraryController.favoritesPlaylistId);

    await library.toggleFavorite(_a);
    expect(library.isFavorite(_a), isTrue);
    expect(
      _keys(library.allSongsOf(LibraryController.favoritesPlaylistId)),
      [_a.key],
    );

    // 重启后收藏与歌单都能恢复。
    final reloaded = LibraryController(store);
    await reloaded.restore();
    expect(reloaded.isFavorite(_a), isTrue);
    expect(
      _keys(reloaded.playlistById(LibraryController.favoritesPlaylistId)!.songs),
      [_a.key],
    );
    await library.close();
    await reloaded.close();
  });

  test('歌单下可建子分类，整单播放聚合去重，删除级联', () async {
    final store = _MemoryStore();
    final library = LibraryController(store);
    await library.restore();

    await library.createPlaylist('歌手甲');
    final root = library.rootPlaylists.firstWhere((p) => p.name == '歌手甲');
    await library.createPlaylist('A类', parentId: root.id);
    await library.createPlaylist('B类', parentId: root.id);
    final children = library.childrenOf(root.id);
    expect(children.map((c) => c.name), ['A类', 'B类']);
    final a = children.firstWhere((c) => c.name == 'A类');
    final b = children.firstWhere((c) => c.name == 'B类');

    await library.addSongTo(a.id, _a);
    await library.addSongTo(a.id, _b);
    await library.addSongTo(b.id, _c);
    await library.addSongTo(root.id, _qq); // 歌单自身也可直接放歌
    await library.addSongTo(a.id, _a); // 重复加入应去重

    expect(_keys(library.allSongsOf(a.id)), [_a.key, _b.key]);
    expect(_keys(library.allSongsOf(b.id)), [_c.key]);
    // 整单播放 = 父歌单 + 所有子分类，去重并保持加入顺序。
    expect(_keys(library.allSongsOf(root.id)), [
      _qq.key,
      _a.key,
      _b.key,
      _c.key,
    ]);

    // 从子分类移除只影响该分类。
    await library.removeSongFrom(a.id, _a);
    expect(_keys(library.allSongsOf(a.id)), [_b.key]);
    expect(_keys(library.allSongsOf(root.id)), [_qq.key, _b.key, _c.key]);

    // 持久化后层级与曲目保持。
    final reloaded = LibraryController(store);
    await reloaded.restore();
    final reloadedRoot = reloaded.rootPlaylists.firstWhere(
      (p) => p.name == '歌手甲',
    );
    expect(reloaded.childrenOf(reloadedRoot.id).length, 2);
    expect(_keys(reloaded.allSongsOf(reloadedRoot.id)), [
      _qq.key,
      _b.key,
      _c.key,
    ]);

    // 删除父歌单会连同子分类一起删除。
    await reloaded.deletePlaylist(reloadedRoot.id);
    expect(reloaded.playlistById(reloadedRoot.id), isNull);
    expect(reloaded.childrenOf(reloadedRoot.id), isEmpty);
    await library.close();
    await reloaded.close();
  });

  test('特殊歌单不可删除；同名与空名被拒绝；旧数据可迁移', () async {
    final store = _MemoryStore();
    // 模拟旧版本数据：只有 favorites 数组，没有 playlists 字段。
    store.values[LibraryController.storageKey] = jsonEncode({
      'favorites': [_a.toJson()],
      'history': ['周杰伦'],
      'theme': 'dark',
      'mode': 'shuffle',
      'downloadLyrics': false,
    });
    final library = LibraryController(store);
    await library.restore();
    expect(library.isFavorite(_a), isTrue);
    expect(library.themePreference, AppThemePreference.dark);
    expect(
      _keys(library.allSongsOf(LibraryController.favoritesPlaylistId)),
      [_a.key],
    );

    // 特殊歌单不可删除（操作被拒绝，不产生新歌单）。
    final before = library.playlists.length;
    await library.deletePlaylist(LibraryController.favoritesPlaylistId);
    expect(library.playlists.length, before);
    expect(library.playlistById(LibraryController.favoritesPlaylistId), isNotNull);

    // 同名/空名不会新增歌单。
    await library.createPlaylist('我的歌单');
    final afterCreate = library.playlists.length;
    await library.createPlaylist('我的歌单');
    await library.createPlaylist('   ');
    expect(library.playlists.length, afterCreate);
    await library.close();
  });
}
