// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Script to identify good opportunities for null safety migration.
///
/// This script sorts libraries based on a "migratable" order. We compute
/// this order by counting how many of a library's dependencies have been
/// migrated.

import 'dart:io';

import 'package:_fe_analyzer_shared/src/messages/severity.dart' show Severity;
import 'package:_fe_analyzer_shared/src/parser/parser.dart';
import 'package:_fe_analyzer_shared/src/scanner/io.dart'
    show readBytesFromFileSync;
import 'package:_fe_analyzer_shared/src/scanner/scanner.dart';
import 'package:front_end/src/api_prototype/front_end.dart';
import 'package:front_end/src/api_prototype/language_version.dart';
import 'package:front_end/src/api_prototype/terminal_color_support.dart'
    show printDiagnosticMessage;
import 'package:front_end/src/base/processed_options.dart';
import 'package:front_end/src/fasta/compiler_context.dart';
import 'package:front_end/src/fasta/source/diet_parser.dart';
import 'package:front_end/src/fasta/source/directive_listener.dart';
import 'package:front_end/src/fasta/uri_translator.dart' show UriTranslator;
import 'package:kernel/target/targets.dart' show TargetFlags;
import 'package:vm/target/vm.dart' show VmTarget;

void main(List<String> args) async {
  var prefix = args.isEmpty ? 'pkg/compiler/' : args.first;
  var files = <Uri, List<int>>{};
  var isLegacy = <Uri>{};
  var isNullSafe = <Uri>{};

  var entryUri = Uri.parse('package:compiler/src/dart2js.dart');
  var options = CompilerOptions()
    ..sdkRoot = Uri.base.resolve("sdk/")
    ..onDiagnostic = _onDiagnosticMessageHandler
    ..compileSdk = true
    ..packagesFileUri = Uri.base.resolve('.dart_tool/package_config.json')
    ..target = VmTarget(TargetFlags());
  var pOptions = ProcessedOptions(options: options);
  var uriResolver = await pOptions.getUriTranslator();
  var context = CompilerContext(pOptions);
  await context.runInContext((_) async {
    collectSources(uriResolver, entryUri, files);
  });

  for (var file in files.keys) {
    if (await uriUsesLegacyLanguageVersion(file, options)) {
      isLegacy.add(file);
    } else {
      isNullSafe.add(file);
    }
  }

  var fileSummary = <Uri, FileData>{};
  for (var file in files.keys) {
    if (!file.path.contains(prefix)) continue;
    var directives = extractDirectiveUris(files[file]!)
        .map(file.resolve)
        .where((uri) => uri.path.contains('pkg/compiler/'));
    var migrated = directives.where(isNullSafe.contains).length;
    var total = directives.length;
    fileSummary[file] = FileData(isNullSafe.contains(file), total, migrated);
  }

  var keys = fileSummary.keys.toList();
  keys.sort((a, b) {
    var fa = fileSummary[a]!;
    var fb = fileSummary[b]!;
    if (fa.isNullSafe && !fb.isNullSafe) return -1;
    if (fb.isNullSafe && !fa.isNullSafe) return 1;
    if (fa.totalDependencies == 0 && fb.totalDependencies != 0) return -1;
    if (fb.totalDependencies == 0 && fa.totalDependencies != 0) return 1;
    if (fa.ratio != fb.ratio) return fb.ratio.compareTo(fa.ratio);
    return fb.migratedDependencies.compareTo(fb.migratedDependencies);
  });

  for (var file in keys) {
    var data = fileSummary[file]!;
    String status;
    String text = shorten(file);
    if (data.isNullSafe) {
      status = '\x1b[33mmigrated ---\x1b[0m | $text';
    } else if (data.totalDependencies == 0) {
      status = '\x1b[32mready    ---\x1b[0m | $text';
    } else if (data.ratio == 1.0) {
      status = '\x1b[32mready   100%\x1b[0m | $text';
    } else {
      var perc = (data.ratio * 100).toStringAsFixed(0).padLeft(3);
      status = '\x1b[31mwait    $perc%\x1b[0m'
          ' | $text [${data.migratedDependencies} / ${data.totalDependencies}]';
    }
    print(status);
  }
}

class FileData {
  final bool isNullSafe;
  final int totalDependencies;
  final int migratedDependencies;

  double get ratio => migratedDependencies / totalDependencies;
  FileData(this.isNullSafe, this.totalDependencies, this.migratedDependencies);
}

void _onDiagnosticMessageHandler(DiagnosticMessage m) {
  if (m.severity == Severity.internalProblem || m.severity == Severity.error) {
    printDiagnosticMessage(m, stderr.writeln);
    exitCode = 1;
  }
}

/// Add to [files] all sources reachable from [start].
void collectSources(
    UriTranslator uriResolver, Uri start, Map<Uri, List<int>> files) {
  void helper(Uri uri) {
    if (uri.scheme == 'dart') return;
    uri = uriResolver.translate(uri) ?? uri;
    if (!uri.path.contains('pkg/compiler/')) return;
    if (files.containsKey(uri)) return;
    var contents = readBytesFromFileSync(uri);
    files[uri] = contents;
    for (var directiveUri in extractDirectiveUris(contents)) {
      helper(uri.resolve(directiveUri));
    }
  }

  helper(start);
}

/// Parse [contents] as a Dart program and return the URIs that appear in its
/// import, export, and part directives.
Set<String> extractDirectiveUris(List<int> contents) {
  var listener = new DirectiveListener();
  new TopLevelParser(listener,
          useImplicitCreationExpression: useImplicitCreationExpressionInCfe)
      .parseUnit(scan(contents).tokens);
  // Note: this purposely ignores part files (listener.parts).
  return new Set<String>()
    ..addAll(listener.imports.map((directive) => directive.uri!))
    ..addAll(listener.exports.map((directive) => directive.uri!));
}

String shorten(Uri uri) {
  if (uri.scheme != 'file') return uri.toString();
  final prefix = Uri.base.path;
  if (uri.path.startsWith(prefix)) return uri.path.substring(prefix.length);
  return uri.toString();
}
