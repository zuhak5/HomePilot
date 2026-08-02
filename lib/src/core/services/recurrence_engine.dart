import '../domain/contracts.dart';
import '../domain/models.dart';

class HomePilotRecurrenceEngine implements RecurrenceEngine {
  const HomePilotRecurrenceEngine();

  @override
  DateTime nextDueDate(DateTime completionDate, RecurrenceRule rule) {
    if (rule.interval < 1) {
      throw ArgumentError.value(
        rule.interval,
        'interval',
        'Must be greater than zero.',
      );
    }
    return switch (rule.unit) {
      RecurrenceUnit.hours => completionDate.add(
        Duration(hours: rule.interval),
      ),
      RecurrenceUnit.days => DateTime(
        completionDate.year,
        completionDate.month,
        completionDate.day + rule.interval,
        completionDate.hour,
        completionDate.minute,
        completionDate.second,
        completionDate.millisecond,
        completionDate.microsecond,
      ),
      RecurrenceUnit.weeks => DateTime(
        completionDate.year,
        completionDate.month,
        completionDate.day + (rule.interval * 7),
        completionDate.hour,
        completionDate.minute,
        completionDate.second,
        completionDate.millisecond,
        completionDate.microsecond,
      ),
      RecurrenceUnit.months => _addMonthsClamped(completionDate, rule.interval),
      RecurrenceUnit.years => _addMonthsClamped(
        completionDate,
        rule.interval * 12,
      ),
    };
  }

  DateTime _addMonthsClamped(DateTime value, int months) {
    final totalMonths = (value.year * 12) + (value.month - 1) + months;
    final year = totalMonths ~/ 12;
    final month = (totalMonths % 12) + 1;
    final lastDayOfTargetMonth = DateTime(year, month + 1, 0).day;
    final day = value.day > lastDayOfTargetMonth
        ? lastDayOfTargetMonth
        : value.day;
    return DateTime(
      year,
      month,
      day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }
}
