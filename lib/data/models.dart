import '../core/values.dart';

typedef Json = Map<String, dynamic>;

/// A row of the `module` table: one data entity type (EME Profile, Topics, ...).
class ModuleInfo {
  ModuleInfo(this.raw);
  final Json raw;

  String get id => '${raw['id']}';

  /// Display name. (`customname` is a template for naming records, e.g. "${data.firstName}", not a label.)
  String name([String lang = 'en']) {
    final n = localized(raw['name'], lang);
    return n.isNotEmpty ? n : id;
  }

  /// Legacy Bootstrap icon name (also used by the /site/find UI).
  String? get icon => raw['moduleicon'] as String?;

  /// Phosphor icon name for this app (e.g. `user-circle`); overrides [icon].
  String? get appIcon => raw['appicon'] as String?;
  bool get isEntity => raw['isentity'] == 'true';
  bool get showOnSearch => raw['showonsearch'] == 'true';
  bool get enableUploading => raw['enableuploading'] == 'true';
  String? get uploadSourcePath => raw['uploadsourcepath'] as String?;
  int get ordering => int.tryParse('${raw['ordering'] ?? ''}') ?? 1000;

  /// `table`, `brickvertical` or `gallery` from the server.
  String? get resultsView => (raw['moduleresultsview'] as Map?)?['id'] as String?;

  bool get isAsset => id == 'asset';
}

/// A top menu entry (`appsection` table).
class AppSection {
  AppSection({required this.moduleId, required this.name, required this.ordering});
  final String moduleId;
  final String name;
  final int ordering;

  factory AppSection.fromJson(Json j) => AppSection(
    moduleId: '${(j['toplevelentity'] as Map?)?['id'] ?? ''}',
    name: localized(j['name']).isNotEmpty ? localized(j['name']) : localized(j['toplevelentity']),
    ordering: int.tryParse('${j['ordering'] ?? ''}') ?? 1000,
  );
}

/// Field definition from `settings/datamanager/fields/listfields`.
class FieldDef {
  FieldDef(this.raw);
  final Json raw;

  String get id => '${raw['id']}';
  String label([String lang = 'en']) {
    final n = localized(raw['name'], lang);
    return n.isNotEmpty ? n : id;
  }

  String get datatype => '${(raw['datatype'] as Map?)?['id'] ?? 'text'}';
  String? get rendertype => (raw['rendertype'] as Map?)?['id'] as String?;

  /// EME convention: a list field without listid uses its own id as the list.
  String get listId => (raw['listid'] as String?)?.isNotEmpty == true ? raw['listid'] as String : id;
  bool get editable => raw['editable'] != 'false';
  bool get internal => raw['internalfield'] == 'true';
  bool get multilanguage => raw['multilanguage'] == 'true' || datatype == 'multilanguage';
  bool get isList => datatype == 'list';
  bool get isAssetRef => isList && listId == 'asset';
  bool get isCategory => isList && (listId == 'category' || rendertype == 'category');
  bool get isMulti =>
      raw['multiple'] == 'true' ||
      const {'multiselect', 'entity', 'tageditor'}.contains(rendertype) ||
      datatype == 'multi';
  bool get isTags => rendertype == 'tageditor' || id == 'keywords';
  bool get isDate => datatype == 'date' || rendertype == 'date';
  bool get isBoolean => datatype == 'boolean';
  bool get isNumber => const {'number', 'double', 'long', 'integer'}.contains(datatype);
  bool get isTextArea => rendertype == 'textarea' || rendertype == 'html';
  bool get isComplex => const {'nested', 'objectarray', 'object', 'json'}.contains(datatype);
}

class FacetOption {
  FacetOption(this.id, this.name, this.count);
  final String id;
  final String name;
  final int count;
}

class Facet {
  Facet(this.id, this.name, this.options);
  final String id;
  final String name;
  final List<FacetOption> options;

  factory Facet.fromJson(Json j) => Facet('${j['id']}', localized(j['name']), [
    for (final c in (j['children'] as List? ?? const []))
      if (c is Map)
        FacetOption(
          '${c['id']}',
          localized(c['name']).isNotEmpty ? localized(c['name']) : '${c['id']}',
          int.tryParse('${c['count'] ?? ''}') ?? 0,
        ),
  ]);
}

class SearchResult {
  SearchResult({
    required this.hits,
    required this.total,
    required this.page,
    required this.pages,
    required this.facets,
  });
  final List<Json> hits;
  final int total;
  final int page;
  final int pages;
  final List<Facet> facets;
}

class CategoryNode {
  CategoryNode({required this.id, required this.name, required this.path, required this.children});
  final String id;
  final String name;
  final String path;
  final List<CategoryNode> children;

  factory CategoryNode.fromJson(Json j) => CategoryNode(
    id: '${j['id']}',
    name: localized(j['name']),
    path: '${j['categorypath'] ?? ''}',
    children: [
      for (final c in (j['children'] as List? ?? const []))
        if (c is Map<String, dynamic>) CategoryNode.fromJson(c),
    ],
  );

  /// Depth-first search.
  CategoryNode? find(String id) {
    if (this.id == id) return this;
    for (final c in children) {
      final f = c.find(id);
      if (f != null) return f;
    }
    return null;
  }

  Iterable<CategoryNode> flatten() sync* {
    yield this;
    for (final c in children) {
      yield* c.flatten();
    }
  }
}

/// Record helpers shared by assets and entities.
extension RecordX on Json {
  String get id => '${this['id']}';

  String title([String lang = 'en']) {
    for (final k in ['assettitle', 'name', 'displayname', 'headline', 'title']) {
      final v = localized(this[k], lang);
      if (v.isNotEmpty) return v;
    }
    return id;
  }

  String? get sourcepath => this['sourcepath'] as String?;
}
