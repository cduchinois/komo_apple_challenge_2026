# Komo — Translation guidance

This file guides Xcode agents when translating Komo. Reference it from `AGENTS.md` for localization tasks.

## Supported languages

| Locale | Language | Notes |
|--------|----------|-------|
| `en` | English (source) | Onboarding voice: lowercase, warm |
| `en-GB` | English (UK) | Copy of `en` |
| `en-AU` | English (Australia) | Copy of `en` |
| `fr` | French | Tutoiement, native-reviewed preferred |
| `es` | Spanish | |
| `de` | German | |
| `pt` | Portuguese | |
| `ja` | Japanese | |
| `zh-Hans` | Chinese (Simplified) | |
| `it` | Italian | |

## Voice & tone

- **English (source):** lowercase, warm, conversational onboarding voice (`"hi, i'm komo."`, `"not now"`, `"let's go"`).
- **French:** tutoiement, même ton doux et direct. Garder komo en minuscules dans l'onboarding quand c'est possible.
- **Main app labels:** peuvent utiliser une casse plus standard (`ÉNERGIE DU JOUR`, `Accueil`).

## Do not translate

- **KOMO** / **komo** — nom du produit (garder la casse selon le contexte).
- **Topic keys** stockées en interne (`meetings`, `screen time`, etc.) — ce sont des clés, pas du texte UI.
- Symboles UI : `★`, `✨`, pourcentages, nombres.

## Glossary

| English | French | Notes |
|---------|--------|-------|
| energy | énergie | |
| insight | insight | terme accepté en FR produit |
| quick win | petit coup de pouce | |
| recharge | recharger | action utilisateur |
| drain | vider / ce qui te vide | contexte bien-être |
| steady | stable | niveau d'énergie |
| charged | chargé | niveau d'énergie |
| drained | vidé | niveau d'énergie |
| check-in | check-in | ou « bilan » si trop long |

## Onboarding storage keys

Les réponses onboarding sont **persistées en anglais** (`morning`, `meetings`, `running on fumes`).  
Ne traduire que les **libellés affichés** via `L10n.option(_:)` — jamais les valeurs stockées.

## Plural & layout

- Prévoir des traductions plus longues en français (+20–30 %).
- Tester Dynamic Type et le widget small/medium après traduction.
- Utiliser `%@` / `%lld` pour les chaînes paramétrées (`"%@ energy"` → `"énergie %@"`).

## Machine translation workflow

Bulk-fill String Catalogs with `Scripts/localize_catalogs.py`:

```bash
python3 -m venv .venv-i18n
.venv-i18n/bin/pip install deep-translator
.venv-i18n/bin/python3 Scripts/localize_catalogs.py
```

- Uses MyMemory with Google fallback via `deep-translator`.
- Preserves existing `fr` entries (skip unless `--force`).
- `en-GB` and `en-AU` are copied from `en`.
- Protects format placeholders (`%@`, `%lld`, `%1$@`) and product name Komo/komo/KOMO.

Re-run with `--force` to overwrite all machine translations.

## Files

| File | Purpose |
|------|---------|
| `Komo/Resources/Localizable.xcstrings` | UI principale |
| `Komo/Resources/InfoPlist.xcstrings` | Permissions Santé / Calendrier |
| `KomoWidget/Localizable.xcstrings` | Widget (copie partagée) |
| `Komo/Resources/L10n.swift` | Helpers + clés onboarding |

## Remaining work

- `AppState.reflectionPool` (~50 cartes insight) — migré dans `ReflectionCatalog.swift`
- `HealthKitDataProvider` insights dynamiques — migré via `HealthKitL10n.swift`
- Toasts/sheets `MainView` — migrés
- `CompanionConfig` — traits personnalisation
- Chaînes DEBUG (`ProfileView`) — optionnel
