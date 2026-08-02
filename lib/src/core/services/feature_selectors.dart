import '../domain/contracts.dart';
import '../domain/feature_models.dart';
import '../domain/models.dart';
import '../domain/task_selectors.dart';
import '../utils/date_utils.dart' as hk_dates;

EntityHealthScore itemHealthScore({
  required Asset asset,
  required List<TaskItem> tasks,
  required DateTime now,
}) {
  final assetTasks = tasks
      .where((task) => task.asset.id == asset.id)
      .where(isTaskActionable)
      .toList();
  if (assetTasks.isEmpty) {
    return const EntityHealthScore(
      score: 0,
      state: HealthState.insufficientData,
      reasons: ['No maintenance plan yet.'],
      nextBestAction: 'Add a maintenance task.',
    );
  }
  final buckets = getTaskBuckets(assetTasks, now);
  var score = 100;
  final reasons = <String>[];
  if (buckets.overdueCount > 0) {
    score -= (buckets.overdueCount * 22).clamp(0, 60).toInt();
    reasons.add('${buckets.overdueCount} overdue task(s).');
  }
  final criticalOpen = assetTasks.where(
    (task) =>
        task.plan.priority == PriorityLevel.critical &&
        getTaskBucketStatus(task, now) != TaskBucketStatus.later,
  );
  if (criticalOpen.isNotEmpty) {
    score -= 20;
    reasons.add(
      buckets.today.any((task) => task.plan.priority == PriorityLevel.critical)
          ? 'Critical task due today.'
          : 'Critical care is due soon.',
    );
  }
  final warranty = asset.deviceDetails?.warrantyUntil;
  if (warranty != null) {
    final remaining = hk_dates.daysBetweenDates(now, warranty);
    if (remaining < 0) {
      score -= 8;
      reasons.add('Warranty has expired.');
    } else if (remaining <= 30) {
      score -= 4;
      reasons.add('Warranty expires within 30 days.');
    }
  }
  final clamped = score.clamp(0, 100).toInt();
  final state = criticalOpen.isNotEmpty && clamped >= 75
      ? HealthState.attention
      : _healthState(clamped);
  return EntityHealthScore(
    score: clamped,
    state: state,
    reasons: reasons.isEmpty ? ['Maintenance is on track.'] : reasons,
    nextBestAction: buckets.active.isEmpty
        ? 'Review upcoming maintenance.'
        : buckets.active.first.plan.title,
  );
}

EntityHealthScore roomHealthScore({
  required Room room,
  required List<Asset> assets,
  required List<TaskItem> tasks,
  required DateTime now,
}) {
  final roomAssets = assets.where((asset) => asset.roomId == room.id).toList();
  if (roomAssets.isEmpty) {
    return const EntityHealthScore(
      score: 0,
      state: HealthState.insufficientData,
      reasons: ['No items in this room yet.'],
      nextBestAction: 'Add the first item.',
    );
  }
  final scores = [
    for (final asset in roomAssets)
      itemHealthScore(asset: asset, tasks: tasks, now: now).score,
  ];
  final average = (scores.reduce((a, b) => a + b) / scores.length).round();
  final buckets = getTaskBuckets(
    tasks.where((task) => task.room.id == room.id).where(isTaskActionable),
    now,
  );
  return EntityHealthScore(
    score: average,
    state: _healthState(average),
    reasons: [
      '${roomAssets.length} item(s).',
      if (buckets.overdueCount > 0) '${buckets.overdueCount} overdue task(s).',
      if (buckets.todayCount > 0) '${buckets.todayCount} due today.',
      if (buckets.overdueCount == 0 && buckets.todayCount == 0)
        'Room is on track.',
    ],
    nextBestAction: buckets.active.isEmpty
        ? 'Add maintenance tasks for this room.'
        : buckets.active.first.plan.title,
  );
}

HomeReadiness homeReadiness({
  required List<Room> rooms,
  required List<Asset> assets,
  required List<TaskItem> tasks,
  required BackupState backupState,
  required DateTime now,
}) {
  final buckets = getTaskBuckets(tasks, now);
  var score = 100;
  final reasons = <String>[];
  if (rooms.isEmpty || assets.isEmpty) {
    score -= 35;
    reasons.add('Home setup is incomplete.');
  }
  if (buckets.overdueCount > 0) {
    score -= (buckets.overdueCount * 12).clamp(0, 45).toInt();
    reasons.add('${buckets.overdueCount} overdue task(s).');
  }
  if (backupState.lastBackup?.successful != true) {
    score -= 10;
    reasons.add('No successful backup yet.');
  }
  final warrantyAlerts = warrantyAlertsFor(assets: assets, now: now);
  if (warrantyAlerts.isNotEmpty) {
    score -= 5;
    reasons.add('${warrantyAlerts.length} warranty alert(s).');
  }
  final clamped = score.clamp(0, 100).toInt();
  return HomeReadiness(
    score: clamped,
    state: _healthState(clamped),
    reasons: reasons.isEmpty ? ['Home maintenance is ready.'] : reasons,
    nextBestAction: buckets.overdue.isNotEmpty
        ? buckets.overdue.first.plan.title
        : buckets.today.isNotEmpty
        ? buckets.today.first.plan.title
        : buckets.tomorrow.isNotEmpty
        ? buckets.tomorrow.first.plan.title
        : 'Review upcoming tasks.',
  );
}

List<WarrantyAlert> warrantyAlertsFor({
  required List<Asset> assets,
  required DateTime now,
  int warningDays = 45,
}) {
  final alerts = <WarrantyAlert>[];
  for (final asset in assets) {
    final expiresAt = asset.deviceDetails?.warrantyUntil;
    if (expiresAt == null) {
      continue;
    }
    final remaining = hk_dates.daysBetweenDates(now, expiresAt);
    if (remaining >= 0 && remaining <= warningDays) {
      alerts.add(
        WarrantyAlert(
          asset: asset,
          expiresAt: expiresAt,
          daysRemaining: remaining,
        ),
      );
    }
  }
  alerts.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
  return alerts;
}

List<TimelineEvent> timelineForAsset({
  required Asset asset,
  required List<TaskItem> tasks,
  required List<MaintenanceRecord> records,
  required List<AssetPhoto> photos,
}) {
  final events = <TimelineEvent>[
    for (final record in records)
      TimelineEvent(
        id: record.id,
        type: TimelineEventType.taskCompleted,
        title: 'Task completed',
        body: record.notes,
        assetId: asset.id,
        taskId: record.planId,
        occurredAt: record.completedAt,
      ),
    for (final photo in photos)
      TimelineEvent(
        id: photo.id,
        type: TimelineEventType.attachment,
        title: photo.caption ?? 'Photo added',
        assetId: asset.id,
        attachmentPath: photo.relativePath,
        occurredAt: photo.createdAt,
      ),
  ];
  events.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return events;
}

List<TaskItem> smartPriorityTasks(List<TaskItem> tasks, DateTime now) {
  final ranked = tasks.where(isTaskActionable).toList();
  ranked.sort(
    (a, b) => _priorityScore(b, now).compareTo(_priorityScore(a, now)),
  );
  return ranked;
}

String smartPriorityLabel(TaskItem task) {
  final severity = switch (task.plan.priority) {
    PriorityLevel.critical => 'Critical',
    PriorityLevel.high => 'High',
    PriorityLevel.medium => 'Medium',
    PriorityLevel.low => 'Routine',
  };
  final context = switch (task.plan.healthGroup) {
    HealthGroup.safety => 'Safety',
    HealthGroup.pets => 'Pet health',
    HealthGroup.appliances => 'Appliance care',
    HealthGroup.plants => 'Plant care',
    HealthGroup.cleaning => 'Cleaning',
    HealthGroup.other => 'Home care',
  };
  return '$severity - $context';
}

int _priorityScore(TaskItem task, DateTime now) {
  final bucket = getTaskBucketStatus(task, now);
  final bucketScore = switch (bucket) {
    TaskBucketStatus.overdue => 1000,
    TaskBucketStatus.today => 700,
    TaskBucketStatus.tomorrow => 500,
    TaskBucketStatus.next7Days => 300,
    TaskBucketStatus.later => 80,
    TaskBucketStatus.completed ||
    TaskBucketStatus.skipped ||
    TaskBucketStatus.archived => 0,
  };
  final priorityScore = switch (task.plan.priority) {
    PriorityLevel.critical => 400,
    PriorityLevel.high => 250,
    PriorityLevel.medium => 100,
    PriorityLevel.low => 25,
  };
  return bucketScore + priorityScore;
}

HealthState _healthState(int score) {
  if (score >= 90) {
    return HealthState.excellent;
  }
  if (score >= 75) {
    return HealthState.good;
  }
  if (score >= 50) {
    return HealthState.attention;
  }
  return HealthState.critical;
}
