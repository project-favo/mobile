import 'package:flutter/material.dart';

import '../notifications/notification_realtime_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Alt menüdeki Profil sekmesi için okunmamış bildirim rozeti.
class NotificationProfileNavIcon extends StatelessWidget {
  const NotificationProfileNavIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationRealtimeService.instance.unreadCount,
      builder: (context, count, _) {
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Icon(Icons.person_outline),
            if (count > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(
                    count > 9 ? '9+' : count.toString(),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySecondary.copyWith(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
