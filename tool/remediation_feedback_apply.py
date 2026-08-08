#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def apply() -> None:
    components_path = "lib/src/ui/components.dart"
    components = read(components_path)
    pattern = re.compile(
        r"ScaffoldFeatureController<SnackBar, SnackBarClosedReason>\? showUndoToast\(.*?\nclass TaskDeletionSnackBarContent",
        re.S,
    )
    replacement = r'''ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showUndoToast(
  BuildContext context, {
  required Widget content,
  required FutureOr<void> Function() onUndo,
  FutureOr<void> Function()? onFinalize,
  FutureOr<void> Function(Object error)? onUndoFailure,
  String? actionLabel,
  Duration duration = const Duration(seconds: 5),
  String? batchGroup,
  String? batchItemType,
  double? bottomOffset,
  bool reserveFloatingActionButton = false,
}) {
  return _showUndoSnackBar(
    context,
    content: content,
    onUndo: onUndo,
    onFinalize: onFinalize,
    onUndoFailure: onUndoFailure,
    actionLabel: actionLabel ?? context.l10n.undo,
    duration: duration,
    batchGroup: batchGroup,
    batchItemType: batchItemType,
    bottomOffset: bottomOffset,
    reserveFloatingActionButton: reserveFloatingActionButton,
  );
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
showTaskMovedToTrashSnackBar(
  BuildContext context, {
  required FutureOr<void> Function() onUndo,
  FutureOr<void> Function()? onFinalize,
  FutureOr<void> Function(Object error)? onUndoFailure,
  String? actionLabel,
  Duration duration = const Duration(seconds: 5),
  double? bottomOffset,
  bool reserveFloatingActionButton = false,
}) {
  return _showUndoSnackBar(
    context,
    content: Text(context.l10n.taskMovedToTrash),
    onUndo: onUndo,
    onFinalize: onFinalize,
    onUndoFailure: onUndoFailure,
    actionLabel: actionLabel ?? context.l10n.undo,
    duration: duration,
    batchGroup: 'trash',
    batchItemType: 'task',
    bottomOffset: bottomOffset,
    reserveFloatingActionButton: reserveFloatingActionButton,
  );
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _showUndoSnackBar(
  BuildContext context, {
  required Widget content,
  required FutureOr<void> Function() onUndo,
  FutureOr<void> Function()? onFinalize,
  FutureOr<void> Function(Object error)? onUndoFailure,
  required String actionLabel,
  required Duration duration,
  String? batchGroup,
  String? batchItemType,
  double? bottomOffset,
  bool reserveFloatingActionButton = false,
}) {
  final item = HkFeedbackItem(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    message: content,
    tone: HkFeedbackTone.success,
    mode: HkFeedbackMode.undoable,
    actionLabel: actionLabel,
    onUndo: onUndo,
    onFinalize: onFinalize,
    onUndoFailure: onUndoFailure,
    duration: duration,
    batchGroup: batchGroup,
    batchItemType: batchItemType,
    bottomOffset: bottomOffset,
    reserveFloatingActionButton: reserveFloatingActionButton,
  );
  return FeedbackCoordinator.instance.show(context, item);
}

class TaskDeletionSnackBarContent'''
    components, count = pattern.subn(replacement, components, count=1)
    if count != 1:
        raise RuntimeError(f"feedback helper block changed: {count}")

    legacy = re.compile(
        r"class TaskDeletionSnackBarContent.*?\nbool _reduceMotion\(BuildContext context\)",
        re.S,
    )
    components, count = legacy.subn(
        "bool _reduceMotion(BuildContext context)",
        components,
        count=1,
    )
    if count != 1:
        raise RuntimeError(f"legacy countdown block changed: {count}")
    write(components_path, components)

    main_path = "lib/main.dart"
    main = read(main_path)
    replacements = [
        (
            """  hk_ui.showToast(\n    context,\n    content: Text(context.l10n.nameMovedToTrash(asset.name)),\n  );""",
            """  hk_ui.showUndoToast(\n    context,\n    content: Text(context.l10n.nameMovedToTrash(asset.name)),\n    batchGroup: 'trash',\n    batchItemType: 'asset',\n    onUndo: () async {\n      await ref.read(assetRepositoryProvider).restoreAsset(asset.id);\n      await refreshNotificationSchedules(ref);\n      if (context.mounted) {\n        hk_ui.showToast(\n          context,\n          content: Text(context.l10n.nameRestored(asset.name)),\n        );\n      }\n    },\n    onUndoFailure: (error) {\n      if (context.mounted) {\n        hk_ui.showToast(\n          context,\n          content: Text(context.l10n.somethingWentWrongPleaseTryAgain),\n          severity: hk_ui.HkToastSeverity.error,\n        );\n      }\n    },\n  );""",
        ),
        (
            """  hk_ui.showToast(\n    context,\n    content: Text(context.l10n.nameMovedToTrash(room.name)),\n  );""",
            """  hk_ui.showUndoToast(\n    context,\n    content: Text(context.l10n.nameMovedToTrash(room.name)),\n    batchGroup: 'trash',\n    batchItemType: 'room',\n    onUndo: () async {\n      await ref.read(assetRepositoryProvider).restoreRoom(room.id);\n      await refreshNotificationSchedules(ref);\n      if (context.mounted) {\n        hk_ui.showToast(\n          context,\n          content: Text(context.l10n.nameRestored(room.name)),\n        );\n      }\n    },\n    onUndoFailure: (error) {\n      if (context.mounted) {\n        hk_ui.showToast(\n          context,\n          content: Text(context.l10n.somethingWentWrongPleaseTryAgain),\n          severity: hk_ui.HkToastSeverity.error,\n        );\n      }\n    },\n  );""",
        ),
        (
            """  hk_ui.showToast(\n    context,\n    content: Text(context.l10n.nameMovedToTrash(area.name)),\n  );""",
            """  hk_ui.showUndoToast(\n    context,\n    content: Text(context.l10n.nameMovedToTrash(area.name)),\n    batchGroup: 'trash',\n    batchItemType: 'area',\n    onUndo: () async {\n      await ref.read(assetRepositoryProvider).restoreArea(area.id);\n      await refreshNotificationSchedules(ref);\n      if (context.mounted) {\n        hk_ui.showToast(\n          context,\n          content: Text(context.l10n.nameRestored(area.name)),\n        );\n      }\n    },\n    onUndoFailure: (error) {\n      if (context.mounted) {\n        hk_ui.showToast(\n          context,\n          content: Text(context.l10n.somethingWentWrongPleaseTryAgain),\n          severity: hk_ui.HkToastSeverity.error,\n        );\n      }\n    },\n  );""",
        ),
    ]
    for old, new in replacements:
        if old not in main:
            raise RuntimeError(f"Trash feedback block not found: {old[:80]}")
        main = main.replace(old, new, 1)
    write(main_path, main)

    write(
        "test/feedback_coordinator_test.dart",
        r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homepilot/src/ui/feedback/feedback_coordinator.dart';
import 'package:homepilot/src/ui/feedback/feedback_model.dart';

void main() {
  setUp(FeedbackCoordinator.instance.resetForTesting);

  testWidgets('unrelated error cannot terminate active Undo', (tester) async {
    var finalized = 0;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final context = tester.element(find.byType(Scaffold));
    FeedbackCoordinator.instance.show(
      context,
      HkFeedbackItem(
        id: 'undo',
        message: const Text('Moved to Trash'),
        mode: HkFeedbackMode.undoable,
        actionLabel: 'Undo',
        batchGroup: 'trash',
        batchItemType: 'task',
        onUndo: () {},
        onFinalize: () => finalized++,
        duration: const Duration(seconds: 5),
      ),
    );
    await tester.pump();
    FeedbackCoordinator.instance.show(
      context,
      const HkFeedbackItem(
        id: 'error',
        message: Text('Unrelated error'),
        tone: HkFeedbackTone.error,
      ),
    );
    await tester.pump();
    expect(FeedbackCoordinator.instance.activeItem?.id, 'undo');
    expect(finalized, 0);
  });

  testWidgets('compatible Trash updates visible batch count and resets bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final context = tester.element(find.byType(Scaffold));
    HkFeedbackItem item(String id, String type) => HkFeedbackItem(
      id: id,
      message: const Text('Moved to Trash'),
      mode: HkFeedbackMode.undoable,
      actionLabel: 'Undo',
      batchGroup: 'trash',
      batchItemType: type,
      onUndo: () {},
      duration: const Duration(seconds: 5),
    );
    FeedbackCoordinator.instance.show(context, item('a', 'task'));
    await tester.pump();
    FeedbackCoordinator.instance.show(context, item('b', 'asset'));
    await tester.pump();
    expect(FeedbackCoordinator.instance.activeItem?.batchCount, 2);
    expect(find.text('×2'), findsOneWidget);
  });

  testWidgets('Undo callback executes exactly once', (tester) async {
    var undoCount = 0;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final context = tester.element(find.byType(Scaffold));
    FeedbackCoordinator.instance.show(
      context,
      HkFeedbackItem(
        id: 'undo',
        message: const Text('Done'),
        mode: HkFeedbackMode.undoable,
        actionLabel: 'Undo',
        onUndo: () => undoCount++,
      ),
    );
    await FeedbackCoordinator.instance.handleAction();
    await FeedbackCoordinator.instance.handleAction();
    expect(undoCount, 1);
  });
}
''',
    )


if __name__ == "__main__":
    apply()
