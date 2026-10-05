import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth/auth_gate.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await GoogleSignIn.instance.initialize();
  runApp(const AnimidesuApp());
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
    this.nextEpisode,
    this.airingAt,
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
  final int? nextEpisode;
  final int? airingAt;

  factory Anime.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as Map<String, dynamic>? ?? const {};
    final cover = json['coverImage'] as Map<String, dynamic>? ?? const {};
    final airing =
        json['nextAiringEpisode'] as Map<String, dynamic>? ?? const {};

    String clean(String text) {
      return text
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&#039;', "'")
          .trim();
    }

    return Anime(
      id: json['id'] as int,
      title: (title['english'] ?? title['romaji'] ?? title['native'] ?? 'Tanpa Judul')
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
      nextEpisode: airing['episode'] as int?,
      airingAt: airing['airingAt'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'cover': cover,
      'banner': banner,
      'description': description,
      'episodes': episodes,
      'status': status,
      'score': score,
      'genres': genres,
      'nextEpisode': nextEpisode,
      'airingAt': airingAt,
    };
  }
}

class HomeData {
  const HomeData({
    required this.trending,
    required this.airing,
    required this.popular,
  });

  final List<Anime> trending;
  final List<Anime> airing;
  final List<Anime> popular;
}

class AniListApi {
  AniListApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static final Uri endpoint = Uri.parse('https://graphql.anilist.co');

  Future<dynamic> post(
    String query, [
    Map<String, dynamic> variables = const {},
  ]) async {
    final response = await _client.post(
      endpoint,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'query': query,
        'variables': variables,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AniList HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['errors'] != null) {
      throw Exception('AniList API error');
    }

    return json['data'];
  }

  static const String fields = '''
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
  ''';

  Future<HomeData> home() async {
    final query = '''
      query Home {
        trending: Page(page: 1, perPage: 10) {
          media(sort: TRENDING_DESC, type: ANIME) {
            $fields
          }
        }

        airing: Page(page: 1, perPage: 10) {
          media(sort: UPDATED_AT_DESC, status: RELEASING, type: ANIME) {
            $fields
          }
        }

        popular: Page(page: 1, perPage: 10) {
          media(sort: POPULARITY_DESC, type: ANIME) {
            $fields
          }
        }
      }
    ''';

    final data = await post(query) as Map<String, dynamic>;

    List<Anime> parse(String name) {
      final page = data[name] as Map<String, dynamic>;
      return (page['media'] as List<dynamic>)
          .map((e) => Anime.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return HomeData(
      trending: parse('trending'),
      airing: parse('airing'),
      popular: parse('popular'),
    );
  }

  Future<List<Anime>> search(String keyword) async {
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

    final data =
        await post(query, {'search': keyword}) as Map<String, dynamic>;

    final page = data['Page'] as Map<String, dynamic>;

    return (page['media'] as List<dynamic>)
        .map((e) => Anime.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Anime> details(int id) async {
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

    final data = await post(query, {'id': id}) as Map<String, dynamic>;

    return Anime.fromJson(
      data['Media'] as Map<String, dynamic>,
    );
  }
}

class LocalStore {
  static const favoriteKey = 'animidesu_favorites';
  static const historyKey = 'animidesu_history';

  Future<SharedPreferences> get prefs =>
      SharedPreferences.getInstance();

  Future<List<Anime>> favorites() async {
    final p = await prefs;
    final raw = p.getStringList(favoriteKey) ?? [];

    return raw
        .map((e) => Anime.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> toggleFavorite(Anime anime) async {
    final p = await prefs;
    final items = await favorites();

    final index = items.indexWhere((e) => e.id == anime.id);

    if (index >= 0) {
      items.removeAt(index);
    } else {
      items.insert(0, anime);
    }

    await p.setStringList(
      favoriteKey,
      items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<bool> isFavorite(int id) async {
    final items = await favorites();
    return items.any((e) => e.id == id);
  }

  Future<List<Anime>> history() async {
    final p = await prefs;
    final raw = p.getStringList(historyKey) ?? [];

    return raw
        .map((e) => Anime.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addHistory(Anime anime) async {
    final p = await prefs;
    final items = await history();

    items.removeWhere((e) => e.id == anime.id);
    items.insert(0, anime);

    if (items.length > 30) {
      items.removeRange(30, items.length);
    }

    await p.setStringList(
      historyKey,
      items.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }
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
        colorSchemeSeed: const Color(0xFF8B5CF6),
        scaffoldBackgroundColor: const Color(0xFF08080C),
      ),
      home: const AuthGate(child: MainShell()),
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
      body: IndexedStack(
        index: index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          setState(() => index = value);
        },
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
  late Future<HomeData> future = widget.api.home();

  final search = TextEditingController();

  List<Anime> results = [];
  Set<int> favorites = {};
  bool searching = false;

  @override
  void initState() {
    super.initState();
    loadFavorites();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> loadFavorites() async {
    final data = await widget.store.favorites();

    if (mounted) {
      setState(() {
        favorites = data.map((e) => e.id).toSet();
      });
    }
  }

  Future<void> favorite(Anime anime) async {
    await widget.store.toggleFavorite(anime);
    await loadFavorites();
  }

  Future<void> doSearch() async {
    final keyword = search.text.trim();

    if (keyword.isEmpty) return;

    setState(() {
      searching = true;
    });

    try {
      final data = await widget.api.search(keyword);

      if (mounted) {
        setState(() {
          results = data;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pencarian gagal: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          searching = false;
        });
      }
    }
  }

  void openAnime(Anime anime) {
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

  Future<void> refresh() async {
    final next = widget.api.home();
    setState(() {
      future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        child: CustomScrollView(
          slivers: [
            const SliverAppBar(
              pinned: true,
              floating: true,
              title: Text(
                'Animidesu',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
              actions: [
                Icon(Icons.notifications_none),
                SizedBox(width: 12),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SearchBar(
                  controller: search,
                  hintText: 'Cari anime, donghua, judul...',
                  leading: const Icon(Icons.search),
                  trailing: [
                    IconButton(
                      onPressed: searching ? null : doSearch,
                      icon: searching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.arrow_forward),
                    ),
                  ],
                  onSubmitted: (_) => doSearch(),
                ),
              ),
            ),
            if (results.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: SectionTitle(title: '🔎 Hasil Pencarian'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: AnimeGrid(
                  items: results,
                  favorites: favorites,
                  onTap: openAnime,
                  onFavorite: favorite,
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: FutureBuilder<HomeData>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 80),
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(18),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.wifi_off,
                                size: 42,
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Katalog belum dapat dimuat.',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text('${snapshot.error}'),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: refresh,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Coba Lagi'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final data = snapshot.data;

                  if (data == null) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    children: [
                      if (data.trending.isNotEmpty)
                        HeroBanner(
                          anime: data.trending.first,
                          onTap: () => openAnime(data.trending.first),
                        ),
                      AnimeSection(
                        title: '🔥 Trending',
                        items: data.trending,
                        favorites: favorites,
                        onTap: openAnime,
                        onFavorite: favorite,
                      ),
                      AnimeSection(
                        title: '📺 Sedang Tayang',
                        items: data.airing,
                        favorites: favorites,
                        onTap: openAnime,
                        onFavorite: favorite,
                      ),
                      AnimeSection(
                        title: '⭐ Populer',
                        items: data.popular,
                        favorites: favorites,
                        onTap: openAnime,
                        onFavorite: favorite,
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
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class AnimeSection extends StatelessWidget {
  const AnimeSection({
    super.key,
    required this.title,
required this.items,
    required this.favorites,
    required this.onTap,
    required this.onFavorite,
  });

  final String title;
  final List<Anime> items;
  final Set<int> favorites;
  final void Function(Anime) onTap;
  final Future<void> Function(Anime) onFavorite;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: title),
        SizedBox(
          height: 300,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final anime = items[index];

              return AnimeCard(
                anime: anime,
                favorite: favorites.contains(anime.id),
                onFavorite: () => onFavorite(anime),
                onTap: () => onTap(anime),
              );
            },
          ),
        ),
      ],
    );
  }
}

class AnimeGrid extends StatelessWidget {
  const AnimeGrid({
    super.key,
    required this.items,
    required this.favorites,
    required this.onTap,
    required this.onFavorite,
  });

  final List<Anime> items;
  final Set<int> favorites;
  final void Function(Anime) onTap;
  final Future<void> Function(Anime) onFavorite;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final anime = items[index];

          return AnimeCard(
            anime: anime,
            favorite: favorites.contains(anime.id),
            onFavorite: () => onFavorite(anime),
            onTap: () => onTap(anime),
          );
        },
        childCount: items.length,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: .49,
      ),
    );
  }
}

class HeroBanner extends StatelessWidget {
  const HeroBanner({
    super.key,
    required this.anime,
    required this.onTap,
  });

  final Anime anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image =
        anime.banner.isEmpty ? anime.cover : anime.banner;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: AspectRatio(
        aspectRatio: 1.7,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const ColoredBox(
                    color: Color(0xFF1D1D28),
                  );
                },
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0xF0000000),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ANIME PILIHAN',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Lihat Detail'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
      width: 148,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(17),
                    child: Image.network(
                      anime.cover,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) {
                        return const ColoredBox(
                          color: Color(0xFF20202A),
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (onFavorite != null)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        child: IconButton(
                          visualDensity:
                              VisualDensity.compact,
                          onPressed: onFavorite,
                          icon: Icon(
                            favorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  if (anime.score != null)
                    Positioned(
                      left: 7,
                      bottom: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius:
                              BorderRadius.circular(7),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          child: Text(
                            '⭐ ${anime.score}',
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
            const SizedBox(height: 7),
            Text(
              anime.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${anime.episodes ?? '?'} eps',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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
    favorite = await widget.store.isFavorite(anime.id);

    try {
      anime = await widget.api.details(anime.id);
    } catch (_) {}

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> toggleFavorite() async {
    await widget.store.toggleFavorite(anime);
    favorite = !favorite;

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> startWatching() async {
    await widget.store.addHistory(anime);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Episode $episode ditambahkan ke histori.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = anime.episodes ?? 12;
    final selected = episode.clamp(1, count);
    final image =
        anime.banner.isEmpty ? anime.cover : anime.banner;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 290,
            pinned: true,
            actions: [
              IconButton(
                onPressed: toggleFavorite,
                icon: Icon(
                  favorite
                      ? Icons.favorite
                      : Icons.favorite_border,
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
                    image,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stackTrace) {
                      return const ColoredBox(
                        color: Color(0xFF171720),
                      );
                    },
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0xFF08080C),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                18,
                16,
                36,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (anime.status.isNotEmpty)
                        Chip(label: Text(anime.status)),
                      if (anime.score != null)
                        Chip(
                          label:
                              Text('⭐ ${anime.score}/100'),
                        ),
                      Chip(
                        label:
                            Text('${anime.episodes ?? '?'} eps'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    anime.description.isEmpty
                        ? 'Deskripsi belum tersedia.'
                        : anime.description,
                    style: const TextStyle(
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Genre',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: anime.genres
                        .map(
                          (genre) => Chip(
                            label: Text(genre),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Episode',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (var i = 1; i <= count; i++)
                        ChoiceChip(
                          label: Text('$i'),
                          selected: i == selected,
                          onSelected: (_) {
                            setState(() => episode = i);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: startWatching,
                      icon: const Icon(
                        Icons.play_arrow,
                      ),
                      label: Text(
                        'Mulai Episode $selected',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Player video, subtitle, kualitas, dan download akan ditambahkan setelah server video berlisensi siap.',
                      ),
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
  int tab = 0;
  bool loading = true;
  List<Anime> items = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);

    final value = tab == 0
        ? await widget.store.favorites()
        : await widget.store.history();

    if (mounted) {
      setState(() {
        items = value;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Koleksi',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              8,
              16,
              10,
            ),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Favorit'),
                  icon: Icon(Icons.favorite),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Histori'),
                  icon: Icon(Icons.history),
                ),
              ],
              selected: {tab},
              onSelectionChanged: (value) {
                setState(() => tab = value.first);
                load();
              },
            ),
          ),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : items.isEmpty
                    ? Center(
                        child: Text(
                          tab == 0
                              ? 'Belum ada favorit.'
                              : 'Belum ada histori.',
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: load,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: items.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                            childAspectRatio: .49,
                          ),
                          itemBuilder: (context, index) {
                            final anime = items[index];

                            return AnimeCard(
                              anime: anime,
                              favorite: true,
                              onTap: () {
                                Navigator.of(context)
                                    .push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DetailScreen(
                                      api: widget.api,
                                      store: widget.store,
                                      anime: anime,
                                    ),
                                  ),
                                );
                              },
                              onFavorite: tab == 0
                                  ? () async {
                                      await widget.store
                                          .toggleFavorite(
                                        anime,
                                      );
                                      load();
                                    }
                                  : null,
                            );
                          },
                        ),
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
  State<ScheduleScreen> createState() =>
      _ScheduleScreenState();
}

class _ScheduleScreenState
    extends State<ScheduleScreen> {
  late Future<HomeData> future = widget.api.home();

  String date(int? timestamp) {
    if (timestamp == null) {
      return 'Waktu belum tersedia';
    }

    final dt =
        DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
    ).toLocal();

    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');

    return '$d/$m $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Jadwal Episode',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: FutureBuilder<HomeData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Gagal memuat jadwal: ${snapshot.error}',
                ),
              ),
            );
          }

          final items = (snapshot.data?.airing ??
                  const <Anime>[])
              .where(
                (anime) => anime.nextEpisode != null,
              )
              .toList();

          if (items.isEmpty) {
            return const Center(
              child: Text(
                'Belum ada jadwal tersedia.',
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              final next = widget.api.home();
              setState(() => future = next);
              await next;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final anime = items[index];

                return Card(
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.all(10),
                    leading: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(10),
                      child: Image.network(
                        anime.cover,
                        width: 58,
                        height: 76,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (context, error, stackTrace) {
                          return const SizedBox(
                            width: 58,
                            height: 76,
                            child: ColoredBox(
                              color: Color(0xFF20202A),
                              child: Icon(
                                Icons.broken_image,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    title: Text(
                      anime.title,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Episode ${anime.nextEpisode}\n${date(anime.airingAt)}',
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
      appBar: AppBar(
        title: const Text(
          'Profil',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    child: Text(
                      'A',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Animidesu User',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text('Level 1 • 0 XP'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading:
                      Icon(Icons.favorite_outline),
                  title: Text('Favorit'),
                  subtitle: Text(
                    'Koleksi anime yang disimpan',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Histori'),
                  subtitle: Text(
                    'Riwayat tontonan',
                  ),
                ),
                ListTile(
                  leading: Icon(
                    Icons.notifications_outlined,
                  ),
                  title: Text('Notifikasi'),
                  subtitle: Text(
                    'Akan ditambahkan bersama backend',
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading:
                      Icon(Icons.palette_outlined),
                  title: Text('Tema'),
                  subtitle: Text(
                    'Dark theme Animidesu',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.language),
                  title: Text('Bahasa'),
                  subtitle: Text('Indonesia'),
                ),
                ListTile(
                  leading:
                      Icon(Icons.download_outlined),
                  title: Text('Download'),
                  subtitle: Text(
                    'Akan hadir bersama player',
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Animidesu 1.2\n\n'
                'Katalog memakai metadata AniList. '
                'Video akan menggunakan sumber yang Anda '
                'miliki atau mempunyai hak distribusi.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
