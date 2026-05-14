part of 'no_hardcoded_user_strings_guard.dart';

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
