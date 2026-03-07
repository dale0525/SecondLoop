import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No hardcoded user-facing strings in lib/', () {
    final directDisallowedPatterns = <RegExp>[
      RegExp(r'''Text\(\s*['"]'''),
      RegExp(r'''labelText:\s*['"]'''),
      RegExp(r'''hintText:\s*['"]'''),
      RegExp(r'''tooltip:\s*['"]'''),
      RegExp(r'''localizedReason:\s*['"]'''),
    ];

    final excludedPaths = <String>{
      'lib/i18n/strings.g.dart',
      'lib/src/rust/frb_generated.dart',
      'lib/src/rust/frb_generated.io.dart',
      'lib/src/rust/frb_generated.web.dart',
    };

    final offenders = <String>[];
    final libDir = Directory('lib');
    if (!libDir.existsSync()) {
      fail('Missing lib/ directory');
    }

    for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      if (excludedPaths.contains(entity.path)) continue;

      final content = entity.readAsStringSync();

      for (final pattern in directDisallowedPatterns) {
        if (!pattern.hasMatch(content)) continue;
        offenders.add('${entity.path}: matches ${pattern.pattern}');
        break;
      }

      final parsed = parseString(
        content: content,
        path: entity.path,
        throwIfDiagnostics: false,
      );
      final visitor = _HardcodedUserFacingStringVisitor(entity.path);
      parsed.unit.visitChildren(visitor);
      offenders.addAll(visitor.offenders);
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}

class _HardcodedUserFacingStringVisitor extends RecursiveAstVisitor<void> {
  _HardcodedUserFacingStringVisitor(this.path);

  final String path;
  final List<String> offenders = <String>[];
  final List<Map<String, Expression>> _scopes = <Map<String, Expression>>[
    <String, Expression>{},
  ];

  @override
  void visitBlock(Block node) {
    _scopes.add(<String, Expression>{});
    super.visitBlock(node);
    _scopes.removeLast();
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    if (initializer != null) {
      _scopes.last[node.name.lexeme] = initializer;
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'Text' &&
        node.argumentList.arguments.isNotEmpty) {
      _checkExpression(node.argumentList.arguments.first, sink: 'Text()');
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
    if (!_isHardcodedUserFacingExpression(expression, <String>{})) {
      return;
    }
    offenders.add(
        '$path: $sink uses composed hardcoded string via ${expression.toSource()}');
  }

  bool _isHardcodedUserFacingExpression(
    Expression expression,
    Set<String> resolvingNames,
  ) {
    final unwrapped = expression.unParenthesized;

    if (unwrapped is SimpleStringLiteral) {
      return unwrapped.value.trim().isNotEmpty;
    }
    if (unwrapped is StringInterpolation) {
      return true;
    }
    if (unwrapped is AdjacentStrings) {
      return true;
    }
    if (unwrapped is BinaryExpression && unwrapped.operator.lexeme == '+') {
      return _containsDirectDisplayString(unwrapped.leftOperand) ||
          _containsDirectDisplayString(unwrapped.rightOperand) ||
          _isHardcodedUserFacingExpression(
              unwrapped.leftOperand, resolvingNames) ||
          _isHardcodedUserFacingExpression(
              unwrapped.rightOperand, resolvingNames);
    }
    if (unwrapped is SimpleIdentifier) {
      final name = unwrapped.name;
      if (!resolvingNames.add(name)) {
        return false;
      }
      final initializer = _resolveVariable(name);
      if (initializer == null) {
        resolvingNames.remove(name);
        return false;
      }
      final result =
          _isHardcodedUserFacingExpression(initializer, resolvingNames);
      resolvingNames.remove(name);
      return result;
    }

    return false;
  }

  bool _containsDirectDisplayString(Expression expression) {
    final unwrapped = expression.unParenthesized;
    return unwrapped is SimpleStringLiteral &&
        unwrapped.value.trim().isNotEmpty;
  }

  Expression? _resolveVariable(String name) {
    for (final scope in _scopes.reversed) {
      final initializer = scope[name];
      if (initializer != null) {
        return initializer;
      }
    }
    return null;
  }
}

const Set<String> _userFacingNamedParameters = <String>{
  'labelText',
  'hintText',
  'tooltip',
  'localizedReason',
};
