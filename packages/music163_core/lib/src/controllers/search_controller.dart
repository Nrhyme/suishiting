import '../data/music_repository.dart';
import '../domain/models.dart';
import 'base_controller.dart';
import 'library_controller.dart';

enum SearchTab { songs, albums, artists }

class SearchController extends SafeNotifier {
  SearchController(this._repository, {this.library});
  final MusicRepository _repository;
  final LibraryController? library;
  String query = '';
  SearchTab tab = SearchTab.songs;
  List<Song> get songs => List.unmodifiable(_songs);
  List<Album> get albums => List.unmodifiable(_albums);
  List<Artist> get artists => List.unmodifiable(_artists);
  List<Song> _songs = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  bool isLoading = false;
  bool isLoadingMore = false;
  bool hasMore = false;
  String? error;
  int _generation = 0;
  int _offset = 0;
  MusicPlatform platform = MusicPlatform.netease;

  Future<void> setPlatform(MusicPlatform value) async {
    if (value == platform || closed) return;
    platform = value;
    await search(query);
  }

  /// 当前标签的结果数量（用于分页文案）。
  int get resultCount => switch (tab) {
    SearchTab.songs => _songs.length,
    SearchTab.albums => _albums.length,
    SearchTab.artists => _artists.length,
  };

  /// 切换单曲/专辑/歌手标签：若目标标签尚无当前关键词的结果则触发搜索。
  Future<void> setTab(SearchTab value) async {
    if (value == tab || closed) return;
    tab = value;
    final results = switch (tab) {
      SearchTab.songs => _songs,
      SearchTab.albums => _albums,
      SearchTab.artists => _artists,
    };
    if (query.isNotEmpty && results.isEmpty && error == null) {
      await search(query);
    } else {
      changed();
    }
  }

  Future<void> search(String text) async {
    if (closed) return;
    final request = ++_generation;
    final selectedPlatform = platform;
    final selectedTab = tab;
    query = text.trim();
    switch (selectedTab) {
      case SearchTab.songs:
        _songs = [];
      case SearchTab.albums:
        _albums = [];
      case SearchTab.artists:
        _artists = [];
    }
    _offset = 0;
    hasMore = false;
    error = null;
    isLoadingMore = false;
    if (query.isEmpty) {
      isLoading = false;
      changed();
      return;
    }
    isLoading = true;
    changed();
    try {
      if (selectedTab == SearchTab.albums) {
        final page = await _repository.searchAlbumsFor(
          selectedPlatform,
          query,
        );
        if (request != _generation || closed) return;
        _albums = page.albums;
        _offset = page.nextOffset ?? page.albums.length;
        hasMore = page.hasMore;
      } else if (selectedTab == SearchTab.artists) {
        final page = await _repository.searchArtistsFor(
          selectedPlatform,
          query,
        );
        if (request != _generation || closed) return;
        _artists = page.artists;
        _offset = page.nextOffset ?? page.artists.length;
        hasMore = page.hasMore;
      } else {
        await library?.addSearch(query);
        if (request != _generation || closed) return;
        final resolved = await _repository.resolveSong(
          selectedPlatform,
          query,
        );
        final page = resolved != null
            ? SearchPage(songs: [resolved], hasMore: false, total: 1)
            : await _repository.searchFor(selectedPlatform, query);
        if (request != _generation || closed) return;
        _songs = page.songs;
        _offset = page.nextOffset ?? page.songs.length;
        hasMore = page.hasMore;
      }
    } catch (e) {
      if (request == _generation) error = userError(e);
    } finally {
      if (request == _generation) {
        isLoading = false;
        changed();
      }
    }
  }

  Future<void> loadMore() async {
    if (isLoading || isLoadingMore || !hasMore || closed) return;
    final request = _generation;
    final selectedTab = tab;
    final selectedPlatform = platform;
    isLoadingMore = true;
    error = null;
    changed();
    try {
      if (selectedTab == SearchTab.albums) {
        final page = await _repository.searchAlbumsFor(
          selectedPlatform,
          query,
          offset: _offset,
        );
        if (request != _generation || closed) return;
        final ids = _albums.map((a) => a.key).toSet();
        _albums = [..._albums, ...page.albums.where((a) => ids.add(a.key))];
        _offset = page.nextOffset ?? _offset + page.albums.length;
        hasMore = page.hasMore;
      } else if (selectedTab == SearchTab.artists) {
        final page = await _repository.searchArtistsFor(
          selectedPlatform,
          query,
          offset: _offset,
        );
        if (request != _generation || closed) return;
        final ids = _artists.map((a) => a.key).toSet();
        _artists = [..._artists, ...page.artists.where((a) => ids.add(a.key))];
        _offset = page.nextOffset ?? _offset + page.artists.length;
        hasMore = page.hasMore;
      } else {
        final page = await _repository.searchFor(
          selectedPlatform,
          query,
          offset: _offset,
        );
        if (request != _generation || closed) return;
        final ids = _songs.map((s) => s.key).toSet();
        _songs = [..._songs, ...page.songs.where((s) => ids.add(s.key))];
        _offset = page.nextOffset ?? _offset + page.songs.length;
        hasMore = page.hasMore;
      }
    } catch (e) {
      if (request == _generation) error = userError(e);
    } finally {
      if (request == _generation) {
        isLoadingMore = false;
        changed();
      }
    }
  }

  /// 获取专辑曲目（用于专辑详情页）。
  Future<List<Song>> albumSongs(Album album) => _repository.albumSongs(album);

  /// 歌手歌曲 / 专辑（用于歌手详情页）。
  Future<List<Song>> artistSongs(Artist artist) =>
      _repository.artistSongsFor(artist);

  Future<List<Album>> artistAlbums(Artist artist) =>
      _repository.artistAlbumsFor(artist);
}
