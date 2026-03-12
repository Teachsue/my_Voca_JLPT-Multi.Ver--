import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'view/home_page.dart';
import 'service/database_service.dart';
import 'service/supabase_service.dart';
import 'view/seasonal_background.dart';
import 'view_model/study_view_model.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  Future<void> initializeApp() async {
    // .env 파일 로드
    await dotenv.load(fileName: ".env");
    
    // Supabase 초기화
    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL'),
      anonKey: dotenv.get('SUPABASE_ANON_KEY'),
    );
    
    // 필수 로컬 DB 초기화
    await DatabaseService.init();
    await initializeDateFormatting('ko_KR', null);

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Provider를 통해 ViewModel 제공
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => StudyViewModel()),
        ],
        child: const MyApp(),
      ),
    );

    // --- 비동기 백그라운드 작업 ---
    Future.microtask(() async {
      try {
        for (int i = 1; i <= 5; i++) {
          await DatabaseService.loadJsonToHive(i);
        }
        await DatabaseService.loadJsonToHive(11);
        await DatabaseService.loadJsonToHive(12);
        
        Future.delayed(const Duration(seconds: 3), () async {
          debugPrint("📡 백그라운드 서버 동기화를 시작합니다...");
          await DatabaseService.syncMasterData();
        });
      } catch (e) {
        debugPrint("⚠️ 백그라운드 작업 중 오류가 발생했습니다: $e");
      }
    });
  }

  try {
    await initializeApp();
  } catch (e) {
    debugPrint("❌ 앱 실행 실패: $e");
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: InitializationErrorPage(
        error: e.toString(),
        onRetry: () => main(),
      ),
    ));
  }
}

class InitializationErrorPage extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const InitializationErrorPage({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(32),
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5B86E5), Color(0xFF36D1DC)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            const Text(
              '연결에 실패했습니다',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            const Text(
              '인터넷 연결을 확인하고 다시 시도해 주세요.\n서버 점검 중일 수도 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 200,
              height: 52,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF5B86E5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: const Text('다시 시도하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                // 에러 상세 보기 토글 등 (선택 사항)
              },
              child: Text(
                '에러 상세 보기: ${error.length > 50 ? error.substring(0, 50) + '...' : error}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 책장을 넘길 때 배경도 함께 이동시켜 잔상을 없애는 커스텀 빌더
class SolidPageTurnTransitionsBuilder extends PageTransitionsBuilder {
  final bool isDarkMode;
  final String appTheme;

  const SolidPageTurnTransitionsBuilder({
    required this.isDarkMode,
    required this.appTheme,
  });

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slideIn = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutQuart));

    final slideOut =
        Tween<Offset>(begin: Offset.zero, end: const Offset(-0.3, 0.0)).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: Curves.easeOutQuart,
          ),
        );

    return SlideTransition(
      position: slideIn,
      child: SlideTransition(
        position: slideOut,
        child: SeasonalBackground(
          isDarkMode: isDarkMode,
          appTheme: appTheme,
          child: child,
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);

    return ValueListenableBuilder<Box>(
      valueListenable: sessionBox.listenable(keys: ['dark_mode', 'app_theme']),
      builder: (context, box, _) {
        final dynamic rawDarkMode = box.get('dark_mode', defaultValue: false);
        final bool isDarkMode = (rawDarkMode == true || rawDarkMode.toString() == 'true');
        final String appTheme = box.get('app_theme', defaultValue: 'auto').toString();

        return MaterialApp(
          title: 'JLPT 단어장',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF5B86E5),
              brightness: isDarkMode ? Brightness.dark : Brightness.light,
            ),
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            textTheme:
                GoogleFonts.notoSansTextTheme(
                  isDarkMode
                      ? ThemeData.dark().textTheme
                      : ThemeData.light().textTheme,
                ).apply(
                  bodyColor: isDarkMode ? Colors.white : Colors.black87,
                  displayColor: isDarkMode ? Colors.white : Colors.black87,
                ),
            scaffoldBackgroundColor: Colors.transparent,
            canvasColor: isDarkMode ? const Color(0xFF1A1C2C) : Colors.white,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
            ),
            pageTransitionsTheme: PageTransitionsTheme(
              builders: {
                TargetPlatform.android: SolidPageTurnTransitionsBuilder(
                  isDarkMode: isDarkMode,
                  appTheme: appTheme,
                ),
                TargetPlatform.iOS: SolidPageTurnTransitionsBuilder(
                  isDarkMode: isDarkMode,
                  appTheme: appTheme,
                ),
              },
            ),
          ),
          builder: (context, child) {
            return child!;
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const HomePage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);

    return ValueListenableBuilder<Box>(
      valueListenable: sessionBox.listenable(keys: ['app_theme']),
      builder: (context, box, _) {
        final String appTheme = box.get('app_theme', defaultValue: 'auto');
        return Scaffold(
          body: SeasonalBackground(
            isDarkMode: isDarkMode,
            appTheme: appTheme,
            child: Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icon.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      '냥냥 일본어',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '오늘도 일본어 한 걸음, 즐겁게 시작해요 🐾',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDarkMode ? Colors.white60 : Colors.blueGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
