import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../service/database_service.dart';
import '../view_model/level_test_view_model.dart';

class LevelTestPage extends StatelessWidget {
  final bool shouldResume;
  
  const LevelTestPage({super.key, this.shouldResume = false});

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;

    return ChangeNotifierProvider(
      create: (context) {
        final vm = LevelTestViewModel();
        if (shouldResume) {
          vm.resumeTest();
        } else {
          vm.initTest();
        }
        return vm;
      },
      child: Scaffold(
        backgroundColor: Colors.transparent, // 배경 테마 투과
        appBar: AppBar(
          title: Text('실력 진단 테스트', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
          backgroundColor: Colors.transparent,
          foregroundColor: textColor,
          elevation: 0,
          centerTitle: true,
        ),
        body: Consumer<LevelTestViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.isFinished) return _buildResultView(context, viewModel, isDarkMode);
            if (viewModel.currentWord == null) return const Center(child: CircularProgressIndicator(color: Color(0xFF5B86E5)));
            return _buildQuizView(context, viewModel, isDarkMode);
          },
        ),
      ),
    );
  }

  Widget _buildResultView(BuildContext context, LevelTestViewModel viewModel, bool isDarkMode) {
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    
    return Container(
      width: double.infinity,
      color: Colors.transparent, // 배경 테마 보장
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 30),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(32),
              boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              children: [
                const Text('🎉', style: TextStyle(fontSize: 50)),
                const SizedBox(height: 16),
                Text('진단 완료!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor)),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResultStat('정답 수', '${viewModel.totalCorrect}', Colors.green),
                    _buildResultStat('정답률', '${((viewModel.totalCorrect / 30) * 100).toInt()}%', Colors.orange),
                  ],
                ),
                const SizedBox(height: 40),
                const Divider(),
                const SizedBox(height: 30),
                Text('당신에게 딱 맞는 레벨은', style: TextStyle(fontSize: 15, color: isDarkMode ? Colors.white60 : Colors.grey[600])),
                const SizedBox(height: 8),
                Text(
                  viewModel.recommendedLevel,
                  style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: Color(0xFF5B86E5), letterSpacing: -2),
                ),
                const SizedBox(height: 8),
                Text('과정을 추천합니다!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
              ],
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B86E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
              child: const Text('나의 맞춤 레벨로 시작하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildQuizView(BuildContext context, LevelTestViewModel viewModel, bool isDarkMode) {
    final Color textColor = isDarkMode ? Colors.white : const Color(0xFF2D3142);
    final word = viewModel.currentWord!;
    final type = viewModel.currentType!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${viewModel.currentIndex + 1} / ${viewModel.totalQuestions}', style: TextStyle(color: isDarkMode ? Colors.white38 : Colors.grey[600], fontWeight: FontWeight.bold)),
                  const Text('레벨 판정 중...', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (viewModel.currentIndex + 1) / viewModel.totalQuestions,
                  minHeight: 6,
                  backgroundColor: isDarkMode ? Colors.white10 : Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5B86E5)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                // 고정된 높이의 문제 카드
                Container(
                  height: 260,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        type == LevelTestType.kanjiToMeaning ? '단어의 뜻을 고르세요' : '단어에 맞는 표현을 고르세요',
                        style: TextStyle(fontSize: 13, color: Colors.blueGrey.withOpacity(0.6), fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF5B86E5).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: Text('[ ${word.koreanPronunciation} ]', style: const TextStyle(fontSize: 16, color: Color(0xFF5B86E5), fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 15),
                      if (type == LevelTestType.kanjiToMeaning) ...[
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(word.kanji, style: TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: textColor)),
                        ),
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            word.meaning, 
                            textAlign: TextAlign.center, 
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textColor),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(viewModel.isAnswered ? word.kana : ' ', style: TextStyle(fontSize: 18, color: isDarkMode ? Colors.white38 : Colors.grey[400], letterSpacing: 1.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ...viewModel.currentOptions.map((option) => _buildOptionButton(viewModel, option, isDarkMode)),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
        if (viewModel.isAnswered)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: viewModel.nextQuestion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B86E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                  child: const Text('다음 문제', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOptionButton(LevelTestViewModel viewModel, String option, bool isDarkMode) {
    String correct;
    switch (viewModel.currentType!) {
      case LevelTestType.kanjiToMeaning: correct = viewModel.currentWord!.meaning; break;
      case LevelTestType.meaningToKanji: correct = viewModel.currentWord!.kanji; break;
      case LevelTestType.meaningToKana: correct = viewModel.currentWord!.kana; break;
    }

    bool isCorrect = option == correct;
    bool isSelected = option == viewModel.selectedAnswer;
    bool isAnswered = viewModel.isAnswered;

    Color backgroundColor = isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white;
    Color borderColor = isDarkMode ? Colors.white10 : Colors.grey[200]!;
    Color textColor = isDarkMode ? Colors.white : Colors.black87;

    if (isAnswered) {
      if (isCorrect) {
        backgroundColor = isDarkMode ? Colors.green.withOpacity(0.2) : Colors.green[50]!;
        borderColor = Colors.green;
        textColor = isDarkMode ? Colors.greenAccent : Colors.green[700]!;
      } else if (isSelected) {
        backgroundColor = isDarkMode ? Colors.red.withOpacity(0.2) : Colors.red[50]!;
        borderColor = Colors.red;
        textColor = isDarkMode ? Colors.redAccent : Colors.red[700]!;
      } else {
        textColor = isDarkMode ? Colors.white24 : Colors.grey[400]!;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 60,
        child: OutlinedButton(
          onPressed: isAnswered ? null : () => viewModel.submitAnswer(option),
          style: OutlinedButton.styleFrom(
            backgroundColor: backgroundColor,
            side: BorderSide(color: borderColor, width: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          child: Text(option, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: textColor, fontWeight: (isAnswered && isCorrect) ? FontWeight.bold : FontWeight.w500)),
        ),
      ),
    );
  }
}
