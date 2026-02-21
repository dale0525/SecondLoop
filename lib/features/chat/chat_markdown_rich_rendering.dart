import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import 'chat_markdown_theme_presets.dart';

List<md.BlockSyntax> buildChatMarkdownBlockSyntaxes() {
  return const <md.BlockSyntax>[
    _LatexBlockSyntax(),
    _MarkmapBlockSyntax(),
  ];
}

List<md.InlineSyntax> buildChatMarkdownInlineSyntaxes() {
  return <md.InlineSyntax>[
    _LatexInlineSyntax(),
  ];
}

const double _kLatexBlockMinLayoutWidth = 220;
const double _kLatexBlockMaxLayoutWidth = 8192;
const double _kLatexInlineMaxViewportWidth = 420;

Map<String, MarkdownElementBuilder> buildChatMarkdownElementBuilders({
  required ChatMarkdownPreviewTheme previewTheme,
  required bool exportRenderMode,
}) {
  return <String, MarkdownElementBuilder>{
    'latex-inline': _LatexInlineBuilder(
      previewTheme: previewTheme,
      exportRenderMode: exportRenderMode,
    ),
    'latex-block': _LatexBlockBuilder(
      previewTheme: previewTheme,
      exportRenderMode: exportRenderMode,
    ),
    'markmap': _MarkmapBlockBuilder(
      previewTheme: previewTheme,
      exportRenderMode: exportRenderMode,
    ),
  };
}

class ChatMarkdownLatexInline extends StatelessWidget {
  const ChatMarkdownLatexInline({
    required this.expression,
    required this.previewTheme,
    required this.exportRenderMode,
    super.key,
  });

  final String expression;
  final ChatMarkdownPreviewTheme previewTheme;
  final bool exportRenderMode;

  @override
  Widget build(BuildContext context) {
    final style = (DefaultTextStyle.of(context).style).copyWith(
      color: previewTheme.textColor,
      fontSize: exportRenderMode ? 13 : null,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: previewTheme.inlineCodeBackground.withOpacity(
          exportRenderMode ? 0.34 : 0.26,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _kLatexInlineMaxViewportWidth,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _kLatexBlockMaxLayoutWidth,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _LatexFormula(
                  expression: expression,
                  textStyle: style,
                  blockMode: true,
                  fallbackColor: previewTheme.mutedTextColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatMarkdownLatexBlock extends StatelessWidget {
  const ChatMarkdownLatexBlock({
    required this.expression,
    required this.previewTheme,
    required this.exportRenderMode,
    super.key,
  });

  final String expression;
  final ChatMarkdownPreviewTheme previewTheme;
  final bool exportRenderMode;

  @override
  Widget build(BuildContext context) {
    final style = (DefaultTextStyle.of(context).style).copyWith(
      color: previewTheme.textColor,
      fontSize: exportRenderMode ? 14 : 15,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.symmetric(
        horizontal: exportRenderMode ? 12 : 14,
        vertical: exportRenderMode ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: previewTheme.codeBlockBackground,
        borderRadius: BorderRadius.circular(exportRenderMode ? 10 : 12),
        border: Border.all(color: previewTheme.borderColor.withOpacity(0.92)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final minFormulaWidth =
              math.max(_kLatexBlockMinLayoutWidth, availableWidth);
          final maxFormulaWidth =
              math.max(minFormulaWidth, _kLatexBlockMaxLayoutWidth);

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: minFormulaWidth,
                maxWidth: maxFormulaWidth,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _LatexFormula(
                  expression: expression,
                  textStyle: style,
                  blockMode: true,
                  fallbackColor: previewTheme.mutedTextColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ChatMarkdownMarkmap extends StatelessWidget {
  const ChatMarkdownMarkmap({
    required this.root,
    required this.previewTheme,
    required this.exportRenderMode,
    super.key,
  });

  final ChatMarkdownMarkmapNode root;
  final ChatMarkdownPreviewTheme previewTheme;
  final bool exportRenderMode;

  @override
  Widget build(BuildContext context) {
    final nodeTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: previewTheme.textColor,
              fontWeight: FontWeight.w600,
              fontSize: exportRenderMode ? 12.5 : 13.5,
            ) ??
        TextStyle(
          color: previewTheme.textColor,
          fontWeight: FontWeight.w600,
          fontSize: exportRenderMode ? 12.5 : 13.5,
        );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.symmetric(
        horizontal: exportRenderMode ? 10 : 12,
        vertical: exportRenderMode ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: previewTheme.codeBlockBackground,
        borderRadius: BorderRadius.circular(exportRenderMode ? 10 : 12),
        border: Border.all(color: previewTheme.borderColor.withOpacity(0.92)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final child in root.children)
                _MarkmapNodeView(
                  node: child,
                  depth: 0,
                  previewTheme: previewTheme,
                  textStyle: nodeTextStyle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LatexInlineSyntax extends md.InlineSyntax {
  _LatexInlineSyntax()
      : super(
          r'(?<!\\)\$(?!\$)(.+?)(?<!\\)\$(?!\$)',
          startCharacter: 0x24,
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = (match.group(1) ?? '').trim();
    if (formula.isEmpty) {
      parser.addNode(md.Text(match.group(0) ?? ''));
      return true;
    }

    final element = md.Element.empty('latex-inline')
      ..attributes['data-latex'] = formula;
    parser.addNode(element);
    return true;
  }
}

class _LatexBlockSyntax extends md.BlockSyntax {
  const _LatexBlockSyntax();

  static final RegExp _openingPattern = RegExp(r'^\s*\$\$(.*)$');
  static final RegExp _closingPattern = RegExp(r'^(.*?)(?<!\\)\$\$\s*$');

  @override
  RegExp get pattern => _openingPattern;

  @override
  md.Node? parse(md.BlockParser parser) {
    final opening = _openingPattern.firstMatch(parser.current.content);
    if (opening == null) return null;

    final lines = <String>[];
    final leadingContent = opening.group(1) ?? '';
    if (leadingContent.trim().isNotEmpty) {
      final inlineClose = _closingPattern.firstMatch(leadingContent);
      if (inlineClose != null) {
        final singleLine = (inlineClose.group(1) ?? '').trim();
        parser.advance();
        if (singleLine.isEmpty) return null;
        return md.Element.empty('latex-block')
          ..attributes['data-latex'] = singleLine;
      }

      lines.add(leadingContent);
    }

    parser.advance();

    while (!parser.isDone) {
      final line = parser.current.content;
      final closing = _closingPattern.firstMatch(line);
      if (closing != null) {
        final beforeClosing = closing.group(1) ?? '';
        if (beforeClosing.trim().isNotEmpty) {
          lines.add(beforeClosing);
        }
        parser.advance();
        break;
      }

      lines.add(line);
      parser.advance();
    }

    final formula = lines.join('\n').trim();
    if (formula.isEmpty) return null;
    return md.Element.empty('latex-block')..attributes['data-latex'] = formula;
  }
}

class _MarkmapBlockSyntax extends md.BlockSyntax {
  const _MarkmapBlockSyntax();

  static final RegExp _openingPattern = RegExp(
    r'^\s{0,3}(```+|~~~+)\s*(?:markmap|mindmap)\s*$',
    caseSensitive: false,
  );

  @override
  RegExp get pattern => _openingPattern;

  @override
  md.Node? parse(md.BlockParser parser) {
    final opening = _openingPattern.firstMatch(parser.current.content);
    if (opening == null) return null;

    final fence = opening.group(1)!;
    final fenceChar = fence[0];
    final closingPattern = RegExp(
      r'^\s{0,3}'
      '${RegExp.escape(fenceChar)}{${fence.length},}'
      r'\s*$',
    );

    parser.advance();

    final lines = <String>[];
    while (!parser.isDone) {
      final line = parser.current.content;
      if (closingPattern.hasMatch(line)) {
        parser.advance();
        break;
      }
      lines.add(line);
      parser.advance();
    }

    final source = lines.join('\n').trimRight();
    if (source.trim().isEmpty) return null;
    return md.Element.empty('markmap')..attributes['data-markmap'] = source;
  }
}

class _LatexInlineBuilder extends MarkdownElementBuilder {
  _LatexInlineBuilder({
    required this.previewTheme,
    required this.exportRenderMode,
  });

  final ChatMarkdownPreviewTheme previewTheme;
  final bool exportRenderMode;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final expression =
        (element.attributes['data-latex'] ?? element.textContent).trim();
    if (expression.isEmpty) {
      return const SizedBox.shrink();
    }

    return ChatMarkdownLatexInline(
      expression: expression,
      previewTheme: previewTheme,
      exportRenderMode: exportRenderMode,
    );
  }
}

class _LatexBlockBuilder extends MarkdownElementBuilder {
  _LatexBlockBuilder({
    required this.previewTheme,
    required this.exportRenderMode,
  });

  final ChatMarkdownPreviewTheme previewTheme;
  final bool exportRenderMode;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final expression =
        (element.attributes['data-latex'] ?? element.textContent).trim();
    if (expression.isEmpty) {
      return const SizedBox.shrink();
    }

    return ChatMarkdownLatexBlock(
      expression: expression,
      previewTheme: previewTheme,
      exportRenderMode: exportRenderMode,
    );
  }
}

class _LatexFormula extends StatelessWidget {
  const _LatexFormula({
    required this.expression,
    required this.textStyle,
    required this.blockMode,
    required this.fallbackColor,
  });

  final String expression;
  final TextStyle textStyle;
  final bool blockMode;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    return Math.tex(
      expression,
      mathStyle: blockMode ? MathStyle.display : MathStyle.text,
      textScaleFactor: 1.0,
      textStyle: textStyle,
      onErrorFallback: (error) {
        return Text(
          expression,
          style: textStyle.copyWith(
            color: fallbackColor,
            fontStyle: FontStyle.italic,
          ),
        );
      },
    );
  }
}

class _MarkmapBlockBuilder extends MarkdownElementBuilder {
  _MarkmapBlockBuilder({
    required this.previewTheme,
    required this.exportRenderMode,
  });

  final ChatMarkdownPreviewTheme previewTheme;
  final bool exportRenderMode;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final source =
        (element.attributes['data-markmap'] ?? element.textContent).trim();
    if (source.isEmpty) {
      return const SizedBox.shrink();
    }

    final root = _parseMarkmapTree(source);
    if (root.children.isEmpty) {
      return const SizedBox.shrink();
    }

    return ChatMarkdownMarkmap(
      root: root,
      previewTheme: previewTheme,
      exportRenderMode: exportRenderMode,
    );
  }
}

class ChatMarkdownMarkmapNode {
  ChatMarkdownMarkmapNode(this.label);

  String label;
  final List<ChatMarkdownMarkmapNode> children = <ChatMarkdownMarkmapNode>[];
}

class _MarkmapNodeView extends StatelessWidget {
  const _MarkmapNodeView({
    required this.node,
    required this.depth,
    required this.previewTheme,
    required this.textStyle,
  });

  final ChatMarkdownMarkmapNode node;
  final int depth;
  final ChatMarkdownPreviewTheme previewTheme;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final indent = depth * 20.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: indent),
              if (depth > 0)
                Container(
                  width: 12,
                  height: 1,
                  color: previewTheme.quoteBorder.withOpacity(0.62),
                ),
              if (depth > 0) const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: previewTheme.inlineCodeBackground.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: previewTheme.borderColor.withOpacity(0.78),
                  ),
                ),
                child: Text(node.label, style: textStyle),
              ),
            ],
          ),
          for (final child in node.children)
            _MarkmapNodeView(
              node: child,
              depth: depth + 1,
              previewTheme: previewTheme,
              textStyle: textStyle,
            ),
        ],
      ),
    );
  }
}

ChatMarkdownMarkmapNode _parseMarkmapTree(String source) {
  final root = ChatMarkdownMarkmapNode('root');
  final stack = <({int level, ChatMarkdownMarkmapNode node})>[
    (level: 0, node: root),
  ];

  final lines =
      source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

  for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line.trim().isEmpty) {
      continue;
    }

    final parsed = _parseMarkmapLine(line);
    if (parsed == null) {
      final text = _stripMarkmapInlineMarkdown(line);
      if (text.isNotEmpty && stack.length > 1) {
        stack.last.node.label = '${stack.last.node.label} $text'.trim();
      }
      continue;
    }

    while (stack.length > 1 && stack.last.level >= parsed.level) {
      stack.removeLast();
    }

    final node = ChatMarkdownMarkmapNode(parsed.label);
    stack.last.node.children.add(node);
    stack.add((level: parsed.level, node: node));
  }

  if (root.children.isEmpty) {
    final fallback = _stripMarkmapInlineMarkdown(source.trim());
    if (fallback.isNotEmpty) {
      root.children.add(ChatMarkdownMarkmapNode(fallback));
    }
  }

  return root;
}

({int level, String label})? _parseMarkmapLine(String line) {
  final heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*$').firstMatch(line);
  if (heading != null) {
    final level = heading.group(1)!.length.clamp(1, 6);
    final label = _stripMarkmapInlineMarkdown(heading.group(2) ?? '');
    if (label.isEmpty) return null;
    return (level: level, label: label);
  }

  final listItem =
      RegExp(r'^(\s*)(?:[-+*]|\d+[.)])\s+(.*?)\s*$').firstMatch(line);
  if (listItem != null) {
    final indent = (listItem.group(1) ?? '').replaceAll('\t', '  ').length;
    final level = 1 + (indent ~/ 2);
    final label = _stripMarkmapInlineMarkdown(listItem.group(2) ?? '');
    if (label.isEmpty) return null;
    return (level: level, label: label);
  }

  return null;
}

String _stripMarkmapInlineMarkdown(String input) {
  var text = input.trim();
  if (text.isEmpty) return text;

  for (final replacement in <({RegExp pattern, int group})>[
    (pattern: RegExp(r'!\[([^\]]*)\]\([^)]*\)'), group: 1),
    (pattern: RegExp(r'\[([^\]]+)\]\([^)]*\)'), group: 1),
    (pattern: RegExp(r'`([^`]*)`'), group: 1),
    (pattern: RegExp(r'(\*\*|__)(.+?)\1'), group: 2),
    (pattern: RegExp(r'(\*|_)(.+?)\1'), group: 2),
    (pattern: RegExp(r'~~(.+?)~~'), group: 1),
  ]) {
    text = text.replaceAllMapped(
      replacement.pattern,
      (match) => match.group(replacement.group) ?? '',
    );
  }

  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
