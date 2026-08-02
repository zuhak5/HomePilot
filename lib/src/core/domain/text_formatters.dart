import 'models.dart';

String pluralize(int count, String singular, [String? plural]) {
  return '$count ${count == 1 ? singular : plural ?? '${singular}s'}';
}

String recurrenceLabel(RecurrenceRule rule) {
  final unit = switch (rule.unit) {
    RecurrenceUnit.hours => rule.interval == 1 ? 'hour' : 'hours',
    RecurrenceUnit.days => rule.interval == 1 ? 'day' : 'days',
    RecurrenceUnit.weeks => rule.interval == 1 ? 'week' : 'weeks',
    RecurrenceUnit.months => rule.interval == 1 ? 'month' : 'months',
    RecurrenceUnit.years => rule.interval == 1 ? 'year' : 'years',
  };
  if (rule.interval == 1) {
    return 'Every $unit';
  }
  return 'Every ${rule.interval} $unit';
}

String sentenceCase(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return trimmed.substring(0, 1).toUpperCase() + trimmed.substring(1);
}
