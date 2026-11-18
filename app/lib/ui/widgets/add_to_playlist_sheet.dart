import 'package:flutter/material.dart';
import 'package:music163_core/music163_core.dart';

import '../utils/app_snackbar.dart';

/// 把 [song] 加入歌单的底部弹窗：列出全部歌单（含子分类层级），
/// 支持当场新建歌单。收藏是特殊歌单「我的收藏」。
Future<void> showAddToPlaylistSheet({
  required BuildContext context,
  required Music163Core core,
  required Song song,
}) async {
  final library = core.library;
  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final colorScheme = Theme.of(context).colorScheme;
          final roots = library.rootPlaylists;

          Widget tile(UserPlaylist playlist, {int depth = 0}) {
            final already = library.playlistHasSong(playlist.id, song);
            return ListTile(
              key: Key('add_to_${playlist.id}'),
              dense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16 + 16.0 * depth,
              ),
              leading: Icon(
                playlist.isSpecial
                    ? Icons.favorite_rounded
                    : (depth > 0
                          ? Icons.subdirectory_arrow_right_rounded
                          : Icons.queue_music_rounded),
                size: 20,
                color: playlist.isSpecial
                    ? colorScheme.error
                    : colorScheme.primary,
              ),
              title: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5),
              ),
              subtitle: Text(
                '${library.allSongsOf(playlist.id).length} 首',
                style: TextStyle(fontSize: 12, color: colorScheme.outline),
              ),
              trailing: already
                  ? Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(playlist.id),
            );
          }

          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '加入歌单',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.name,
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
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final root in roots) ...[
                        tile(root),
                        for (final child in library.childrenOf(root.id))
                          tile(child, depth: 1),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('add_to_new_playlist'),
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: Icon(
                    Icons.add_circle_outline_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  title: const Text(
                    '新建歌单…',
                    style: TextStyle(fontSize: 14.5),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('__new__'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  if (selected == null || !context.mounted) return;
  try {
    var playlistId = selected;
    if (selected == '__new__') {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('新建歌单'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(hintText: '请输入歌单名称'),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (name == null || name.isEmpty || !context.mounted) return;
      await library.createPlaylist(name);
      playlistId = library.playlists.last.id;
    }
    await library.addSongTo(playlistId, song);
    if (context.mounted) {
      final playlist = library.playlistById(playlistId);
      AppSnackBar.show(
        context,
        message: '已将「${song.name}」加入「${playlist?.name ?? '歌单'}」',
      );
    }
  } catch (e) {
    if (context.mounted) AppSnackBar.show(context, message: e.toString());
  }
}
