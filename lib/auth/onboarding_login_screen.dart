import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

class OnboardingLoginScreen extends StatefulWidget {
  const OnboardingLoginScreen({super.key});

  @override
  State<OnboardingLoginScreen> createState() => _OnboardingLoginScreenState();
}

class _OnboardingLoginScreenState extends State<OnboardingLoginScreen> {
  final PageController pageController = PageController();
  final auth = const AnimidesuAuthService();

  int page = 0;
  bool loading = false;

  final slides = const [
    _Slide(
      icon: Icons.movie_filter_rounded,
      eyebrow: 'SELAMAT DATANG',
      title: 'Dunia anime\nkamu, satu tempat.',
      description:
          'Temukan cerita favoritmu, simpan koleksi, dan nikmati pengalaman Animidesu yang dibuat untuk pecinta anime.',
    ),
    _Slide(
      icon: Icons.explore_rounded,
      eyebrow: 'JELAJAHI',
      title: 'Temukan anime\nyang kamu suka.',
      description:
          'Lihat trending, anime terbaru, jadwal episode, dan temukan judul berikutnya hanya dalam beberapa ketukan.',
    ),
    _Slide(
      icon: Icons.auto_awesome_rounded,
      eyebrow: 'SIAP MULAI?',
      title: 'Masuk ke\nAnimidesu.',
      description:
          'Simpan favorit dan histori di akunmu. Tekan tombol Google untuk masuk dengan cepat dan aman.',
    ),
  ];

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      await auth.signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Login Google gagal.')),
      );
    } on GoogleSignInException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google Sign-In gagal: ${e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void next() {
    if (page == slides.length - 1) return;
    pageController.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = slides[page];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF07070B),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -130,
              right: -110,
              child: _Glow(color: scheme.primary),
            ),
            Positioned(
              bottom: -160,
              left: -140,
              child: _Glow(color: scheme.secondary),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                  child: Row(
                    children: [
                      const Text(
                        'ANIMIDESU',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${page + 1}/${slides.length}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .55),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: pageController,
                    itemCount: slides.length,
                    onPageChanged: (value) => setState(() => page = value),
                    itemBuilder: (context, index) {
                      final item = slides[index];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 190,
                              height: 190,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(48),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .08),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    scheme.primary.withValues(alpha: .28),
                                    scheme.secondary.withValues(alpha: .08),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.primary.withValues(alpha: .12),
                                    blurRadius: 60,
                                    spreadRadius: 8,
                                  ),
                                ],
                              ),
                              child: Icon(item.icon, size: 92),
                            ),
                            const SizedBox(height: 38),
                            Text(
                              item.eyebrow,
                              style: TextStyle(
                                color: scheme.primary,
                                fontSize: 11,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              item.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 34,
                                height: 1.03,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              item.description,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: Colors.white.withValues(alpha: .66),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          slides.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: i == page ? 26 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: i == page
                                  ? scheme.primary
                                  : Colors.white.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (page == slides.length - 1)
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 58,
                              child: FilledButton(
                                onPressed: loading ? null : signIn,
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: loading
                                    ? const SizedBox(
                                        width: 23,
                                        height: 23,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 27,
                                            height: 27,
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                            alignment: Alignment.center,
                                            child: const Text(
                                              'G',
                                              style: TextStyle(
                                                color: Color(0xFF4285F4),
                                                fontSize: 18,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 11),
                                          const Text(
                                            'Lanjut dengan Google',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Masuk untuk menyimpan profil dan koleksi Animidesu.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: .4),
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            TextButton(
                              onPressed: next,
                              child: const Text('Lewati'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: next,
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Lanjut'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              right: 18,
              top: 70,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  active.eyebrow,
                  key: ValueKey(active.eyebrow),
                  style: const TextStyle(fontSize: 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      height: 320,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .08),
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
}
