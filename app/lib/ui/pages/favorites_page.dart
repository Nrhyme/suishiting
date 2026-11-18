import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:music163_core/music163_core.dart';

import '../utils/app_snackbar.dart';
import '../utils/formatters.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/song_cover.dart';

/// 歌单页：收藏是固定特殊歌单「我的收藏」。
/// 支持新建歌单、歌单内再建子分类（如「歌手名」下建「A类/B类」），
/// 可单独播放某个子分类，也可整单（含全部子分类）播放。
class FavoritesPageView extends StatelessWidget {
  const FavoritesPageView({
    super.key,
    required this.core,
    required this.onNavigateToSearch,
    required this.onNavigateToDownloads,
  });

  final Music163Core core;
  final VoidCallback onNavigateToSearch;
  final VoidCallback onNavigateToDownloads;

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: '请输入名称'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, UserPlaylist? parent) async {
    final name = await _promptName(
      context,
      title: parent == null ? '新建歌单' : '在「${parent.name}」中新建分类',
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await core.library.createPlaylist(name, parentId: parent?.id);
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.show(context, message: e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([core, core.library, core.player]),
      builder: (context, _) {
        final playlists = core.library.rootPlaylists;
        final colorScheme = Theme.of(context).colorScheme;

        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '我的歌单 (${playlists.length})',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '歌单下可再建分类；收藏是特殊歌单。仅保存在本机',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('playlists_create_button'),
                    onPressed: () => unawaited(_createPlaylist(context, null)),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新建歌单'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: playlists.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHigh,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.queue_music_rounded,
                                  size: 32,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                '还没有歌单',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '点击右上角「新建歌单」，或在搜索结果里把歌曲加入歌单。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: colorScheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                key: const Key('favorites_go_search_button'),
                                onPressed: onNavigateToSearch,
                                icon: const Icon(Icons.search_rounded),
                                label: const Text('前往搜索歌曲'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const Key('playlists_list'),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                      itemCount: playlists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        final children = core.library.childrenOf(playlist.id);
                        final allSongs = core.library.allSongsOf(playlist.id);
                        final isCurrent = core.player.currentSong != null &&
                            allSongs.any(
                              (s) => s.key == core.player.currentSong!.key,
                            );

                        return Material(
                          color: isCurrent
                              ? colorScheme.primaryContainer.withValues(
                                  alpha: 0.4,
                                )
                              : colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            key: Key('playlist_item_${playlist.id}'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PlaylistDetailPage(
                                    core: core,
                                    playlistId: playlist.id,
                                    onNavigateToDownloads:
                                        onNavigateToDownloads,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isCurrent
                                      ? colorScheme.primary.withValues(
                                          alpha: 0.6,
                                        )
                                      : colorScheme.outlineVariant.withValues(
                                          alpha: 0.45,
                                        ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: playlist.isSpecial
                                          ? colorScheme.errorContainer
                                          : colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      playlist.isSpecial
                                          ? Icons.favorite_rounded
                                          : Icons.queue_music_rounded,
                                      color: playlist.isSpecial
                                          ? colorScheme.onErrorContainer
                                          : colorScheme.onSecondaryContainer,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          playlist.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${allSongs.length} 首'
                                          '${children.isNotEmpty ? ' · ${children.length} 个分类' : ''}'
                                          ' · 含子分类共 ${allSongs.length} 首',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (allSongs.isNotEmpty)
                                    IconButton(
                                      key: Key(
                                        'playlist_play_btn_${playlist.id}',
                                      ),
                                      tooltip: '播放整个歌单（含子分类）',
                                      onPressed: () {
                                        unawaited(
                                          core.player.playQueue(
                                            allSongs,
                                            startIndex: 0,
                                          ),
                                        );
                                      },
                                      icon: Icon(
                                        Icons.play_circle_outline_rounded,
                                        color: colorScheme.primary,
                                        size: 26,
                                      ),
                                    ),
                                  PopupMenuButton<String>(
                                    key: Key('playlist_menu_${playlist.id}'),
                                    icon: Icon(
                                      Icons.more_vert_rounded,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    onSelected: (action) {
                                      if (action == 'create_child') {
                                        unawaited(
                                          _createPlaylist(context, playlist),
                                        );
                                      } else if (action == 'rename') {
                                        unawaited(() async {
                                          final name = await _promptName(
                                            context,
                                            title: '重命名歌单',
                                            initialValue: playlist.name,
                                          );
                                          if (name == null ||
                                              name.isEmpty ||
                                              !context.mounted) {
                                            return;
                                          }
                                          try {
                                            await core.library.renamePlaylist(
                                              playlist.id,
                                              name,
                                            );
                                          } catch (e) {
                                            if (context.mounted) {
                                              AppSnackBar.show(
                                                context,
                                                message: e.toString(),
                                              );
                                            }
                                          }
                                        }());
                                      } else if (action == 'delete') {
                                        unawaited(
                                          core.library.deletePlaylist(
                                            playlist.id,
                                          ),
                                        );
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'create_child',
                                        child: Text('新建子分类'),
                                      ),
                                      if (!playlist.isSpecial) ...[
                                        const PopupMenuItem(
                                          value: 'rename',
                                          child: Text('重命名'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('删除歌单'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// 歌单详情页：展示歌单歌曲与子分类，可单独播放子分类或整单播放。
class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.core,
    required this.playlistId,
    required this.onNavigateToDownloads,
  });

  final Music163Core core;
  final String playlistId;
  final VoidCallback onNavigateToDownloads;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  UserPlaylist? _selectedChild;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.core,
        widget.core.library,
        widget.core.player,
        widget.core.downloads,
      ]),
      builder: (context, _) {
        final library = widget.core.library;
        final playlist = library.playlistById(widget.playlistId);
        if (playlist == null) {
          // 歌单已被删除，退出详情页。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        }
        final children = library.childrenOf(playlist.id);
        final visibleSongs = _selectedChild == null
            ? library.allSongsOf(playlist.id)
            : library.allSongsOf(_selectedChild!.id);
        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _selectedChild == null
                  ? playlist.name
                  : '${playlist.name} · ${_selectedChild!.name}',
            ),
            actions: [
              IconButton(
                tooltip: _selectedChild == null ? '新建子分类' : '返回歌单',
                onPressed: () {
                  if (_selectedChild != null) {
                    setState(() => _selectedChild = null);
                    return;
                  }
                  unawaited(() async {
                    final name = await _promptSheetName(
                      context,
                      '在「${playlist.name}」中新建分类',
                    );
                    if (name == null || name.isEmpty) return;
                    try {
                      await library.createPlaylist(
                        name,
                        parentId: playlist.id,
                      );
                    } catch (e) {
                      if (mounted) {
                        AppSnackBar.show(this.context, message: e.toString());
                      }
                    }
                  }());
                },
                icon: Icon(
                  _selectedChild == null
                      ? Icons.create_new_folder_outlined
                      : Icons.arrow_upward_rounded,
                ),
              ),
              IconButton(
                tooltip: '新建歌单（顶层）',
                onPressed: () async {
                  final name = await _promptSheetName(context, '新建歌单');
                  if (name == null || name.isEmpty || !context.mounted) return;
                  try {
                    await library.createPlaylist(name);
                  } catch (e) {
                    if (context.mounted) {
                      AppSnackBar.show(context, message: e.toString());
                    }
                  }
                },
                icon: const Icon(Icons.playlist_add_rounded),
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_selectedChild == null && children.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final child in children)
                            ActionChip(
                              key: Key('playlist_child_${child.id}'),
                              avatar: Icon(
                                Icons.folder_rounded,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                              label: Text(
                                '${child.name} (${library.allSongsOf(child.id).length})',
                              ),
                              onPressed: () =>
                                  setState(() => _selectedChild = child),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedChild == null
                                ? '整单播放共 ${visibleSongs.length} 首（含子分类，已去重）'
                                : '${_selectedChild!.name} 共 ${visibleSongs.length} 首',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (visibleSongs.isNotEmpty)
                          FilledButton.tonalIcon(
                            key: const Key('playlist_detail_play_all'),
                            onPressed: () {
                              unawaited(
                                widget.core.player.playQueue(
                                  visibleSongs,
                                  startIndex: 0,
                                ),
                              );
                            },
                            icon: const Icon(Icons.play_arrow_rounded, size: 18),
                            label: Text(
                              _selectedChild == null ? '播放全部' : '播放此分类',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: visibleSongs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.music_off_rounded,
                                size: 44,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _selectedChild == null
                                    ? '该歌单暂无歌曲，可在搜索结果中加入'
                                    : '「${_selectedChild!.name}」暂无歌曲',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        key: const Key('playlist_detail_songs'),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                        itemCount: visibleSongs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final song = visibleSongs[index];
                          final player = widget.core.player;
                          final isCurrent =
                              player.currentSong?.key == song.key;
                          final isPlaying = isCurrent && player.isPlaying;
                          final sourcePlaylist = _selectedChild ?? playlist;

                          return _PlaylistSongTile(
                            core: widget.core,
                            song: song,
                            isCurrent: isCurrent,
                            isPlaying: isPlaying,
                            sourcePlaylistId: sourcePlaylist.id,
                            onTap: () {
                              if (isCurrent && player.isPlaying) {
                                unawaited(player.pause());
                              } else if (isCurrent &&
                                  player.source != null &&
                                  player.error == null) {
                                unawaited(player.resume());
                              } else {
                                unawaited(
                                  player.playQueue(
                                    visibleSongs,
                                    startIndex: index,
                                  ),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _promptSheetName(BuildContext context, String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: '请输入名称'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _PlaylistSongTile extends StatelessWidget {
  const _PlaylistSongTile({
    required this.core,
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.sourcePlaylistId,
    required this.onTap,
  });

  final Music163Core core;
  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final String sourcePlaylistId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleParts = <String>[
      if (song.artists.isNotEmpty) song.artists,
      if (song.album.isNotEmpty) song.album,
    ];
    return Material(
      color: isCurrent
          ? colorScheme.primaryContainer.withValues(alpha: 0.4)
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent
                  ? colorScheme.primary.withValues(alpha: 0.6)
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              SongCover(
                artworkUrl: song.artworkUrl,
                size: 46,
                borderRadius: 10,
                isPlaying: isPlaying,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isCurrent
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitleParts.isEmpty
                          ? '未知艺人'
                          : subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: song.platform == MusicPlatform.qq
                      ? colorScheme.tertiaryContainer
                      : colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  song.platform.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: song.platform == MusicPlatform.qq
                        ? colorScheme.onTertiaryContainer
                        : colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              if (song.duration > Duration.zero)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    UiFormatters.formatDuration(song.duration),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              IconButton(
                tooltip: '加入其他歌单',
                onPressed: () => showAddToPlaylistSheet(
                  context: context,
                  core: core,
                  song: song,
                ),
                icon: Icon(
                  Icons.playlist_add_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
              IconButton(
                tooltip: '从此歌单移除',
                onPressed: () {
                  unawaited(
                    core.library.removeSongFrom(sourcePlaylistId, song),
                  );
                },
                icon: Icon(
                  Icons.remove_circle_outline_rounded,
                  color: colorScheme.error,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
