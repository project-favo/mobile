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

  const ProfileAvatar({
    super.key,
    required this.radius,
    this.imageUrl,
    this.memoryBytes,
    this.fallbackInitial = '?',
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Uint8List? _networkBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _networkBytes = peekProfileImageBytes(widget.imageUrl);
    _kickLoad();
  }

  @override
  void didUpdateWidget(ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.memoryBytes != widget.memoryBytes) {
      // setState ile hemen yeniden çiz — yoksa eski avatar bir frame kalır
      setState(() {
        _networkBytes = peekProfileImageBytes(widget.imageUrl);
      });
      _kickLoad();
    }
  }

  void _kickLoad() {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) return;
    if (_networkBytes != null && _networkBytes!.isNotEmpty) return;
    final raw = widget.imageUrl;
    if (raw == null || raw.trim().isEmpty) return;
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) return;
    final raw = widget.imageUrl;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _loading = true);
    final bytes = await loadProfileImageBytesFromRaw(raw);
    if (!mounted) return;
    setState(() {
      _networkBytes = bytes;
      _loading = false;
    });
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

    // Show placeholder immediately while network bytes load,
    // instead of shimmer delay that feels like UI lag.
    return Opacity(
      opacity: _loading ? 0.72 : 1.0,
      child: _placeholderCircle(widget.radius, widget.fallbackInitial),
    );
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

  const ProfileAvatarImage({
    super.key,
    required this.size,
    this.imageUrl,
    this.memoryBytes,
    this.fallbackInitial = '?',
  });

  @override
  State<ProfileAvatarImage> createState() => _ProfileAvatarImageState();
}

class _ProfileAvatarImageState extends State<ProfileAvatarImage> {
  Uint8List? _networkBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _networkBytes = peekProfileImageBytes(widget.imageUrl);
    _kickLoad();
  }

  @override
  void didUpdateWidget(ProfileAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.memoryBytes != widget.memoryBytes) {
      setState(() {
        _networkBytes = peekProfileImageBytes(widget.imageUrl);
      });
      _kickLoad();
    }
  }

  void _kickLoad() {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) {
      return;
    }
    if (_networkBytes != null && _networkBytes!.isNotEmpty) return;
    final raw = widget.imageUrl;
    if (raw == null || raw.trim().isEmpty) return;
    _loadBytes();
  }

  Future<void> _loadBytes() async {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) return;
    final raw = widget.imageUrl;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _loading = true);
    final bytes = await loadProfileImageBytesFromRaw(raw);
    if (!mounted) return;
    setState(() {
      _networkBytes = bytes;
      _loading = false;
    });
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

    return Opacity(
      opacity: _loading ? 0.72 : 1.0,
      child: _initials(widget.size, radius),
    );
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
