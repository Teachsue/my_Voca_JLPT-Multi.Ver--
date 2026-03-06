import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';
import 'quiz_page.dart';

class WrongAnswerPage extends StatefulWidget {
  const WrongAnswerPage({super.key});

  @override
  State<WrongAnswerPage> createState() => _WrongAnswerPageState();
}

class _WrongAnswerPageState extends State<WrongAnswerPage> {
  @override
  void initState() {
    super.initState();
    // [최적화] 페이지 진입 시 해당 사용자의 최신 학습 기록만 가져옴
    if (SupabaseService.isGoogleLinked) {
      SupabaseService.downloadProgressFromServer();
    }
  }

  @override
  void dispose() {
    // [최적화] 페이지를 나갈 때 변경사항을 한 번에 서버로 전송
    if (SupabaseService.isGoogleLinked) {
      SupabaseService.uploadLocalDataToCloud();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color subTextColor = isDarkMode ? Colors.white60 : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('오답노트', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep_rounded), onPressed: () => _showResetDialog(context, isDarkMode)),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: Hive.box<Word>(DatabaseService.boxName).listenable(),
          builder: (context, Box<Word> box, _) {
            final wrongWords = box.values.where((w) => w.is_wrong_note).toList()
              ..sort((a, b) => b.incorrect_count.compareTo(a.incorrect_count));

            if (wrongWords.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_turned_in_rounded, size: 64, color: isDarkMode ? Colors.white10 : Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('오답노트가 비어있습니다!', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: subTextColor)),
                  ],
                ),
              );
            }

            return Stack(
              children: [
                ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 120),
                  itemCount: wrongWords.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final word = wrongWords[index];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(word.kanji, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                                    const SizedBox(width: 8),
                                    Text(word.kana, style: TextStyle(fontSize: 13, color: subTextColor)),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                      child: Text('틀림 ${word.incorrect_count}', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                      onPressed: () async {
                                        word.is_wrong_note = false;
                                        await word.save();
                                        await SupabaseService.upsertWordProgress(word);
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(word.meaning, style: TextStyle(fontSize: 15, color: isDarkMode ? Colors.white70 : Colors.grey[700])),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                _buildQuizButton(context, isDarkMode, wrongWords),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuizButton(BuildContext context, bool isDarkMode, List<Word> wrongWords) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: double.infinity, height: 55,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => QuizPage(level: '오답노트', questionCount: wrongWords.length, day: -1, initialWords: wrongWords))),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('오답 퀴즈 풀기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context, bool isDarkMode) { /* 생략 */ }
}
