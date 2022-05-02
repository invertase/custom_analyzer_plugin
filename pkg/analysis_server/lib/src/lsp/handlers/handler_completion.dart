// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math' as math;

import 'package:analysis_server/lsp_protocol/protocol_custom_generated.dart';
import 'package:analysis_server/lsp_protocol/protocol_generated.dart';
import 'package:analysis_server/lsp_protocol/protocol_special.dart';
import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:analysis_server/src/domains/completion/available_suggestions.dart';
import 'package:analysis_server/src/lsp/client_capabilities.dart';
import 'package:analysis_server/src/lsp/handlers/handlers.dart';
import 'package:analysis_server/src/lsp/lsp_analysis_server.dart';
import 'package:analysis_server/src/lsp/mapping.dart';
import 'package:analysis_server/src/provisional/completion/completion_core.dart';
import 'package:analysis_server/src/services/completion/completion_performance.dart';
import 'package:analysis_server/src/services/completion/dart/completion_manager.dart';
import 'package:analysis_server/src/services/completion/filtering/fuzzy_matcher.dart';
import 'package:analysis_server/src/services/completion/yaml/analysis_options_generator.dart';
import 'package:analysis_server/src/services/completion/yaml/fix_data_generator.dart';
import 'package:analysis_server/src/services/completion/yaml/pubspec_generator.dart';
import 'package:analysis_server/src/services/completion/yaml/yaml_completion_generator.dart';
import 'package:analysis_server/src/services/snippets/dart/snippet_manager.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/source/line_info.dart';
import 'package:analyzer/src/services/available_declarations.dart';
import 'package:analyzer/src/util/file_paths.dart' as file_paths;
import 'package:analyzer/src/util/performance/operation_performance.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as plugin;
import 'package:analyzer_plugin/src/utilities/completion/completion_target.dart';

class CompletionHandler extends MessageHandler<CompletionParams, CompletionList>
    with LspPluginRequestHandlerMixin {
  /// Whether to include symbols from libraries that have not been imported.
  final bool suggestFromUnimportedLibraries;

  CompletionHandler(super.server, LspInitializationOptions options)
      : suggestFromUnimportedLibraries = options.suggestFromUnimportedLibraries;

  @override
  Method get handlesMessage => Method.textDocument_completion;

  @override
  LspJsonHandler<CompletionParams> get jsonHandler =>
      CompletionParams.jsonHandler;

  @override
  Future<ErrorOr<CompletionList>> handle(CompletionParams params,
      MessageInfo message, CancellationToken token) async {
    final clientCapabilities = server.clientCapabilities;
    if (clientCapabilities == null) {
      // This should not happen unless a client misbehaves.
      return serverNotInitializedError;
    }

    final requestLatency = message.timeSinceRequest;
    final triggerCharacter = params.context?.triggerCharacter;
    final pos = params.position;
    final path = pathOfDoc(params.textDocument);

    // IMPORTANT:
    // This handler is frequently called while the user is typing, which means
    // during any `await` there is a good chance of the file contents being
    // updated, but we must return results consistent with the file at the time
    // this request started so that the client can compensate for any typing
    // in the meantime.
    //
    // To do this, tell the server to lock requests until we have a resolved
    // unit and LineInfo.
    late ErrorOr<LineInfo> lineInfo;
    late ErrorOr<ResolvedUnitResult> unit;
    await server.lockRequestsWhile(() async {
      unit = await path.mapResult(requireResolvedUnit);
      lineInfo = await unit.map(
        // If we don't have a unit, we can still try to obtain the line info from
        // the server (this could be because the file is non-Dart, such as YAML or
        // another handled by a plugin).
        (error) => path.mapResult(getLineInfo),
        (unit) => success(unit.lineInfo),
      );
    });

    if (token.isCancellationRequested) {
      return cancelled();
    }

    // Map the offset, propagating the previous failure if we didn't have a
    // valid LineInfo.
    final offsetResult = !lineInfo.isError
        ? toOffset(lineInfo.result, pos)
        : failure<int>(lineInfo);

    if (offsetResult.isError) {
      return failure(offsetResult);
    }
    final offset = offsetResult.result;

    Future<ErrorOr<CompletionList>>? serverResultsFuture;
    final pathContext = server.resourceProvider.pathContext;
    final fileExtension = pathContext.extension(path.result);

    final maxResults =
        server.clientConfiguration.forResource(path.result).maxCompletionItems;

    CompletionPerformance? completionPerformance;
    if (fileExtension == '.dart' && !unit.isError) {
      final result = unit.result;
      var performance = OperationPerformanceImpl('<root>');
      serverResultsFuture = performance.runAsync(
        'request',
        (performance) async {
          final thisPerformance = CompletionPerformance(
            operation: performance,
            path: result.path,
            requestLatency: requestLatency,
            content: result.content,
            offset: offset,
          );
          completionPerformance = thisPerformance;
          server.performanceStats.completion.add(thisPerformance);

          // `await` required for `performance.runAsync` to count time.
          return await _getServerDartItems(
            clientCapabilities,
            unit.result,
            thisPerformance,
            performance,
            offset,
            triggerCharacter,
            token,
          );
        },
      );
    } else if (fileExtension == '.yaml') {
      YamlCompletionGenerator? generator;
      if (file_paths.isAnalysisOptionsYaml(pathContext, path.result)) {
        generator = AnalysisOptionsGenerator(server.resourceProvider);
      } else if (file_paths.isFixDataYaml(pathContext, path.result)) {
        generator = FixDataGenerator(server.resourceProvider);
      } else if (file_paths.isPubspecYaml(pathContext, path.result)) {
        generator =
            PubspecGenerator(server.resourceProvider, server.pubPackageService);
      }
      if (generator != null) {
        serverResultsFuture = _getServerYamlItems(
          generator,
          clientCapabilities,
          path.result,
          lineInfo.result,
          offset,
          token,
        );
      }
    }

    serverResultsFuture ??=
        Future.value(success(CompletionList(isIncomplete: false, items: [])));

    final pluginResultsFuture = _getPluginResults(
        clientCapabilities, lineInfo.result, path.result, offset);

    // Await both server + plugin results together to allow async/IO to
    // overlap.
    final serverAndPluginResults =
        await Future.wait([serverResultsFuture, pluginResultsFuture]);
    final serverResults = serverAndPluginResults[0];
    final pluginResults = serverAndPluginResults[1];

    if (serverResults.isError) return serverResults;
    if (pluginResults.isError) return pluginResults;

    final untruncatedItems = serverResults.result.items
        .followedBy(pluginResults.result.items)
        .toList();

    final truncatedItems = untruncatedItems.length > maxResults
        ? (untruncatedItems..sort(sortTextComparer)).sublist(0, maxResults)
        : untruncatedItems;

    // If we're tracing performance (only Dart), record the number of results
    // after truncation.
    completionPerformance?.transmittedSuggestionCount = truncatedItems.length;

    return success(CompletionList(
      // If any set of the results is incomplete, the whole batch must be
      // marked as such.
      isIncomplete: serverResults.result.isIncomplete ||
          pluginResults.result.isIncomplete ||
          truncatedItems.length != untruncatedItems.length,
      items: truncatedItems,
    ));
  }

  /// Build a list of existing imports so we can filter out any suggestions
  /// that resolve to the same underlying declared symbol.
  /// Map with key "elementName/elementDeclaringLibraryUri"
  /// Value is a set of imported URIs that import that element.
  Map<String, Set<String>> _buildLookupOfImportedSymbols(
      ResolvedUnitResult unit) {
    final alreadyImportedSymbols = <String, Set<String>>{};
    final importElementList = unit.libraryElement.imports;
    for (var import in importElementList) {
      final importedLibrary = import.importedLibrary;
      if (importedLibrary == null) continue;

      for (var element in import.namespace.definedNames.values) {
        final librarySource = element.librarySource;
        final elementName = element.name;
        if (librarySource != null && elementName != null) {
          final declaringLibraryUri = librarySource.uri;

          final key =
              _createImportedSymbolKey(elementName, declaringLibraryUri);
          alreadyImportedSymbols
              .putIfAbsent(key, () => <String>{})
              .add('${importedLibrary.librarySource.uri}');
        }
      }
    }
    return alreadyImportedSymbols;
  }

  /// The insert length is the shorter of the replacementLength or the
  /// difference between the replacementOffset and the caret position.
  int _computeInsertLength(
      int offset, int replacementOffset, int replacementLength) {
    final insertLength =
        math.min(offset - replacementOffset, replacementLength);
    assert(insertLength >= 0);
    assert(insertLength <= replacementLength);
    return insertLength;
  }

  String _createImportedSymbolKey(String name, Uri declaringUri) =>
      '$name/$declaringUri';

  Future<List<CompletionItem>> _getDartSnippetItems({
    required LspClientCapabilities clientCapabilities,
    required ResolvedUnitResult unit,
    required int offset,
    required LineInfo lineInfo,
  }) async {
    final request = DartSnippetRequest(
      unit: unit,
      offset: offset,
    );
    final snippetManager = DartSnippetManager();
    final snippets = await snippetManager.computeSnippets(request);

    return snippets
        .map((snippet) => snippetToCompletionItem(
              server,
              clientCapabilities,
              unit.path,
              lineInfo,
              toPosition(lineInfo.getLocation(offset)),
              snippet,
            ))
        .toList();
  }

  Future<ErrorOr<CompletionList>> _getPluginResults(
    LspClientCapabilities capabilities,
    LineInfo lineInfo,
    String path,
    int offset,
  ) async {
    final requestParams = plugin.CompletionGetSuggestionsParams(path, offset);
    final pluginResponses = await requestFromPlugins(path, requestParams,
        timeout: const Duration(milliseconds: 100));

    final pluginResults = pluginResponses
        .map((e) => plugin.CompletionGetSuggestionsResult.fromResponse(e))
        .toList();

    return success(CompletionList(
      isIncomplete: false,
      items: _pluginResultsToItems(
        capabilities,
        lineInfo,
        offset,
        pluginResults,
      ).toList(),
    ));
  }

  Future<ErrorOr<CompletionList>> _getServerDartItems(
    LspClientCapabilities capabilities,
    ResolvedUnitResult unit,
    CompletionPerformance completionPerformance,
    OperationPerformanceImpl performance,
    int offset,
    String? triggerCharacter,
    CancellationToken token,
  ) async {
    final useSuggestionSets =
        suggestFromUnimportedLibraries && capabilities.applyEdit;

    final completionRequest = DartCompletionRequest.forResolvedUnit(
      resolvedUnit: unit,
      offset: offset,
      dartdocDirectiveInfo: server.getDartdocDirectiveInfoFor(unit),
      completionPreference: CompletionPreference.replace,
    );
    final target = completionRequest.target;

    if (triggerCharacter != null) {
      if (!_triggerCharacterValid(offset, triggerCharacter, target)) {
        return success(CompletionList(isIncomplete: false, items: []));
      }
    }

    Set<ElementKind>? includedElementKinds;
    Set<String>? includedElementNames;
    List<IncludedSuggestionRelevanceTag>? includedSuggestionRelevanceTags;
    if (useSuggestionSets) {
      includedElementKinds = <ElementKind>{};
      includedElementNames = <String>{};
      includedSuggestionRelevanceTags = <IncludedSuggestionRelevanceTag>[];
    }

    try {
      final serverSuggestions2 =
          await performance.runAsync('computeSuggestions', (performance) async {
        var contributor = DartCompletionManager(
          budget: CompletionBudget(CompletionBudget.defaultDuration),
          includedElementKinds: includedElementKinds,
          includedElementNames: includedElementNames,
          includedSuggestionRelevanceTags: includedSuggestionRelevanceTags,
        );

        // `await` required for `performance.runAsync` to count time.
        return await contributor.computeSuggestions(
          completionRequest,
          performance,
        );
      });

      final serverSuggestions =
          performance.run('buildSuggestions', (performance) {
        return serverSuggestions2
            .map((serverSuggestion) => serverSuggestion.build())
            .toList();
      });

      final insertLength = _computeInsertLength(
        offset,
        completionRequest.replacementOffset,
        completionRequest.replacementLength,
      );

      if (token.isCancellationRequested) {
        return cancelled();
      }

      /// completeFunctionCalls should be suppressed if the target is an
      /// invocation that already has an argument list, otherwise we would
      /// insert dupes.
      final completeFunctionCalls = _hasExistingArgList(target.entity)
          ? false
          : server.clientConfiguration.global.completeFunctionCalls;

      final results = performance.run('mapSuggestions', (performance) {
        return serverSuggestions.map(
          (item) {
            var itemReplacementOffset =
                item.replacementOffset ?? completionRequest.replacementOffset;
            var itemReplacementLength =
                item.replacementLength ?? completionRequest.replacementLength;
            var itemInsertLength = insertLength;

            // Recompute the insert length if it may be affected by the above.
            if (item.replacementOffset != null ||
                item.replacementLength != null) {
              itemInsertLength = _computeInsertLength(
                  offset, itemReplacementOffset, itemInsertLength);
            }

            // Convert to LSP ranges using the LineInfo.
            Range? replacementRange = toRange(
                unit.lineInfo, itemReplacementOffset, itemReplacementLength);
            Range? insertionRange =
                toRange(unit.lineInfo, itemReplacementOffset, itemInsertLength);

            return toCompletionItem(
              capabilities,
              unit.lineInfo,
              item,
              replacementRange: replacementRange,
              insertionRange: insertionRange,
              // TODO(dantup): Move commit characters to the main response
              // and remove from each individual item (to reduce payload size)
              // once the following change ships (and the Dart VS Code
              // extension is updated to use it).
              // https://github.com/microsoft/vscode-languageserver-node/issues/673
              includeCommitCharacters:
                  server.clientConfiguration.global.previewCommitCharacters,
              completeFunctionCalls: completeFunctionCalls,
            );
          },
        ).toList();
      });

      // Now compute items in suggestion sets.
      var includedSuggestionSets = <IncludedSuggestionSet>[];
      final declarationsTracker = server.declarationsTracker;
      if (declarationsTracker != null &&
          includedElementKinds != null &&
          includedElementNames != null &&
          includedSuggestionRelevanceTags != null) {
        performance.run('computeIncludedSetList', (performance) {
          // Checked in `if` above.
          includedElementNames!;

          computeIncludedSetList(
            declarationsTracker,
            completionRequest,
            includedSuggestionSets,
            includedElementNames,
          );
        });

        // Build a fast lookup for imported symbols so that we can filter out
        // duplicates.
        final alreadyImportedSymbols = _buildLookupOfImportedSymbols(unit);

        performance.run('addIncludedSuggestionSets', (performance) {
          // Checked in `if` above.
          includedSuggestionRelevanceTags!;

          for (var includedSet in includedSuggestionSets) {
            final library = declarationsTracker.getLibrary(includedSet.id);
            if (library == null) {
              break;
            }

            // Make a fast lookup for tag relevance.
            final tagBoosts = <String, int>{};
            for (var t in includedSuggestionRelevanceTags) {
              tagBoosts[t.tag] = t.relevanceBoost;
            }

            // Only specific types of child declarations should be included.
            // This list matches what's in _protocolAvailableSuggestion in
            // the DAS implementation.
            bool shouldIncludeChild(Declaration child) =>
                child.kind == DeclarationKind.CONSTRUCTOR ||
                child.kind == DeclarationKind.ENUM_CONSTANT ||
                (child.kind == DeclarationKind.GETTER && child.isStatic) ||
                (child.kind == DeclarationKind.FIELD && child.isStatic);

            // Collect declarations and their children.
            final allDeclarations = library.declarations
                .followedBy(library.declarations
                    .expand((decl) => decl.children.where(shouldIncludeChild)))
                .toList();

            final setResults = allDeclarations
                // Filter to only the kinds we should return.
                .where((item) => includedElementKinds!
                    .contains(protocolElementKind(item.kind)))
                .where((item) {
              // Check existing imports to ensure we don't already import
              // this element (this exact element from its declaring
              // library, not just something with the same name). If we do
              // we'll want to skip it.
              final declaringUri =
                  item.parent?.locationLibraryUri ?? item.locationLibraryUri!;

              // For enums and named constructors, only the parent enum/class is in
              // the list of imported symbols so we use the parents name.
              final nameKey = item.kind == DeclarationKind.ENUM_CONSTANT ||
                      item.kind == DeclarationKind.CONSTRUCTOR
                  ? item.parent!.name
                  : item.name;
              final key = _createImportedSymbolKey(nameKey, declaringUri);
              final importingUris = alreadyImportedSymbols[key];

              // Keep it only if:
              // - no existing imports include it
              //     (in which case all libraries will be offered as
              //     auto-imports)
              // - this is the first imported URI that includes it
              //     (we don't want to repeat it for each imported library that
              //     includes it)
              return importingUris == null ||
                  importingUris.first == '${library.uri}';
            }).map((item) => declarationToCompletionItem(
                      capabilities,
                      unit.path,
                      offset,
                      includedSet,
                      library,
                      tagBoosts,
                      unit.lineInfo,
                      item,
                      completionRequest.replacementOffset,
                      insertLength,
                      completionRequest.replacementLength,
                      // TODO(dantup): Move commit characters to the main response
                      // and remove from each individual item (to reduce payload size)
                      // once the following change ships (and the Dart VS Code
                      // extension is updated to use it).
                      // https://github.com/microsoft/vscode-languageserver-node/issues/673
                      includeCommitCharacters: server
                          .clientConfiguration.global.previewCommitCharacters,
                      completeFunctionCalls: completeFunctionCalls,
                    ));
            results.addAll(setResults);
          }
        });
      }

      // Add in any snippets.
      final snippetsEnabled =
          server.clientConfiguration.forResource(unit.path).enableSnippets;
      // We can only produce edits with edit builders for files inside
      // the root, so skip snippets entirely if not.
      final isEditableFile =
          unit.session.analysisContext.contextRoot.isAnalyzed(unit.path);
      if (capabilities.completionSnippets &&
          snippetsEnabled &&
          isEditableFile) {
        await performance.runAsync('addSnippets', (performance) async {
          results.addAll(await _getDartSnippetItems(
            clientCapabilities: capabilities,
            unit: unit,
            offset: offset,
            lineInfo: unit.lineInfo,
          ));
        });
      }

      // Perform fuzzy matching based on the identifier in front of the caret to
      // reduce the size of the payload.
      final matchingResults = performance.run('fuzzyFilter', (performance) {
        final fuzzyPattern = completionRequest.targetPrefix;
        final fuzzyMatcher =
            FuzzyMatcher(fuzzyPattern, matchStyle: MatchStyle.TEXT);

        return results
            .where((e) => fuzzyMatcher.score(e.filterText ?? e.label) > 0)
            .toList();
      });

      // Transmitted count will be set after combining with plugins.
      completionPerformance.computedSuggestionCount = matchingResults.length;

      return success(
          CompletionList(isIncomplete: false, items: matchingResults));
    } on AbortCompletion {
      return success(CompletionList(isIncomplete: false, items: []));
    } on InconsistentAnalysisException {
      return success(CompletionList(isIncomplete: false, items: []));
    }
  }

  Future<ErrorOr<CompletionList>> _getServerYamlItems(
    YamlCompletionGenerator generator,
    LspClientCapabilities capabilities,
    String path,
    LineInfo lineInfo,
    int offset,
    CancellationToken token,
  ) async {
    final suggestions = generator.getSuggestions(path, offset);
    final insertLength = _computeInsertLength(
      offset,
      suggestions.replacementOffset,
      suggestions.replacementLength,
    );
    final replacementRange = toRange(
        lineInfo, suggestions.replacementOffset, suggestions.replacementLength);
    final insertionRange =
        toRange(lineInfo, suggestions.replacementOffset, insertLength);

    final completionItems = suggestions.suggestions
        .map(
          (item) => toCompletionItem(
            capabilities,
            lineInfo,
            item,
            replacementRange: replacementRange,
            insertionRange: insertionRange,
            includeCommitCharacters: false,
            completeFunctionCalls: false,
            // Add on any completion-kind-specific resolution data that will be
            // used during resolve() calls to provide additional information.
            resolutionData: item.kind == CompletionSuggestionKind.PACKAGE_NAME
                ? PubPackageCompletionItemResolutionInfo(
                    // The completion for package names may contain a trailing
                    // ': ' for convenience, so if it's there, trim it off.
                    packageName: item.completion.split(':').first,
                  )
                : null,
          ),
        )
        .toList();
    return success(CompletionList(isIncomplete: false, items: completionItems));
  }

  /// Returns true if [node] is part of an invocation and already has an argument
  /// list.
  bool _hasExistingArgList(Object? node) {
    // print^('foo');
    if (node is ast.ExpressionStatement) {
      node = node.expression;
    }
    // super.foo^();
    if (node is ast.SimpleIdentifier) {
      node = node.parent;
    }
    // new Aaaa.bar^()
    if (node is ast.ConstructorName) {
      node = node.parent;
    }
    return (node is ast.InvocationExpression &&
            !node.argumentList.beginToken.isSynthetic) ||
        (node is ast.InstanceCreationExpression &&
            !node.argumentList.beginToken.isSynthetic) ||
        // "ClassName.^()" will appear as accessing a property named '('.
        (node is ast.PropertyAccess && node.propertyName.name.startsWith('('));
  }

  Iterable<CompletionItem> _pluginResultsToItems(
    LspClientCapabilities capabilities,
    LineInfo lineInfo,
    int offset,
    List<plugin.CompletionGetSuggestionsResult> pluginResults,
  ) {
    return pluginResults.expand((result) {
      final insertLength = _computeInsertLength(
        offset,
        result.replacementOffset,
        result.replacementLength,
      );
      final replacementRange =
          toRange(lineInfo, result.replacementOffset, result.replacementLength);
      final insertionRange =
          toRange(lineInfo, result.replacementOffset, insertLength);

      return result.results.map(
        (item) => toCompletionItem(
          capabilities,
          lineInfo,
          item,
          replacementRange: replacementRange,
          insertionRange: insertionRange,
          // Plugins cannot currently contribute commit characters and we should
          // not assume that the Dart ones would be correct for all of their
          // completions.
          includeCommitCharacters: false,
          completeFunctionCalls: false,
        ),
      );
    });
  }

  /// Checks whether the given [triggerCharacter] is valid for [target].
  ///
  /// Some trigger characters are only valid in certain locations, for example
  /// a single quote ' is valid to trigger completion after typing an import
  /// statement, but not when terminating a string. The client has no context
  /// and sends the requests unconditionally.
  bool _triggerCharacterValid(
      int offset, String triggerCharacter, CompletionTarget target) {
    final node = target.containingNode;

    switch (triggerCharacter) {
      // For quotes, it's only valid if we're right after the opening quote of a
      // directive.
      case '"':
      case "'":
        return node is ast.SimpleStringLiteral &&
            node.parent is ast.Directive &&
            offset == node.contentsOffset;
      // Braces only for starting interpolated expressions.
      case '{':
        return node is ast.InterpolationExpression &&
            node.expression.offset == offset;
      // Slashes only as path separators in directives.
      case '/':
        return node is ast.SimpleStringLiteral &&
            node.parent is ast.Directive &&
            offset >= node.contentsOffset &&
            offset <= node.contentsEnd;
    }

    return true; // Any other trigger character can be handled always.
  }

  /// Compares [CompletionItem]s by the `sortText` field, which is derived from
  /// relevance.
  ///
  /// For items with the same relevance, shorter items are sorted first so that
  /// truncation always removes longer items first (which can be included by
  /// typing more of their characters).
  static int sortTextComparer(CompletionItem item1, CompletionItem item2) {
    // Note: It should never be the case that we produce items without sortText
    // but if they're null, fall back to label which is what the client would do
    // when sorting.
    final item1Text = item1.sortText ?? item1.label;
    final item2Text = item2.sortText ?? item2.label;

    // If both items have the same text, this means they had the same relevance.
    // In this case, sort by the length of the name ascending, so that shorter
    // items are first. This is because longer items can be obtained by typing
    // additional characters where shorter ones may not.
    //
    // For example, with:
    //   - String aaa1;
    //   - String aaa2;
    //   - ...
    //   - String aaa(N); // up to past the truncation amount
    //   - String aaa;    // declared last, same prefix
    //
    // Typing 'aaa' should not allow 'aaa' to be truncated before 'aaa1'.
    if (item1Text == item2Text) {
      return item1.label.length.compareTo(item2.label.length);
    }

    return item1Text.compareTo(item2Text);
  }
}
