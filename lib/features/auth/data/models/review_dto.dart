import '../../../../core/utils/product_listing_flags.dart';
import '../../../../core/utils/review_visibility_flags.dart';

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

  factory ReviewDto.fromJson(Map<String, dynamic> json) {
    return ReviewDto(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
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
      isReviewInactive: isReviewDataInactiveOrHiddenInMap(json),
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
    return ReviewMediaDto(
      id: json['id']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      uploadDate: json['uploadDate']?.toString() ?? '',
      url: json['url']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
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
  final List<int> imageData; // Base64 veya binary data
  final String mimeType;

  ReviewMediaRequestDto({
    required this.imageData,
    required this.mimeType,
  });

  Map<String, dynamic> toJson() {
    return {
      'imageData': imageData,
      'mimeType': mimeType,
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

