import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';
import 'package:music163_core/music163_core.dart';

import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../utils/formatters.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/song_cover.dart';

/// 搜索与曲目解析页。
/// 支持网易云音乐与 QQ 音乐双平台切换、搜索历史、一键队列播放、收藏与下载。
class SearchPageView extends StatefulWidget {
  const SearchPageView({
    super.key,
    required this.core,
    required this.onNavigateToDownloads,
    required this.onNavigateToAccount,
  });

  final Music163Core core;
  final VoidCallback onNavigateToDownloads;
  final VoidCallback onNavigateToAccount;

  @override
  State<SearchPageView> createState() => _SearchPageViewState();
}

class _SearchPageViewState extends State<SearchPageView> {
  late final TextEditingController _inputController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(text: widget.core.search.query);
    _inputController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitSearch([String? overrideQuery]) async {
    _focusNode.unfocus();
    final target = overrideQuery ?? _inputController.text;
    if (overrideQuery != null) {
      _inputController.value = TextEditingValue(
        text: overrideQuery,
        selection: TextSelection.collapsed(offset: overrideQuery.length),
      );
    }
    await widget.core.search.search(target);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty || !mounted) return;
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _handlePlayTap(List<Song> songs, int index) async {
    final song = songs[index];
    final player = widget.core.player;
    final isCurrent = player.currentSong?.key == song.key;
    if (isCurrent && player.isPlaying) {
      await player.pause();
    } else if (isCurrent && player.source != null && player.error == null) {
      await player.resume();
    } else {
      await player.playQueue(songs, startIndex: index);
    }
  }

  Future<void> _handleDownloadTap(
    BuildContext context,
    Song song,
    DownloadTask? existingTask,
  ) async {
    final downloads = widget.core.downloads;
    if (existingTask == null) {
      await downloads.enqueue(song);
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        message: '已将「${song.name}」加入下载任务',
        action: SnackBarAction(
          label: '查看下载',
          onPressed: widget.onNavigateToDownloads,
        ),
      );
      return;
    }

    if (existingTask.state == DownloadState.failed ||
        existingTask.state == DownloadState.cancelled) {
      await downloads.retry(existingTask.id);
      if (!context.mounted) return;
      AppSnackBar.show(context, message: '已重新开始下载「${song.name}」');
      return;
    }

    widget.onNavigateToDownloads();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.core,
        widget.core.search,
        widget.core.library,
        widget.core.auth,
        widget.core.qqAuth,
        widget.core.player,
        widget.core.downloads,
      ]),
      builder: (context, _) {
        final search = widget.core.search;
        final auth = widget.core.auth;
        final qqAuth = widget.core.qqAuth;
        final isQq = search.platform == MusicPlatform.qq;
        final isCurrentPlatformLoggedIn = isQq
            ? qqAuth.isLoggedIn
            : auth.isLoggedIn;
        final currentPlatformAccountLabel = isQq
            ? (qqAuth.isLoggedIn
                  ? 'QQ 音乐已登录：${qqAuth.profile?.nickname ?? 'QQ 音乐用户'}'
                  : 'QQ 音乐未登录（点击设置）')
            : (auth.isLoggedIn
                  ? '已登录：${auth.profile?.nickname ?? '网易云用户'}'
                  : '匿名模式（点击登录账号）');
        final colorScheme = Theme.of(context).colorScheme;

        return Column(
          children: [
            Container(
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
                  _PlatformSwitchBar(
                    selected: search.platform,
                    onChanged: (platform) {
                      search.setPlatform(platform);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('search_input_field'),
                          controller: _inputController,
                          focusNode: _focusNode,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _submitSearch(),
                          decoration: InputDecoration(
                            hintText: isQq
                                ? '搜索 QQ 音乐歌名、歌手、数字 ID、songmid 或链接'
                                : '搜索歌名、歌手、数字 ID 或网易云分享链接',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_inputController.text.isNotEmpty)
                                  IconButton(
                                    key: const Key('search_clear_button'),
                                    tooltip: '清空输入',
                                    onPressed: () {
                                      _inputController.clear();
                                      search.search('');
                                    },
                                    icon: const Icon(Icons.clear_rounded),
                                  ),
                                IconButton(
                                  key: const Key('search_paste_button'),
                                  tooltip: '粘贴剪贴板内容',
                                  onPressed: _pasteFromClipboard,
                                  icon: const Icon(Icons.content_paste_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        key: const Key('search_submit_button'),
                        onPressed: search.isLoading ? null : _submitSearch,
                        icon: search.isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(Icons.travel_explore_rounded),
                        label: const Text('搜索'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ChoiceChip(
                        key: const Key('search_tab_songs'),
                        label: const Text('单曲'),
                        selected: search.tab == SearchTab.songs,
                        onSelected: (_) => search.setTab(SearchTab.songs),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        key: const Key('search_tab_albums'),
                        label: const Text('专辑'),
                        selected: search.tab == SearchTab.albums,
                        onSelected: (_) => search.setTab(SearchTab.albums),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        key: const Key('search_tab_artists'),
                        label: const Text('歌手'),
                        selected: search.tab == SearchTab.artists,
                        onSelected: (_) => search.setTab(SearchTab.artists),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionChip(
                        key: const Key('search_account_status_chip'),
                        avatar: Icon(
                          isCurrentPlatformLoggedIn
                              ? Icons.verified_user_rounded
                              : Icons.person_outline_rounded,
                          size: 16,
                          color: isCurrentPlatformLoggedIn
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        label: Text(currentPlatformAccountLabel),
                        onPressed: widget.onNavigateToAccount,
                      ),
                      ActionChip(
                        key: const Key('search_quality_status_chip'),
                        avatar: Icon(
                          Icons.high_quality_rounded,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        label: Text('优先音质：${widget.core.quality.label}'),
                        onPressed: widget.onNavigateToAccount,
                      ),
                      if (search.tab == SearchTab.songs &&
                          search.songs.isNotEmpty)
                        ActionChip(
                          key: const Key('search_play_all_button'),
                          avatar: Icon(
                            Icons.playlist_play_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                          label: Text('播放全部 (${search.songs.length})'),
                          onPressed: () {
                            unawaited(
                              widget.core.player.playQueue(
                                search.songs,
                                startIndex: 0,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context, search)),
          ],
        );
      },
    );
  }

  /// 滚动接近底部时自动加载下一页（同时保留显式的「加载更多」按钮）。
  Widget _withAutoLoadMore(SearchController search, Widget child) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.axis == Axis.vertical &&
            metrics.maxScrollExtent > 0 &&
            metrics.pixels >= metrics.maxScrollExtent - 320 &&
            search.hasMore &&
            !search.isLoadingMore &&
            !search.isLoading) {
          unawaited(search.loadMore());
        }
        return false;
      },
      child: child,
    );
  }

  Widget _buildBody(BuildContext context, SearchController search) {
    final colorScheme = Theme.of(context).colorScheme;
    final platformLabel = search.platform.label;
    final isAlbumTab = search.tab == SearchTab.albums;
    final isArtistTab = search.tab == SearchTab.artists;
    final results = switch (search.tab) {
      SearchTab.songs => search.songs,
      SearchTab.albums => search.albums,
      SearchTab.artists => search.artists,
    };

    if (search.isLoading && results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '正在请求$platformLabel接口解析「${search.query}」…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (search.error != null && results.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              elevation: 0,
              color: colorScheme.errorContainer.withValues(alpha: 0.55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: colorScheme.error.withValues(alpha: 0.4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 44,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '检索未能完成',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      search.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      key: const Key('search_error_retry_button'),
                      onPressed: () => search.search(search.query),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试搜索'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (search.query.isEmpty && results.isEmpty) {
      final history = widget.core.library.history;
      if (history.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 46,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                ),
                const SizedBox(height: 10),
                Text(
                  '输入歌名、歌手、歌曲 ID 或分享链接即可搜索',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return SingleChildScrollView(
        key: const Key('search_history_section'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '搜索历史',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  key: const Key('search_history_clear_button'),
                  onPressed: widget.core.library.clearHistory,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空历史'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in history)
                  InputChip(
                    key: Key('search_history_item_$item'),
                    label: Text(item),
                    onPressed: () => _submitSearch(item),
                    deleteIcon: Icon(
                      Icons.close_rounded,
                      key: Key('search_history_remove_$item'),
                      size: 16,
                    ),
                    onDeleted: () {
                      unawaited(widget.core.library.removeSearch(item));
                    },
                  ),
              ],
            ),
          ],
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isArtistTab
                      ? Icons.person_search_rounded
                      : (isAlbumTab
                            ? Icons.album_outlined
                            : Icons.music_off_rounded),
                  size: 48,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  isArtistTab
                      ? '未在$platformLabel找到与「${search.query}」相关的歌手'
                      : (isAlbumTab
                            ? '未在$platformLabel找到与「${search.query}」相关的专辑'
                            : '未在$platformLabel找到与「${search.query}」相关的歌曲'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (isAlbumTab) {
      return _withAutoLoadMore(
        search,
        ListView.separated(
          key: const Key('search_album_results_list'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          itemCount: search.albums.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == search.albums.length) {
              return _buildPaginationFooter(context, search);
            }
            final album = search.albums[index];
            return _AlbumResultCard(
              album: album,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AlbumDetailPage(
                      core: widget.core,
                      album: album,
                      onNavigateToDownloads: widget.onNavigateToDownloads,
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    }

    if (isArtistTab) {
      return _withAutoLoadMore(
        search,
        ListView.separated(
          key: const Key('search_artist_results_list'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          itemCount: search.artists.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == search.artists.length) {
              return _buildPaginationFooter(context, search);
            }
            final artist = search.artists[index];
            return _ArtistResultCard(
              artist: artist,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ArtistDetailPage(
                      core: widget.core,
                      artist: artist,
                      onNavigateToDownloads: widget.onNavigateToDownloads,
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    }

    final taskMap = <String, DownloadTask>{
      for (final task in widget.core.downloads.tasks) task.song.key: task,
      for (final task in widget.core.downloads.tasks) task.id: task,
    };

    return _withAutoLoadMore(
      search,
      ListView.separated(
        key: const Key('search_results_list'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        itemCount: search.songs.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == search.songs.length) {
            return _buildPaginationFooter(context, search);
          }

          final song = search.songs[index];
          final player = widget.core.player;
          final isCurrentSong = player.currentSong?.key == song.key;
          final isPlayingThis = isCurrentSong && player.isPlaying;
          final isLoadingThis = isCurrentSong && player.isLoading;
          final isTrialThis = isCurrentSong && (player.source?.isTrial ?? false);
          final downloadTask = taskMap[song.key];
          final isFavorite = widget.core.library.isFavorite(song);

          return _SongResultCard(
            song: song,
            isCurrentSong: isCurrentSong,
            isPlaying: isPlayingThis,
            isLoading: isLoadingThis,
            isTrial: isTrialThis,
            isFavorite: isFavorite,
            downloadTask: downloadTask,
            onPlayTap: () => _handlePlayTap(search.songs, index),
            onFavoriteTap: () {
              unawaited(widget.core.library.toggleFavorite(song));
            },
            onDownloadTap: () => _handleDownloadTap(context, song, downloadTask),
            onAddToPlaylistTap: () => showAddToPlaylistSheet(
              context: context,
              core: widget.core,
              song: song,
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaginationFooter(BuildContext context, SearchController search) {
    final colorScheme = Theme.of(context).colorScheme;
    final count = search.resultCount;
    final unit = switch (search.tab) {
      SearchTab.songs => '首',
      SearchTab.albums => '张专辑',
      SearchTab.artists => '位歌手',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (search.error != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      search.error!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (search.hasMore)
            OutlinedButton.icon(
              key: const Key('search_load_more_button'),
              onPressed: search.isLoadingMore ? null : search.loadMore,
              icon: search.isLoadingMore
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(
                search.isLoadingMore
                    ? '正在加载更多…'
                    : '加载更多（已显示 $count $unit）',
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '已加载全部 $count $unit',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlatformSwitchBar extends StatelessWidget {
  const _PlatformSwitchBar({required this.selected, required this.onChanged});

  final MusicPlatform selected;
  final ValueChanged<MusicPlatform> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          for (final platform in MusicPlatform.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: selected == platform
                      ? colorScheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    key: Key('search_platform_${platform.name}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onChanged(platform),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 42),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                platform == MusicPlatform.qq
                                    ? Icons.queue_music_rounded
                                    : Icons.cloud_queue_rounded,
                                size: 18,
                                color: selected == platform
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  platform.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: selected == platform
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: selected == platform
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SongResultCard extends StatelessWidget {
  const _SongResultCard({
    required this.song,
    required this.isCurrentSong,
    required this.isPlaying,
    required this.isLoading,
    required this.isTrial,
    required this.isFavorite,
    required this.downloadTask,
    required this.onPlayTap,
    required this.onFavoriteTap,
    required this.onDownloadTap,
    this.onAddToPlaylistTap,
  });

  final Song song;
  final bool isCurrentSong;
  final bool isPlaying;
  final bool isLoading;
  final bool isTrial;
  final bool isFavorite;
  final DownloadTask? downloadTask;
  final VoidCallback onPlayTap;
  final VoidCallback onFavoriteTap;
  final VoidCallback onDownloadTap;
  final VoidCallback? onAddToPlaylistTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final subtitleParts = <String>[
      if (song.artists.isNotEmpty) song.artists,
      if (song.album.isNotEmpty) song.album,
    ];

    return Material(
      color: isCurrentSong
          ? colorScheme.primaryContainer.withValues(alpha: isDark ? 0.32 : 0.45)
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('song_item_${song.key}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onPlayTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrentSong
                  ? colorScheme.primary.withValues(alpha: 0.6)
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SongCover(
                artworkUrl: song.artworkUrl,
                size: 54,
                borderRadius: 12,
                isPlaying: isPlaying,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isCurrentSong
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
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _MetaTag(
                          text: song.platform.label,
                          background: song.platform == MusicPlatform.qq
                              ? colorScheme.tertiaryContainer
                              : colorScheme.secondaryContainer,
                          foreground: song.platform == MusicPlatform.qq
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSecondaryContainer,
                        ),
                        _MetaTag(
                          text: 'ID: ${song.displayId}',
                          background: colorScheme.surfaceContainerHigh,
                          foreground: colorScheme.onSurfaceVariant,
                        ),
                        if (song.duration > Duration.zero)
                          _MetaTag(
                            text: UiFormatters.formatDuration(song.duration),
                            background: colorScheme.surfaceContainerHigh,
                            foreground: colorScheme.onSurfaceVariant,
                          ),
                        if (isTrial)
                          _MetaTag(
                            text: '试听片段',
                            background: isDark
                                ? AppTheme.trialSurfaceDark
                                : AppTheme.trialSurfaceLight,
                            foreground: isDark
                                ? AppTheme.trialAmberDark
                                : AppTheme.trialAmberLight,
                          ),
                        if (downloadTask != null)
                          _MetaTag(
                            text: UiFormatters.downloadStateLabel(
                              downloadTask!.state,
                            ),
                            background: switch (downloadTask!.state) {
                              DownloadState.completed =>
                                colorScheme.secondaryContainer,
                              DownloadState.failed =>
                                colorScheme.errorContainer,
                              _ => colorScheme.primaryContainer,
                            },
                            foreground: switch (downloadTask!.state) {
                              DownloadState.completed =>
                                colorScheme.onSecondaryContainer,
                              DownloadState.failed =>
                                colorScheme.onErrorContainer,
                              _ => colorScheme.onPrimaryContainer,
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                key: Key('song_favorite_btn_${song.key}'),
                tooltip: isFavorite ? '取消收藏' : '收藏歌曲',
                onPressed: onFavoriteTap,
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
              if (onAddToPlaylistTap != null)
                IconButton(
                  key: Key('song_add_to_playlist_btn_${song.key}'),
                  tooltip: '加入歌单',
                  onPressed: onAddToPlaylistTap,
                  icon: Icon(
                    Icons.playlist_add_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ),
              IconButton(
                key: Key('song_play_btn_${song.key}'),
                tooltip: isPlaying ? '暂停' : '播放',
                onPressed: isLoading ? null : onPlayTap,
                icon: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(
                        isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_outline_rounded,
                        color: isCurrentSong
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                        size: 28,
                      ),
              ),
              IconButton(
                key: Key('song_download_btn_${song.key}'),
                tooltip: switch (downloadTask?.state) {
                  DownloadState.completed => '已下载，查看下载任务',
                  DownloadState.queued ||
                  DownloadState.resolving ||
                  DownloadState.downloading => '正在下载，点击查看进度',
                  DownloadState.failed || DownloadState.cancelled => '重试下载',
                  null => '下载歌曲',
                },
                onPressed: onDownloadTap,
                icon: Icon(
                  switch (downloadTask?.state) {
                    DownloadState.completed => Icons.download_done_rounded,
                    DownloadState.queued ||
                    DownloadState.resolving ||
                    DownloadState.downloading => Icons.downloading_rounded,
                    DownloadState.failed ||
                    DownloadState.cancelled => Icons.refresh_rounded,
                    null => Icons.download_for_offline_outlined,
                  },
                  color: switch (downloadTask?.state) {
                    DownloadState.completed => colorScheme.primary,
                    DownloadState.failed => colorScheme.error,
                    _ => colorScheme.onSurfaceVariant,
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

/// 歌手搜索结果卡片。
class _ArtistResultCard extends StatelessWidget {
  const _ArtistResultCard({required this.artist, required this.onTap});

  final Artist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('artist_item_${artist.key}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: colorScheme.surfaceContainerHigh,
                backgroundImage: artist.avatarUrl == null
                    ? null
                    : NetworkImage(artist.avatarUrl!),
                child: artist.avatarUrl == null
                    ? Icon(
                        Icons.person_rounded,
                        color: colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MetaTag(
                          text: artist.platform.label,
                          background: artist.platform == MusicPlatform.qq
                              ? colorScheme.tertiaryContainer
                              : colorScheme.secondaryContainer,
                          foreground: artist.platform == MusicPlatform.qq
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSecondaryContainer,
                        ),
                        if (artist.songCount > 0)
                          _MetaTag(
                            text: '歌曲 ${artist.songCount}',
                            background: colorScheme.surfaceContainerHigh,
                            foreground: colorScheme.onSurfaceVariant,
                          ),
                        if (artist.albumCount > 0)
                          _MetaTag(
                            text: '专辑 ${artist.albumCount}',
                            background: colorScheme.surfaceContainerHigh,
                            foreground: colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 歌手详情页：歌手歌曲列表 + 歌手专辑列表。
class ArtistDetailPage extends StatefulWidget {
  const ArtistDetailPage({
    super.key,
    required this.core,
    required this.artist,
    required this.onNavigateToDownloads,
  });

  final Music163Core core;
  final Artist artist;
  final VoidCallback onNavigateToDownloads;

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
  List<Song> _songs = const [];
  List<Album> _albums = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.core.search.artistSongs(widget.artist),
        widget.core.search.artistAlbums(widget.artist),
      ]);
      if (!mounted) return;
      setState(() {
        _songs = results[0] as List<Song>;
        _albums = results[1] as List<Album>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _handleDownloadTap(Song song) async {
    final downloads = widget.core.downloads;
    final existing = downloads.tasks
        .where((t) => t.song.key == song.key || t.id == song.key)
        .firstOrNull;
    if (existing == null) {
      await downloads.enqueue(song);
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: '已将「${song.name}」加入下载任务',
        action: SnackBarAction(
          label: '查看下载',
          onPressed: widget.onNavigateToDownloads,
        ),
      );
    } else if (existing.state == DownloadState.failed ||
        existing.state == DownloadState.cancelled) {
      await downloads.retry(existing.id);
    } else {
      widget.onNavigateToDownloads();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.artist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          widget.core.player,
          widget.core.library,
          widget.core.downloads,
        ]),
        builder: (context, _) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 44,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }

          final taskMap = <String, DownloadTask>{
            for (final task in widget.core.downloads.tasks)
              task.song.key: task,
            for (final task in widget.core.downloads.tasks) task.id: task,
          };

          return ListView(
            key: const Key('artist_detail_list'),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: colorScheme.surfaceContainerHigh,
                      backgroundImage: widget.artist.avatarUrl == null
                          ? null
                          : NetworkImage(widget.artist.avatarUrl!),
                      child: widget.artist.avatarUrl == null
                          ? Icon(
                              Icons.person_rounded,
                              color: colorScheme.onSurfaceVariant,
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.artist.platform.label} · '
                            '歌曲 ${_songs.length} · 专辑 ${_albums.length}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_songs.isNotEmpty)
                      FilledButton.tonalIcon(
                        key: const Key('artist_play_all_button'),
                        onPressed: () {
                          unawaited(
                            widget.core.player.playQueue(
                              _songs,
                              startIndex: 0,
                            ),
                          );
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('播放全部'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionHeader(
                icon: Icons.music_note_rounded,
                title: '歌曲',
                trailing: '${_songs.length} 首',
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _songs.length; i++) ...[
                _buildSongTile(_songs[i], i, taskMap),
                if (i != _songs.length - 1) const SizedBox(height: 8),
              ],
              const SizedBox(height: 20),
              _SectionHeader(
                icon: Icons.album_rounded,
                title: '专辑',
                trailing: '${_albums.length} 张',
              ),
              const SizedBox(height: 8),
              if (_albums.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '该歌手的专辑暂不可用',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final album in _albums) ...[
                  _AlbumResultCard(
                    album: album,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AlbumDetailPage(
                            core: widget.core,
                            album: album,
                            onNavigateToDownloads:
                                widget.onNavigateToDownloads,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSongTile(
    Song song,
    int index,
    Map<String, DownloadTask> taskMap,
  ) {
    final player = widget.core.player;
    final isCurrentSong = player.currentSong?.key == song.key;
    final isPlayingThis = isCurrentSong && player.isPlaying;
    final isLoadingThis = isCurrentSong && player.isLoading;

    return _SongResultCard(
      song: song,
      isCurrentSong: isCurrentSong,
      isPlaying: isPlayingThis,
      isLoading: isLoadingThis,
      isTrial: isCurrentSong && (player.source?.isTrial ?? false),
      isFavorite: widget.core.library.isFavorite(song),
      downloadTask: taskMap[song.key],
      onPlayTap: () {
        if (isCurrentSong && player.isPlaying) {
          unawaited(player.pause());
        } else if (isCurrentSong &&
            player.source != null &&
            player.error == null) {
          unawaited(player.resume());
        } else {
          unawaited(player.playQueue(_songs, startIndex: index));
        }
      },
      onFavoriteTap: () {
        unawaited(widget.core.library.toggleFavorite(song));
      },
      onDownloadTap: () => _handleDownloadTap(song),
      onAddToPlaylistTap: () => showAddToPlaylistSheet(
        context: context,
        core: widget.core,
        song: song,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
class _AlbumResultCard extends StatelessWidget {
  const _AlbumResultCard({required this.album, required this.onTap});

  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('album_item_${album.key}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              SongCover(
                artworkUrl: album.artworkUrl,
                size: 56,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      album.artists.isEmpty ? '未知艺人' : album.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MetaTag(
                          text: album.platform.label,
                          background: album.platform == MusicPlatform.qq
                              ? colorScheme.tertiaryContainer
                              : colorScheme.secondaryContainer,
                          foreground: album.platform == MusicPlatform.qq
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSecondaryContainer,
                        ),
                        if (album.songCount > 0)
                          _MetaTag(
                            text: '${album.songCount} 首',
                            background: colorScheme.surfaceContainerHigh,
                            foreground: colorScheme.onSurfaceVariant,
                          ),
                        if (album.publishTime.isNotEmpty)
                          _MetaTag(
                            text: album.publishTime,
                            background: colorScheme.surfaceContainerHigh,
                            foreground: colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 专辑详情页：加载专辑曲目，支持播放全部、单曲播放/收藏/下载/加入歌单。
class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({
    super.key,
    required this.core,
    required this.album,
    required this.onNavigateToDownloads,
  });

  final Music163Core core;
  final Album album;
  final VoidCallback onNavigateToDownloads;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  List<Song> _songs = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final songs = await widget.core.search.albumSongs(widget.album);
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _handleDownloadTap(Song song) async {
    final downloads = widget.core.downloads;
    final existing = downloads.tasks
        .where((t) => t.song.key == song.key || t.id == song.key)
        .firstOrNull;
    if (existing == null) {
      await downloads.enqueue(song);
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: '已将「${song.name}」加入下载任务',
        action: SnackBarAction(
          label: '查看下载',
          onPressed: widget.onNavigateToDownloads,
        ),
      );
    } else if (existing.state == DownloadState.failed ||
        existing.state == DownloadState.cancelled) {
      await downloads.retry(existing.id);
    } else {
      widget.onNavigateToDownloads();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.album.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          widget.core.player,
          widget.core.library,
          widget.core.downloads,
        ]),
        builder: (context, _) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 44,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }

          final taskMap = <String, DownloadTask>{
            for (final task in widget.core.downloads.tasks)
              task.song.key: task,
            for (final task in widget.core.downloads.tasks) task.id: task,
          };

          return Column(
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
                child: Row(
                  children: [
                    SongCover(
                      artworkUrl: widget.album.artworkUrl,
                      size: 52,
                      borderRadius: 10,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.album.artists.isEmpty
                                ? '未知艺人'
                                : widget.album.artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '共 ${_songs.length} 首曲目',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_songs.isNotEmpty)
                      FilledButton.tonalIcon(
                        key: const Key('album_play_all_button'),
                        onPressed: () {
                          unawaited(
                            widget.core.player.playQueue(
                              _songs,
                              startIndex: 0,
                            ),
                          );
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('播放全部'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  key: const Key('album_songs_list'),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                  itemCount: _songs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    final player = widget.core.player;
                    final isCurrentSong = player.currentSong?.key == song.key;
                    final isPlayingThis = isCurrentSong && player.isPlaying;
                    final isLoadingThis = isCurrentSong && player.isLoading;

                    return _SongResultCard(
                      song: song,
                      isCurrentSong: isCurrentSong,
                      isPlaying: isPlayingThis,
                      isLoading: isLoadingThis,
                      isTrial:
                          isCurrentSong && (player.source?.isTrial ?? false),
                      isFavorite: widget.core.library.isFavorite(song),
                      downloadTask: taskMap[song.key],
                      onPlayTap: () {
                        if (isCurrentSong && player.isPlaying) {
                          unawaited(player.pause());
                        } else if (isCurrentSong &&
                            player.source != null &&
                            player.error == null) {
                          unawaited(player.resume());
                        } else {
                          unawaited(
                            player.playQueue(_songs, startIndex: index),
                          );
                        }
                      },
                      onFavoriteTap: () {
                        unawaited(widget.core.library.toggleFavorite(song));
                      },
                      onDownloadTap: () => _handleDownloadTap(song),
                      onAddToPlaylistTap: () => showAddToPlaylistSheet(
                        context: context,
                        core: widget.core,
                        song: song,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
