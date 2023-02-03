import 'dart:convert';
import 'dart:io';

import 'package:maxminddb/src/database.dart';
import 'package:test/test.dart';

void main() async {
  final databases = [
    {
      'name': 'MaxMind-DB-test-ipv4-24.mmdb',
      'major_version': 2,
      'minor_version': 0,
      'build_epoch': 1628006507,
      'type': 'Test',
      'description': {'en': 'Test Database', 'zh': 'Test Database Chinese'},
      'ip_version': 4,
      'languages': ['en', 'zh'],
      'node_count': 164,
      'record_size': 24,
      'containing_addresses': ['1.1.1.1'],
      'missing_addresses': ['8.8.8.8'],
    },
    {
      'name': 'MaxMind-DB-test-ipv4-28.mmdb',
      'major_version': 2,
      'minor_version': 0,
      'build_epoch': 1628006507,
      'type': 'Test',
      'description': {'en': 'Test Database', 'zh': 'Test Database Chinese'},
      'ip_version': 4,
      'languages': ['en', 'zh'],
      'node_count': 164,
      'record_size': 28,
      'containing_addresses': ['1.1.1.1'],
      'missing_addresses': ['8.8.8.8'],
    },
    {
      'name': 'MaxMind-DB-test-ipv4-32.mmdb',
      'major_version': 2,
      'minor_version': 0,
      'build_epoch': 1628006507,
      'type': 'Test',
      'description': {'en': 'Test Database', 'zh': 'Test Database Chinese'},
      'ip_version': 4,
      'languages': ['en', 'zh'],
      'node_count': 164,
      'record_size': 32,
      'containing_addresses': ['1.1.1.1'],
      'missing_addresses': ['8.8.8.8'],
    },
    {
      'name': 'MaxMind-DB-test-ipv6-24.mmdb',
      'major_version': 2,
      'minor_version': 0,
      'build_epoch': 1628006507,
      'type': 'Test',
      'description': {'en': 'Test Database', 'zh': 'Test Database Chinese'},
      'ip_version': 6,
      'languages': ['en', 'zh'],
      'node_count': 416,
      'record_size': 24,
      'containing_addresses': ['::2:0:58', '::1:ffff:ffff'],
      'missing_addresses': ['2001:1:2::'],
    },
    {
      'name': 'MaxMind-DB-test-ipv6-28.mmdb',
      'major_version': 2,
      'minor_version': 0,
      'build_epoch': 1628006507,
      'type': 'Test',
      'description': {'en': 'Test Database', 'zh': 'Test Database Chinese'},
      'ip_version': 6,
      'languages': ['en', 'zh'],
      'node_count': 416,
      'record_size': 28,
      'containing_addresses': ['::2:0:58', '::1:ffff:ffff'],
      'missing_addresses': ['2001:1:2::'],
    },
    {
      'name': 'MaxMind-DB-test-ipv6-32.mmdb',
      'major_version': 2,
      'minor_version': 0,
      'build_epoch': 1628006507,
      'type': 'Test',
      'description': {'en': 'Test Database', 'zh': 'Test Database Chinese'},
      'ip_version': 6,
      'languages': ['en', 'zh'],
      'node_count': 416,
      'record_size': 32,
      'containing_addresses': ['::2:0:58', '::1:ffff:ffff'],
      'missing_addresses': ['2001:1:2::'],
    },
  ];

  await Future.wait(
    databases.map((e) async {
      if (!await File(e['name']! as String).exists()) {
        await downloadDatabase(e['name']! as String);
      }
    }),
  );

  for (final databaseData in databases) {
    final databaseMemory = await MaxMindDatabase.memory(
      File(databaseData['name']! as String).readAsBytesSync(),
    );
    final databaseFile =
        await MaxMindDatabase.file(File(databaseData['name']! as String));
    for (final database in [databaseMemory, databaseFile]) {
      test(
          'Test ${databaseData['name']} metadata using ${database.data.runtimeType}',
          () {
        expect(
          database.binaryFormatMajorVersion,
          databaseData['major_version'],
        );
        expect(
          database.binaryFormatMinorVersion,
          databaseData['minor_version'],
        );
        expect(database.buildEpoch, databaseData['build_epoch']);
        expect(
          jsonEncode(database.databaseType),
          jsonEncode(databaseData['type']),
        );
        expect(
          jsonEncode(database.description),
          jsonEncode(databaseData['description']),
        );
        expect(database.ipVersion, databaseData['ip_version']);
        expect(
          jsonEncode(database.languages),
          jsonEncode(databaseData['languages']),
        );
        expect(database.nodeCount, databaseData['node_count']);
        expect(database.recordSize, databaseData['record_size']);
      });

      test(
          'Test ${databaseData['name']} search using ${database.data.runtimeType}',
          () async {
        for (final address
            in databaseData['containing_addresses']! as List<String>) {
          expect(
            jsonEncode(await database.search(address)),
            jsonEncode({'ip': address}),
          );
        }
        for (final address
            in databaseData['missing_addresses']! as List<String>) {
          expect(await database.search(address), null);
        }
        if (database.ipVersion == 4) {
          expect(
            () => database.search('::'),
            throwsA(
              predicate(
                (e) =>
                    e is Exception &&
                    e.toString() ==
                        "Exception: An IPv6 address can't be processed by this IPv4 database.",
              ),
            ),
          );
        }
      });
    }
  }

  final cityDatabase = File('GeoLite2-City.mmdb');
  test(
    'Test double and location',
    () async {
      if (await cityDatabase.exists()) {
        final database = await MaxMindDatabase.file(cityDatabase);
        expect(
          (((await database.search('8.8.8.8'))
                  as Map<String, dynamic>?)?['location']
              as Map<String, dynamic>?)?['latitude'],
          37.751,
        );
        expect(
          (((await database.search('8.8.8.8'))
                  as Map<String, dynamic>?)?['location']
              as Map<String, dynamic>?)?['longitude'],
          -97.822,
        );
      }
    },
    skip: !await cityDatabase.exists(),
  );
}

Future<void> downloadDatabase(String name) async {
  final request = await HttpClient().getUrl(
    Uri.parse(
      'https://raw.githubusercontent.com/maxmind/MaxMind-DB/2bf1713b3b5adcb022cf4bb77eb0689beaadcfef/test-data/$name',
    ),
  );
  final response = await request.close();
  await response.pipe(File(name).openWrite());
}
