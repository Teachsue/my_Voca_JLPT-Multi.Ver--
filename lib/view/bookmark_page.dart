import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';

class BookmarkPage extends StatefulWidget {
  const BookmarkPage({super.key});

  @override
  State<BookmarkPage> createState() => _BookmarkPageState();
}

class _BookmarkPageState extends State<BookmarkPage> {
  @override
  void initState() {
    super.initState();
    // 진입 시 서버에서 최신 북마크 상태 가져오기 (데이터 최적화를 위해 호출)
    SupabaseService.downloadProgressFromServer();
  }

  @override
  void dispose() {
    // 나갈 때 로컬의 변경사항(북마크 해제 등)을 서버에 일괄 반영
    SupabaseService.uploadLocalDataToCloud();
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
        title: Text('북마크', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: Hive.box<Word>(DatabaseService.boxName).listenable(),
          builder: (context, Box<Word> box, _) {
            final bookmarkedWords = box.values.where((w) => w.isBookmarked).toList();

            if (bookmarkedWords.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bookmark_border_rounded, size: 64, color: isDarkMode ? Colors.white10 : Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text('북마크한 단어가 없습니다.', style: TextStyle(fontSize: 17, color: subTextColor)),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              itemCount: bookmarkedWords.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final word = bookmarkedWords[index];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
                  ),
                  child: Row(
                    children: [
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
                      IconButton(
                        icon: const Icon(Icons.bookmark_rounded, color: Colors.orangeAccent, size: 26),
                        onPressed: () async {
                          word.isBookmarked = false;
                          await word.save();
                          // 개별 변경사항도 즉시 서버에 알림
                          await SupabaseService.upsertWordProgress(word);
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
