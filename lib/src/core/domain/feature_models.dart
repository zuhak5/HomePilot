import 'models.dart';

enum RecommendationSource { localRule, weather, adaptive }

enum TimelineEventType {
  taskCompleted,
  taskSkipped,
  snoozed,
  issue,
  service,
  attachment,
  warranty,
}

enum HealthState { excellent, good, attention, critical, insufficientData }

class Recommendation {
  const Recommendation({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.source,
    required this.confidence,
    required this.createdAt,
    this.relatedEntityId,
    this.suggestedActions = const [],
    this.dismissedAt,
    this.appliedAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final RecommendationSource source;
  final double confidence;
  final String? relatedEntityId;
  final List<String> suggestedActions;
  final DateTime createdAt;
  final DateTime? dismissedAt;
  final DateTime? appliedAt;
}

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.occurredAt,
    this.body,
    this.assetId,
    this.taskId,
    this.attachmentPath,
  });

  final String id;
  final TimelineEventType type;
  final String title;
  final String? body;
  final String? assetId;
  final String? taskId;
  final String? attachmentPath;
  final DateTime occurredAt;
}

class AttachmentSummary {
  const AttachmentSummary({
    required this.id,
    required this.assetId,
    required this.type,
    required this.label,
    required this.relativePath,
    required this.createdAt,
  });

  final String id;
  final String assetId;
  final String type;
  final String label;
  final String relativePath;
  final DateTime createdAt;
}

class EntityHealthScore {
  const EntityHealthScore({
    required this.score,
    required this.state,
    required this.reasons,
    this.nextBestAction,
  });

  final int score;
  final HealthState state;
  final List<String> reasons;
  final String? nextBestAction;
}

enum HomeSetupStep { room, maintainedItem, scheduledTask }

class HomeSetupProgress {
  const HomeSetupProgress({
    required this.completedSteps,
    required this.nextStep,
  });

  static const totalSteps = 3;

  final int completedSteps;
  final HomeSetupStep? nextStep;

  bool get isEligible => completedSteps == totalSteps;
}

class HomeReadiness {
  const HomeReadiness({
    required this.score,
    required this.state,
    required this.reasons,
    required this.nextBestAction,
  });

  final int score;
  final HealthState state;
  final List<String> reasons;
  final String nextBestAction;
}

class WarrantyAlert {
  const WarrantyAlert({
    required this.asset,
    required this.expiresAt,
    required this.daysRemaining,
  });

  final Asset asset;
  final DateTime expiresAt;
  final int daysRemaining;
}
