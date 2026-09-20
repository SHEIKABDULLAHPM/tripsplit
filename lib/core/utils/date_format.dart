/// Date formatting helpers shared by presentation widgets.
abstract final class DateFormats {
  DateFormats._();

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Formats `2026-09-14` as `14 Sep 2026` (local time).
  static String date(DateTime date) {
    final local = date.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}';
  }
}
