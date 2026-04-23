import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/auth/data/models/user_response_dto.dart';
import '../../features/auth/presentation/profile/pages/user_profile_page.dart';
import 'content_availability_messages.dart';
import 'content_unavailable_dialog.dart';

/// Aynı metin [UserProfilePage] dışa atarken kullanılan [showContentUnavailableDialog] ile; tema uyumlu.
void showUserProfileUnavailableDialog(BuildContext? context) {
  if (context == null || !context.mounted) return;
  unawaited(
    showContentUnavailableDialog(
      context,
      title: kTitleUserUnavailable,
      message: kMessageUserProfileNoLongerAvailable,
      onContinue: () async {},
    ),
  );
}

/// Profil sayfası hemen açılır; deaktif / askı tespiti [UserProfilePage] içinde, ek bekleme yok.
void openUserProfileIfActive(
  BuildContext context, {
  required String userId,
  required String userName,
  String? profileImageUrl,
}) {
  final id = userId.trim();
  if (id.isEmpty) return;
  if (!context.mounted) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => UserProfilePage(
        userId: id,
        userName: userName,
        profileImageUrl: profileImageUrl,
      ),
    ),
  );
}

/// [u] yukarıda belli; engelli değilse aynı anda profil açılır. Profil resmi hedefte yüklenir.
void openUserProfileIfDtoAllows(
  BuildContext context, {
  required UserResponseDto? u,
  required String userId,
  required String userName,
  String? profileImageUrl,
}) {
  if (u != null && u.isProfileViewBlocked) {
    showUserProfileUnavailableDialog(context);
    return;
  }
  if (!context.mounted) return;
  final id = userId.trim();
  if (id.isEmpty) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => UserProfilePage(
        userId: id,
        userName: userName,
        profileImageUrl: profileImageUrl,
        prefillUser: u,
        prefillProfileImage: null,
      ),
    ),
  );
}
