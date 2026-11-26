import '../../core/values.dart';
import '../../data/models.dart';

enum ColumnKind { thumb, text, bytes, chips, date }

class ColumnDef {
  const ColumnDef(
    this.id,
    this.label, {
    this.kind = ColumnKind.text,
    this.flex = 2,
    this.sortable = true,
    this.field,
  });
  final String id;

  /// The field definition, when known: drives the typed cell rendering.
  final FieldDef? field;
  final String label;
  final ColumnKind kind;
  final int flex;
  final bool sortable;

  double get minWidth => switch (kind) {
    ColumnKind.thumb => 92,
    ColumnKind.bytes || ColumnKind.date => 110,
    _ => 140,
  };

  String format(Json record) => switch (kind) {
    ColumnKind.bytes => formatBytes(record[id]),
    _ => displayValue(record[id]),
  };
}

/// Server bookkeeping fields that make poor columns or form inputs.
const systemFields = {
  'id',
  'description',
  'sourcepath',
  'archivesourcepath',
  'emrecordstatus',
  'entitysourcetype',
  'rootcategory',
  'securityenabled',
  'securityalwaysvisible',
  'llmerror',
  'taggedbyllm',
  'semantictopicsindexed',
  'badge',
  'category-exact',
  'category-featured',
  'md5hex',
  'recordtype',
  'primaryimage',
  'primarymedia',
  'urlname',
  'editorgroups',
  'editorusers',
  'viewgroups',
  'viewusers',
  'viewergroups',
  'viewerusers',
  'permissionsupdateddate',
  'downloads',
  'originalurl',
  'mediarendertype',
  'isfolder',
  'importstatus',
  'previewstatus',
  'pushstatus',
  'publisheds3',
  'existsonpush',
  'missinggenerated',
  'googletranscoded',
  'googletagged',
  'emiderror',
  'emidwritten',
  'xmperror',
  'duplicate',
  'duplicatesourcepath',
  'facescancomplete',
  'facescanerror',
  'facehasprofile',
  'haschat',
  'hasfulltext',
  'assetexpired',
  'islocked',
  'foldersourcepath',
  'ordering',
  '_thumbpath',
};

const _assetColumns = [
  ColumnDef(
    '_thumb',
    'Preview',
    kind: ColumnKind.thumb,
    flex: 1,
    sortable: false,
  ),
  ColumnDef('assettitle', 'Title', flex: 3),
  ColumnDef('name', 'File name', flex: 3),
  ColumnDef('filesize', 'Size', kind: ColumnKind.bytes, flex: 1),
  ColumnDef('assettype', 'Type', flex: 1),
  ColumnDef('editstatus', 'Status', flex: 1),
  ColumnDef('owner', 'Owner', flex: 1),
  ColumnDef('assetaddeddate', 'Added', kind: ColumnKind.date, flex: 1),
  ColumnDef('fileformat', 'Format', flex: 1),
  ColumnDef(
    'keywordsai',
    'AI tags',
    kind: ColumnKind.chips,
    flex: 3,
    sortable: false,
  ),
];

/// Columns hidden by default (still available in the column picker).
Set<String> defaultHidden(String moduleId, List<ColumnDef> all) =>
    moduleId == 'asset'
    ? {'owner', 'assetaddeddate', 'fileformat', 'keywordsai'}
    : {for (final c in all.skip(6)) c.id};

/// Builds the column set for a module from its field definitions, falling back to
/// the keys present in the results when definitions are not available.
List<ColumnDef> columnsFor(
  String moduleId,
  List<FieldDef> fields,
  List<Json> hits, {
  String lang = 'en',
}) {
  if (moduleId == 'asset') return _assetColumns;
  final present = <String>{for (final h in hits) ...h.keys};
  final cols = <ColumnDef>[
    const ColumnDef(
      '_thumb',
      'Preview',
      kind: ColumnKind.thumb,
      flex: 1,
      sortable: false,
    ),
    ColumnDef(
      'name',
      fields.where((f) => f.id == 'name').firstOrNull?.label(lang) ?? 'Name',
      flex: 3,
    ),
  ];
  final seen = {'name', '_thumb'};
  if (fields.isNotEmpty) {
    for (final f in fields) {
      if (seen.contains(f.id) ||
          systemFields.contains(f.id) ||
          f.internal ||
          f.isComplex)
        continue;
      if (!present.contains(f.id) &&
          !const {
            'keywords',
            'searchcategory',
            'entity_date',
            'longcaption',
          }.contains(f.id)) {
        continue;
      }
      seen.add(f.id);
      cols.add(
        ColumnDef(
          f.id,
          f.label(lang),
          kind: f.isDate
              ? ColumnKind.date
              : (f.isMulti ? ColumnKind.chips : ColumnKind.text),
          flex: f.isTextArea ? 3 : 2,
          sortable: !f.isMulti,
          field: f,
        ),
      );
    }
  } else {
    for (final k in present) {
      if (seen.contains(k) || systemFields.contains(k)) continue;
      seen.add(k);
      cols.add(ColumnDef(k, _humanize(k)));
    }
  }
  // Two fields can share a label (e.g. "Description"); tell them apart.
  final counts = <String, int>{};
  for (final c in cols) {
    counts[c.label] = (counts[c.label] ?? 0) + 1;
  }
  return [
    for (final c in cols)
      (counts[c.label] ?? 0) > 1 && c.id != 'name'
          ? ColumnDef(
              c.id,
              '${c.label} (${c.id})',
              kind: c.kind,
              flex: c.flex,
              sortable: c.sortable,
              field: c.field,
            )
          : c,
  ];
}

String _humanize(String id) {
  final s = id
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return s.isEmpty ? id : s[0].toUpperCase() + s.substring(1);
}
