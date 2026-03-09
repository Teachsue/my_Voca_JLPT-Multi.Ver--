import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'day_selection_page.dart';
import 'quiz_page.dart';
import '../service/database_service.dart';

class LevelSummaryPage extends StatelessWidget {
  final String level;

  const LevelSummaryPage({super.key, required this.level});

  // 테마에 따른 정보 및 색상 가져오기
  Map<String, dynamic> _getThemeInfo(bool isDarkMode) {
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final String appTheme = sessionBox.get('app_theme', defaultValue: 'auto');
    int month = DateTime.now().month;
    String target = appTheme;
    
    if (target == 'auto') {
      if (month >= 3 && month <= 5) target = 'spring';
      else if (month >= 6 && month <= 8) target = 'summer';
      else if (month >= 9 && month <= 11) target = 'autumn';
      else target = 'winter';
    }

    if (isDarkMode) return {'color': const Color(0xFF5B86E5), 'emoji': '🌙'};
    
    switch (target) {
      case 'spring': return {'color': Colors.pinkAccent, 'emoji': '🌸'};
      case 'summer': return {'color': Colors.blueAccent, 'emoji': '🌊'};
      case 'autumn': return {'color': Colors.orangeAccent, 'emoji': '🍁'};
      case 'winter':
      default: return {'color': Colors.blueGrey, 'emoji': '❄️'};
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeInfo = _getThemeInfo(isDarkMode);
    final Color themeColor = themeInfo['color'];
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color subTextColor = isDarkMode ? Colors.white60 : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('$level 학습 정보', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildActionCard(context, title: '단어 학습하기', subtitle: 'DAY별 20개씩 기초부터 탄탄하게', icon: Icons.menu_book_rounded, color: const Color(0xFF5B86E5), isDarkMode: isDarkMode, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => DaySelectionPage(level: level)))),
              const SizedBox(height: 16),
              _buildActionCard(context, title: '랜덤 퀴즈 풀기', subtitle: '다양한 문제 수로 실력 테스트', icon: Icons.quiz_rounded, color: Colors.orangeAccent, isDarkMode: isDarkMode, onTap: () => _showQuizCountDialog(context, isDarkMode, themeInfo)),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required bool isDarkMode, required VoidCallback onTap}) {
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color subTextColor = isDarkMode ? Colors.white60 : Colors.grey[600]!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color, size: 28)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)), const SizedBox(height: 2), Text(subtitle, style: TextStyle(fontSize: 13, color: subTextColor))])), Icon(Icons.chevron_right_rounded, color: isDarkMode ? Colors.white24 : Colors.grey[400])]),
      ),
    );
  }

  void _showQuizCountDialog(BuildContext context, bool isDarkMode, Map<String, dynamic> themeInfo) {
    final Color themeColor = themeInfo['color'];
    final String emoji = themeInfo['emoji'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        title: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 16),
            Text('랜덤 퀴즈 설정', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: isDarkMode ? Colors.white : Colors.black87)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('학습 컨디션에 맞춰 문제 수를 선택하세요!', style: TextStyle(color: isDarkMode ? Colors.white60 : Colors.blueGrey, fontSize: 14)),
            const SizedBox(height: 24),
            _buildCountOption(context, 10, isDarkMode, themeColor),
            _buildCountOption(context, 20, isDarkMode, themeColor),
            _buildCountOption(context, 30, isDarkMode, themeColor),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.pop(context), child: Text('다음에 하기', style: TextStyle(color: isDarkMode ? Colors.white24 : Colors.grey, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }

  Widget _buildCountOption(BuildContext context, int count, bool isDarkMode, Color themeColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => QuizPage(level: level, questionCount: count, day: -1))); },
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), side: BorderSide(color: isDarkMode ? Colors.white10 : themeColor.withOpacity(0.3), width: 1.5), foregroundColor: isDarkMode ? Colors.white : themeColor),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.bolt_rounded, size: 18, color: isDarkMode ? Colors.white38 : themeColor), const SizedBox(width: 8), Text('$count문제 도전하기', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
        ),
      ),
    );
  }
}
