import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';
import 'quiz_page.dart';

class WrongAnswerPage extends StatelessWidget {
  const WrongAnswerPage({super.key});

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
          IconButton(
            icon: Icon(Icons.delete_sweep_rounded, size: 22, color: textColor),
            onPressed: () => _showResetDialog(context, isDarkMode),
            tooltip: '초기화'
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: Hive.box<Word>(DatabaseService.boxName).listenable(),
          builder: (context, Box<Word> box, _) {
            final wrongWords = box.values.where((w) => w.incorrectCount > 0).toList()
              ..sort((a, b) => b.incorrectCount.compareTo(a.incorrectCount));

            if (wrongWords.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_turned_in_rounded, size: 64, color: isDarkMode ? Colors.white10 : Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('오답 기록이 없습니다.\n모든 단어를 마스터하셨네요!', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: subTextColor)),
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
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28, height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: isDarkMode ? Colors.white10 : Colors.grey[100], shape: BoxShape.circle),
                            child: Text('${index + 1}', style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  children: [
                                    Text(word.kanji, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                                    Text(word.kana, style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white38 : Colors.grey[400])),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100],
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isDarkMode ? Colors.white10 : Colors.grey[300]!, width: 0.5),
                                      ),
                                      child: Text(
                                        word.level == 11 ? '히라가나' : (word.level == 12 ? '가타카나' : 'N${word.level}'),
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white54 : Colors.grey[600]),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(word.meaning, style: TextStyle(fontSize: 15, color: isDarkMode ? Colors.white70 : Colors.grey[700])),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                child: Text('틀림 ${word.incorrectCount}', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: isDarkMode ? Colors.white24 : Colors.red[200], size: 22),
                                onPressed: () async { 
                                  word.incorrectCount = 0; 
                                  await word.save(); 
                                  // 서버와 실시간 동기화
                                  await SupabaseService.upsertWordProgress(word);
                                },
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.only(top: 4),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          isDarkMode ? const Color(0xFF1A1C2C).withOpacity(0.8) : Colors.white.withOpacity(0.8),
                          isDarkMode ? const Color(0xFF1A1C2C) : Colors.white,
                        ],
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity, height: 55,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => QuizPage(level: '오답노트', questionCount: wrongWords.length, day: -1, initialWords: wrongWords))),
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('오답 퀴즈 풀기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context, bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('오답 기록 초기화', style: TextStyle(fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87)),
        content: Text('모든 단어의 오답 기록을 삭제하시겠습니까?', style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              final box = Hive.box<Word>(DatabaseService.boxName);
              final wrongWords = box.values.where((w) => w.incorrectCount > 0).toList();
              
              // 1. 로컬 데이터 초기화 (빠르게 수행)
              for (var word in wrongWords) {
                word.incorrectCount = 0;
                await word.save();
              }

              // 2. 서버 데이터 일괄 초기화 (한 번의 요청으로 끝!)
              await SupabaseService.resetWrongAnswers();

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('초기화', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
