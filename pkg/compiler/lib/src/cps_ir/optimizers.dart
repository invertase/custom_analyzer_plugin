// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js.cps_ir.optimizers;

import '../constants/constant_system.dart';
import '../constants/expressions.dart';
import '../constants/values.dart';
import '../dart_types.dart' as types;
import '../dart2jslib.dart' as dart2js;
import '../resolution/operators.dart';
import '../tree/tree.dart' show LiteralDartString;
import 'cps_ir_nodes.dart';
import '../types/types.dart' show TypeMask, TypesTask;
import '../types/constants.dart' show computeTypeMask;
import '../elements/elements.dart' show ClassElement, Element, Entity,
    FieldElement, FunctionElement, ParameterElement;
import '../dart2jslib.dart' show ClassWorld;

part 'type_propagation.dart';
part 'redundant_phi.dart';
part 'shrinking_reductions.dart';

/// An optimization pass over the CPS IR.
abstract class Pass {
  /// Applies optimizations to root, rewriting it in the process.
  void rewrite(RootNode root);

  String get passName;
}
