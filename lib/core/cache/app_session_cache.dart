import 'current_user_cache.dart';
import 'follow_notification_horizon_prefs.dart';
import 'product_review_notification_horizon_prefs.dart';
import 'activity_memory_cache.dart';
import 'following_id_set_cache.dart';
import 'friend_feed_memory_cache.dart';
import 'home_feed_cache.dart';
import 'home_top_picks_cache.dart';
import 'message_list_cache.dart';
import 'product_memory_cache.dart';
import 'profile_warm_cache.dart';
import 'review_memory_cache.dart';
import 'search_warm_cache.dart';
import 'chat_outgoing_user_cache.dart';
import 'conversation_list_cache.dart';
import '../utils/user_display_name_prefs.dart';
import '../utils/review_report_storage.dart';
import '../notifications/app_badge_sync.dart';

/// [AuthService.signOut] ve Firebase-only çıkışlarda: hesap değişiminde kalan tüm in-memory
/// ve (ilgili) disk önbelleklerini temizle.
void clearAllAppCachesOnLogout() {
  final uid = CurrentUserCache.instance.userId?.trim();
  CurrentUserCache.instance.clear();
  if (uid != null && uid.isNotEmpty) {
    // ignore: discarded_futures
    FollowNotificationHorizonPrefs.instance.removeAllForViewer(uid);
    // ignore: discarded_futures
    ProductReviewNotificationHorizonPrefs.instance.removeAllForViewer(uid);
  }
  SearchWarmCache.instance.clear();
  HomeFeedCache.instance.clear();
  HomeTopPicksCache.clear();
  ProductMemoryCache.instance.clear();
  ReviewMemoryCache.instance.clear();
  ProfileWarmCache.instance.clear();
  ActivityMemoryCache.instance.clear();
  FriendFeedMemoryCache.instance.clear();
  ConversationListCache.instance.clear();
  MessageListCache.instance.clear();
  FollowingIdSetCache.instance.invalidate();
  ReviewReportStorage.clearMemory();
  ChatOutgoingUserCache.clear();
  // ignore: discarded_futures
  UserDisplayNamePrefs.instance.removeAllCaseDisplayKeys();
  // Logout: OS / launcher simge badge'ini 0'la; okunmamış toplamı sunucu push ile güncellenecek.
  // ignore: discarded_futures
  clearAppLauncherBadge();
}
