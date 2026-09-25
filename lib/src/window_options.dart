/// Initial window configuration in logical pixels, independent of display scale.
final class GpuiWindowOptions {
  const GpuiWindowOptions({
    this.title = 'GPUI-Dart',
    this.width = 860,
    this.height = 650,
  });

  final String title;
  final double width;
  final double height;

  Map<String, Object> toJson() {
    if (title.trim().isEmpty ||
        !width.isFinite ||
        !height.isFinite ||
        width < 320 ||
        width > 8192 ||
        height < 240 ||
        height > 8192) {
      throw ArgumentError(
        'Window requires a title, width 320..8192 and height 240..8192',
      );
    }
    return {'title': title, 'width': width, 'height': height};
  }
}
