import 'style.dart';
import 'table_view.dart';

/// Declarative formatting for one dataset column, evaluated natively for
/// visible cells only. A non-numeric value in a column with [decimals]
/// renders the raw string unchanged; rules still evaluate against it.
final class UiColumnFormat {
  const UiColumnFormat({this.decimals, this.rules = const []});

  /// Fixed-point rendering with 0–6 decimals, no grouping.
  final int? decimals;

  /// First matching rule wins. At most 16.
  final List<UiFormatRule> rules;

  Map<String, Object> toJson() {
    final decimals = this.decimals;
    if (decimals != null) {
      RangeError.checkValueInInterval(decimals, 0, 6, 'decimals');
    }
    if (rules.length > 16) {
      throw ArgumentError.value(rules.length, 'rules', 'at most 16 rules');
    }
    return {
      if (decimals != null) 'number': {'decimals': decimals},
      if (rules.isNotEmpty)
        'rules': rules.map((rule) => rule.toJson()).toList(),
    };
  }
}

final class UiFormatRule {
  const UiFormatRule({required this.when, this.color, this.icon});

  final UiFormatCondition when;
  final UiColor? color;
  final UiCellIcon? icon;

  Map<String, Object> toJson() => {
    'when': when.toJson(),
    if (color != null) 'color': color!.toJson(),
    if (icon != null) 'icon': icon!.wire,
  };
}

/// Same comparison set as view filters: numeric when both sides parse as
/// finite doubles, lexical otherwise.
final class UiFormatCondition {
  const UiFormatCondition(this.op, this.value);

  final UiFilterOp op;
  final String value;

  Map<String, Object> toJson() => {'op': op.name, 'value': value};
}

enum UiCellIcon {
  arrowUp('arrow_up'),
  arrowDown('arrow_down'),
  dot('dot'),
  warning('warning');

  const UiCellIcon(this.wire);
  final String wire;
}
