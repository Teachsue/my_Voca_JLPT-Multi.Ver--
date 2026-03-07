import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../service/database_service.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  bool _isDayCompleted(DateTime day) {
    final box = Hive.box(DatabaseService.sessionBoxName);
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    return box.get('todays_words_completed_$dateStr', defaultValue: false);
  }

  // 연속 학습 일수 계산
  int _calculateStreak() {
    int streak = 0;
    DateTime checkDay = DateTime.now();
    
    while (_isDayCompleted(checkDay)) {
      streak++;
      checkDay = checkDay.subtract(const Duration(days: 1));
    }
    
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final int currentStreak = _calculateStreak();
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color subTextColor = isDarkMode ? Colors.white70 : Colors.black54;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('학습 캘린더', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: isDarkMode ? [] : [
                    BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 8)),
                  ],
                ),
                child: TableCalendar(
                  firstDay: DateTime.utc(2024, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: _calendarFormat,
                  locale: 'ko_KR',
                  daysOfWeekHeight: 40,
                  rowHeight: 52,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                  // 요일별 색상 설정 (일요일: 빨강, 토요일: 파랑)
                  calendarStyle: CalendarStyle(
                    weekendTextStyle: const TextStyle(color: Colors.redAccent),
                    holidayTextStyle: const TextStyle(color: Colors.redAccent),
                    todayDecoration: BoxDecoration(
                      color: const Color(0xFF5B86E5).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: const TextStyle(color: Color(0xFF5B86E5), fontWeight: FontWeight.bold),
                    selectedDecoration: const BoxDecoration(
                      color: Color(0xFF5B86E5),
                      shape: BoxShape.circle,
                    ),
                    defaultTextStyle: TextStyle(color: textColor),
                    outsideTextStyle: TextStyle(color: subTextColor.withOpacity(0.5)),
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                    leftChevronIcon: Icon(Icons.chevron_left_rounded, color: subTextColor),
                    rightChevronIcon: Icon(Icons.chevron_right_rounded, color: subTextColor),
                  ),
                  calendarBuilders: CalendarBuilders(
                    // 토요일 색상 처리를 위한 빌더
                    dowBuilder: (context, day) {
                      if (day.weekday == DateTime.saturday) {
                        return const Center(child: Text('토', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)));
                      }
                      if (day.weekday == DateTime.sunday) {
                        return const Center(child: Text('일', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)));
                      }
                      // 일반 요일 텍스트 색상
                      return Center(child: Text(
                        ['월', '화', '수', '목', '금'][day.weekday - 1],
                        style: TextStyle(color: subTextColor, fontWeight: FontWeight.bold),
                      ));
                    },
                    // 토요일 숫자 색상
                    defaultBuilder: (context, day, focusedDay) {
                      if (day.weekday == DateTime.saturday) {
                        return Center(child: Text('${day.day}', style: const TextStyle(color: Colors.blueAccent)));
                      }
                      return null;
                    },
                    // 도장(Stamp) 디자인 개선
                    markerBuilder: (context, date, events) {
                      if (_isDayCompleted(date)) {
                        return Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                            child: const Icon(Icons.check, color: Colors.white, size: 10),
                          ),
                        );
                      }
                      return null;
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (currentStreak > 0) ...[
              _buildStreakCard(currentStreak),
              const SizedBox(height: 24),
            ],
            _buildStatusHeader(textColor),
            const SizedBox(height: 12),
            _buildCompletionStatus(cardColor, textColor, subTextColor, isDarkMode),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text('학습 상세 정보', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textColor)),
        ],
      ),
    );
  }

  Widget _buildStreakCard(int streak) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.orange.shade400, Colors.orange.shade700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Text(
              '$streak일 연속으로 공부했어요! 🔥',
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionStatus(Color cardColor, Color textColor, Color subTextColor, bool isDarkMode) {
    bool isCompleted = _isDayCompleted(_selectedDay ?? _focusedDay);
    final dateStr = DateFormat('yyyy년 M월 d일').format(_selectedDay ?? _focusedDay);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDarkMode ? [] : [
            BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (isCompleted ? Colors.orange : Colors.grey).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isCompleted ? Icons.workspace_premium_rounded : Icons.calendar_today_rounded,
                color: isCompleted ? Colors.orange : (isDarkMode ? Colors.white38 : Colors.grey),
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateStr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        isCompleted ? '오늘의 단어 학습 완료' : '학습 기록이 없습니다',
                        style: TextStyle(
                          fontSize: 14,
                          color: isCompleted ? (isDarkMode ? Colors.orangeAccent : Colors.orange.shade800) : subTextColor,
                          fontWeight: isCompleted ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (isCompleted) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.check_circle_rounded, color: Colors.orange, size: 16),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
