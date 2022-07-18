// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class Base {}

class Mixin1a extends Base {}

class Mixin1b extends Mixin1a {}

class C1a extends Base with Mixin1a {}

class C1b extends Base with Mixin1b {}

mixin Mixin2a on Base {}

mixin Mixin2b on Base, Mixin2a {}

class C2a extends Base with Mixin2a {}

class C2b extends Base with Mixin2a, Mixin2b {}
