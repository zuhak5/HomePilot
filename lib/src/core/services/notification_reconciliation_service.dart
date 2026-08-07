import 'dart:async';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../domain/contracts.dart';

class NotificationReconciliationService {
  NotificationReconciliationService({
    required this.db,
    required this.scheduler,
  });

  final AppDatabase db;
  final NotificationScheduler scheduler;

  Future<void> drainRequests() async {
    final now = DateTime.now();
    final requests =
        await (db.select(db.notificationReconciliationRequests)
              ..where(
                (row) =>
                    row.nextAttemptAt.isNull() |
                    row.nextAttemptAt.isSmallerOrEqualValue(now),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();

    for (final request in requests) {
      try {
        if (request.planId != null) {
          await scheduler.cancelPlanReminders(request.planId!);
        }
        await scheduler.refreshSchedules();
        // Succeeded: remove request
        await (db.delete(
          db.notificationReconciliationRequests,
        )..where((row) => row.scopeKey.equals(request.scopeKey))).go();
      } catch (e) {
        // Failed: record attempts & backoff
        final attempts = request.attempts + 1;
        final backoffSeconds = (attempts * attempts * 5).clamp(5, 300);
        final nextAttempt = now.add(Duration(seconds: backoffSeconds));
        await (db.update(
          db.notificationReconciliationRequests,
        )..where((row) => row.scopeKey.equals(request.scopeKey))).write(
          NotificationReconciliationRequestsCompanion(
            attempts: Value(attempts),
            nextAttemptAt: Value(nextAttempt),
            lastErrorCode: const Value('scheduler_failure'),
            lastErrorMessage: Value(
              e.toString().substring(0, e.toString().length.clamp(0, 200)),
            ),
            updatedAt: Value(now),
          ),
        );
      }
    }
  }
}
