import '../../../../core/utils/product_listing_flags.dart';
import '../../../../core/utils/review_visibility_flags.dart';
import '../../../../core/utils/user_account_flags.dart';

class ReviewDto {
  final String id;
  final String title;
  final String? description;
  final bool isCollaborative;
  final int rating;
  final String createdAt;
  final String productId;
  final String productName;
  final String ownerId;
  final String ownerUserName;
  final String? ownerProfilePhotoUrl;
  final List<ReviewMediaDto> mediaList;
  final int likeCount;
  final bool isLikedByCurrentUser;

  /// true: ürün artık vitrinde yok (askı, kaldırıldı) — My Reviews gibi listelerde satır gösterilmez
  final bool isProductNotListed;

  /// true: yorum pasif, moderasyonda veya silinmiş — listeler ve detayda gösterilmez
  final bool isReviewInactive;

  ReviewDto({
    required this.id,
    required this.title,
    this.description,
    required this.isCollaborative,
    required this.rating,
    required this.createdAt,
    required this.productId,
    required this.productName,
    required this.ownerId,
    required this.ownerUserName,
    this.ownerProfilePhotoUrl,
    required this.mediaList,
    required this.likeCount,
    required this.isLikedByCurrentUser,
    this.isProductNotListed = false,
    this.isReviewInactive = false,
  });

  static String? _ownerPhotoFromJson(Map<String, dynamic> json) {
    final direct = json['ownerProfilePhotoUrl'] ??
        json['ownerProfileImageUrl'] ??
        json['ownerImageUrl'] ??
        json['ownerAvatarUrl'];
    if (direct != null && direct.toString().isNotEmpty) {
      return direct.toString();
    }
    final owner = json['owner'];
    if (owner is Map<String, dynamic>) {
      return (owner['profileImageUrl'] ??
              owner['profilePhotoUrl'] ??
              owner['avatarUrl'])
          ?.toString();
    }
    return null;
  }

  static bool _productNotListedFromJson(Map<String, dynamic> json) {
    return isProductNotListedFromJsonMap(json);
  }

  /// Backend farklı anahtarlar kullanabildiği için metin alanlarını sırayla okur.
  static String? _firstNonEmptyString(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  factory ReviewDto.fromJson(Map<String, dynamic> json) {
    var ownerInactive = false;
    final o = json['owner'];
    if (o is Map<String, dynamic>) {
      ownerInactive = isUserAccountInactiveInMap(o) || isUserSuspendedSignalInMap(o);
    }
    final title = _firstNonEmptyString(json, const [
          'title',
          'reviewTitle',
          'subject',
        ]) ??
        '';
    final description = _firstNonEmptyString(json, const [
      'description',
      'reviewText',
      'content',
      'body',
      'text',
      'comment',
    ]);
    return ReviewDto(
      id: json['id']?.toString() ?? '',
      title: title,
      description: description,
      isCollaborative: json['isCollaborative'] as bool? ?? false,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt']?.toString() ?? '',
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      ownerUserName: json['ownerUserName']?.toString() ?? '',
      ownerProfilePhotoUrl: _ownerPhotoFromJson(json),
      mediaList: (json['mediaList'] as List?)
              ?.map((item) => ReviewMediaDto.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      isLikedByCurrentUser: json['isLikedByCurrentUser'] as bool? ?? false,
      isProductNotListed: _productNotListedFromJson(json),
      isReviewInactive:
          isReviewDataInactiveOrHiddenInMap(json) || ownerInactive,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCollaborative': isCollaborative,
      'rating': rating,
      'createdAt': createdAt,
      'productId': productId,
      'productName': productName,
      'ownerId': ownerId,
      'ownerUserName': ownerUserName,
      'mediaList': mediaList.map((m) => m.toJson()).toList(),
      'likeCount': likeCount,
      'isLikedByCurrentUser': isLikedByCurrentUser,
      'isProductNotListed': isProductNotListed,
      'isReviewInactive': isReviewInactive,
    };
  }
}

class ReviewMediaDto {
  final String id;
  final String mimeType;
  final String uploadDate;
  final String? url; // Backend'den direkt URL geliyorsa
  final String? imageUrl; // Alternatif field adı

  ReviewMediaDto({
    required this.id,
    required this.mimeType,
    required this.uploadDate,
    this.url,
    this.imageUrl,
  });

  factory ReviewMediaDto.fromJson(Map<String, dynamic> json) {
    final id = ReviewDto._firstNonEmptyString(json, const [
          'id',
          'mediaId',
          'reviewMediaId',
          'fileId',
          'attachmentId',
        ]) ??
        '';
    return ReviewMediaDto(
      id: id,
      mimeType: json['mimeType']?.toString() ?? '',
      uploadDate: json['uploadDate']?.toString() ?? '',
      url: ReviewDto._firstNonEmptyString(json, const [
        'url',
        'mediaUrl',
        'src',
        'fileUrl',
      ]),
      imageUrl: ReviewDto._firstNonEmptyString(json, const [
        'imageUrl',
        'thumbnailUrl',
        'previewUrl',
      ]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mimeType': mimeType,
      'uploadDate': uploadDate,
      if (url != null) 'url': url,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }

  /// Media URL'ini döndürür - önce url/imageUrl, yoksa id'den oluşturur
  String getMediaUrl(String baseUrl) {
    if (url != null && url!.isNotEmpty) {
      return url!;
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return imageUrl!;
    }
    // Fallback: id'den URL oluştur
    return '$baseUrl/api/media/$id';
  }
}

class CreateReviewRequestDto {
  final String productId;
  final String title;
  final String? description;
  final bool isCollaborative;
  final int rating;
  final List<ReviewMediaRequestDto>? mediaList;

  CreateReviewRequestDto({
    required this.productId,
    required this.title,
    this.description,
    this.isCollaborative = false,
    required this.rating,
    this.mediaList,
  });

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'title': title,
      'description': description,
      'isCollaborative': isCollaborative,
      'rating': rating,
      if (mediaList != null) 'mediaList': mediaList!.map((m) => m.toJson()).toList(),
    };
  }
}

class ReviewMediaRequestDto {
  /// PUT ile korunacak mevcut medya (sunucu `id` bekler).
  final String? existingMediaId;
  final List<int>? imageData;
  final String? mimeType;

  const ReviewMediaRequestDto.upload({
    required List<int> this.imageData,
    required String this.mimeType,
  }) : existingMediaId = null;

  const ReviewMediaRequestDto.retain({required String this.existingMediaId})
      : imageData = null,
        mimeType = null;

  Map<String, dynamic> toJson() {
    final id = existingMediaId?.trim();
    if (id != null && id.isNotEmpty) {
      return {'id': id};
    }
    return {
      'imageData': imageData!,
      'mimeType': mimeType ?? 'image/jpeg',
    };
  }
}

class UpdateReviewRequestDto {
  final String? title;
  final String? description;
  final bool? isCollaborative;
  final int? rating;
  final List<ReviewMediaRequestDto>? mediaList;

  UpdateReviewRequestDto({
    this.title,
    this.description,
    this.isCollaborative,
    this.rating,
    this.mediaList,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (title != null) json['title'] = title;
    if (description != null) json['description'] = description;
    if (isCollaborative != null) json['isCollaborative'] = isCollaborative;
    if (rating != null) json['rating'] = rating;
    if (mediaList != null) json['mediaList'] = mediaList!.map((m) => m.toJson()).toList();
    return json;
  }
}

/// GET /api/reviews/top-reviewers — en çok review yazan kullanıcılar
class TopReviewerDto {
  final String userId;
  final String userName;
  final String? profileImageUrl;
  final int reviewCount;

  const TopReviewerDto({
    required this.userId,
    required this.userName,
    this.profileImageUrl,
    required this.reviewCount,
  });

  factory TopReviewerDto.fromJson(Map<String, dynamic> json) {
    return TopReviewerDto(
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      userName: json['userName']?.toString() ?? json['user_name']?.toString() ?? '',
      profileImageUrl: json['profileImageUrl']?.toString() ??
          json['profile_image_url']?.toString(),
      reviewCount: (json['reviewCount'] as num?)?.toInt() ??
          (json['review_count'] as num?)?.toInt() ??
          0,
    );
  }
}

/// Review şikayeti gövdesi (`/flag` ve uyumluluk için `/report`).
class ReportReviewRequestDto {
  final String reason;
  final String? notes;

  ReportReviewRequestDto({
    required this.reason,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'reason': reason,
        'notes': notes?.trim() ?? '',
      };
}

