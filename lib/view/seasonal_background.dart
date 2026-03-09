import 'package:flutter/material.dart';

class SeasonalBackground extends StatelessWidget {
  final Widget child;
  final bool isDarkMode;
  final String appTheme;

  const SeasonalBackground({
    super.key, 
    required this.child, 
    required this.isDarkMode, 
    required this.appTheme
  });

  Map<String, dynamic> _getSeasonalTheme() {
    int month = DateTime.now().month;
    String target = appTheme;
    if (target == 'auto') {
      if (month >= 3 && month <= 5) {
        target = 'spring';
      } else if (month >= 6 && month <= 8) {
        target = 'summer';
      } else if (month >= 9 && month <= 11) {
        target = 'autumn';
      } else {
        target = 'winter';
      }
    }

    if (isDarkMode) {
      switch (target) {
        case 'spring':
          return {
            'colors': [const Color(0xFF2D1B22), const Color(0xFF1A1C2C)],
            'icon': Icons.local_florist_rounded,
            'iconColor': Colors.pink.withOpacity(0.05),
          };
        case 'summer':
          return {
            'colors': [const Color(0xFF1B2D2D), const Color(0xFF1A1C2C)],
            'icon': Icons.wb_sunny_rounded,
            'iconColor': Colors.blue.withOpacity(0.05),
          };
        case 'autumn':
          return {
            'colors': [const Color(0xFF2D241B), const Color(0xFF1A1C2C)],
            'icon': Icons.eco_rounded,
            'iconColor': Colors.orange.withOpacity(0.05),
          };
        case 'winter':
        default:
          return {
            'colors': [const Color(0xFF1B222D), const Color(0xFF1A1C2C)],
            'icon': Icons.ac_unit_rounded,
            'iconColor': Colors.blueGrey.withOpacity(0.05),
          };
      }
    }

    switch (target) {
      case 'spring':
        return {
          'colors': [const Color(0xFFFFF0F5), const Color(0xFFFFFFFF)],
          'icon': Icons.local_florist_rounded,
          'iconColor': Colors.pink.withOpacity(0.08),
        };
      case 'summer':
        return {
          'colors': [const Color(0xFFE0F7FA), const Color(0xFFFFFFFF)],
          'icon': Icons.wb_sunny_rounded,
          'iconColor': Colors.blue.withOpacity(0.08),
        };
      case 'autumn':
        return {
          'colors': [const Color(0xFFFFF3E0), const Color(0xFFFFFFFF)],
          'icon': Icons.eco_rounded,
          'iconColor': Colors.orange.withOpacity(0.08),
        };
      case 'winter':
      default:
        return {
          'colors': [const Color(0xFFF1F4F8), const Color(0xFFFFFFFF)],
          'icon': Icons.ac_unit_rounded,
          'iconColor': Colors.blueGrey.withOpacity(0.08),
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _getSeasonalTheme();
    
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: theme['colors'],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      // [수정] clipBehavior를 antiAlias로 설정하여 화면 밖 아이콘이 노란색 오버플로우 선을 유발하지 않도록 함
      child: Stack(
        clipBehavior: Clip.antiAlias, 
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Icon(theme['icon'], size: 250, color: theme['iconColor']),
          ),
          child,
        ],
      ),
    );
  }
}
