// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:extendedip/extendedip.dart';
import 'package:maxminddb/maxminddb.dart';

void main(List<String> args) {
  CommandRunner(
    "maxminddb",
    "A dart tool for working with MAXMINDs mmdb databases.",
  )
    ..addCommand(SearchCommand())
    ..run(args);
}

class SearchCommand extends Command {
  @override
  final name = "search";
  @override
  final description = "Search in a MAXMIND mmdb databases.";

  @override
  String get invocation => "${super.invocation} <search> [<search> ...]";

  SearchCommand() {
    argParser
      ..addFlag(
        "memory",
        abbr: "m",
        help: "Load the database to memory",
      )
      ..addOption(
        "database",
        abbr: "d",
        help: "The Database file.",
        defaultsTo: "GeoLite2-City.mmdb",
        valueHelp: "/path/to/database/DATABASE.mmdb",
      )
      ..addOption(
        "output",
        abbr: "o",
        aliases: ["out"],
        allowed: ["plain", "json"],
        help: "The output format",
        defaultsTo: "plain",
      );
  }

  @override
  Future<void> run() async {
    late MaxMindDatabase database;

    final databaseFile = File(argResults!["database"] as String);
    if (!await databaseFile.exists()) {
      stderr.writeln("The file ${databaseFile.absolute.path} doesn't exist.");
      exit(-1);
    }

    if (argResults?["memory"] == true) {
      database = await MaxMindDatabase.memory(
        databaseFile.readAsBytesSync(),
      );
    } else {
      database = await MaxMindDatabase.file(databaseFile);
    }

    try {
      final results = {
        for (var search in argResults!.rest)
          search: await () async {
            try {
              return await database.search(search);
            } catch (error) {
              throw "Failed to search $search: $error";
            }
          }()
      };

      switch (argResults!["output"]) {
        case "json":
          stdout.writeln(jsonEncode(results));
          break;
        case "plain":
        default:
          for (final e in results.entries) {
            stdout.writeln("${e.key}: ${e.value}");
          }
      }
    } catch (e) {
      stderr.writeln(e);
      exit(-1);
    }
  }
}
