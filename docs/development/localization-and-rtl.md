# Localization and Right-to-Left Layout

## Supported locales

HomePilot currently supports English and Arabic. The ARB source files under `lib/l10n/` and `l10n.yaml` are authoritative. Generated localization Dart files are outputs and must not be edited manually.

## Workflow

1. Add or update the English message in `app_en.arb`.
2. Add the corresponding Arabic message and metadata.
3. Use meaningful message keys based on purpose rather than literal wording.
4. Add placeholder metadata, types, examples, and plural/select forms where needed.
5. Regenerate:

```powershell
flutter gen-l10n
```

6. Replace hardcoded user-visible strings with `AppLocalizations` access.
7. Test both locales and layout directions.

## Message rules

- Keep placeholders semantic and stable.
- Do not concatenate translated fragments to form sentences.
- Use ICU plural/select syntax for grammatical variation.
- Format dates, times, numbers, and quantities with locale-aware APIs.
- Avoid embedding punctuation assumptions that break Arabic text.
- Keep technical identifiers, file names, and version strings separate from translated prose.
- Do not expose raw backend error text directly to users.

## RTL layout

Use directional APIs:

- `EdgeInsetsDirectional` instead of left/right-specific padding.
- `AlignmentDirectional` where start/end semantics are intended.
- `BorderRadiusDirectional` where corners follow reading direction.
- `TextAlign.start` and `TextAlign.end` where appropriate.
- Direction-aware icons and animation when meaning depends on navigation direction.

Do not mirror universal symbols such as media controls, checkmarks, or product logos unless their semantic direction requires it.

## Testing checklist

For meaningful UI changes, verify:

- English LTR and Arabic RTL.
- Long translations and text scaling.
- Form labels, validation, hints, and error states.
- Dialogs, snackbars, bottom sheets, and notifications.
- Charts, dates, recurrence text, and statistics.
- Route transitions, back affordances, and chevrons.
- Mixed Arabic/Latin content such as versions, asset serial numbers, and URLs.
- Accessibility labels in both locales.

## Generated-file discipline

Generated files may change substantially after Flutter upgrades. Keep those changes isolated and review the source ARB diff first. Never patch generated localization output to fix a translation or build issue.

## Review ownership

Arabic changes should receive language review when wording affects destructive actions, permissions, privacy, monetization, account deletion, or backup/restore. A mechanically valid translation is not sufficient for high-impact consent text.