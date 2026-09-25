/// Optional typed style attached to any snapshot node. Absence of a field
/// leaves the gpui-kit theme default in place; there is no inheritance.
final class UiStyle {
  const UiStyle({
    this.padding,
    this.gap,
    this.width,
    this.height,
    this.align,
    this.justify,
    this.background,
    this.foreground,
    this.borderColor,
    this.borderRadius,
    this.fontSize,
    this.fontWeight,
  });

  /// Logical pixels: top, right, bottom, left. Each edge 0–512.
  final List<double>? padding;

  /// Logical pixels, 0–512.
  final double? gap;
  final UiSize? width;
  final UiSize? height;
  final UiAlign? align;
  final UiJustify? justify;
  final UiColor? background;
  final UiColor? foreground;
  final UiColor? borderColor;

  /// Logical pixels, 0–512.
  final double? borderRadius;

  /// Logical pixels, 8–96. Text nodes only.
  final double? fontSize;

  /// Text nodes only.
  final UiFontWeight? fontWeight;

  Map<String, Object> toJson() {
    final padding = this.padding;
    if (padding != null && padding.length != 4) {
      throw ArgumentError.value(
        padding,
        'padding',
        'must be [top, right, bottom, left]',
      );
    }
    return {
      'padding': ?padding,
      'gap': ?gap,
      if (width != null) 'width': width!.toJson(),
      if (height != null) 'height': height!.toJson(),
      if (align != null) 'align': align!.wire,
      if (justify != null) 'justify': justify!.wire,
      if (background != null) 'background': background!.toJson(),
      if (foreground != null) 'foreground': foreground!.toJson(),
      if (borderColor != null) 'border_color': borderColor!.toJson(),
      'border_radius': ?borderRadius,
      'font_size': ?fontSize,
      if (fontWeight != null) 'font_weight': fontWeight!.wire,
    };
  }
}

/// A fixed pixel size, `"full"` (fill the parent) or `"fit"` (shrink to content).
sealed class UiSize {
  const UiSize._();

  const factory UiSize.px(double value) = UiPxSize;

  static const UiSize full = UiFullSize();
  static const UiSize fit = UiFitSize();

  Object toJson();
}

final class UiPxSize extends UiSize {
  const UiPxSize(this.value) : super._();
  final double value;
  @override
  Map<String, Object> toJson() => {'px': value};
}

final class UiFullSize extends UiSize {
  const UiFullSize() : super._();
  @override
  String toJson() => 'full';
}

final class UiFitSize extends UiSize {
  const UiFitSize() : super._();
  @override
  String toJson() => 'fit';
}

enum UiAlign {
  start('start'),
  center('center'),
  end('end'),
  stretch('stretch');

  const UiAlign(this.wire);
  final String wire;
}

enum UiJustify {
  start('start'),
  center('center'),
  end('end'),
  spaceBetween('space_between');

  const UiJustify(this.wire);
  final String wire;
}

enum UiFontWeight {
  normal('normal'),
  medium('medium'),
  semibold('semibold'),
  bold('bold');

  const UiFontWeight(this.wire);
  final String wire;
}

/// Theme roles that exist in gpui-kit's ThemeColor at the pinned revision.
enum ThemeToken {
  background('background'),
  foreground('foreground'),
  primary('primary'),
  primaryForeground('primary_foreground'),
  secondary('secondary'),
  secondaryForeground('secondary_foreground'),
  muted('muted'),
  mutedForeground('muted_foreground'),
  accent('accent'),
  accentForeground('accent_foreground'),
  danger('danger'),
  dangerForeground('danger_foreground'),
  border('border'),
  success('success'),
  warning('warning'),
  info('info');

  const ThemeToken(this.wire);
  final String wire;
}

/// A theme token reference or a raw `#RRGGBB` / `#RRGGBBAA` hex color.
sealed class UiColor {
  const UiColor._();

  const factory UiColor.token(ThemeToken token) = UiTokenColor;

  /// Validates the `#RRGGBB` / `#RRGGBBAA` format eagerly.
  factory UiColor.hex(String value) {
    if (!RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(value)) {
      throw ArgumentError.value(value, 'value', 'must be #RRGGBB or #RRGGBBAA');
    }
    return UiHexColor(value);
  }

  String toJson();
}

final class UiTokenColor extends UiColor {
  const UiTokenColor(this.token) : super._();
  final ThemeToken token;
  @override
  String toJson() => 'token:${token.wire}';
}

final class UiHexColor extends UiColor {
  const UiHexColor(this.value) : super._();
  final String value;
  @override
  String toJson() => value;
}
