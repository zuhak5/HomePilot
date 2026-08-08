import 'dart:async';
import 'package:flutter/material.dart';

enum HkFeedbackTone { neutral, info, success, warning, error, destructive }

enum HkFeedbackMode { passive, actionable, undoable, progress }

enum HkFeedbackDismissReason {
  timeout,
  userAction,
  userDismiss,
  superceded,
  routeChange,
}

@immutable
class HkFeedbackItem {
  const HkFeedbackItem({
    required this.id,
    required this.message,
    this.tone = HkFeedbackTone.neutral,
    this.mode = HkFeedbackMode.passive,
    this.actionLabel,
    this.onAction,
    this.onUndo,
    this.onFinalize,
    this.onUndoFailure,
    this.onDismiss,
    this.duration = const Duration(seconds: 4),
    this.batchCount = 1,
    this.batchGroup,
    this.batchItemType,
    this.dedupeKey,
    this.bottomOffset,
    this.reserveFloatingActionButton = false,
  });

  final String id;
  final Widget message;
  final HkFeedbackTone tone;
  final HkFeedbackMode mode;
  final String? actionLabel;
  final FutureOr<void> Function()? onAction;
  final FutureOr<void> Function()? onUndo;
  final FutureOr<void> Function()? onFinalize;
  final FutureOr<void> Function(Object error)? onUndoFailure;
  final void Function(HkFeedbackDismissReason)? onDismiss;
  final Duration duration;
  final int batchCount;

  /// Operations may batch only when this stable semantic group matches.
  /// Entity type is retained separately so mixed Trash batches remain possible
  /// without treating arbitrary actionable messages as compatible.
  final String? batchGroup;
  final String? batchItemType;
  final String? dedupeKey;
  final double? bottomOffset;
  final bool reserveFloatingActionButton;

  bool get protectsActionOpportunity => mode == HkFeedbackMode.undoable;

  HkFeedbackItem copyWith({
    String? id,
    Widget? message,
    HkFeedbackTone? tone,
    HkFeedbackMode? mode,
    String? actionLabel,
    FutureOr<void> Function()? onAction,
    FutureOr<void> Function()? onUndo,
    FutureOr<void> Function()? onFinalize,
    FutureOr<void> Function(Object error)? onUndoFailure,
    void Function(HkFeedbackDismissReason)? onDismiss,
    Duration? duration,
    int? batchCount,
    String? batchGroup,
    String? batchItemType,
    String? dedupeKey,
    double? bottomOffset,
    bool? reserveFloatingActionButton,
  }) {
    return HkFeedbackItem(
      id: id ?? this.id,
      message: message ?? this.message,
      tone: tone ?? this.tone,
      mode: mode ?? this.mode,
      actionLabel: actionLabel ?? this.actionLabel,
      onAction: onAction ?? this.onAction,
      onUndo: onUndo ?? this.onUndo,
      onFinalize: onFinalize ?? this.onFinalize,
      onUndoFailure: onUndoFailure ?? this.onUndoFailure,
      onDismiss: onDismiss ?? this.onDismiss,
      duration: duration ?? this.duration,
      batchCount: batchCount ?? this.batchCount,
      batchGroup: batchGroup ?? this.batchGroup,
      batchItemType: batchItemType ?? this.batchItemType,
      dedupeKey: dedupeKey ?? this.dedupeKey,
      bottomOffset: bottomOffset ?? this.bottomOffset,
      reserveFloatingActionButton:
          reserveFloatingActionButton ?? this.reserveFloatingActionButton,
    );
  }
}
