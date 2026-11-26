
import 'package:eme_data_app/core/api_client.dart';
import 'package:eme_data_app/core/icons.dart';
import 'package:eme_data_app/core/values.dart';
import 'package:eme_data_app/data/models.dart';
import 'package:eme_data_app/data/repository.dart';
import 'package:eme_data_app/features/data/columns.dart';
import 'package:eme_data_app/features/record/field_inputs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eme_data_app/core/ph.dart';

void main() {
  group('values', () {
    test('localized picks language, falls back to en then first', () {
      expect(
        localized({'en': 'Articles', 'es': 'Artículos'}, 'es'),
        'Artículos',
      );
      expect(
        localized({'en': 'Articles', 'es': 'Artículos'}, 'fr'),
        'Articles',
      );
      expect(localized({'de': 'Kanal'}), 'Kanal');
      expect(localized({'id': 'photo', 'name': 'Photos'}), 'Photos');
      expect(localized({'id': 'x'}), 'x');
      expect(localized(null), '');
    });

    test('displayValue renders lists, booleans and ISO dates', () {
      expect(
        displayValue([
          {'id': 'a', 'name': 'A'},
          {'id': 'b', 'name': 'B'},
        ]),
        'A, B',
      );
      expect(displayValue('true'), 'Yes');
      expect(displayValue('2026-10-20T00:00:00.000Z'), isNot(contains('T')));
    });

    test('valueIds normalizes every serialized list shape', () {
      expect(valueIds('x'), ['x']);
      expect(valueIds({'id': 'x', 'name': 'X'}), ['x']);
      expect(
        valueIds([
          {'id': 'a'},
          'b',
        ]),
        ['a', 'b'],
      );
      expect(valueIds(null), isEmpty);
    });

    test('formatBytes', () {
      expect(formatBytes('694368'), '678.1 KB');
      expect(formatBytes(3177000), '3.03 MB');
      expect(formatBytes('nope'), '');
    });

    test('encodePath keeps slashes and escapes segments', () {
      expect(
        encodePath('Entity Asset/Cyber Basics.pdf'),
        'Entity%20Asset/Cyber%20Basics.pdf',
      );
    });

    test('module icons: appicon, then aliased moduleicon, then fallback', () {
      ModuleInfo m(Map<String, dynamic> raw) => ModuleInfo({'id': 'x', ...raw});
      expect(
        moduleIcon(m({'appicon': 'rocket', 'moduleicon': 'person'})),
        Ph.rocket,
      );
      expect(moduleIcon(m({'appicon': 'rocket'}), filled: true), PhFill.rocket);
      expect(moduleIcon(m({'moduleicon': 'person'})), Ph.user);
      expect(moduleIcon(m({'moduleicon': 'file-earmark-post'})), Ph.article);
      // An unknown appicon falls back to the legacy icon, then to the default.
      expect(
        moduleIcon(m({'appicon': 'nope', 'moduleicon': 'geo-alt'})),
        Ph.mapPin,
      );
      expect(moduleIcon(m({})), Ph.squaresFour);
      expect(phosphorIcon('arrow-u-down-left'), Ph.arrowUDownLeft);
    });
  });

  group('SearchQuery', () {
    test('defaults to a match-all term with string paging', () {
      final r = const SearchQuery().toRequest('asset');
      expect(r['page'], '1');
      expect(r['hitsperpage'], '36');
      expect((r['query'] as Map)['terms'], [
        {'field': 'id', 'operation': 'matches', 'value': '*'},
      ]);
    });

    test('text, folder, facets and sort', () {
      final r = const SearchQuery(
        text: 'laptop',
        categoryId: 'cat1',
        filters: {
          'assettype': {'photo'},
        },
        sortField: 'assettitle',
        sortAscending: false,
      ).toRequest('asset');
      final terms = (r['query'] as Map)['terms'] as List;
      expect(
        terms,
        contains(
          equals({
            'field': 'description',
            'operation': 'freeform',
            'value': 'laptop',
          }),
        ),
      );
      expect(
        terms,
        contains(
          equals({'field': 'category', 'operation': 'exact', 'value': 'cat1'}),
        ),
      );
      expect(
        terms,
        contains(
          equals({
            'field': 'assettype',
            'operation': 'orsgroup',
            'values': ['photo'],
          }),
        ),
      );
      expect(r['assetsortby'], 'assettitleDown');
    });

    test('equality ignores filter ordering', () {
      const a = SearchQuery(
        filters: {
          'x': {'1', '2'},
        },
      );
      const b = SearchQuery(
        filters: {
          'x': {'2', '1'},
        },
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ApiClient.decodeBody', () {
    test('parses the server text/json body', () {
      expect(
        ApiClient.decodeBody('\n{ "response": {"status":"ok"} }')?['response'],
        {'status': 'ok'},
      );
    });
    test('returns null for HTML error pages', () {
      expect(ApiClient.decodeBody('<!doctype html><html>404</html>'), isNull);
    });
  });

  group('FieldValue payload', () {
    FieldDef def(Map<String, dynamic> raw) => FieldDef(raw);

    test('multilanguage uses field.lang keys and clears removed languages', () {
      final v = FieldValue(def({'id': 'name', 'multilanguage': 'true'}), {
        'en': 'Test',
        'es': 'Prueba',
      });
      v.multilang!.remove('es');
      v.removedLanguages.add('es');
      expect(v.toPayload(), {'name.es': '', 'name.en': 'Test'});
    });

    test('lists send ids, multi lists send id arrays', () {
      final single = FieldValue(
        def({
          'id': 'emeprofiletype',
          'datatype': {'id': 'list'},
        }),
        {'id': 'a', 'name': 'A'},
      );
      expect(single.toPayload(), {'emeprofiletype': 'a'});
      expect(single.names['a'], 'A');
      final multi = FieldValue(
        def({
          'id': 'emeskillset',
          'datatype': {'id': 'list'},
          'rendertype': {'id': 'multiselect'},
        }),
        [
          {'id': 'x'},
          {'id': 'y'},
        ],
      );
      expect(multi.toPayload(), {
        'emeskillset': ['x', 'y'],
      });
    });

    test('booleans and dates', () {
      expect(
        FieldValue(
          def({
            'id': 'b',
            'datatype': {'id': 'boolean'},
          }),
          'true',
        ).toPayload(),
        {'b': 'true'},
      );
      final d = FieldValue(
        def({
          'id': 'd',
          'datatype': {'id': 'date'},
        }),
        '2026-10-20T18:00:00.000Z',
      );
      expect(d.toPayload()['d'], '2026-10-20T18:00:00.000Z');
    });

    test('a list field without listid uses its own id', () {
      expect(
        def({
          'id': 'emepersonality',
          'datatype': {'id': 'list'},
        }).listId,
        'emepersonality',
      );
    });
  });

  group('columns', () {
    test('entity columns skip system fields and keep the thumbnail first', () {
      final cols = columnsFor('emeprofile', [], [
        {
          'id': '1',
          'name': {'en': 'A'},
          'sourcepath': 'x',
          'jobtitle': 'Dev',
        },
      ]);
      expect(cols.first.kind, ColumnKind.thumb);
      expect(cols.map((c) => c.id), containsAll(['name', 'jobtitle']));
      expect(cols.map((c) => c.id), isNot(contains('sourcepath')));
    });
  });
}
