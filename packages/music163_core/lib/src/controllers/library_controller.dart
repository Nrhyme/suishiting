import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/credentials.dart';
import '../domain/models.dart';
import 'base_controller.dart';

enum AppThemePreference { light, dark, system }

enum PlaybackMode { sequence, repeatAll, repeatOne, shuffle }

/// 本机歌单：支持两级层级（歌单 → 子分类）。
/// 「我的收藏」是固定特殊歌单（不可删除/改名），对应收藏功能。
@immutable
class UserPlaylist {
  UserPlaylist({
    required this.id,
    required this.name,
    this.parentId,
    this.isSpecial = false,
    List<Song> songs = const [],
  }) : songs = List.unmodifiable(songs);
  final String id;
  final String name;
  final String? parentId;
  final bool isSpecial;
  final List<Song> songs;

  UserPlaylist copyWith({String? name, String? parentId, List<Song>? songs}) =>
      UserPlaylist(
        id: id,
        name: name ?? this.name,
        parentId: parentId ?? this.parentId,
        isSpecial: isSpecial,
        songs: songs ?? this.songs,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'special': isSpecial,
    'songs': songs.map((e) => e.toJson()).toList(),
  };
}

class LibraryController extends SafeNotifier {
  LibraryController(this._store);
  final CredentialStore _store;
  static const storageKey = 'suishiting.library.v1';
  static const favoritesPlaylistId = 'favorites';
  final List<Song> _favorites = [];
  final List<String> _history = [];
  final List<UserPlaylist> _playlists = [];
  List<Song> get favorites => List.unmodifiable(_favorites);
  List<String> get history => List.unmodifiable(_history);
  List<UserPlaylist> get playlists => List.unmodifiable(_playlists);
  /// 收藏固定排在最前的特殊歌单。
  List<UserPlaylist> get rootPlaylists {
    final roots = _playlists.where((p) => p.parentId == null).toList()
      ..sort((a, b) {
        if (a.isSpecial != b.isSpecial) return a.isSpecial ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return List.unmodifiable(roots);
  }

  UserPlaylist? playlistById(String id) =>
      _playlists.where((p) => p.id == id).firstOrNull;

  List<UserPlaylist> childrenOf(String id) =>
      List.unmodifiable(_playlists.where((p) => p.parentId == id));

  /// 递归聚合歌单自身与其所有子歌单中的歌曲（含去重，保持顺序）。
  List<Song> allSongsOf(String id) {
    final playlist = playlistById(id);
    if (playlist == null) return const [];
    final songs = <String, Song>{};
    void collect(UserPlaylist p) {
      for (final song in p.songs) {
        songs.putIfAbsent(song.key, () => song);
      }
      for (final child in _playlists.where((c) => c.parentId == p.id)) {
        collect(child);
      }
    }

    collect(playlist);
    return List.unmodifiable(songs.values);
  }

  AppThemePreference themePreference = AppThemePreference.light;
  PlaybackMode playbackMode = PlaybackMode.sequence;
  bool downloadLyrics = true;
  String? error;
  Future<void> _writes = Future.value();

  Future<void> restore() async {
    final raw = await _store.read(storageKey);
    if (raw == null) {
      // 全新安装也要有固定的「我的收藏」歌单。
      _ensureFavoritesPlaylist();
      changed();
      return;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      themePreference =
          AppThemePreference.values
              .where((e) => e.name == data['theme'])
              .firstOrNull ??
          AppThemePreference.light;
      playbackMode =
          PlaybackMode.values
              .where((e) => e.name == data['mode'])
              .firstOrNull ??
          PlaybackMode.sequence;
      downloadLyrics = data['downloadLyrics'] is bool
          ? data['downloadLyrics'] as bool
          : true;
      for (final item in (data['favorites'] as List? ?? []).take(1000)) {
        try {
          final song = Song.fromJson(Map<String, dynamic>.from(item as Map));
          if (!isFavorite(song)) _favorites.add(song);
        } catch (_) {
          error = '部分收藏记录无法读取。';
        }
      }
      for (final item in (data['playlists'] as List? ?? []).take(100)) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          final songs = (map['songs'] as List? ?? [])
              .whereType<Map>()
              .take(1000)
              .map((s) => Song.fromJson(Map<String, dynamic>.from(s)))
              .toList();
          _playlists.add(
            UserPlaylist(
              id: map['id'] as String? ?? _newId(),
              name: (map['name'] as String?)?.trim().isNotEmpty == true
                  ? map['name'] as String
                  : '未命名歌单',
              parentId: map['parentId'] as String?,
              isSpecial: map['special'] == true,
              songs: songs,
            ),
          );
        } catch (_) {
          error = '部分歌单记录无法读取。';
        }
      }
      _ensureFavoritesPlaylist();
      for (final item in data['history'] as List? ?? []) {
        if (item is String &&
            item.trim().isNotEmpty &&
            !_history.contains(item)) {
          _history.add(item);
        }
        if (_history.length == 30) break;
      }
    } catch (_) {
      error = '本机偏好记录无法读取，请重新设置。';
    }
    changed();
  }

  bool isFavorite(Song song) => _favorites.any((e) => e.key == song.key);
  bool playlistHasSong(String playlistId, Song song) =>
      playlistById(playlistId)?.songs.any((e) => e.key == song.key) ?? false;

  /// 保证固定的「我的收藏」歌单存在（收藏是特殊歌单）。
  void _ensureFavoritesPlaylist() {
    if (_playlists.any((p) => p.id == favoritesPlaylistId && p.isSpecial)) {
      return;
    }
    _playlists.insert(
      0,
      UserPlaylist(
        id: favoritesPlaylistId,
        name: '我的收藏',
        isSpecial: true,
        songs: _favorites,
      ),
    );
  }

  String _newId() =>
      'pl_${DateTime.now().microsecondsSinceEpoch}_${_playlists.length}';

  void _addToMemory(String playlistId, Song song) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) return;
    final playlist = _playlists[index];
    if (playlist.songs.any((e) => e.key == song.key)) return;
    _playlists[index] = playlist.copyWith(
      songs: [...playlist.songs, song],
    );
  }

  Future<void> _update(void Function() mutation) {
    final result = _writes.catchError((Object _) {}).then((_) async {
      if (closed) return;
      // Apply in call order, and restore the last saved state on failure.
      final beforeFavorites = List<Song>.of(_favorites);
      final beforeHistory = List<String>.of(_history);
      final beforePlaylists = List<UserPlaylist>.of(_playlists);
      final beforeTheme = themePreference;
      final beforeMode = playbackMode;
      final beforeLyrics = downloadLyrics;
      try {
        mutation();
        await _store.write(
          storageKey,
          jsonEncode({
            'favorites': _favorites.map((e) => e.toJson()).toList(),
            'playlists': _playlists.map((e) => e.toJson()).toList(),
            'history': _history,
            'theme': themePreference.name,
            'mode': playbackMode.name,
            'downloadLyrics': downloadLyrics,
          }),
        );
        error = null;
      } catch (_) {
        _favorites
          ..clear()
          ..addAll(beforeFavorites);
        _history
          ..clear()
          ..addAll(beforeHistory);
        _playlists
          ..clear()
          ..addAll(beforePlaylists);
        themePreference = beforeTheme;
        playbackMode = beforeMode;
        downloadLyrics = beforeLyrics;
        error = '本机设置保存失败，请重试。';
      }
      changed();
    });
    _writes = result;
    return result;
  }

  Future<void> toggleFavorite(Song song) => _update(() {
    if (isFavorite(song)) {
      _favorites.removeWhere((e) => e.key == song.key);
    } else if (_favorites.length < 1000) {
      _favorites.insert(0, song);
    } else {
      throw const MusicException('收藏已达1000首，请先整理收藏。');
    }
    final index = _playlists.indexWhere(
      (p) => p.id == favoritesPlaylistId,
    );
    if (index >= 0) {
      _playlists[index] = UserPlaylist(
        id: favoritesPlaylistId,
        name: _playlists[index].name,
        isSpecial: true,
        songs: _favorites,
      );
    }
  });

  Future<void> createPlaylist(String name, {String? parentId}) => _update(() {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const MusicException('歌单名称不能为空。');
    if (trimmed.length > 60) throw const MusicException('歌单名称过长。');
    if (_playlists.length >= 100) {
      throw const MusicException('歌单数量已达上限（100 个）。');
    }
    final siblings = _playlists
        .where((p) => p.parentId == parentId)
        .map((p) => p.name)
        .toSet();
    if (siblings.contains(trimmed)) {
      throw MusicException(parentId == null ? '已存在同名歌单。' : '该歌单下已存在同名分类。');
    }
    _playlists.add(
      UserPlaylist(id: _newId(), name: trimmed, parentId: parentId),
    );
  });

  Future<void> renamePlaylist(String id, String name) => _update(() {
    final playlist = playlistById(id);
    if (playlist == null || playlist.isSpecial) {
      throw const MusicException('该歌单无法重命名。');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const MusicException('歌单名称不能为空。');
    final index = _playlists.indexOf(playlist);
    _playlists[index] = playlist.copyWith(name: trimmed);
  });

  Future<void> deletePlaylist(String id) => _update(() {
    final playlist = playlistById(id);
    if (playlist == null || playlist.isSpecial) {
      throw const MusicException('该歌单无法删除。');
    }
    void removeRecursively(String pid) {
      for (final child
          in _playlists.where((c) => c.parentId == pid).map((c) => c.id).toList()) {
        removeRecursively(child);
      }
      _playlists.removeWhere((p) => p.id == pid);
    }

    removeRecursively(id);
  });

  Future<void> addSongTo(String playlistId, Song song) => _update(() {
    final playlist = playlistById(playlistId);
    if (playlist == null) throw const MusicException('歌单不存在。');
    if (playlist.songs.length >= 1000) {
      throw const MusicException('该歌单已达1000首，请先整理。');
    }
    if (playlist.id == favoritesPlaylistId) {
      if (!isFavorite(song)) {
        if (_favorites.length >= 1000) {
          throw const MusicException('收藏已达1000首，请先整理收藏。');
        }
        _favorites.insert(0, song);
        _playlists[_playlists.indexOf(playlist)] = UserPlaylist(
          id: favoritesPlaylistId,
          name: playlist.name,
          isSpecial: true,
          songs: _favorites,
        );
      }
      return;
    }
    _addToMemory(playlistId, song);
  });

  Future<void> removeSongFrom(String playlistId, Song song) => _update(() {
    if (playlistId == favoritesPlaylistId) {
      _favorites.removeWhere((e) => e.key == song.key);
      final index = _playlists.indexWhere((p) => p.id == favoritesPlaylistId);
      if (index >= 0) {
        _playlists[index] = UserPlaylist(
          id: favoritesPlaylistId,
          name: _playlists[index].name,
          isSpecial: true,
          songs: _favorites,
        );
      }
      return;
    }
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index < 0) throw const MusicException('歌单不存在。');
    final playlist = _playlists[index];
    _playlists[index] = playlist.copyWith(
      songs: playlist.songs.where((e) => e.key != song.key).toList(),
    );
  });
  Future<void> addSearch(String query) {
    final text = query.trim();
    if (text.isEmpty) return Future.value();
    return _update(() {
      _history.removeWhere((e) => e.toLowerCase() == text.toLowerCase());
      _history.insert(0, text.length > 1000 ? text.substring(0, 1000) : text);
      if (_history.length > 30) _history.removeRange(30, _history.length);
    });
  }

  Future<void> removeSearch(String text) =>
      _update(() => _history.remove(text));
  Future<void> clearHistory() => _update(_history.clear);
  Future<void> setTheme(AppThemePreference value) =>
      _update(() => themePreference = value);
  Future<void> setDownloadLyrics(bool value) =>
      _update(() => downloadLyrics = value);
  Future<void> setPlaybackMode(PlaybackMode value) =>
      _update(() => playbackMode = value);
  Future<void> close() async {
    await _writes.catchError((Object _) {});
    dispose();
  }
}
