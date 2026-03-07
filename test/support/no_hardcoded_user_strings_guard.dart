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

const Map<String, Set<String>> _userFacingNamedParametersByInvocation =
    <String, Set<String>>{
  'mediaAnnotationCapabilityCard': <String>{
    'title',
    'description',
    'statusLabel',
  },
  'mediaAnnotationRoutingGuideCard': <String>{
    'title',
    'pro',
    'byok',
  },
};

const Map<String, Set<int>> _userFacingPositionalArgumentsByInvocation =
    <String, Set<int>>{
  'mediaAnnotationSectionTitle': <int>{1},
};

final RegExp _displayTextPattern =
    RegExp(r'[A-Za-z\u00C0-\u024F\u4E00-\u9FFF]');

const String i18nGuardPolicy =
    'This test exists to enforce i18n for user-facing copy. '
    'Do not bypass it with helper wrappers, locale branches, or string composition. '
    'Add new copy to lib/i18n/strings_*.i18n.json and regenerate with `pixi run i18n-gen`. '
    'Move display text into generated i18n keys instead.';

List<String> scanLibForHardcodedUserFacingStrings() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    fail('Missing lib/ directory');
  }

  final sources = <_ParsedSourceFile>[];
  for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    if (_excludedPaths.contains(entity.path)) continue;

    final content = entity.readAsStringSync();
    final parsed = parseString(
      content: content,
      path: entity.path,
      throwIfDiagnostics: false,
    );
    sources.add(
      _ParsedSourceFile(
        displayPath: entity.path,
        absolutePath: entity.absolute.path,
        content: content,
        unit: parsed.unit,
      ),
    );
  }

  final unitIndicesByPath = _buildLibraryUnitIndices(sources);
  final offenders = <String>[];
  for (final source in sources) {
    offenders.addAll(
      _scanSourceForHardcodedUserFacingStrings(
        content: source.content,
        path: source.displayPath,
        parsedUnit: source.unit,
        unitIndex: unitIndicesByPath[source.absolutePath],
      ),
    );
  }
  return offenders;
}

List<String> scanSourceForHardcodedUserFacingStrings({
  required String content,
  required String path,
  CompilationUnit? parsedUnit,
}) {
  return _scanSourceForHardcodedUserFacingStrings(
    content: content,
    path: path,
    parsedUnit: parsedUnit,
  );
}

List<String> _scanSourceForHardcodedUserFacingStrings({
  required String content,
  required String path,
  CompilationUnit? parsedUnit,
  _CompilationUnitIndex? unitIndex,
}) {
  final offenders = <String>[];

  for (final pattern in _directDisallowedPatterns) {
    if (!pattern.hasMatch(content)) continue;
    offenders.add('$path: matches ${pattern.pattern}');
    break;
  }

  final unit = parsedUnit ??
      parseString(
        content: content,
        path: path,
        throwIfDiagnostics: false,
      ).unit;
  final resolvedUnitIndex =
      unitIndex ?? _CompilationUnitIndex.fromUnits(<CompilationUnit>[unit]);
  final visitor = _HardcodedUserFacingStringVisitor(path, resolvedUnitIndex);
  unit.visitChildren(visitor);
  offenders.addAll(visitor.offenders);
  return offenders;
}

final class _ParsedSourceFile {
  const _ParsedSourceFile({
    required this.displayPath,
    required this.absolutePath,
    required this.content,
    required this.unit,
  });

  final String displayPath;
  final String absolutePath;
  final String content;
  final CompilationUnit unit;

  bool get isPartFile =>
      unit.directives.any((directive) => directive is PartOfDirective);

  Iterable<String> partAbsolutePaths() sync* {
    for (final directive in unit.directives) {
      if (directive is! PartDirective) continue;
      final partPath = directive.uri.stringValue;
      if (partPath == null || partPath.isEmpty) continue;
      yield File.fromUri(Uri.file(absolutePath).resolve(partPath)).path;
    }
  }
}

Map<String, _CompilationUnitIndex> _buildLibraryUnitIndices(
  Iterable<_ParsedSourceFile> sources,
) {
  final sourcesByAbsolutePath = <String, _ParsedSourceFile>{
    for (final source in sources) source.absolutePath: source,
  };
  final unitIndicesByPath = <String, _CompilationUnitIndex>{};

  for (final source in sources) {
    if (source.isPartFile) continue;
    final groupUnits = <CompilationUnit>[source.unit];
    final groupPaths = <String>{source.absolutePath};
    for (final partPath in source.partAbsolutePaths()) {
      final partSource = sourcesByAbsolutePath[partPath];
      if (partSource == null) continue;
      groupUnits.add(partSource.unit);
      groupPaths.add(partPath);
    }

    final unitIndex = _CompilationUnitIndex.fromUnits(groupUnits);
    for (final groupPath in groupPaths) {
      unitIndicesByPath[groupPath] = unitIndex;
    }
  }

  for (final source in sources) {
    unitIndicesByPath.putIfAbsent(
      source.absolutePath,
      () => _CompilationUnitIndex.fromUnits(<CompilationUnit>[source.unit]),
    );
  }
  return unitIndicesByPath;
}

String? _invocationNameOf(AstNode? node) {
  if (node is MethodInvocation) {
    return node.methodName.name;
  }
  if (node is FunctionExpressionInvocation &&
      node.function is SimpleIdentifier) {
    return (node.function as SimpleIdentifier).name;
  }
  return null;
}

bool _isUserFacingNamedExpression(NamedExpression node) {
  final sinkName = node.name.label.name;
  if (_userFacingNamedParameters.contains(sinkName)) {
    return true;
  }
  final invocationName = _invocationNameOf(node.parent?.parent);
  if (invocationName == null) {
    return false;
  }
  final namedParameters =
      _userFacingNamedParametersByInvocation[invocationName];
  return namedParameters?.contains(sinkName) ?? false;
}

Iterable<Expression> _userFacingPositionalArgumentsForInvocation(
  AstNode invocation,
  ArgumentList argumentList,
) sync* {
  final invocationName = _invocationNameOf(invocation);
  if (invocationName == null) {
    return;
  }
  final positionalIndices =
      _userFacingPositionalArgumentsByInvocation[invocationName];
  if (positionalIndices == null || positionalIndices.isEmpty) {
    return;
  }
  for (final index in positionalIndices) {
    if (index < 0 || index >= argumentList.arguments.length) {
      continue;
    }
    final argument = argumentList.arguments[index];
    if (argument is NamedExpression) {
      yield argument.expression;
      continue;
    }
    yield argument;
  }
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
  final List<String> _extensionOnTypeStack = <String>[];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _classStack.add(node.name.lexeme);
    super.visitClassDeclaration(node);
    _classStack.removeLast();
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _extensionOnTypeStack.add(node.extendedType.toSource());
    super.visitExtensionDeclaration(node);
    _extensionOnTypeStack.removeLast();
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
      parameterNames:
          _parameterNamesOf(declaration.functionExpression.parameters),
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
    for (final argument in _userFacingPositionalArgumentsForInvocation(
      node,
      node.argumentList,
    )) {
      _checkExpression(argument, sink: '$methodName()');
    }
    _checkInvocationArgumentsForwardedIntoUserFacingSinks(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _checkInvocationArgumentsForwardedIntoUserFacingSinks(node);
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    if (_isUserFacingNamedExpression(node)) {
      final sinkName = node.name.label.name;
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

  void _checkInvocationArgumentsForwardedIntoUserFacingSinks(
      AstNode invocation) {
    if (_isAlreadyCheckedAsDirectSinkExpression(invocation)) {
      return;
    }
    final function = _resolveInvokedFunction(invocation);
    if (function == null) {
      return;
    }

    final argumentList = switch (invocation) {
      MethodInvocation(:final argumentList) => argumentList,
      FunctionExpressionInvocation(:final argumentList) => argumentList,
      _ => null,
    };
    if (argumentList == null) {
      return;
    }
    if (!_invocationPassesHardcodedStringsIntoUserFacingSinks(
      function,
      argumentList,
    )) {
      return;
    }

    offenders.add(
      '$path: invocation forwards hardcoded user-facing string into sink indirection via ${invocation.toSource()}',
    );
  }

  bool _isAlreadyCheckedAsDirectSinkExpression(AstNode node) {
    final parent = node.parent;
    if (parent is NamedExpression) {
      return _isUserFacingNamedExpression(parent);
    }
    if (parent is! ArgumentList || parent.arguments.isEmpty) {
      return false;
    }

    final target = parent.parent;
    final argumentIndex = parent.arguments.indexOf(node as Expression);
    final invocationName = _invocationNameOf(target);
    if (invocationName != null) {
      final positionalIndices =
          _userFacingPositionalArgumentsByInvocation[invocationName];
      if (positionalIndices?.contains(argumentIndex) ?? false) {
        return true;
      }
    }

    if (!identical(parent.arguments.first, node)) {
      return false;
    }
    if (target is InstanceCreationExpression) {
      return _userFacingConstructors.contains(
        target.constructorName.type.toSource(),
      );
    }
    if (target is MethodInvocation) {
      return _userFacingConstructors.contains(target.methodName.name);
    }
    return false;
  }

  bool _invocationPassesHardcodedStringsIntoUserFacingSinks(
    _FunctionLikeNode function,
    ArgumentList argumentList,
  ) {
    final sinkParameterNames = function.parameterNamesUsedInUserFacingSinks();
    if (sinkParameterNames.isEmpty) {
      return false;
    }

    final argumentsByParameterName = _argumentsByParameterName(
      function,
      argumentList,
    );
    for (final parameterName in sinkParameterNames) {
      final argument = argumentsByParameterName[parameterName];
      if (argument == null) {
        continue;
      }
      if (_isHardcodedUserFacingExpression(
        argument,
        _ResolutionContext(allowBranching: true),
      )) {
        return true;
      }
    }
    return false;
  }

  Map<String, Expression> _argumentsByParameterName(
    _FunctionLikeNode function,
    ArgumentList argumentList,
  ) {
    final argumentsByParameterName = <String, Expression>{};
    var positionalIndex = 0;
    for (final argument in argumentList.arguments) {
      if (argument is NamedExpression) {
        argumentsByParameterName[argument.name.label.name] =
            argument.expression;
        continue;
      }
      if (positionalIndex >= function.parameterNames.length) {
        continue;
      }
      final parameterName = function.parameterNames[positionalIndex];
      positionalIndex += 1;
      if (parameterName.isEmpty) {
        continue;
      }
      argumentsByParameterName[parameterName] = argument;
    }
    return argumentsByParameterName;
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

    final isImplicitThisTarget =
        target == null || target is ThisExpression || target is SuperExpression;
    final currentClass = _classStack.isEmpty ? null : _classStack.last;
    if (currentClass != null && isImplicitThisTarget) {
      final classMethod = unitIndex.resolveClassMethod(currentClass, name);
      if (classMethod != null) {
        return classMethod;
      }
    }

    final currentExtensionOnType =
        _extensionOnTypeStack.isEmpty ? null : _extensionOnTypeStack.last;
    if (currentExtensionOnType != null && isImplicitThisTarget) {
      final extensionMethod = unitIndex.resolveExtensionMethod(
        currentExtensionOnType,
        name,
      );
      if (extensionMethod != null) {
        return extensionMethod;
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
    required this.extensionMethods,
  });

  factory _CompilationUnitIndex.fromUnits(Iterable<CompilationUnit> units) {
    final collector = _CompilationUnitIndexCollector();
    for (final unit in units) {
      unit.visitChildren(collector);
    }
    return _CompilationUnitIndex(
      topLevelFunctions: collector.topLevelFunctions,
      classMethods: collector.classMethods,
      extensionMethods: collector.extensionMethods,
    );
  }

  final Map<String, _FunctionLikeNode> topLevelFunctions;
  final Map<String, Map<String, _FunctionLikeNode>> classMethods;
  final Map<String, Map<String, _FunctionLikeNode>> extensionMethods;

  _FunctionLikeNode? resolveClassMethod(String className, String methodName) {
    return classMethods[className]?[methodName];
  }

  _FunctionLikeNode? resolveExtensionMethod(String onType, String methodName) {
    return extensionMethods[onType]?[methodName];
  }
}

class _CompilationUnitIndexCollector extends RecursiveAstVisitor<void> {
  final Map<String, _FunctionLikeNode> topLevelFunctions =
      <String, _FunctionLikeNode>{};
  final Map<String, Map<String, _FunctionLikeNode>> classMethods =
      <String, Map<String, _FunctionLikeNode>>{};
  final Map<String, Map<String, _FunctionLikeNode>> extensionMethods =
      <String, Map<String, _FunctionLikeNode>>{};
  String? _currentClassName;
  String? _currentExtensionOnType;

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
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final previousExtensionOnType = _currentExtensionOnType;
    _currentExtensionOnType = node.extendedType.toSource();
    extensionMethods.putIfAbsent(
      _currentExtensionOnType!,
      () => <String, _FunctionLikeNode>{},
    );
    super.visitExtensionDeclaration(node);
    _currentExtensionOnType = previousExtensionOnType;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_currentClassName != null || _currentExtensionOnType != null) {
      return;
    }
    topLevelFunctions[node.name.lexeme] = _FunctionLikeNode(
      name: node.name.lexeme,
      body: node.functionExpression.body,
      parameterTypes: _parameterTypesOf(node.functionExpression.parameters),
      parameterNames: _parameterNamesOf(node.functionExpression.parameters),
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final className = _currentClassName;
    if (className != null) {
      classMethods.putIfAbsent(className, () => <String, _FunctionLikeNode>{})[
          node.name.lexeme] = _FunctionLikeNode(
        name: node.name.lexeme,
        body: node.body,
        ownerName: className,
        parameterTypes: _parameterTypesOf(node.parameters),
        parameterNames: _parameterNamesOf(node.parameters),
      );
      super.visitMethodDeclaration(node);
      return;
    }

    final extensionOnType = _currentExtensionOnType;
    if (extensionOnType != null) {
      extensionMethods.putIfAbsent(
        extensionOnType,
        () => <String, _FunctionLikeNode>{},
      )[node.name.lexeme] = _FunctionLikeNode(
        name: node.name.lexeme,
        body: node.body,
        ownerName: 'extension:$extensionOnType',
        parameterTypes: _parameterTypesOf(node.parameters),
        parameterNames: _parameterNamesOf(node.parameters),
      );
      super.visitMethodDeclaration(node);
      return;
    }

    super.visitMethodDeclaration(node);
  }
}

final class _FunctionLikeNode {
  const _FunctionLikeNode({
    required this.name,
    required this.body,
    required this.parameterTypes,
    required this.parameterNames,
    this.ownerName,
  });

  final String name;
  final String? ownerName;
  final FunctionBody body;
  final List<String?> parameterTypes;
  final List<String> parameterNames;

  String get signature => ownerName == null ? name : '$ownerName::$name';

  Set<String> parameterNamesUsedInUserFacingSinks() {
    if (parameterNames.isEmpty) {
      return const <String>{};
    }
    final visitor = _ParameterSinkUsageVisitor(parameterNames.toSet());
    body.visitChildren(visitor);
    return visitor.usedParameterNames;
  }

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

class _ParameterSinkUsageVisitor extends RecursiveAstVisitor<void> {
  _ParameterSinkUsageVisitor(this.parameterNames);

  final Set<String> parameterNames;
  final Set<String> usedParameterNames = <String>{};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructorName = node.constructorName.type.toSource();
    if (_userFacingConstructors.contains(constructorName) &&
        node.argumentList.arguments.isNotEmpty) {
      _recordIfParameter(node.argumentList.arguments.first);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName.name;
    if (_userFacingConstructors.contains(methodName) &&
        node.argumentList.arguments.isNotEmpty) {
      _recordIfParameter(node.argumentList.arguments.first);
    }
    for (final argument in _userFacingPositionalArgumentsForInvocation(
      node,
      node.argumentList,
    )) {
      _recordIfParameter(argument);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (node.function is SimpleIdentifier &&
        _userFacingConstructors.contains(
          (node.function as SimpleIdentifier).name,
        ) &&
        node.argumentList.arguments.isNotEmpty) {
      _recordIfParameter(node.argumentList.arguments.first);
    }
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    if (_isUserFacingNamedExpression(node)) {
      _recordIfParameter(node.expression);
    }
    super.visitNamedExpression(node);
  }

  void _recordIfParameter(Expression expression) {
    final unwrapped = expression.unParenthesized;
    if (unwrapped is SimpleIdentifier &&
        parameterNames.contains(unwrapped.name)) {
      usedParameterNames.add(unwrapped.name);
      return;
    }
    if (unwrapped is PostfixExpression &&
        unwrapped.operator.lexeme == '!' &&
        unwrapped.operand is SimpleIdentifier) {
      final operand = unwrapped.operand as SimpleIdentifier;
      if (parameterNames.contains(operand.name)) {
        usedParameterNames.add(operand.name);
      }
    }
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

List<String> _parameterNamesOf(FormalParameterList? parameters) {
  if (parameters == null) return const <String>[];
  return parameters.parameters.map((parameter) {
    final normalized =
        parameter is DefaultFormalParameter ? parameter.parameter : parameter;
    if (normalized is SimpleFormalParameter) {
      return normalized.name?.lexeme ?? '';
    }
    if (normalized is FieldFormalParameter) {
      return normalized.name.lexeme;
    }
    if (normalized is FunctionTypedFormalParameter) {
      return normalized.name.lexeme;
    }
    return '';
  }).toList(growable: false);
}
