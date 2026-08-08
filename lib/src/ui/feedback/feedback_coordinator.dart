import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:homepilot/src/core/services/feedback_messenger.dart';

import 'feedback_model.dart';

class FeedbackCoordinator extends ChangeNotifier {
  FeedbackCoordinator._();

  static final FeedbackCoordinator instance = FeedbackCoordinator._();

  int _currentToken = 0;
  HkFeedbackItem? _activeItem;
  HkFeedbackItem? _pendingError;
  HkFeedbackItem? _pendingWarning;
  HkFeedbackItem? _pendingPassive;
  bool _actionExecuted = false;

  HkFeedbackItem? get activeItem => _activeItem;

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? show(
    BuildContext context,
    HkFeedbackItem item,
  ) {
    final active = _activeItem;
    if (active != null && active.protectsActionOpportunity) {
      if (item.mode == HkFeedbackMode.undoable && _canBatchUndo(active, item)) {
        _mergeUndo(item);
        return _renderActive(context, replaceSameUndo: true);
      }
      _queueLatest(item);
      return null;
    }

    if (active != null &&
        item.dedupeKey != null &&
        active.dedupeKey == item.dedupeKey) {
      return null;
    }

    return _activate(context, item);
  }

  bool _canBatchUndo(HkFeedbackItem active, HkFeedbackItem incoming) =>
      active.batchGroup != null && active.batchGroup == incoming.batchGroup;

  void _mergeUndo(HkFeedbackItem incoming) {
    final active = _activeItem;
    if (active == null) return;
    final previousUndo = active.onUndo;
    final incomingUndo = incoming.onUndo;
    final previousFinalize = active.onFinalize;
    final incomingFinalize = incoming.onFinalize;
    final previousFailure = active.onUndoFailure;
    final incomingFailure = incoming.onUndoFailure;
    _activeItem = active.copyWith(
      batchCount: active.batchCount + incoming.batchCount,
      batchItemType: active.batchItemType == incoming.batchItemType
          ? active.batchItemType
          : 'mixed',
      onUndo: () async {
        // Reverse operation order is the safest default for dependent Trash
        // cascades: the newest operation is restored first.
        if (incomingUndo != null) await incomingUndo();
        if (previousUndo != null) await previousUndo();
      },
      onFinalize: () async {
        if (previousFinalize != null) await previousFinalize();
        if (incomingFinalize != null) await incomingFinalize();
      },
      onUndoFailure: (error) async {
        if (incomingFailure != null) await incomingFailure(error);
        if (previousFailure != null) await previousFailure(error);
      },
    );
    _actionExecuted = false;
    notifyListeners();
  }

  void _queueLatest(HkFeedbackItem item) {
    if (item.tone == HkFeedbackTone.error ||
        item.tone == HkFeedbackTone.destructive) {
      _pendingError = item;
    } else if (item.tone == HkFeedbackTone.warning) {
      _pendingWarning = item;
    } else {
      _pendingPassive = item;
    }
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _activate(
    BuildContext context,
    HkFeedbackItem item,
  ) {
    final previous = _activeItem;
    if (previous != null && !previous.protectsActionOpportunity) {
      previous.onDismiss?.call(HkFeedbackDismissReason.superceded);
    }
    _activeItem = item;
    _actionExecuted = false;
    notifyListeners();
    return _renderActive(context);
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _renderActive(
    BuildContext context, {
    bool replaceSameUndo = false,
  }) {
    final item = _activeItem;
    if (item == null) return null;
    final messenger =
        ScaffoldMessenger.maybeOf(context) ??
        (hkRootScaffoldMessengerKey.currentState?.mounted == true
            ? hkRootScaffoldMessengerKey.currentState
            : null);
    if (messenger == null) return null;

    // Increment before hiding so the close callback from the prior visual bar
    // cannot finalize the logical Undo batch that is being re-rendered.
    final token = ++_currentToken;
    messenger.hideCurrentSnackBar();

    final media = MediaQuery.maybeOf(context);
    final bottomObstruction = math.max(
      media?.viewPadding.bottom ?? 0,
      media?.viewInsets.bottom ?? 0,
    );
    final width = media?.size.width ?? 0;
    final trailingReserve = item.reserveFloatingActionButton && width >= 560
        ? 152.0
        : 0.0;
    final margin = EdgeInsetsDirectional.fromSTEB(
      16,
      0,
      16 + trailingReserve,
      bottomObstruction + (item.bottomOffset ?? 12),
    );

    final controller = messenger.showSnackBar(
      SnackBar(
        content: AnimatedBuilder(
          animation: this,
          builder: (context, _) {
            final current = _activeItem;
            return _FeedbackBarContent(item: current ?? item);
          },
        ),
        duration: item.duration,
        behavior: SnackBarBehavior.floating,
        margin: margin,
        action: item.actionLabel != null
            ? SnackBarAction(
                label: item.actionLabel!,
                onPressed: () => unawaited(handleAction()),
              )
            : null,
      ),
    );

    controller.closed.then((reason) {
      if (_currentToken != token || _activeItem?.id != item.id) return;
      if (reason == SnackBarClosedReason.action) return;
      unawaited(
        _finalizeActive(
          reason == SnackBarClosedReason.swipe ||
                  reason == SnackBarClosedReason.dismiss
              ? HkFeedbackDismissReason.userDismiss
              : HkFeedbackDismissReason.timeout,
        ),
      );
    });
    return controller;
  }

  Future<void> handleAction() async {
    if (_actionExecuted || _activeItem == null) return;
    _actionExecuted = true;
    final item = _activeItem!;
    _activeItem = null;
    _currentToken++;
    notifyListeners();

    try {
      if (item.onUndo != null) {
        await item.onUndo!();
      } else if (item.onAction != null) {
        await item.onAction!();
      }
    } on Object catch (error) {
      final failure = item.onUndoFailure;
      if (failure != null) await failure(error);
    } finally {
      item.onDismiss?.call(HkFeedbackDismissReason.userAction);
      _processNext();
    }
  }

  Future<void> _finalizeActive(HkFeedbackDismissReason reason) async {
    if (_actionExecuted || _activeItem == null) return;
    _actionExecuted = true;
    final item = _activeItem!;
    _activeItem = null;
    notifyListeners();
    try {
      if (item.onFinalize != null) await item.onFinalize!();
    } finally {
      item.onDismiss?.call(reason);
      _processNext();
    }
  }

  void _processNext() {
    final context = hkRootScaffoldMessengerKey.currentContext;
    if (context == null ||
        hkRootScaffoldMessengerKey.currentState?.mounted != true) {
      return;
    }
    final next = _pendingError ?? _pendingWarning ?? _pendingPassive;
    if (next == null) return;
    if (identical(next, _pendingError)) {
      _pendingError = null;
    } else if (identical(next, _pendingWarning)) {
      _pendingWarning = null;
    } else {
      _pendingPassive = null;
    }
    _activate(context, next);
  }

  void resetForTesting() {
    _currentToken++;
    _activeItem = null;
    _pendingError = null;
    _pendingWarning = null;
    _pendingPassive = null;
    _actionExecuted = false;
    try {
      hkRootScaffoldMessengerKey.currentState?.clearSnackBars();
    } catch (_) {}
    notifyListeners();
  }
}

class _FeedbackBarContent extends StatelessWidget {
  const _FeedbackBarContent({required this.item});

  final HkFeedbackItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (item.tone) {
      HkFeedbackTone.success => (Icons.check_circle_rounded, scheme.primary),
      HkFeedbackTone.warning => (Icons.warning_amber_rounded, scheme.tertiary),
      HkFeedbackTone.error => (Icons.error_rounded, scheme.error),
      HkFeedbackTone.destructive => (Icons.delete_rounded, scheme.error),
      HkFeedbackTone.info => (Icons.info_rounded, scheme.secondary),
      HkFeedbackTone.neutral => (Icons.notifications_rounded, scheme.onInverseSurface),
    };
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: item.message),
        if (item.batchCount > 1) ...[
          const SizedBox(width: 8),
          Semantics(
            label: '${item.batchCount}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '×${item.batchCount}',
                textDirection: TextDirection.ltr,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
