import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:homepilot/l10n/app_localizations_ext.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';

enum PermissionEducationStep { location, notifications, exactAlarms }

class PermissionEducationOverlay extends StatefulWidget {
  const PermissionEducationOverlay({
    required this.step,
    required this.targetLink,
    required this.onContinue,
    required this.onNotNow,
    required this.onClose,
    required this.primaryLabel,
    this.onBack,
    this.targetRect,
    this.busy = false,
    super.key,
  });

  final PermissionEducationStep step;
  final LayerLink targetLink;
  final VoidCallback onContinue;
  final VoidCallback onNotNow;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final String primaryLabel;
  final Rect? targetRect;
  final bool busy;

  @override
  State<PermissionEducationOverlay> createState() =>
      _PermissionEducationOverlayState();
}

class _PermissionEducationOverlayState extends State<PermissionEducationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.maybeOf(context);
    final reduceMotion =
        media?.disableAnimations == true || media?.accessibleNavigation == true;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0.45;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = media.disableAnimations || media.accessibleNavigation;
    final bottomInset = math.max(media.padding.bottom, 8.0) + 92;
    final topInset = math.max(media.padding.top, 12.0) + HkSpacing.sm;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCardHeight = math.max(
          280.0,
          constraints.maxHeight - topInset - bottomInset,
        );
        return Stack(
          key: const ValueKey('permission-education-overlay'),
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            ModalBarrier(
              dismissible: false,
              color: scheme.scrim.withValues(alpha: 0.28),
            ),
            _PermissionEducationHalo(
              animation: _controller,
              reduceMotion: reduceMotion,
              step: widget.step,
              targetLink: widget.targetLink,
              targetRect: widget.targetRect,
              viewportSize: constraints.biggest,
            ),
            PositionedDirectional(
              start: HkSpacing.md,
              end: HkSpacing.md,
              bottom: bottomInset,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 440,
                    maxHeight: maxCardHeight,
                  ),
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.04, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _PermissionEducationCard(
                      key: ValueKey(widget.step),
                      step: widget.step,
                      animation: _controller,
                      reduceMotion: reduceMotion,
                      primaryLabel: widget.primaryLabel,
                      busy: widget.busy,
                      onContinue: widget.onContinue,
                      onNotNow: widget.onNotNow,
                      onClose: widget.onClose,
                      onBack: widget.onBack,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

double _haloSize(PermissionEducationStep step) => switch (step) {
  PermissionEducationStep.location => 92,
  PermissionEducationStep.notifications => 70,
  PermissionEducationStep.exactAlarms => 76,
};

class _PermissionEducationHalo extends StatelessWidget {
  const _PermissionEducationHalo({
    required this.animation,
    required this.reduceMotion,
    required this.step,
    required this.targetLink,
    required this.targetRect,
    required this.viewportSize,
  });

  final Animation<double> animation;
  final bool reduceMotion;
  final PermissionEducationStep step;
  final LayerLink targetLink;
  final Rect? targetRect;
  final Size viewportSize;

  @override
  Widget build(BuildContext context) {
    final haloSize = _haloSize(step);
    final rect = targetRect;
    if (rect != null && rect.isFinite) {
      final maxLeft = math.max(0.0, viewportSize.width - haloSize);
      final maxTop = math.max(0.0, viewportSize.height - haloSize);
      final left = math.min(
        math.max(rect.center.dx - (haloSize / 2), 0.0),
        maxLeft,
      );
      final top = math.min(
        math.max(rect.center.dy - (haloSize / 2), 0.0),
        maxTop,
      );
      return Positioned(
        left: left,
        top: top,
        width: haloSize,
        height: haloSize,
        child: _PermissionEducationHaloBody(
          animation: animation,
          reduceMotion: reduceMotion,
        ),
      );
    }
    return CompositedTransformFollower(
      link: targetLink,
      targetAnchor: Alignment.center,
      followerAnchor: Alignment.center,
      showWhenUnlinked: false,
      child: SizedBox(
        width: haloSize,
        height: haloSize,
        child: _PermissionEducationHaloBody(
          animation: animation,
          reduceMotion: reduceMotion,
        ),
      ),
    );
  }
}

class _PermissionEducationHaloBody extends StatelessWidget {
  const _PermissionEducationHaloBody({
    required this.animation,
    required this.reduceMotion,
  });

  final Animation<double> animation;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final progress = reduceMotion ? 0.45 : animation.value;
          return Opacity(
            opacity: 0.64 - (progress * 0.22),
            child: Container(
              key: const ValueKey('permission-education-target-halo'),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: HkColors.appPrimary, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: HkColors.appPrimary.withValues(alpha: 0.22),
                    blurRadius: 24,
                    spreadRadius: 6,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PermissionEducationCard extends StatelessWidget {
  const _PermissionEducationCard({
    required this.step,
    required this.animation,
    required this.reduceMotion,
    required this.primaryLabel,
    required this.busy,
    required this.onContinue,
    required this.onNotNow,
    required this.onClose,
    required this.onBack,
    super.key,
  });

  final PermissionEducationStep step;
  final Animation<double> animation;
  final bool reduceMotion;
  final String primaryLabel;
  final bool busy;
  final VoidCallback onContinue;
  final VoidCallback onNotNow;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepNumber = _stepNumber(step);
    final title = _stepTitle(context, step);
    final body = _stepBody(context, step);
    final reassurance = _stepReassurance(context, step);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${context.l10n.permissionStep(stepNumber, 3)}. $title',
      child: Material(
        key: const ValueKey('permission-education-card'),
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        borderRadius: BorderRadius.circular(HkRadii.xxl),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HkRadii.xxl),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
            boxShadow: HkShadows.ambient(tint: scheme.primary),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HkSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (onBack != null)
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        onPressed: busy ? null : onBack,
                        icon: const Icon(Symbols.arrow_back_rounded),
                      )
                    else
                      const SizedBox(width: 48),
                    Expanded(
                      child: Text(
                        context.l10n.permissionStep(stepNumber, 3),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.close,
                      onPressed: busy ? null : onClose,
                      icon: const Icon(Symbols.close_rounded),
                    ),
                  ],
                ),
                SizedBox(
                  height: 116,
                  child: switch (step) {
                    PermissionEducationStep.location =>
                      _LocationPermissionIllustration(
                        animation: animation,
                        reduceMotion: reduceMotion,
                      ),
                    PermissionEducationStep.notifications =>
                      _NotificationPermissionIllustration(
                        animation: animation,
                        reduceMotion: reduceMotion,
                      ),
                    PermissionEducationStep.exactAlarms =>
                      _AlarmPermissionIllustration(
                        animation: animation,
                        reduceMotion: reduceMotion,
                      ),
                  },
                ),
                const SizedBox(height: HkSpacing.sm),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: HkSpacing.xs),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: HkSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(HkSpacing.sm),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.44),
                    borderRadius: BorderRadius.circular(HkRadii.lg),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        switch (step) {
                          PermissionEducationStep.location =>
                            Symbols.privacy_tip_rounded,
                          PermissionEducationStep.notifications =>
                            Symbols.tune_rounded,
                          PermissionEducationStep.exactAlarms =>
                            Symbols.schedule_rounded,
                        },
                        size: 20,
                        color: scheme.primary,
                        semanticLabel: null,
                      ),
                      const SizedBox(width: HkSpacing.xs),
                      Expanded(
                        child: Text(
                          reassurance,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onPrimaryContainer,
                                height: 1.35,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HkSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: busy ? null : onNotNow,
                        child: Text(context.l10n.notNow),
                      ),
                    ),
                    const SizedBox(width: HkSpacing.xs),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: busy ? null : onContinue,
                        icon: busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(switch (step) {
                                PermissionEducationStep.location =>
                                  Symbols.my_location_rounded,
                                PermissionEducationStep.notifications =>
                                  Symbols.notifications_active_rounded,
                                PermissionEducationStep.exactAlarms =>
                                  Symbols.alarm_on_rounded,
                              }),
                        label: Text(primaryLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int _stepNumber(PermissionEducationStep step) => switch (step) {
  PermissionEducationStep.location => 1,
  PermissionEducationStep.notifications => 2,
  PermissionEducationStep.exactAlarms => 3,
};

String _stepTitle(BuildContext context, PermissionEducationStep step) =>
    switch (step) {
      PermissionEducationStep.location => context.l10n.getLocalMaintenanceTips,
      PermissionEducationStep.notifications =>
        context.l10n.neverMissImportantMaintenance,
      PermissionEducationStep.exactAlarms =>
        context.l10n.exactAlarmEducationTitle,
    };

String _stepBody(BuildContext context, PermissionEducationStep step) =>
    switch (step) {
      PermissionEducationStep.location => context.l10n.locationEducationBody,
      PermissionEducationStep.notifications =>
        context.l10n.notificationEducationBody,
      PermissionEducationStep.exactAlarms =>
        context.l10n.preciseAlarmsPermissionBody,
    };

String _stepReassurance(BuildContext context, PermissionEducationStep step) =>
    switch (step) {
      PermissionEducationStep.location => context.l10n.locationEducationPrivacy,
      PermissionEducationStep.notifications =>
        context.l10n.notificationEducationReassurance,
      PermissionEducationStep.exactAlarms =>
        context.l10n.approximateReminderTimingWarning,
    };

class _LocationPermissionIllustration extends StatelessWidget {
  const _LocationPermissionIllustration({
    required this.animation,
    required this.reduceMotion,
  });

  final Animation<double> animation;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.getLocalMaintenanceTips,
      image: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final phase = reduceMotion ? 0.35 : animation.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(HkRadii.xl),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primaryContainer.withValues(alpha: 0.78),
                        scheme.surfaceContainerLowest,
                      ],
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.96 + (phase * 0.06),
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.28),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.16),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Symbols.location_on_rounded,
                          size: 58,
                          color: scheme.primary,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Icon(
                            Symbols.home_rounded,
                            size: 23,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 54 + (phase * 6),
                  top: 18,
                  child: Icon(
                    Symbols.partly_cloudy_day_rounded,
                    color: HkColors.appWarning,
                    size: 31,
                  ),
                ),
                PositionedDirectional(
                  end: 58,
                  bottom: 16 + (phase * 4),
                  child: Icon(
                    Symbols.eco_rounded,
                    color: scheme.primary,
                    size: 26,
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DashedArcPainter(
                      color: scheme.primary.withValues(alpha: 0.58),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NotificationPermissionIllustration extends StatelessWidget {
  const _NotificationPermissionIllustration({
    required this.animation,
    required this.reduceMotion,
  });

  final Animation<double> animation;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.neverMissImportantMaintenance,
      image: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final phase = reduceMotion ? 0.4 : animation.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(HkRadii.xl),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primaryContainer.withValues(alpha: 0.74),
                        scheme.surfaceContainerLowest,
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 78 + (phase * 6),
                  height: 78 + (phase * 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.22),
                      width: 3,
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: reduceMotion ? 0 : (phase - 0.5) * 0.08,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.18),
                          blurRadius: 22,
                        ),
                      ],
                    ),
                    child: Icon(
                      Symbols.notifications_active_rounded,
                      color: scheme.primary,
                      size: 39,
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 51,
                  bottom: 16,
                  child: _IllustrationBadge(
                    icon: Symbols.checklist_rounded,
                    color: scheme.primary,
                  ),
                ),
                PositionedDirectional(
                  end: 51,
                  top: 15,
                  child: _IllustrationBadge(
                    icon: Symbols.calendar_month_rounded,
                    color: HkColors.appWarning,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AlarmPermissionIllustration extends StatelessWidget {
  const _AlarmPermissionIllustration({
    required this.animation,
    required this.reduceMotion,
  });

  final Animation<double> animation;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: context.l10n.exactAlarmEducationTitle,
      image: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final phase = reduceMotion ? 0.35 : animation.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(HkRadii.xl),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primaryContainer.withValues(alpha: 0.74),
                        scheme.surfaceContainerLowest,
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 82 + (phase * 5),
                  height: 82 + (phase * 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.22),
                      width: 3,
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, reduceMotion ? 0 : -2 + (phase * 4)),
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.18),
                          blurRadius: 22,
                        ),
                      ],
                    ),
                    child: Icon(
                      Symbols.alarm_on_rounded,
                      color: scheme.primary,
                      size: 40,
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 50,
                  bottom: 16,
                  child: _IllustrationBadge(
                    icon: Symbols.task_alt_rounded,
                    color: scheme.primary,
                  ),
                ),
                PositionedDirectional(
                  end: 50,
                  top: 16,
                  child: _IllustrationBadge(
                    icon: Symbols.schedule_rounded,
                    color: HkColors.appWarning,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IllustrationBadge extends StatelessWidget {
  const _IllustrationBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 39,
      height: 39,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(HkRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Icon(icon, color: color, size: 23),
    );
  }
}

class _DashedArcPainter extends CustomPainter {
  const _DashedArcPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.32,
        size.height * 0.18,
        size.width * 0.58,
        size.height * 0.26,
      );
    final metrics = path.computeMetrics();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    for (final metric in metrics) {
      var start = 0.0;
      while (start < metric.length) {
        canvas.drawPath(
          metric.extractPath(start, math.min(start + 6, metric.length)),
          paint,
        );
        start += 11;
      }
    }
    final tip = Offset(size.width * 0.58, size.height * 0.26);
    final arrow = Path()
      ..moveTo(tip.dx - 9, tip.dy - 2)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 5, tip.dy + 8);
    canvas.drawPath(arrow, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedArcPainter oldDelegate) =>
      oldDelegate.color != color;
}
