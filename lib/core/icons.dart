import 'package:flutter/widgets.dart';

import '../data/models.dart';
import 'ph.dart';

/// Bootstrap names still stored in `moduleicon` (used by the legacy /site/find UI),
/// mapped to the closest Phosphor icon. Set `appicon` on a module to override.
const _bootstrapAliases = {
  'book-half': 'book-open',
  'buildings': 'buildings',
  'category': 'tag',
  'chat': 'chat-circle',
  'check-square': 'check-square',
  'coin': 'coins',
  'file-earmark': 'file',
  'file-earmark-post': 'article',
  'file-earmark-richtext': 'file-text',
  'files': 'files',
  'folder-check': 'list-checks',
  'geo-alt': 'map-pin',
  'grid': 'squares-four',
  'image': 'image',
  'image-fill': 'image',
  'images': 'images',
  'magic': 'magic-wand',
  'mortarboard': 'graduation-cap',
  'node-plus-fill': 'hard-drives',
  'person': 'user',
  'person-fill': 'user',
  'person-arms-up': 'person-arms-spread',
  'person-circle': 'user-circle',
  'product': 'package',
  'shop-window': 'storefront',
};

/// Looks up a Phosphor icon by its web name (`user-circle`); [filled] picks the fill weight.
IconData? phosphorIcon(String? name, {bool filled = false}) {
  if (name == null) return null;
  final key = name.trim().toLowerCase().replaceFirst(
    RegExp(r'^(ph-|ph:|bi-)'),
    '',
  );
  final pair = phosphorIconMap[key];
  if (pair == null) return null;
  return filled ? pair.$2 : pair.$1;
}

/// Icon for a module: `appicon` (Phosphor name) first, then the legacy Bootstrap
/// `moduleicon` through [_bootstrapAliases] (or an identically named Phosphor icon).
IconData moduleIcon(
  ModuleInfo? module, {
  bool filled = false,
  IconData? fallback,
}) {
  final fb = fallback ?? (filled ? PhFill.squaresFour : Ph.squaresFour);
  if (module == null) return fb;
  final legacy = module.icon?.trim().replaceFirst('bi-', '');
  return phosphorIcon(module.appIcon, filled: filled) ??
      phosphorIcon(_bootstrapAliases[legacy], filled: filled) ??
      phosphorIcon(legacy, filled: filled) ??
      fb;
}
