import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:homepilot/l10n/app_localizations_ext.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../src/core/domain/models.dart';
import '../../../../src/ui/app_theme.dart';
import '../application/permission_education_controller.dart';
import '../domain/permission_capability.dart';

class PermissionSetupScreen extends ConsumerStatefulWidget {
  const PermissionSetupScreen({
    this.source = PermissionEducationSource.settings,
    this.onChooseLocationManually,
    super.key,
  });

  final PermissionEducationSource source;
  final Future<HomeLocation?> Function(BuildContext context)?
  onChooseLocationManually;

  @override
  ConsumerState<PermissionSetupScreen> createState() =>
      _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends ConsumerState<PermissionSetupScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBindingObserver;
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(() {
      ref
          .read(permissionEducationControllerProvider.notifier)
          .initialize(source: widget.source, forceShow: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref
          .read(permissionEducationControllerProvider.notifier)
          .handleAppResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final PermissionEducationControllerState state = ref.watch(
      permissionEducationControllerProvider,
    );
    final PermissionEducationController notifier = ref.read(
      permissionEducationControllerProvider.notifier,
    );
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.permissionSetup),
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(HkSpacing.gutter),
              children: [
                Text(
                  context.l10n.permissionSetupSubtitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: HkSpacing.md),
                for (final cap in PermissionCapability.values) ...[
                  if (cap != PermissionCapability.exactReminderTiming ||
                      state.capabilityStatuses[cap]?.permissionState !=
                          AppPermissionState.unavailable)
                    _CapabilityStatusCard(
                      capability: cap,
                      status: state.capabilityStatuses[cap],
                      isBusy: state.isBusy,
                      onAction: () async {
                        switch (cap) {
                          case PermissionCapability.deviceLocation:
                            await notifier.useCurrentLocation();
                          case PermissionCapability.notifications:
                            await notifier.enableNotifications();
                          case PermissionCapability.exactReminderTiming:
                            await notifier.enableExactTiming();
                        }
                      },
                      onChooseManual: () async {
                        if (widget.onChooseLocationManually != null) {
                          final chosen = await widget.onChooseLocationManually!(
                            context,
                          );
                          if (chosen != null) {
                            await notifier.chooseLocationManually(chosen);
                          }
                        }
                      },
                      onOpenSettings: () => notifier.openSettingsForCurrent(),
                    ),
                  const SizedBox(height: HkSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CapabilityStatusCard extends StatelessWidget {
  const _CapabilityStatusCard({
    required this.capability,
    required this.status,
    required this.isBusy,
    required this.onAction,
    required this.onChooseManual,
    required this.onOpenSettings,
  });

  final PermissionCapability capability;
  final CapabilityStatus? status;
  final bool isBusy;
  final VoidCallback onAction;
  final VoidCallback onChooseManual;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final permState = status?.permissionState ?? AppPermissionState.denied;
    final isGranted = permState == AppPermissionState.granted;
    final isBlocked =
        permState == AppPermissionState.permanentlyDenied ||
        permState == AppPermissionState.serviceDisabled;

    final title = switch (capability) {
      PermissionCapability.deviceLocation =>
        context.l10n.permissionSetupWeatherTitle,
      PermissionCapability.notifications =>
        context.l10n.neverMissImportantMaintenance,
      PermissionCapability.exactReminderTiming =>
        context.l10n.permissionSetupExactOptionalTitle,
    };

    final body = switch (capability) {
      PermissionCapability.deviceLocation =>
        context.l10n.permissionSetupWeatherBody,
      PermissionCapability.notifications =>
        context.l10n.notificationEducationBody,
      PermissionCapability.exactReminderTiming =>
        context.l10n.permissionSetupExactOptionalBody,
    };

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HkRadii.xl),
        side: BorderSide(
          color: isGranted
              ? HkColors.appPrimary.withValues(alpha: 0.3)
              : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HkSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (capability) {
                    PermissionCapability.deviceLocation =>
                      Symbols.location_on_rounded,
                    PermissionCapability.notifications =>
                      Symbols.notifications_active_rounded,
                    PermissionCapability.exactReminderTiming =>
                      Symbols.alarm_on_rounded,
                  },
                  color: isGranted
                      ? HkColors.appPrimary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: HkSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HkSpacing.xs,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isGranted
                        ? HkColors.appPrimary.withValues(alpha: 0.15)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(HkRadii.sm),
                  ),
                  child: Text(
                    isGranted ? 'Allowed' : (isBlocked ? 'Blocked' : 'Not set'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isGranted
                          ? HkColors.appPrimary
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: HkSpacing.xs),
            Text(
              body,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: HkSpacing.sm),
            if (!isGranted)
              Wrap(
                spacing: HkSpacing.xs,
                children: [
                  if (isBlocked)
                    OutlinedButton.icon(
                      onPressed: isBusy ? null : onOpenSettings,
                      icon: const Icon(Symbols.settings_rounded, size: 18),
                      label: Text(context.l10n.permissionSetupManageInSettings),
                    )
                  else
                    FilledButton.icon(
                      onPressed: isBusy ? null : onAction,
                      icon: const Icon(Symbols.check_rounded, size: 18),
                      label: Text(switch (capability) {
                        PermissionCapability.deviceLocation =>
                          context.l10n.permissionSetupUseCurrentLocation,
                        PermissionCapability.notifications =>
                          context.l10n.enableNotificationsOnboarding,
                        PermissionCapability.exactReminderTiming =>
                          context.l10n.permissionSetupAllowPreciseTiming,
                      }),
                    ),
                  if (capability == PermissionCapability.deviceLocation)
                    OutlinedButton.icon(
                      onPressed: isBusy ? null : onChooseManual,
                      icon: const Icon(Symbols.search_rounded, size: 18),
                      label: Text(context.l10n.permissionSetupChooseLocation),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
