import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const AnimidesuApp());
}

class AnimidesuApp extends StatelessWidget {
  const AnimidesuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Animidesu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF0B0B10),
      ),
      home: const MainShell(),
    );
  }
}

class Anime {
  const Anime({
    required this.id,
    required this.title,
    required this.cover,
    this.banner = '',
    this.description = '',
    this.episodes,
    this.status = '',
    this.score,
    this.genres = const [],
    this.nextAiringAt,
    this.nextEpisode,
  });

  final int id;
  final String title;
  final String cover;
  final String banner;
  final String description;
  final int? episodes;
  final String status;
  final int? score;
  final List<String> genres;
  final int? nextAiringAt;
  final int? nextEpisode;

  factory Anime.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as Map<String, dynamic>?) ?? const {};
    final cover = (json['coverImage'] as Map<String, dynamic>?) ?? const {};
    final next =
        (json['nextAiringEpisode'] as Map<String, dynamic>?) ?? const {};

    String clean(String value) {
      return value
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&#039;', "'")
          .trim();
    }

    return Anime(
      id: json['id'] as int,
      title: (title['english'] ?? title['romaji'] ?? title['native'] ??
              'Tanpa Judul')
          .toString(),
      cover: (cover['extraLarge'] ?? cover['large'] ?? cover['medium'] ?? '')
          .toString(),
      banner: (json['bannerImage'] ?? cover['large'] ?? '').toString(),
      description: clean((json['description'] ?? '').toString()),
      episodes: json['episodes'] as int?,
      status: (json['status'] ?? '').toString(),
      score: json['averageScore'] as int?,
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      nextAiringAt: next['airingAt'] as int?,
      nextEpisode: next['episode'] as int?,
    );
  }
}

class AniListApi {
  AniListApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static final Uri endpoint = Uri.parse('https://graphql.anilist.co');

  Future<Map<String, dynamic>> _query(
    String query, [
    Map<String, dynamic> variables = const {},
  ]) async {
    final response = await _client.post(
      endpoint,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'query': query, 'variables': variables}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AniList HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['errors'] != null) {
      throw Exception('AniList mengembalikan error.');
    }
    return data;
  }

  Future<List<Anime>> home() async {
    const query = r'''
      query Home {
        trending: Page(page: 1, perPage: 10) {
          media(sort: TRENDING_DESC, type: ANIME) {
            id
            title { romaji english native }
            coverImage { large extraLarge medium }
            bannerImage
            description(asHtml: false)
            episodes
            status
            genres
            averageScore
            nextAiringEpisode { episode airingAt }
          }
        }
        popular: Page(page: 1, perPage: 10) {
          media(sort: POPULARITY_DESC, type: ANIME) {
            id
            title { romaji english native }
            coverImage { large extraLarge medium }
            bannerImage
            description(asHtml: false)
            episodes
            status
            genres
            averageScore
            nextAiringEpisode { episode airingAt }
          }
        }
        airing: Page(page: 1, perPage: 10) {
          media(sort: UPDATED_AT_DESC, status: RELEASING, type: ANIME) {
            id
            title { romaji english native }
            coverImage { large extraLarge medium }
            bannerImage
            description(asHtml: false)
            episodes
            status
            genres
            averageScore
            nextAiringEpisode { episode airingAt }
          }
        }
      }
    ''';

    final data = await _query(query);
    final root = data['data'] as Map<String, dynamic>;
    final seen = <int>{};
    final result = <Anime>[];

    for (final key in const ['trending', 'airing', 'popular']) {
      final page = root[key] as Map<String, dynamic>;
      for (final raw in page['media'] as List<dynamic>) {
        final anime = Anime.fromJson(raw as Map<String, dynamic>);
        if (seen.add(anime.id)) result.add(anime);
      }
    }

    return result;
  }

  Future<List<Anime>> search(String text) async {
    const query = r'''
      query Search($search: String) {
        Page(page: 1, perPage: 30) {
          media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
            id
            title { romaji english native }
            coverImage { large extraLarge medium }
            bannerImage
            description(asHtml: false)
            episodes
            status
            genres
            averageScore
            nextAiringEpisode { episode airingAt }
          }
        }
      }
    ''';

    final data = await _query(query, {'search': text});
    final page =
        (data['data'] as Map<String, dynamic>)['Page'] as Map<String, dynamic>;

    return (page['media'] as List<dynamic>)
        .map((e) => Anime.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Anime> detail(int id) async {
    const query = r'''
      query Detail($id: Int) {
        Media(id: $id, type: ANIME) {
          id
          title { romaji english native }
          coverImage { large extraLarge medium }
          bannerImage
          description(asHtml: false)
          episodes
          status
          genres
          averageScore
          nextAiringEpisode { episode airingAt }
        }
      }
    ''';

    final data = await _query(query, {'id': id});
    final media =
        (data['data'] as Map<String, dynamic>)['Media'] as Map<String, dynamic>;

    return Anime.fromJson(media);
  }
}

class LocalStore {
  static const favoritesKey = 'favorites_v11';
  static const historyKey = 'history_v11';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<Set<int>> favorites() async {
    final prefs = await _prefs();
    return (prefs.getStringList(favoritesKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  Future<void> toggleFavorite(int id) async {
    final prefs = await _prefs();
    final ids = await favorites();
    if (ids.contains(id)) {
      ids.remove(id);
    } else {
      ids.add(id);
    }
    await prefs.setStringList(
      favoritesKey,
      ids.map((e) => e.toString()).toList(),
    );
  }

  Future<Map<int, double>> history() async {
    final prefs = await _prefs();
    final raw = prefs.getString(historyKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(int.parse(key), (value as num).toDouble()),
    );
  }

  Future<void> saveProgress(int animeId, double progress) async {
    final prefs = await _prefs();
    final items = await history();
    items[animeId] = progress.clamp(0.0, 1.0);
    await prefs.setString(
      historyKey,
      jsonEncode(
        items.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final api = AniListApi();
  final store = LocalStore();
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(api: api, store: store),
      LibraryScreen(api: api, store: store),
      ScheduleScreen(api: api),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Koleksi',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Jadwal',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

class AnimeCard extends StatelessWidget {
  const AnimeCard({
    super.key,
    required this.anime,
    required this.onTap,
    this.favorite = false,
    this.onFavorite,
  });

  final Anime anime;
  final VoidCallback onTap;
  final bool favorite;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: .68,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      anime.cover,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const ColoredBox(
                          color: Color(0xFF22222A),
                          child: Center(child: Icon(Icons.broken_image)),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: onFavorite,
                        icon: Icon(
                          favorite ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  if (anime.score != null)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          child: Text(
                            '${anime.score}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              anime.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              '${anime.episodes ?? '?'} eps • ${anime.status.isEmpty ? '-' : anime.status}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.store,
  });

  final AniListApi api;
  final LocalStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Anime>> future = widget.api.home();
  Set<int> favorites = {};
  final searchController = TextEditingController();
  List<Anime> results = [];
  bool searching = false;

  @override
  void initState() {
    super.initState();
    loadFavorites();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadFavorites() async {
    favorites = await widget.store.favorites();
    if (mounted) setState(() {});
  }

  Future<void> favorite(Anime anime) async {
    await widget.store.toggleFavorite(anime.id);
    await loadFavorites();
  }

  Future<void> submitSearch() async {
    final text = searchController.text.trim();
    if (text.isEmpty) return;
    setState(() => searching = true);
    try {
      final value = await widget.api.search(text);
      if (mounted) setState(() => results = value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pencarian gagal: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  void openDetails(Anime anime) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailScreen(
          api: widget.api,
          store: widget.store,
          anime: anime,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          final next = widget.api.home();
          setState(() => future = next);
          await next;
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              floating: true,
              title: const Text(
                'Animidesu',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              actions: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_none),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SearchBar(
                  controller: searchController,
                  hintText: 'Cari anime...',
                  leading: const Icon(Icons.search),
                  trailing: [
                    IconButton(
                      onPressed: searching ? null : submitSearch,
                      icon: searching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward),
                    ),
                  ],
                  onSubmitted: (_) => submitSearch(),
                ),
              ),
            ),
            if (results.isNotEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Text(
                    'Hasil pencarian',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            if (results.isNotEmpty) _animeGrid(results),
            SliverToBoxAdapter(
              child: FutureBuilder<List<Anime>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(36),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Gagal memuat katalog. Cek koneksi internet lalu tarik layar untuk mencoba lagi.\n\n${snapshot.error}',
                          ),
                        ),
                      ),
                    );
                  }

                  final list = snapshot.data ?? const <Anime>[];
                  return Column(
                    children: [
                      _horizontalSection(
                        context,
                        '🔥 Trending',
                        list.take(10).toList(),
                      ),
                      _horizontalSection(
                        context,
                        '📺 Sedang Tayang',
                        list.skip(10).take(10).toList(),
                      ),
                      _horizontalSection(
                        context,
                        '⭐ Populer',
                        list.skip(20).take(10).toList(),
                      ),
                      const SizedBox(height: 100),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _horizontalSection(
    BuildContext context,
    String title,
    List<Anime> items,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        SizedBox(
          height: 300,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final anime = items[index];
              return AnimeCard(
                anime: anime,
                onTap: () => openDetails(anime),
                favorite: favorites.contains(anime.id),
                onFavorite: () => favorite(anime),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _animeGrid(List<Anime> items) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final anime = items[index];
            return AnimeCard(
              anime: anime,
              onTap: () => openDetails(anime),
              favorite: favorites.contains(anime.id),
              onFavorite: () => favorite(anime),
            );
          },
          childCount: items.length,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: .48,
        ),
      ),
    );
  }
}

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.api,
    required this.store,
    required this.anime,
  });

  final AniListApi api;
  final LocalStore store;
  final Anime anime;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Anime anime = widget.anime;
  bool favorite = false;
  int episode = 1;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    favorite = (await widget.store.favorites()).contains(anime.id);
    try {
      anime = await widget.api.detail(anime.id);
    } catch (_) {
      // Keep the card data if the detail request fails.
    }
    if (mounted) setState(() {});
  }

  Future<void> toggleFavorite() async {
    await widget.store.toggleFavorite(anime.id);
    favorite = !favorite;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final maxEpisode = anime.episodes ?? 12;
    final selectedEpisode = episode.clamp(1, maxEpisode);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            actions: [
              IconButton(
                onPressed: toggleFavorite,
                icon: Icon(
                  favorite ? Icons.favorite : Icons.favorite_border,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                anime.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    anime.banner.isEmpty ? anime.cover : anime.banner,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(color: Color(0xFF181820)),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xFF0B0B10)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (anime.status.isNotEmpty)
                        Chip(label: Text(anime.status)),
                      if (anime.score != null)
                        Chip(label: Text('Score ${anime.score}')),
                      Chip(label: Text('${anime.episodes ?? '?'} episode')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    anime.description.isEmpty
                        ? 'Deskripsi belum tersedia.'
                        : anime.description,
                    style: const TextStyle(height: 1.55),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Genre',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: anime.genres
                        .map((genre) => Chip(label: Text(genre)))
                        .toList(),
                  ),
                  const SizedBox(height: 22),
                  DropdownButtonFormField<int>(
                    initialValue: selectedEpisode,
                    decoration: const InputDecoration(
                      labelText: 'Episode',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var i = 1; i <= maxEpisode; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text('Episode $i'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => episode = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Player akan diaktifkan setelah server streaming berlisensi ditambahkan.',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: Text('Tonton Episode $selectedEpisode'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.api,
    required this.store,
  });

  final AniListApi api;
  final LocalStore store;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String tab = 'Favorit';
  bool loading = true;
  Set<int> favoriteIds = {};
  Map<int, double> historyMap = {};
  List<Anime> items = [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() => loading = true);
    favoriteIds = await widget.store.favorites();
    historyMap = await widget.store.history();

    final ids = tab == 'Favorit' ? favoriteIds : historyMap.keys.toSet();
    final result = <Anime>[];

    for (final id in ids.take(24)) {
      try {
        result.add(await widget.api.detail(id));
      } catch (_) {
        // Skip unavailable entries.
      }
    }

    if (mounted) {
      setState(() {
        items = result;
        loading = false;
      });
    }
  }

  Future<void> toggleFavorite(Anime anime) async {
    await widget.store.toggleFavorite(anime.id);
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Koleksi')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'Favorit',
                  label: Text('Favorit'),
                  icon: Icon(Icons.favorite),
                ),
                ButtonSegment(
                  value: 'Histori',
                  label: Text('Histori'),
                  icon: Icon(Icons.history),
                ),
              ],
              selected: {tab},
              onSelectionChanged: (value) {
                setState(() => tab = value.first);
                reload();
              },
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Text(
                          tab == 'Favorit'
                              ? 'Belum ada anime favorit.'
                              : 'Belum ada histori tontonan.',
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 12,
                          childAspectRatio: .48,
                        ),
                        itemBuilder: (context, index) {
                          final anime = items[index];
                          return AnimeCard(
                            anime: anime,
                            favorite: favoriteIds.contains(anime.id),
                            onFavorite: () => toggleFavorite(anime),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DetailScreen(
                                    api: widget.api,
                                    store: widget.store,
                                    anime: anime,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.api,
  });

  final AniListApi api;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late Future<List<Anime>> future = widget.api.home();

  String dateText(int? timestamp) {
    if (timestamp == null) return 'Waktu belum tersedia';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toLocal();
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$dd/$mm ${hh}:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jadwal Episode')),
      body: FutureBuilder<List<Anime>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Gagal memuat jadwal: ${snapshot.error}'));
          }

          final list = (snapshot.data ?? const <Anime>[])
              .where((anime) => anime.nextEpisode != null)
              .toList();

          if (list.isEmpty) {
            return const Center(child: Text('Belum ada jadwal tersedia.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              final next = widget.api.home();
              setState(() => future = next);
              await next;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final anime = list[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(10),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        anime.cover,
                        width: 55,
                        height: 75,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(
                          width: 55,
                          height: 75,
                          child: ColoredBox(
                            color: Color(0xFF22222A),
                            child: Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Episode ${anime.nextEpisode}\n${dateText(anime.nextAiringAt)}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 34,
                    child: Text('A', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Animidesu User',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text('Level 1 • 0 XP'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.favorite_outline),
                  title: Text('Favorit'),
                  subtitle: Text('Koleksi anime tersimpan di perangkat'),
                ),
                ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Histori'),
                  subtitle: Text('Progress tontonan tersimpan lokal'),
                ),
                ListTile(
                  leading: Icon(Icons.notifications_outlined),
                  title: Text('Notifikasi'),
                  subtitle: Text('Akan diaktifkan pada tahap backend'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Tentang Animidesu 1.1'),
              subtitle: Text(
                'Metadata anime menggunakan AniList. Fitur streaming akan memakai sumber video yang Anda miliki atau berlisensi.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
