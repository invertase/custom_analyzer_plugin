// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/summary2/macro_application_error.dart';
import 'package:analyzer/src/test_utilities/package_config_file_builder.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'element_text.dart';
import 'elements_base.dart';
import 'macros_environment.dart';

main() {
  try {
    MacrosEnvironment.instance;
  } catch (_) {
    print('Cannot initialize environment. Skip macros tests.');
    test('fake', () {});
    return;
  }

  defineReflectiveSuite(() {
    defineReflectiveTests(MacroElementsKeepLinkingTest);
    defineReflectiveTests(MacroElementsFromBytesTest);
  });
}

@reflectiveTest
class MacroElementsFromBytesTest extends MacroElementsTest {
  @override
  bool get keepLinkingLibraries => false;
}

@reflectiveTest
class MacroElementsKeepLinkingTest extends MacroElementsTest {
  @override
  bool get keepLinkingLibraries => true;
}

class MacroElementsTest extends ElementsBaseTest {
  @override
  bool get keepLinkingLibraries => false;

  /// The path for external packages.
  String get packagesRootPath => '/packages';

  /// Return the code for `DeclarationTextMacro`.
  String get _declarationTextCode {
    var code = MacrosEnvironment.instance.packageAnalyzerFolder
        .getChildAssumingFile('test/src/summary/macro/declaration_text.dart')
        .readAsStringSync();
    return code.replaceAll('/*macro*/', 'macro');
  }

  Future<void> setUp() async {
    writeTestPackageConfig(
      PackageConfigFileBuilder(),
      macrosEnvironment: MacrosEnvironment.instance,
    );
  }

  test_application_getter_withoutPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'dart:async';
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassTypesMacro {
  FutureOr<void> buildTypesForClass(clazz, builder) {
    builder.declareType(
      'MyClass',
      DeclarationCode.fromString('class MyClass {}'),
    );
  }
}

const myMacro = MyMacro();
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@myMacro
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(
        library,
        r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @33
        metadata
          Annotation
            atSign: @ @18
            name: SimpleIdentifier
              token: myMacro @19
              staticElement: package:test/a.dart::@getter::myMacro
              staticType: null
            element: package:test/a.dart::@getter::myMacro
        constructors
          synthetic @-1
  parts
    package:test/_macro_types.dart
      classes
        class MyClass @6
          constructors
            synthetic @-1
  exportScope
    A: package:test/test.dart;A
    MyClass: package:test/test.dart;package:test/_macro_types.dart;MyClass
''',
        withExportScope: true);
  }

  test_application_getter_withoutPrefix_namedConstructor() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'dart:async';
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassTypesMacro {
  const MyMacro.named();

  FutureOr<void> buildTypesForClass(clazz, builder) {
    builder.declareType(
      'MyClass',
      DeclarationCode.fromString('class MyClass {}'),
    );
  }
}

const myMacro = MyMacro.named();
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@myMacro
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(
        library,
        r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @33
        metadata
          Annotation
            atSign: @ @18
            name: SimpleIdentifier
              token: myMacro @19
              staticElement: package:test/a.dart::@getter::myMacro
              staticType: null
            element: package:test/a.dart::@getter::myMacro
        constructors
          synthetic @-1
  parts
    package:test/_macro_types.dart
      classes
        class MyClass @6
          constructors
            synthetic @-1
  exportScope
    A: package:test/test.dart;A
    MyClass: package:test/test.dart;package:test/_macro_types.dart;MyClass
''',
        withExportScope: true);
  }

  test_application_getter_withPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'dart:async';
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassTypesMacro {
  FutureOr<void> buildTypesForClass(clazz, builder) {
    builder.declareType(
      'MyClass',
      DeclarationCode.fromString('class MyClass {}'),
    );
  }
}

const myMacro = MyMacro();
''');

    var library = await buildLibrary(r'''
import 'a.dart' as prefix;

@prefix.myMacro
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(
        library,
        r'''
library
  imports
    package:test/a.dart as prefix @19
  definingUnit
    classes
      class A @50
        metadata
          Annotation
            atSign: @ @28
            name: PrefixedIdentifier
              prefix: SimpleIdentifier
                token: prefix @29
                staticElement: self::@prefix::prefix
                staticType: null
              period: . @35
              identifier: SimpleIdentifier
                token: myMacro @36
                staticElement: package:test/a.dart::@getter::myMacro
                staticType: null
              staticElement: package:test/a.dart::@getter::myMacro
              staticType: null
            element: package:test/a.dart::@getter::myMacro
        constructors
          synthetic @-1
  parts
    package:test/_macro_types.dart
      classes
        class MyClass @6
          constructors
            synthetic @-1
  exportScope
    A: package:test/test.dart;A
    MyClass: package:test/test.dart;package:test/_macro_types.dart;MyClass
''',
        withExportScope: true);
  }

  test_application_getter_withPrefix_namedConstructor() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'dart:async';
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassTypesMacro {
  const MyMacro.named();

  FutureOr<void> buildTypesForClass(clazz, builder) {
    builder.declareType(
      'MyClass',
      DeclarationCode.fromString('class MyClass {}'),
    );
  }
}

const myMacro = MyMacro.named();
''');

    var library = await buildLibrary(r'''
import 'a.dart' as prefix;

@prefix.myMacro
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(
        library,
        r'''
library
  imports
    package:test/a.dart as prefix @19
  definingUnit
    classes
      class A @50
        metadata
          Annotation
            atSign: @ @28
            name: PrefixedIdentifier
              prefix: SimpleIdentifier
                token: prefix @29
                staticElement: self::@prefix::prefix
                staticType: null
              period: . @35
              identifier: SimpleIdentifier
                token: myMacro @36
                staticElement: package:test/a.dart::@getter::myMacro
                staticType: null
              staticElement: package:test/a.dart::@getter::myMacro
              staticType: null
            element: package:test/a.dart::@getter::myMacro
        constructors
          synthetic @-1
  parts
    package:test/_macro_types.dart
      classes
        class MyClass @6
          constructors
            synthetic @-1
  exportScope
    A: package:test/test.dart;A
    MyClass: package:test/test.dart;package:test/_macro_types.dart;MyClass
''',
        withExportScope: true);
  }

  test_application_newInstance_withoutPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'dart:async';
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassTypesMacro {
  FutureOr<void> buildTypesForClass(clazz, builder) {
    builder.declareType(
      'MyClass',
      DeclarationCode.fromString('class MyClass {}'),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(
        library,
        r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @35
        metadata
          Annotation
            atSign: @ @18
            name: SimpleIdentifier
              token: MyMacro @19
              staticElement: package:test/a.dart::@class::MyMacro
              staticType: null
            arguments: ArgumentList
              leftParenthesis: ( @26
              rightParenthesis: ) @27
            element: package:test/a.dart::@class::MyMacro::@constructor::•
        constructors
          synthetic @-1
  parts
    package:test/_macro_types.dart
      classes
        class MyClass @6
          constructors
            synthetic @-1
  exportScope
    A: package:test/test.dart;A
    MyClass: package:test/test.dart;package:test/_macro_types.dart;MyClass
''',
        withExportScope: true);
  }

  test_application_newInstance_withoutPrefix_namedConstructor() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'dart:async';
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassTypesMacro {
  const MyMacro.named();

  FutureOr<void> buildTypesForClass(clazz, builder) {
    builder.declareType(
      'MyClass',
      DeclarationCode.fromString('class MyClass {}'),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@MyMacro.named()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(
        library,
        r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @41
        metadata
          Annotation
            atSign: @ @18
            name: PrefixedIdentifier
              prefix: SimpleIdentifier
                token: MyMacro @19
                staticElement: package:test/a.dart::@class::MyMacro
                staticType: null
              period: . @26
              identifier: SimpleIdentifier
                token: named @27
                staticElement: package:test/a.dart::@class::MyMacro::@constructor::named
                staticType: null
              staticElement: package:test/a.dart::@class::MyMacro::@constructor::named
              staticType: null
            arguments: ArgumentList
              leftParenthesis: ( @32
              rightParenthesis: ) @33
            element: package:test/a.dart::@class::MyMacro::@constructor::named
        constructors
          synthetic @-1
  parts
    package:test/_macro_types.dart
      classes
        class MyClass @6
          constructors
            synthetic @-1
  exportScope
    A: package:test/test.dart;A
    MyClass: package:test/test.dart;package:test/_macro_types.dart;MyClass
''',
        withExportScope: true);
  }

  test_application_newInstance_withPrefix() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassTypesMacro {
  buildTypesForClass(clazz, builder) {
    builder.declareType(
      'MyClass',
      DeclarationCode.fromString('class MyClass {}'),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart' as prefix;

@prefix.MyMacro()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(
        library,
        r'''
library
  imports
    package:test/a.dart as prefix @19
  definingUnit
    classes
      class A @52
        metadata
          Annotation
            atSign: @ @28
            name: PrefixedIdentifier
              prefix: SimpleIdentifier
                token: prefix @29
                staticElement: self::@prefix::prefix
                staticType: null
              period: . @35
              identifier: SimpleIdentifier
                token: MyMacro @36
                staticElement: package:test/a.dart::@class::MyMacro
                staticType: null
              staticElement: package:test/a.dart::@class::MyMacro
              staticType: null
            arguments: ArgumentList
              leftParenthesis: ( @43
              rightParenthesis: ) @44
            element: package:test/a.dart::@class::MyMacro::@constructor::•
        constructors
          synthetic @-1
  parts
    package:test/_macro_types.dart
      classes
        class MyClass @6
          constructors
            synthetic @-1
  exportScope
    A: package:test/test.dart;A
    MyClass: package:test/test.dart;package:test/_macro_types.dart;MyClass
''',
        withExportScope: true);
  }

  test_application_newInstance_withPrefix_namedConstructor() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassTypesMacro {
  const MyMacro.named();

  buildTypesForClass(clazz, builder) {
    builder.declareType(
      'MyClass',
      DeclarationCode.fromString('class MyClass {}'),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart' as prefix;

@prefix.MyMacro.named()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(
        library,
        r'''
library
  imports
    package:test/a.dart as prefix @19
  definingUnit
    classes
      class A @58
        metadata
          Annotation
            atSign: @ @28
            name: PrefixedIdentifier
              prefix: SimpleIdentifier
                token: prefix @29
                staticElement: self::@prefix::prefix
                staticType: null
              period: . @35
              identifier: SimpleIdentifier
                token: MyMacro @36
                staticElement: package:test/a.dart::@class::MyMacro
                staticType: null
              staticElement: package:test/a.dart::@class::MyMacro
              staticType: null
            period: . @43
            constructorName: SimpleIdentifier
              token: named @44
              staticElement: package:test/a.dart::@class::MyMacro::@constructor::named
              staticType: null
            arguments: ArgumentList
              leftParenthesis: ( @49
              rightParenthesis: ) @50
            element: package:test/a.dart::@class::MyMacro::@constructor::named
        constructors
          synthetic @-1
  parts
    package:test/_macro_types.dart
      classes
        class MyClass @6
          constructors
            synthetic @-1
  exportScope
    A: package:test/test.dart;A
    MyClass: package:test/test.dart;package:test/_macro_types.dart;MyClass
''',
        withExportScope: true);
  }

  test_arguments_error() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'Object',
        'bar': 'Object',
      },
      constructorParametersCode: '(this.foo, this.bar)',
      argumentsCode: '(0, const Object())',
      expectedErrors: 'Argument(annotation: 0, argument: 1, '
          'message: Not supported: InstanceCreationExpressionImpl)',
    );
  }

  test_arguments_getter_type_bool() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'bool',
        'bar': 'bool',
      },
      constructorParametersCode: '(this.foo, this.bar)',
      argumentsCode: '(true, false)',
      usingGetter: true,
      expected: r'''
foo: true
bar: false
''',
    );
  }

  test_arguments_getter_type_int() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'int'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(42)',
      usingGetter: true,
      expected: r'''
foo: 42
''',
    );
  }

  test_arguments_getter_type_string() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'String'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: "('aaa')",
      usingGetter: true,
      expected: r'''
foo: aaa
''',
    );
  }

  test_arguments_newInstance_kind_optionalNamed() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'int',
        'bar': 'int',
      },
      constructorParametersCode: '({this.foo = -1, this.bar = -2})',
      argumentsCode: '(foo: 1)',
      expected: r'''
foo: 1
bar: -2
''',
    );
  }

  test_arguments_newInstance_kind_optionalPositional() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'int',
        'bar': 'int',
      },
      constructorParametersCode: '([this.foo = -1, this.bar = -2])',
      argumentsCode: '(1)',
      expected: r'''
foo: 1
bar: -2
''',
    );
  }

  test_arguments_newInstance_kind_requiredNamed() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'int'},
      constructorParametersCode: '({required this.foo})',
      argumentsCode: '(foo: 42)',
      expected: r'''
foo: 42
''',
    );
  }

  test_arguments_newInstance_kind_requiredPositional() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'int'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(42)',
      expected: r'''
foo: 42
''',
    );
  }

  test_arguments_newInstance_type_bool() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'bool',
        'bar': 'bool',
      },
      constructorParametersCode: '(this.foo, this.bar)',
      argumentsCode: '(true, false)',
      expected: r'''
foo: true
bar: false
''',
    );
  }

  test_arguments_newInstance_type_double() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'double'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(1.2)',
      expected: r'''
foo: 1.2
''',
    );
  }

  test_arguments_newInstance_type_double_negative() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'double'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(-1.2)',
      expected: r'''
foo: -1.2
''',
    );
  }

  test_arguments_newInstance_type_int() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'int'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(42)',
      expected: r'''
foo: 42
''',
    );
  }

  test_arguments_newInstance_type_int_negative() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'int'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(-42)',
      expected: r'''
foo: -42
''',
    );
  }

  test_arguments_newInstance_type_list() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'List<Object?>',
      },
      constructorParametersCode: '(this.foo)',
      argumentsCode: '([1, 2, true, 3, 4.2])',
      expected: r'''
foo: [1, 2, true, 3, 4.2]
''',
    );
  }

  test_arguments_newInstance_type_map() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'Map<Object?, Object?>',
      },
      constructorParametersCode: '(this.foo)',
      argumentsCode: '({1: true, "abc": 2.3})',
      expected: r'''
foo: {1: true, abc: 2.3}
''',
    );
  }

  test_arguments_newInstance_type_null() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'Object?'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: '(null)',
      expected: r'''
foo: null
''',
    );
  }

  test_arguments_newInstance_type_set() async {
    await _assertTypesPhaseArgumentsText(
      fields: {
        'foo': 'Set<Object?>',
      },
      constructorParametersCode: '(this.foo)',
      argumentsCode: '({1, 2, 3})',
      expected: r'''
foo: {1, 2, 3}
''',
    );
  }

  test_arguments_newInstance_type_string() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'String'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: "('aaa')",
      expected: r'''
foo: aaa
''',
    );
  }

  test_arguments_newInstance_type_string_adjacent() async {
    await _assertTypesPhaseArgumentsText(
      fields: {'foo': 'String'},
      constructorParametersCode: '(this.foo)',
      argumentsCode: "('aaa' 'bbb' 'ccc')",
      expected: r'''
foo: aaabbbccc
''',
    );
  }

  /// TODO(scheglov) Not quite correct - we should not add a synthetic one.
  /// Fix it when adding actual augmentation libraries.
  test_declarationsPhase_class_constructor() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassDeclarationsMacro {
  const MyMacro();

  buildDeclarationsForClass(clazz, builder) async {
    builder.declareInClass(
      DeclarationCode.fromString('A.named(int a);'),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(library, r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @35
        metadata
          Annotation
            atSign: @ @18
            name: SimpleIdentifier
              token: MyMacro @19
              staticElement: package:test/a.dart::@class::MyMacro
              staticType: null
            arguments: ArgumentList
              leftParenthesis: ( @26
              rightParenthesis: ) @27
            element: package:test/a.dart::@class::MyMacro::@constructor::•
        constructors
          synthetic @-1
          named @-1
            parameters
              requiredPositional a @-1
                type: int
''');
  }

  test_declarationsPhase_class_field() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassDeclarationsMacro {
  const MyMacro();

  buildDeclarationsForClass(clazz, builder) async {
    builder.declareInClass(
      DeclarationCode.fromString('int foo = 0;'),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(library, r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @35
        metadata
          Annotation
            atSign: @ @18
            name: SimpleIdentifier
              token: MyMacro @19
              staticElement: package:test/a.dart::@class::MyMacro
              staticType: null
            arguments: ArgumentList
              leftParenthesis: ( @26
              rightParenthesis: ) @27
            element: package:test/a.dart::@class::MyMacro::@constructor::•
        fields
          foo @-1
            type: int
        constructors
          synthetic @-1
        accessors
          synthetic get foo @-1
            returnType: int
          synthetic set foo @-1
            parameters
              requiredPositional _foo @-1
                type: int
            returnType: void
''');
  }

  test_declarationsPhase_class_getter() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassDeclarationsMacro {
  const MyMacro();

  buildDeclarationsForClass(clazz, builder) async {
    builder.declareInClass(
      DeclarationCode.fromString('int get foo => 0;'),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(library, r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @35
        metadata
          Annotation
            atSign: @ @18
            name: SimpleIdentifier
              token: MyMacro @19
              staticElement: package:test/a.dart::@class::MyMacro
              staticType: null
            arguments: ArgumentList
              leftParenthesis: ( @26
              rightParenthesis: ) @27
            element: package:test/a.dart::@class::MyMacro::@constructor::•
        fields
          synthetic foo @-1
            type: int
        constructors
          synthetic @-1
        accessors
          get foo @-1
            returnType: int
''');
  }

  test_declarationsPhase_class_method() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassDeclarationsMacro {
  const MyMacro();

  buildDeclarationsForClass(clazz, builder) async {
    builder.declareInClass(
      DeclarationCode.fromString('int foo(double a) => 0;'),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(library, r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @35
        metadata
          Annotation
            atSign: @ @18
            name: SimpleIdentifier
              token: MyMacro @19
              staticElement: package:test/a.dart::@class::MyMacro
              staticType: null
            arguments: ArgumentList
              leftParenthesis: ( @26
              rightParenthesis: ) @27
            element: package:test/a.dart::@class::MyMacro::@constructor::•
        constructors
          synthetic @-1
        methods
          foo @-1
            parameters
              requiredPositional a @-1
                type: double
            returnType: int
''');
  }

  test_declarationsPhase_class_setter() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassDeclarationsMacro {
  const MyMacro();

  buildDeclarationsForClass(clazz, builder) async {
    builder.declareInClass(
      DeclarationCode.fromString('set foo(int a) {}'),
    );
  }
}
''');

    var library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    checkElementText(library, r'''
library
  imports
    package:test/a.dart
  definingUnit
    classes
      class A @35
        metadata
          Annotation
            atSign: @ @18
            name: SimpleIdentifier
              token: MyMacro @19
              staticElement: package:test/a.dart::@class::MyMacro
              staticType: null
            arguments: ArgumentList
              leftParenthesis: ( @26
              rightParenthesis: ) @27
            element: package:test/a.dart::@class::MyMacro::@constructor::•
        fields
          synthetic foo @-1
            type: int
        constructors
          synthetic @-1
        accessors
          set foo @-1
            parameters
              requiredPositional a @-1
                type: int
            returnType: void
''');
  }

  test_introspect_types_ClassDeclaration_interfaces() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A implements B, C<int, String> {}
''', r'''
class A
  interfaces
    B
    C<int, String>
''');
  }

  test_introspect_types_ClassDeclaration_isAbstract() async {
    await _assertTypesPhaseIntrospectionText(r'''
abstract class A {}
''', r'''
abstract class A
''');
  }

  test_introspect_types_ClassDeclaration_mixins() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A with B, C<int, String> {}
''', r'''
class A
  mixins
    B
    C<int, String>
''');
  }

  test_introspect_types_ClassDeclaration_superclass() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B {}
''', r'''
class A
  superclass: B
''');
  }

  test_introspect_types_ClassDeclaration_superclass_nullable() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B<int?> {}
''', r'''
class A
  superclass: B<int?>
''');
  }

  test_introspect_types_ClassDeclaration_superclass_typeArguments() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B<String, List<int>> {}
''', r'''
class A
  superclass: B<String, List<int>>
''');
  }

  test_introspect_types_ClassDeclaration_typeParameters() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A<T, U extends List<T>> {}
''', r'''
class A
  typeParameters
    T
    U
      bound: List<T>
''');
  }

  test_introspect_types_functionTypeAnnotation_formalParameters_namedOptional_simpleFormalParameter() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B<void Function(int a, {int? b, int? c})> {}
''', r'''
class A
  superclass: B<void Function(int a, {int? b}, {int? c})>
''');
  }

  test_introspect_types_functionTypeAnnotation_formalParameters_namedRequired_simpleFormalParameter() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B<void Function(int a, {required int b, required int c})> {}
''', r'''
class A
  superclass: B<void Function(int a, {required int b}, {required int c})>
''');
  }

  test_introspect_types_functionTypeAnnotation_formalParameters_positionalOptional_simpleFormalParameter() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B<void Function(int a, [int b, int c])> {}
''', r'''
class A
  superclass: B<void Function(int a, [int b], [int c])>
''');
  }

  /// TODO(scheglov) Tests for unnamed positional formal parameters.
  test_introspect_types_functionTypeAnnotation_formalParameters_positionalRequired_simpleFormalParameter() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B<void Function(int a, double b)> {}
''', r'''
class A
  superclass: B<void Function(int a, double b)>
''');
  }

  test_introspect_types_functionTypeAnnotation_nullable() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B<void Function()?> {}
''', r'''
class A
  superclass: B<void Function()?>
''');
  }

  test_introspect_types_functionTypeAnnotation_returnType() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B<void Function()> {}
''', r'''
class A
  superclass: B<void Function()>
''');
  }

  test_introspect_types_functionTypeAnnotation_returnType_omitted() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B<Function()> {}
''', r'''
class A
  superclass: B<OmittedType Function()>
''');
  }

  test_introspect_types_functionTypeAnnotation_typeParameters() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends B<void Function<T, U extends num>()> {}
''', r'''
class A
  superclass: B<void Function<T, U extends num>()>
''');
  }

  test_introspect_types_namedTypeAnnotation_prefixed() async {
    await _assertTypesPhaseIntrospectionText(r'''
class A extends prefix.B {}
''', r'''
class A
  superclass: B
''');
  }

  test_macroApplicationErrors_declarationsPhase_throwsException() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassDeclarationsMacro {
  const MyMacro();

  buildDeclarationsForClass(clazz, builder) async {
    throw 'foo bar';
  }
}
''');

    final library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    final A = library.getType('A') as ClassElementImpl;
    final error = A.macroApplicationErrors.single;
    error as UnknownMacroApplicationError;

    expect(error.annotationIndex, 0);
    expect(error.message, 'foo bar');
    expect(error.stackTrace, contains('MyMacro.buildDeclarationsForClass'));
  }

  test_macroApplicationErrors_typedPhase_compileTimeError() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassTypesMacro {
  buildTypesForClass(clazz, builder) {
    unresolved;
  }
}
''');

    final library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    final A = library.getType('A') as ClassElementImpl;
    final error = A.macroApplicationErrors.single;
    error as UnknownMacroApplicationError;

    expect(error.annotationIndex, 0);
    expect(error.message, contains('unresolved'));
    expect(error.stackTrace, contains('executeTypesMacro'));
  }

  test_macroApplicationErrors_typesPhase_throwsException() async {
    newFile('$testPackageLibPath/a.dart', r'''
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class MyMacro implements ClassTypesMacro {
  buildTypesForClass(clazz, builder) {
    throw 'foo bar';
  }
}
''');

    final library = await buildLibrary(r'''
import 'a.dart';

@MyMacro()
class A {}
''', preBuildSequence: [
      {'package:test/a.dart'}
    ]);

    final A = library.getType('A') as ClassElementImpl;
    final error = A.macroApplicationErrors.single;
    error as UnknownMacroApplicationError;

    expect(error.annotationIndex, 0);
    expect(error.message, 'foo bar');
    expect(error.stackTrace, contains('MyMacro.buildTypesForClass'));
  }

  test_macroFlag_class() async {
    var library = await buildLibrary(r'''
macro class A {}
''');
    checkElementText(library, r'''
library
  definingUnit
    classes
      macro class A @12
        constructors
          synthetic @-1
''');
  }

  test_macroFlag_classAlias() async {
    var library = await buildLibrary(r'''
mixin M {}
macro class A = Object with M;
''');
    checkElementText(library, r'''
library
  definingUnit
    classes
      macro class alias A @23
        supertype: Object
        mixins
          M
        constructors
          synthetic const @-1
            constantInitializers
              SuperConstructorInvocation
                superKeyword: super @0
                argumentList: ArgumentList
                  leftParenthesis: ( @0
                  rightParenthesis: ) @0
                staticElement: dart:core::@class::Object::@constructor::•
    mixins
      mixin M @6
        superclassConstraints
          Object
''');
  }

  void writeTestPackageConfig(
    PackageConfigFileBuilder config, {
    MacrosEnvironment? macrosEnvironment,
  }) {
    config = config.copy();

    config.add(
      name: 'test',
      rootPath: testPackageRootPath,
    );

    if (macrosEnvironment != null) {
      var packagesRootFolder = getFolder(packagesRootPath);
      macrosEnvironment.packageSharedFolder.copyTo(packagesRootFolder);
      config.add(
        name: '_fe_analyzer_shared',
        rootPath: getFolder('$packagesRootPath/_fe_analyzer_shared').path,
      );
    }

    newPackageConfigJsonFile(
      testPackageRootPath,
      config.toContent(
        toUriStr: toUriStr,
      ),
    );
  }

  /// Build a macro with specified [fields], initialized in the constructor
  /// with [constructorParametersCode], and apply this macro  with
  /// [argumentsCode] to an empty class.
  ///
  /// The macro generates exactly one top-level constant `x`, with a textual
  /// dump of the field values. So, we check that the analyzer built these
  /// values, and the macro executor marshalled these values to the running
  /// macro isolate.
  Future<void> _assertTypesPhaseArgumentsText({
    required Map<String, String> fields,
    required String constructorParametersCode,
    required String argumentsCode,
    String? expected,
    String? expectedErrors,
    bool usingGetter = false,
  }) async {
    final dumpCode = fields.keys.map((name) {
      return "$name: \$$name\\\\n";
    }).join('');

    newFile('$testPackageLibPath/arguments_text.dart', '''
import 'dart:async';
import 'package:_fe_analyzer_shared/src/macros/api.dart';

macro class ArgumentsTextMacro implements ClassTypesMacro {
${fields.entries.map((e) => '  final ${e.value} ${e.key};').join('\n')}

  const ArgumentsTextMacro${constructorParametersCode.trim()};

  FutureOr<void> buildTypesForClass(clazz, builder) {
    builder.declareType(
      'x',
      DeclarationCode.fromString(
        "const x = '$dumpCode';",
      ),
    );
  }
}

${usingGetter ? 'const argumentsTextMacro = ArgumentsTextMacro$argumentsCode;' : ''}
''');

    final library = await buildLibrary('''
import 'arguments_text.dart';

${usingGetter ? '@argumentsTextMacro' : '@ArgumentsTextMacro$argumentsCode'}
class A {}
    ''', preBuildSequence: [
      {'package:test/arguments_text.dart'}
    ]);

    final A = library.definingCompilationUnit.getType('A');
    if (expectedErrors != null) {
      expect(_errorsStrForClassElement(A), expectedErrors);
      return;
    } else {
      _assertNoErrorsForClassElement(A);
    }

    if (expected != null) {
      final x = library.parts.single.topLevelVariables.single;
      expect(x.name, 'x');
      x as ConstTopLevelVariableElementImpl;
      final actual = (x.constantInitializer as SimpleStringLiteral).value;

      if (actual != expected) {
        print(actual);
      }
      expect(actual, expected);
    } else {
      fail("Either 'expected' or 'expectedErrors' must be provided.");
    }
  }

  /// Assert that the textual dump of the introspection information for
  /// the first declaration in [declarationCode] is the same as [expected].
  Future<void> _assertTypesPhaseIntrospectionText(
      String declarationCode, String expected) async {
    var actual = await _getDeclarationText(declarationCode);
    if (actual != expected) {
      print(actual);
    }
    expect(actual, expected);
  }

  /// The [declarationCode] is expected to start with a declaration. It may
  /// include other declaration below, for example to reference them in
  /// the first declaration.
  ///
  /// Use `DeclarationTextMacro` to generate a library that produces exactly
  /// one part, with exactly one top-level constant `x`, with a string
  /// literal initializer. We expect that the value of this literal is
  /// the textual dump of the introspection information for the first
  /// declaration.
  Future<String> _getDeclarationText(String declarationCode) async {
    newFile(
      '$testPackageLibPath/declaration_text.dart',
      _declarationTextCode,
    );

    var library = await buildLibrary('''
import 'declaration_text.dart';

@DeclarationTextMacro()
$declarationCode
''', preBuildSequence: [
      {'package:test/declaration_text.dart'}
    ]);

    _assertNoErrorsForClassElement(
      library.definingCompilationUnit.getType('A'),
    );

    var x = library.parts.single.topLevelVariables.single;
    expect(x.name, 'x');
    x as ConstTopLevelVariableElementImpl;
    var x_literal = x.constantInitializer as SimpleStringLiteral;
    return x_literal.value;
  }

  static void _assertNoErrorsForClassElement(ClassElement? element) {
    var actual = _errorsStrForClassElement(element);
    expect(actual, isEmpty);
  }

  static String _errorsStrForClassElement(ClassElement? element) {
    element as ClassElementImpl;
    return element.macroApplicationErrors.map((e) {
      return e.toStringForTest();
    }).join('\n');
  }
}
