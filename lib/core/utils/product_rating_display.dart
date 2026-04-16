/// Ürün kartı / detayda anlamlı puan var mı (0.0 ve boş yıldız göstermemek için).
bool productHasMeaningfulRating(double? averageRating) {
  final r = averageRating ?? 0.0;
  if (r.isNaN || r.isInfinite) return false;
  return r > 0.001;
}
