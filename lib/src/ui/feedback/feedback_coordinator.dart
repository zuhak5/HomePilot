import 'package:flutter/material.dart';
import 'package:homepilot/src/core/services/feedback_messenger.dart';
import 'feedback_model.dart';

class FeedbackCoordinator extends ChangeNotifier {
  FeedbackCoordinator._();

  static final FeedbackCoordinator instance = FeedbackCoordinator._();

  int _currentToken = 0;
  HkFeedbackItem? _activeItem;
  final List<HkFeedbackItem> _pendingQueue = [];
  bool _actionExecuted = false;

  HkFeedbackItem? get activeItem => _activeItem;

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? show(
    BuildContext context,
    HkFeedbackItem item,
  ) {
    if (_activeItem != null && _activeItem!.mode == HkFeedbackMode.undoable) {
      if (item.mode == HkFeedbackMode.undoable &&
          _canBatchUndo(_activeItem!, item)) {
        _batchUndoItem(item);
        notifyListeners();
        return null;
      }
      if (item.tone != HkFeedbackTone.error &&
          item.tone != HkFeedbackTone.destructive) {
        _pendingQueue.add(item);
        return null;
      }
    }

    return _showItem(context, item);
  }

  bool _canBatchUndo(HkFeedbackItem active, HkFeedbackItem incoming) {
    return active.batchItemType == incoming.batchItemType ||
        (active.batchItemType != null && incoming.batchItemType != null);
  }

  void _batchUndoItem(HkFeedbackItem incoming) {
    if (_activeItem == null) return;
    final newCount = _activeItem!.batchCount + incoming.batchCount;
    final prevUndo = _activeItem!.onUndo;
    final incomingUndo = incoming.onUndo;
    final prevFinalize = _activeItem!.onFinalize;
    final incomingFinalize = incoming.onFinalize;

    _activeItem = _activeItem!.copyWith(
      batchCount: newCount,
      onUndo: () async {
        if (incomingUndo != null) await incomingUndo();
        if (prevUndo != null) await prevUndo();
      },
      onFinalize: () async {
        if (prevFinalize != null) await prevFinalize();
        if (incomingFinalize != null) await incomingFinalize();
      },
    );
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _showItem(
    BuildContext context,
    HkFeedbackItem item,
  ) {
    _executePendingFinalize();

    _activeItem = item;
    _actionExecuted = false;
    notifyListeners();

    final messenger =
        ScaffoldMessenger.maybeOf(context) ??
        (hkRootScaffoldMessengerKey.currentState?.mounted == true
            ? hkRootScaffoldMessengerKey.currentState
            : null);

    if (messenger == null) return null;

    final isAccessible =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    final effectiveDuration = isAccessible
        ? const Duration(seconds: 15)
        : (item.mode == HkFeedbackMode.undoable
              ? const Duration(seconds: 5)
              : item.duration);

    messenger.hideCurrentSnackBar();
    final token = ++_currentToken;
    final controller = messenger.showSnackBar(
      SnackBar(
        content: item.message,
        duration: effectiveDuration,
        behavior: SnackBarBehavior.floating,
        action: item.actionLabel != null
            ? SnackBarAction(
                label: item.actionLabel!,
                onPressed: () {
                  handleAction();
                },
              )
            : null,
      ),
    );

    controller.closed.then((reason) {
      if (_currentToken == token &&
          _activeItem?.id == item.id &&
          reason != SnackBarClosedReason.action &&
          !_actionExecuted) {
        _onTimeout();
      }
    });

    return controller;
  }

  void resetForTesting() {
    _currentToken++;
    _activeItem = null;
    _pendingQueue.clear();
    _actionExecuted = false;
    try {
      hkRootScaffoldMessengerKey.currentState?.clearSnackBars();
    } catch (_) {}
  }

  void handleAction() async {
    if (_actionExecuted || _activeItem == null) return;
    _actionExecuted = true;

    final item = _activeItem;
    _activeItem = null;
    notifyListeners();

    if (item?.onUndo != null) {
      await item!.onUndo!();
    } else if (item?.onAction != null) {
      await item!.onAction!();
    }

    item?.onDismiss?.call(HkFeedbackDismissReason.userAction);
    _processNextQueue();
  }

  void _onTimeout() async {
    if (_actionExecuted || _activeItem == null) return;

    final item = _activeItem;
    _activeItem = null;
    notifyListeners();

    if (item?.onFinalize != null) {
      await item!.onFinalize!();
    }

    item?.onDismiss?.call(HkFeedbackDismissReason.timeout);
    _processNextQueue();
  }

  void _executePendingFinalize() {
    if (_activeItem != null && !_actionExecuted) {
      _actionExecuted = true;
      final item = _activeItem;
      if (item?.onFinalize != null) {
        item!.onFinalize!();
      }
      item?.onDismiss?.call(HkFeedbackDismissReason.superceded);
    }
  }

  void _processNextQueue() {
    if (_pendingQueue.isNotEmpty &&
        hkRootScaffoldMessengerKey.currentState?.mounted == true &&
        hkRootScaffoldMessengerKey.currentContext != null) {
      final next = _pendingQueue.removeAt(0);
      _showItem(hkRootScaffoldMessengerKey.currentContext!, next);
    }
  }
}
