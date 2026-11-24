# eMedia Data

A Flutter web front end for managing data on an EME server (`/site/mediadb/services`).

- **Shell:** an icon rail, a collapsible **Data Entities** sidebar (⌘B) and an entity top menu (the server's `appsection` table). Quick asset search is on ⌘K.
- **Results:** every module has **Table**, **Grid** and **Column** (Finder-style) views. Each has sort, paging, a column picker and a **Summary** panel with facet filters. Assets also get a folder tree.
- **Uploads:** drag and drop anywhere on a results page, or use the Upload button. Uploads queue with progress, cancel and retry.
  - On **Assets**, files go into the selected folder.
  - On an **entity** list, each file becomes a new record named after it, and the file becomes the record's picture.
  - In a record's **Files** tab, files go into that record's folder.
- **Asset viewer** (`/asset/<id>`): **Data**, **Viewer** (zoomable image or PDF), **History** and **Download** tabs. Use ←/→ to step through the current results.
- **Records:** forms are built from the server's field definitions, including multilanguage text, lists, multi-select, tags, dates and booleans. You can create, edit and delete records.
- **Themes:** dark by default; switch to light from the rail.

## Run

```bash
flutter pub get
flutter run -d chrome          # or: flutter build web
```

The default server is `http://localhost:8080`. You can change it on the sign-in screen.

## Sign in

Sign-in is passwordless:
1. Enter your email and the app emails you a 6 digit code (`sendusercode.json`).
2. Enter the code. The app redeems it with `token.json grant_type=otp` and registers an Ed25519 key for this browser.
3. Later sessions sign in silently with that key (`grant_type=key`). Signing out revokes the key.

You can also paste an application password (`emeapp.<id>.<secret>`) instead.

## Deep links

- `#/m/<module>`: a module's results
- `#/m/<module>?open=<id>`: opens a record (`?open=new` opens a blank form)
- `#/asset/<id>?tab=viewer`: opens the asset viewer on a tab (`data`, `viewer`, `history` or `download`)

## Layout

```
lib/core/       API client, settings, value formatting, icon map, browser downloads
lib/data/       models, repository (all endpoints), Riverpod providers
lib/features/   auth, shell, data (views, folders, summary), record (forms), assets (viewer), upload
lib/theme/      dark and light themes
```

## Icons

The app uses [Phosphor](https://phosphoricons.com) icons: regular weight normally, fill weight for selected items.

- **Fonts:** the font files are vendored in `assets/fonts/phosphor/` (MIT licensed). The `phosphor_flutter` package no longer compiles on current Flutter, because `IconData` is now a final class.
- **Constants:** `lib/core/ph.dart` holds the generated constants (`Ph.house`, `PhFill.house`) and a map from names to icons.

Each entity's icon is picked in this order:

1. **`appicon`** on the module (a Phosphor name such as `user-circle`, as listed on phosphoricons.com). Set this to change an entity's icon.
2. **`moduleicon`**, the Bootstrap name the `/site/find` UI also uses. Common names are mapped to Phosphor in `lib/core/icons.dart`.
3. A default icon.
