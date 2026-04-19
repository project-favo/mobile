import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/resolve_media_url.dart';

/// Liste / kartlarda sabit kare; görsel [BoxFit.contain] ile ortalanır (aşırı kırpma yok).
class UniformProductThumbnail extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final BorderRadius borderRadius;

  const UniformProductThumbnail({
    super.key,
    required this.imageUrl,
    required this.size,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    final resolved = resolveMediaUrl(imageUrl);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (size * dpr).round().clamp(48, 1600);

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: AppColors.background,
          child:
              resolved != null && resolved.isNotEmpty
                  ? Image.network(
                    resolved,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    width: size,
                    height: size,
                    cacheWidth: px,
                    cacheHeight: px,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                  : _placeholder(),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return ColoredBox(
      color: AppColors.border.withValues(alpha: 0.25),
      child: Icon(
        Icons.photo_outlined,
        color: AppColors.textSecondary.withValues(alpha: 0.7),
        size: size * 0.32,
      ),
    );
  }
}
