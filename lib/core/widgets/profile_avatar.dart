import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/load_profile_image_bytes.dart';

/// Ağ veya data URI profil görseli: önce [memoryBytes], sonra kimlik doğrulamalı indirme.
class ProfileAvatar extends StatefulWidget {
  final double radius;
  final String? imageUrl;
  final Uint8List? memoryBytes;
  final String fallbackInitial;

  /// Aynı [imageUrl] altında sunucu görseli değiştiğinde üst widget artırır; önbellek atlanır.
  final int imageRevision;

  const ProfileAvatar({
    super.key,
    required this.radius,
    this.imageUrl,
    this.memoryBytes,
    this.fallbackInitial = '?',
    this.imageRevision = 0,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Uint8List? _networkBytes;

  @override
  void initState() {
    super.initState();
    if (widget.imageRevision != 0) {
      evictProfileImageBytesCacheForRaw(widget.imageUrl);
    }
    _networkBytes = peekProfileImageBytes(widget.imageUrl);
    _kickLoad(bypassMemoryCache: widget.imageRevision != 0);
  }

  @override
  void didUpdateWidget(ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revisionChanged = oldWidget.imageRevision != widget.imageRevision;
    final urlChanged = oldWidget.imageUrl != widget.imageUrl;
    final memChanged = oldWidget.memoryBytes != widget.memoryBytes;
    if (!revisionChanged && !urlChanged && !memChanged) return;

    if (revisionChanged) {
      evictProfileImageBytesCacheForRaw(widget.imageUrl);
    }
    if (urlChanged) {
      evictProfileImageBytesCacheForRaw(oldWidget.imageUrl);
    }

    setState(() {
      if (widget.imageUrl == null || widget.imageUrl!.trim().isEmpty) {
        _networkBytes = null;
      } else {
        _networkBytes = revisionChanged
            ? null
            : peekProfileImageBytes(widget.imageUrl);
      }
    });
    _kickLoad(bypassMemoryCache: revisionChanged);
  }

  void _kickLoad({bool bypassMemoryCache = false}) {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) return;
    final raw = widget.imageUrl;
    if (raw == null || raw.trim().isEmpty) return;
    if (!bypassMemoryCache &&
        _networkBytes != null &&
        _networkBytes!.isNotEmpty) {
      return;
    }
    _loadBytes(bypassMemoryCache: bypassMemoryCache);
  }

  Future<void> _loadBytes({bool bypassMemoryCache = false}) async {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) return;
    final raw = widget.imageUrl;
    if (raw == null || raw.trim().isEmpty) return;

    final trimmedUrl = raw.trim();
    final revisionAtStart = widget.imageRevision;

    final bytes = await loadProfileImageBytesFromRaw(
      raw,
      bypassMemoryCache: bypassMemoryCache,
    );
    if (!mounted) return;
    if (widget.imageUrl?.trim() != trimmedUrl) return;
    if (widget.imageRevision != revisionAtStart) return;
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) return;

    setState(() => _networkBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: AppColors.surface,
        backgroundImage: MemoryImage(widget.memoryBytes!),
      );
    }

    if (_networkBytes != null && _networkBytes!.isNotEmpty) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: AppColors.surface,
        backgroundImage: MemoryImage(_networkBytes!),
      );
    }

    return _placeholderCircle(widget.radius, widget.fallbackInitial);
  }

  Widget _placeholderCircle(double radius, String fallbackInitial) {
    if (fallbackInitial.isNotEmpty && fallbackInitial != '?') {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: Text(
          _firstInitial(fallbackInitial),
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            fontSize: radius * 0.45,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.surface,
      child: Icon(Icons.person_outline_rounded,
          size: radius * 1.2, color: AppColors.primary),
    );
  }

  static String _firstInitial(String s) {
    if (s.isEmpty) return '?';
    return s[0].toUpperCase();
  }
}

/// Mesaj balonları ve app bar için; aynı yükleme mantığı.
class ProfileAvatarImage extends StatefulWidget {
  final double size;
  final String? imageUrl;
  final Uint8List? memoryBytes;
  final String fallbackInitial;
  final int imageRevision;

  const ProfileAvatarImage({
    super.key,
    required this.size,
    this.imageUrl,
    this.memoryBytes,
    this.fallbackInitial = '?',
    this.imageRevision = 0,
  });

  @override
  State<ProfileAvatarImage> createState() => _ProfileAvatarImageState();
}

class _ProfileAvatarImageState extends State<ProfileAvatarImage> {
  Uint8List? _networkBytes;

  @override
  void initState() {
    super.initState();
    if (widget.imageRevision != 0) {
      evictProfileImageBytesCacheForRaw(widget.imageUrl);
    }
    _networkBytes = peekProfileImageBytes(widget.imageUrl);
    _kickLoad(bypassMemoryCache: widget.imageRevision != 0);
  }

  @override
  void didUpdateWidget(ProfileAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revisionChanged = oldWidget.imageRevision != widget.imageRevision;
    final urlChanged = oldWidget.imageUrl != widget.imageUrl;
    final memChanged = oldWidget.memoryBytes != widget.memoryBytes;
    if (!revisionChanged && !urlChanged && !memChanged) return;

    if (revisionChanged) {
      evictProfileImageBytesCacheForRaw(widget.imageUrl);
    }
    if (urlChanged) {
      evictProfileImageBytesCacheForRaw(oldWidget.imageUrl);
    }

    setState(() {
      if (widget.imageUrl == null || widget.imageUrl!.trim().isEmpty) {
        _networkBytes = null;
      } else {
        _networkBytes = revisionChanged
            ? null
            : peekProfileImageBytes(widget.imageUrl);
      }
    });
    _kickLoad(bypassMemoryCache: revisionChanged);
  }

  void _kickLoad({bool bypassMemoryCache = false}) {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) {
      return;
    }
    final raw = widget.imageUrl;
    if (raw == null || raw.trim().isEmpty) return;
    if (!bypassMemoryCache &&
        _networkBytes != null &&
        _networkBytes!.isNotEmpty) {
      return;
    }
    _loadBytes(bypassMemoryCache: bypassMemoryCache);
  }

  Future<void> _loadBytes({bool bypassMemoryCache = false}) async {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) return;
    final raw = widget.imageUrl;
    if (raw == null || raw.trim().isEmpty) return;

    final trimmedUrl = raw.trim();
    final revisionAtStart = widget.imageRevision;

    final bytes = await loadProfileImageBytesFromRaw(
      raw,
      bypassMemoryCache: bypassMemoryCache,
    );
    if (!mounted) return;
    if (widget.imageUrl?.trim() != trimmedUrl) return;
    if (widget.imageRevision != revisionAtStart) return;
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) return;

    setState(() => _networkBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.size / 2;

    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          widget.memoryBytes!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
        ),
      );
    }

    if (_networkBytes != null && _networkBytes!.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          _networkBytes!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
        ),
      );
    }

    return _initials(widget.size, radius);
  }

  Widget _initials(double size, double radius) {
    final letter = _ProfileAvatarState._firstInitial(
      widget.fallbackInitial.isEmpty ? '?' : widget.fallbackInitial,
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
      child: Text(
        letter,
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.35,
        ),
      ),
    );
  }
}
