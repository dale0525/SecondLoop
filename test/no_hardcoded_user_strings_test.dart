import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

final List<RegExp> _directDisallowedPatterns = <RegExp>[
  RegExp(r'''Text\(\s*['"]'''),
  RegExp(r'''SelectableText\(\s*['"]'''),
  RegExp(r'''labelText:\s*['"]'''),
  RegExp(r'''hintText:\s*['"]'''),
  RegExp(r'''tooltip:\s*['"]'''),
  RegExp(r'''localizedReason:\s*['"]'''),
  RegExp(r'''emptyText:\s*['"]'''),
];

const Set<String> _excludedPaths = <String>{
  'lib/i18n/strings.g.dart',
  'lib/src/rust/frb_generated.dart',
  'lib/src/rust/frb_generated.io.dart',
  'lib/src/rust/frb_generated.web.dart',
};

const Set<String> _userFacingNamedParameters = <String>{
  'labelText',
  'hintText',
  'tooltip',
  'localizedReason',
  'emptyText',
};

const Set<String> _userFacingConstructors = <String>{
  'Text',
  'SelectableText',
};

final RegExp _displayTextPattern =
    RegExp(r'[A-Za-z\u00C0-\u024F\u4E00-\u9FFF]');

const String _i18nGuardPolicy =
    'This test exists to enforce i18n for user-facing copy. '
    'Do not bypass it with helper wrappers, locale branches, or string composition. '
    'Add new copy to lib/i18n/strings_*.i18n.json and regenerate with `pixi run i18n-gen`. '
    'Move display text into generated i18n keys instead.';

void main() {
  test('Flags helper methods that hide hardcoded user-facing strings', () {
    final offenders = _scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    Text(_title());
  }

  String _title() => _isZh ? '设置应用锁密码' : 'Set app lock password';

  bool get _isZh => true;
}
''',
      path: 'snippet_helper_method.dart',
    );

    expect(offenders, isNotEmpty);
    expect(offenders.single, contains('indirection'));
  });

  test('Flags helper wrappers with literal copy passed into user-facing sinks',
      () {
    final offenders = _scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    InputDecoration(labelText: _text('状态', 'Status'));
  }

  String _text(String zh, String en) => _isZh ? zh : en;

  bool get _isZh => true;
}
''',
      path: 'snippet_helper_wrapper.dart',
    );

    expect(offenders, isNotEmpty);
    expect(offenders.single, contains('indirection'));
  });

  test('Flags locale branches passed directly into user-facing sinks', () {
    final offenders = _scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    Text(_isZh ? '设置' : 'Settings');
    InputDecoration(labelText: zh ? '保存' : 'Save');
  }

  bool get _isZh => true;
  bool get zh => true;
}
''',
      path: 'snippet_direct_locale_branch.dart',
    );

    expect(offenders, hasLength(2));
    expect(offenders.first, contains('indirection'));
    expect(offenders.last, contains('indirection'));
  });

  test('Does not flag locale branches inside i18n method arguments', () {
    final offenders = _scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    Text(
      context.t.releaseNotes.updatedTo(
        version: hasNotes ? version : 'v$appVersion',
      ),
    );
  }
}
''',
      path: 'snippet_i18n_method_argument.dart',
    );

    expect(offenders, isEmpty);
  });

  test('Does not flag non-linguistic formatting helpers', () {
    final offenders = _scanSourceForHardcodedUserFacingStrings(
      content: r'''
class Demo {
  void build() {
    Text(_buildIndexLabel());
  }

  String _buildIndexLabel() {
    final current = 1;
    final total = 3;
    return '$current/$total';
  }
}
''',
      path: 'snippet_numeric_format.dart',
    );

    expect(offenders, isEmpty);
  });

  test('Policy text explicitly warns against bypassing i18n guard', () {
    expect(_i18nGuardPolicy, contains('Do not bypass'));
    expect(_i18nGuardPolicy, contains('i18n'));
  });

  test('No hardcoded user-facing strings in lib/', () {
    final offenders = _scanLibForHardcodedUserFacingStrings();
    expect(offenders, isEmpty, reason: _formatFailureReason(offenders));
  });
}

String _formatFailureReason(List<String> offenders) {
  if (offenders.isEmpty) return _i18nGuardPolicy;
  return '$_i18nGuardPolicy\n${offenders.join('\n')}';
}

List<String> _scanLibForHardcodedUserFacingStrings() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    fail('Missing lib/ directory');
  }

  final offenders = <String>[];
  for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    if (_excludedPaths.contains(entity.path)) continue;

    final content = entity.readAsStringSync();
    offenders.addAll(
      _scanSourceForHardcodedUserFacingStrings(
        content: content,
        path: entity.path,
      ),
    );
  }
  return offenders;
}

List<String> _scanSourceForHardcodedUserFacingStrings({
  required String content,
  required String path,
}) {
  final offenders = <String>[];

  for (final pattern in _directDisallowedPatterns) {
    if (!pattern.hasMatch(content)) continue;
    offenders.add('$path: matches ${pattern.pattern}');
    break;
  }

  final parsed = parseString(
    content: content,
    path: path,
    throwIfDiagnostics: false,
  );
  final unitIndex = _CompilationUnitIndex.fromUnit(parsed.unit);
  final visitor = _HardcodedUserFacingStringVisitor(path, unitIndex);
  parsed.unit.visitChildren(visitor);
  offenders.addAll(visitor.offenders);
  return offenders;
}

class _HardcodedUserFacingStringVisitor extends RecursiveAstVisitor<void> {
  _HardcodedUserFacingStringVisitor(this.path, this.unitIndex);

  final String path;
  final _CompilationUnitIndex unitIndex;
  final List<String> offenders = <String>[];
  final List<Map<String, Expression>> _variableScopes =
      <Map<String, Expression>>[
    <String, Expression>{},
  ];
  final List<Map<String, _FunctionLikeNode>> _functionScopes =
      <Map<String, _FunctionLikeNode>>[
    <String, _FunctionLikeNode>{},
  ];
  final List<String> _classStack = <String>[];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _classStack.add(node.name.lexeme);
    super.visitClassDeclaration(node);
    _classStack.removeLast();
  }

  @override
  void visitBlock(Block node) {
    _variableScopes.add(<String, Expression>{});
    _functionScopes.add(<String, _FunctionLikeNode>{});
    super.visitBlock(node);
    _functionScopes.removeLast();
    _variableScopes.removeLast();
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    if (initializer != null) {
      _variableScopes.last[node.name.lexeme] = initializer;
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    final declaration = node.functionDeclaration;
    _functionScopes.last[declaration.name.lexeme] = _FunctionLikeNode(
      name: declaration.name.lexeme,
      body: declaration.functionExpression.body,
      parameterTypes:
          _parameterTypesOf(declaration.functionExpression.parameters),
    );
    super.visitFunctionDeclarationStatement(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructorName = node.constructorName.type.toSource();
    if (_userFacingConstructors.contains(constructorName) &&
        node.argumentList.arguments.isNotEmpty) {
      _checkExpression(
        node.argumentList.arguments.first,
        sink: '$constructorName()',
      );
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    if (_userFacingConstructors.contains(methodName) &&
        node.argumentList.arguments.isNotEmpty) {
      _checkExpression(node.argumentList.arguments.first,
          sink: '$methodName()');
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    final sinkName = node.name.label.name;
    if (_userFacingNamedParameters.contains(sinkName)) {
      _checkExpression(node.expression, sink: '$sinkName:');
    }
    super.visitNamedExpression(node);
  }

  void _checkExpression(Expression expression, {required String sink}) {
    if (!_isHardcodedUserFacingExpression(
      expression,
      _ResolutionContext(allowBranching: true),
    )) {
      return;
    }
    offenders.add(
      '$path: $sink uses hardcoded user-facing string hidden behind helper or branch indirection via ${expression.toSource()}',
    );
  }

  bool _isHardcodedUserFacingExpression(
    Expression expression,
    _ResolutionContext context,
  ) {
    final unwrapped = expression.unParenthesized;

    if (unwrapped is NamedExpression) {
      return _isHardcodedUserFacingExpression(unwrapped.expression, context);
    }
    if (unwrapped is SimpleStringLiteral) {
      if (_looksLikeInternalCodeLiteral(unwrapped.value)) {
        return false;
      }
      return _containsDisplayTextLiteral(unwrapped.value);
    }
    if (unwrapped is StringInterpolation) {
      if (_looksLikeInternalCodeInterpolation(unwrapped)) {
        return false;
      }
      for (final element in unwrapped.elements) {
        if (element is InterpolationString &&
            _containsDisplayTextLiteral(element.value)) {
          return true;
        }
        if (element is InterpolationExpression &&
            _isHardcodedUserFacingExpression(element.expression, context)) {
          return true;
        }
      }
      return false;
    }
    if (unwrapped is AdjacentStrings) {
      for (final string in unwrapped.strings) {
        if (_isHardcodedUserFacingExpression(string, context)) {
          return true;
        }
      }
      return false;
    }
    if (unwrapped is ConditionalExpression) {
      if (!context.allowBranching) return false;
      return _isHardcodedUserFacingExpression(
              unwrapped.thenExpression, context) ||
          _isHardcodedUserFacingExpression(unwrapped.elseExpression, context);
    }
    if (unwrapped is SwitchExpression) {
      if (!context.allowBranching) return false;
      for (final switchCase in unwrapped.cases) {
        if (_isHardcodedUserFacingExpression(switchCase.expression, context)) {
          return true;
        }
      }
      return false;
    }
    if (unwrapped is BinaryExpression && unwrapped.operator.lexeme == '+') {
      return _containsDisplayTextLiteral(unwrapped.leftOperand.toSource()) ||
          _containsDisplayTextLiteral(unwrapped.rightOperand.toSource()) ||
          _isHardcodedUserFacingExpression(unwrapped.leftOperand, context) ||
          _isHardcodedUserFacingExpression(unwrapped.rightOperand, context);
    }
    if (unwrapped is SimpleIdentifier) {
      if (!context.allowIdentifierResolution) {
        return false;
      }
      final name = unwrapped.name;
      if (!context.resolvingIdentifiers.add(name)) {
        return false;
      }
      final initializer = _resolveVariable(name);
      if (initializer == null) {
        context.resolvingIdentifiers.remove(name);
        return false;
      }
      final result = _isHardcodedUserFacingExpression(initializer, context);
      context.resolvingIdentifiers.remove(name);
      return result;
    }
    if (unwrapped is MethodInvocation) {
      if (_argumentListContainsHardcodedUserFacingString(
        unwrapped.argumentList,
        context,
      )) {
        return true;
      }
      final function = _resolveInvokedFunction(unwrapped);
      return function != null &&
          _functionReturnsHardcodedUserFacingString(function, context);
    }
    if (unwrapped is FunctionExpressionInvocation) {
      if (_argumentListContainsHardcodedUserFacingString(
        unwrapped.argumentList,
        context,
      )) {
        return true;
      }
      final function = _resolveInvokedFunction(unwrapped);
      return function != null &&
          _functionReturnsHardcodedUserFacingString(function, context);
    }

    return false;
  }

  bool _argumentListContainsHardcodedUserFacingString(
    ArgumentList argumentList,
    _ResolutionContext context,
  ) {
    for (final argument in argumentList.arguments) {
      final expression =
          argument is NamedExpression ? argument.expression : argument;
      if (_isHardcodedUserFacingExpression(expression, context)) {
        return true;
      }
    }
    return false;
  }

  bool _functionReturnsHardcodedUserFacingString(
    _FunctionLikeNode function,
    _ResolutionContext context,
  ) {
    if (!function.shouldCheckReturnLiterals) {
      return false;
    }
    if (!context.resolvingFunctions.add(function.signature)) {
      return false;
    }

    final helperContext = context.forHelperBody();
    for (final expression in function.returnedExpressions()) {
      if (_isHardcodedUserFacingExpression(expression, helperContext)) {
        context.resolvingFunctions.remove(function.signature);
        return true;
      }
    }

    context.resolvingFunctions.remove(function.signature);
    return false;
  }

  bool _containsDisplayTextLiteral(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    return _displayTextPattern.hasMatch(trimmed);
  }

  bool _looksLikeInternalCodeLiteral(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || RegExp(r'\s').hasMatch(trimmed)) {
      return false;
    }
    return RegExp(r'^[a-z0-9_./:-]+$').hasMatch(trimmed) &&
        RegExp(r'[0-9_./:-]').hasMatch(trimmed);
  }

  bool _looksLikeInternalCodeInterpolation(StringInterpolation interpolation) {
    final literalParts = interpolation.elements
        .whereType<InterpolationString>()
        .map((element) => element.value)
        .join()
        .trim();
    if (literalParts.isEmpty || RegExp(r'\s').hasMatch(literalParts)) {
      return false;
    }
    if (!RegExp(r'^[a-z0-9_./:-]*$').hasMatch(literalParts)) {
      return false;
    }
    return interpolation.elements.any((e) => e is InterpolationExpression);
  }

  Expression? _resolveVariable(String name) {
    for (final scope in _variableScopes.reversed) {
      final initializer = scope[name];
      if (initializer != null) {
        return initializer;
      }
    }
    return null;
  }

  _FunctionLikeNode? _resolveInvokedFunction(AstNode invocation) {
    if (invocation is MethodInvocation) {
      return _resolveNamedFunction(
        invocation.methodName.name,
        target: invocation.target,
      );
    }
    if (invocation is FunctionExpressionInvocation &&
        invocation.function is SimpleIdentifier) {
      final identifier = invocation.function as SimpleIdentifier;
      return _resolveNamedFunction(identifier.name);
    }
    return null;
  }

  _FunctionLikeNode? _resolveNamedFunction(String name, {Expression? target}) {
    for (final scope in _functionScopes.reversed) {
      final function = scope[name];
      if (function != null) {
        return function;
      }
    }

    final currentClass = _classStack.isEmpty ? null : _classStack.last;
    final isCurrentClassTarget =
        target == null || target is ThisExpression || target is SuperExpression;
    if (currentClass != null && isCurrentClassTarget) {
      final classMethod = unitIndex.resolveClassMethod(currentClass, name);
      if (classMethod != null) {
        return classMethod;
      }
    }

    return unitIndex.topLevelFunctions[name];
  }
}

final class _ResolutionContext {
  _ResolutionContext({
    this.allowBranching = false,
    this.allowIdentifierResolution = false,
    Set<String>? resolvingIdentifiers,
    Set<String>? resolvingFunctions,
  })  : resolvingIdentifiers = resolvingIdentifiers ?? <String>{},
        resolvingFunctions = resolvingFunctions ?? <String>{};

  final bool allowBranching;
  final bool allowIdentifierResolution;
  final Set<String> resolvingIdentifiers;
  final Set<String> resolvingFunctions;

  _ResolutionContext forHelperBody() {
    return _ResolutionContext(
      allowBranching: true,
      allowIdentifierResolution: true,
      resolvingIdentifiers: resolvingIdentifiers,
      resolvingFunctions: resolvingFunctions,
    );
  }
}

final class _CompilationUnitIndex {
  const _CompilationUnitIndex({
    required this.topLevelFunctions,
    required this.classMethods,
  });

  factory _CompilationUnitIndex.fromUnit(CompilationUnit unit) {
    final collector = _CompilationUnitIndexCollector();
    unit.visitChildren(collector);
    return _CompilationUnitIndex(
      topLevelFunctions: collector.topLevelFunctions,
      classMethods: collector.classMethods,
    );
  }

  final Map<String, _FunctionLikeNode> topLevelFunctions;
  final Map<String, Map<String, _FunctionLikeNode>> classMethods;

  _FunctionLikeNode? resolveClassMethod(String className, String methodName) {
    return classMethods[className]?[methodName];
  }
}

class _CompilationUnitIndexCollector extends RecursiveAstVisitor<void> {
  final Map<String, _FunctionLikeNode> topLevelFunctions =
      <String, _FunctionLikeNode>{};
  final Map<String, Map<String, _FunctionLikeNode>> classMethods =
      <String, Map<String, _FunctionLikeNode>>{};
  String? _currentClassName;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final previousClassName = _currentClassName;
    _currentClassName = node.name.lexeme;
    classMethods.putIfAbsent(
      _currentClassName!,
      () => <String, _FunctionLikeNode>{},
    );
    super.visitClassDeclaration(node);
    _currentClassName = previousClassName;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_currentClassName != null) {
      return;
    }
    topLevelFunctions[node.name.lexeme] = _FunctionLikeNode(
      name: node.name.lexeme,
      body: node.functionExpression.body,
      parameterTypes: _parameterTypesOf(node.functionExpression.parameters),
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final className = _currentClassName;
    if (className == null) {
      super.visitMethodDeclaration(node);
      return;
    }
    classMethods.putIfAbsent(
            className, () => <String, _FunctionLikeNode>{})[node.name.lexeme] =
        _FunctionLikeNode(
      name: node.name.lexeme,
      body: node.body,
      ownerName: className,
      parameterTypes: _parameterTypesOf(node.parameters),
    );
    super.visitMethodDeclaration(node);
  }
}

final class _FunctionLikeNode {
  const _FunctionLikeNode({
    required this.name,
    required this.body,
    required this.parameterTypes,
    this.ownerName,
  });

  final String name;
  final String? ownerName;
  final FunctionBody body;
  final List<String?> parameterTypes;

  String get signature => ownerName == null ? name : '$ownerName::$name';

  bool get shouldCheckReturnLiterals {
    if (parameterTypes.isEmpty) return true;
    if (parameterTypes.length != 1) return false;
    final normalized = (parameterTypes.first ?? '').replaceAll('?', '').trim();
    return normalized == 'BuildContext';
  }

  Iterable<Expression> returnedExpressions() sync* {
    if (body is ExpressionFunctionBody) {
      yield (body as ExpressionFunctionBody).expression;
      return;
    }
    if (body is! BlockFunctionBody) {
      return;
    }
    final collector = _ReturnExpressionCollector();
    body.visitChildren(collector);
    yield* collector.expressions;
  }
}

class _ReturnExpressionCollector extends RecursiveAstVisitor<void> {
  final List<Expression> expressions = <Expression>[];

  @override
  void visitReturnStatement(ReturnStatement node) {
    final expression = node.expression;
    if (expression != null) {
      expressions.add(expression);
    }
    super.visitReturnStatement(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {}

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {}

  @override
  void visitFunctionExpression(FunctionExpression node) {}

  @override
  void visitMethodDeclaration(MethodDeclaration node) {}
}

List<String?> _parameterTypesOf(FormalParameterList? parameters) {
  if (parameters == null) return const <String?>[];
  return parameters.parameters.map((parameter) {
    final normalized =
        parameter is DefaultFormalParameter ? parameter.parameter : parameter;
    if (normalized is SimpleFormalParameter) {
      return normalized.type?.toSource();
    }
    if (normalized is FieldFormalParameter) {
      return normalized.type?.toSource();
    }
    if (normalized is FunctionTypedFormalParameter) {
      return normalized.returnType?.toSource();
    }
    return null;
  }).toList(growable: false);
}
