import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_providers.dart';

class CloudSyncBootstrap extends ConsumerStatefulWidget {
  const CloudSyncBootstrap({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CloudSyncBootstrap> createState() => _CloudSyncBootstrapState();
}

class _CloudSyncBootstrapState extends ConsumerState<CloudSyncBootstrap>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(_resumeSync);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      scheduleMicrotask(_resumeSync);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      scheduleMicrotask(_pauseSync);
    }
  }

  Future<void> _resumeSync() async {
    try {
      await ref.read(syncCoordinatorProvider)?.onAppResumed();
    } on Object {
      // The coordinator persists and exposes failures through SyncStatus.
      // Startup and the offline app must remain available.
    }
  }

  Future<void> _pauseSync() async {
    await ref.read(syncCoordinatorProvider)?.onAppPaused();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
