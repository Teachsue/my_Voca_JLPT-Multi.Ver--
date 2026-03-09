import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import '../service/database_service.dart';
import 'word_list_page.dart';

class DaySelectionPage extends StatefulWidget {
  final String level;

  const DaySelectionPage({super.key, required this.level});

  @override
  State<DaySelectionPage> createState() => _DaySelectionPageState();
}

class _DaySelectionPageState extends State<DaySelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = "";
  List<List<Word>> _allDayChunks = [];

  @override
  void initState() {
    super.initState();
    _calculateDayChunks();
  }

  void _calculateDayChunks() {
    final String levelStr = widget.level.replaceAll(RegExp(r'[^0-9]'), '');
    final int levelInt = int.tryParse(levelStr) ?? 5; // 기본값 N5
    final List<Word> allWords = DatabaseService.getWordsByLevel(levelInt);
    if (allWords.isEmpty) return;
    
    // 1. ID 순으로 정렬 후 고정 시드(42)로 셔플하여 순서 고정 (메인 페이지 로직과 일치)
    // 비슷한 발음의 단어가 모이는 것을 방지하기 위해 섞어서 보여줌
    allWords.sort((a, b) => a.id.compareTo(b.id)); 
    allWords.shuffle(Random(42)); 
    
    // 2. 모든 레벨 Day당 20개씩 단어 묶기
    final List<List<Word>> chunks = [];
    const int chunkSize = 20;
    for (int i = 0; i < allWords.length; i += chunkSize) {
      int end = (i + chunkSize < allWords.length) ? i + chunkSize : allWords.length;
      List<Word> chunk = allWords.sublist(i, end);
      
      // 마지막 묶음이 10개 미만이면 이전 묶음에 합침 (단, 이전 묶음이 존재할 때만)
      if (chunks.isNotEmpty && chunk.length < 10) {
        chunks.last.addAll(chunk);
      } else {
        chunks.add(chunk);
      }
    }
    _allDayChunks = chunks;
  }

  // 계절 및 모드에 따른 배너 색상을 가져오는 함수
  List<Color> _getBannerColors(bool isDarkMode) {
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final String appTheme = sessionBox.get('app_theme', defaultValue: 'auto');
    if (isDarkMode) return [const Color(0xFF3F4E4F), const Color(0xFF2C3333)];
    int month = DateTime.now().month;
    String target = appTheme;
    if (target == 'auto') {
      if (month >= 3 && month <= 5) target = 'spring';
      else if (month >= 6 && month <= 8) target = 'summer';
      else if (month >= 9 && month <= 11) target = 'autumn';
      else target = 'winter';
    }
    switch (target) {
      case 'spring': return [const Color(0xFFFFB7C5), const Color(0xFFF08080)];
      case 'summer': return [const Color(0xFF4FC3F7), const Color(0xFF1976D2)];
      case 'autumn': return [const Color(0xFFFBC02D), const Color(0xFFE64A19)];
      case 'winter':
      default: return [const Color(0xFF90A4AE), const Color(0xFF455A64)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final List<Color> bannerColors = _getBannerColors(isDarkMode);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'DAY 번호 검색...',
                  hintStyle: TextStyle(color: isDarkMode ? Colors.white38 : Colors.grey),
                  border: InputBorder.none,
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) => setState(() { _searchQuery = value; }),
              )
            : Text('${widget.level} DAY 선택', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        actions: [
          IconButton(icon: Icon(Icons.home_rounded, size: 22, color: textColor), onPressed: () => Navigator.popUntil(context, (route) => route.isFirst)),
          IconButton(icon: Icon(_isSearching ? Icons.close : Icons.search, color: textColor), onPressed: () => setState(() {
            _isSearching = !_isSearching;
            if (!_isSearching) { _searchController.clear(); _searchQuery = ""; }
          })),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box(DatabaseService.sessionBoxName).listenable(keys: ['last_day_${widget.level}']),
        builder: (context, sessionBox, _) {
          final int lastDay = sessionBox.get('last_day_${widget.level}', defaultValue: 0);
          return ValueListenableBuilder(
            valueListenable: Hive.box<Word>(DatabaseService.boxName).listenable(),
            builder: (context, Box<Word> box, _) {
              if (_allDayChunks.isEmpty) return Center(child: CircularProgressIndicator(color: const Color(0xFF5B86E5)));
              final filteredDays = _searchQuery.isEmpty ? List.generate(_allDayChunks.length, (i) => i) : List.generate(_allDayChunks.length, (i) => i).where((index) => (index + 1).toString().contains(_searchQuery)).toList();
              if (filteredDays.isEmpty) return Center(child: Text('검색 결과가 없습니다.', style: TextStyle(color: textColor)));

              return Column(
                children: [
                  if (!_isSearching && lastDay > 0 && _searchQuery.isEmpty)
                    Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 0), child: _buildResumeCard(context, lastDay, isDarkMode, bannerColors)),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 60),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85),
                      itemCount: filteredDays.length,
                      itemBuilder: (context, index) {
                        final dayIndex = filteredDays[index];
                        return _buildDayGridItem(context, dayIndex + 1, _allDayChunks[dayIndex], (dayIndex + 1) == lastDay, isDarkMode);
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildResumeCard(BuildContext context, int lastDay, bool isDarkMode, List<Color> bannerColors) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => WordListPage(level: widget.level, initialDayIndex: lastDay - 1, allDayChunks: _allDayChunks))),
      child: Container(
        width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: bannerColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDarkMode ? [] : [BoxShadow(color: bannerColors[0].withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.history_rounded, color: Colors.white, size: 28)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('이어서 학습하기', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)), const SizedBox(height: 2), Text('DAY $lastDay', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))])), const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 20)]),
      ),
    );
  }

  Widget _buildDayGridItem(BuildContext context, int day, List<Word> words, bool isRecent, bool isDarkMode) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => WordListPage(level: widget.level, initialDayIndex: day - 1, allDayChunks: _allDayChunks))),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isRecent ? Border.all(color: const Color(0xFF5B86E5), width: 2) : null,
          boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF5B86E5).withOpacity(0.1), shape: BoxShape.circle), child: Text('$day', style: const TextStyle(color: Color(0xFF5B86E5), fontWeight: FontWeight.w900, fontSize: 18))),
            const SizedBox(height: 10),
            Text('DAY $day', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87)),
            Text('${words.length} 단어', style: TextStyle(color: isDarkMode ? Colors.white38 : Colors.grey[600], fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
