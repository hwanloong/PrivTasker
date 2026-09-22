import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../theme/app_theme.dart';

/// 轻量 Markdown 渲染器。
///
/// 为什么不直接用 flutter_markdown：那份实现会把字体交给它自己的默认值，
/// 没法保证「英文 Times、中文宋体、代码 Consolas」这套混排落到每个 span 上。
/// 这里自己解析，样式完全可控。
///
/// 支持：标题、段落、无序/有序列表、引用、分割线、围栏代码块、
/// **表格**，以及行内的 **加粗**、*斜体*、`行内代码`、[链接](url)、~~删除线~~。
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.text,
    this.baseSize = 15,
    this.onOpenLink,
  });

  final String text;
  final double baseSize;
  final void Function(String url)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final AppSurface s = AppSurface.of(context);
    final List<_Block> blocks = _parseBlocks(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks
          .map((_Block b) => _buildBlock(context, b, s))
          .toList(),
    );
  }

  Widget _buildBlock(BuildContext context, _Block block, AppSurface s) {
    final TextStyle base = AppFonts.body(size: baseSize, color: s.text);
    final TextStyle inlineCode = AppFonts.code(
      size: baseSize - 1.6,
      color: s.text,
      height: 1.5,
    );

    switch (block) {
      case final _CodeBlock b:
        return _CodeBlockView(block: b, surface: s);

      case final _MathBlock m:
        // 手机上宽公式必然超出屏幕，所以外面套横向滚动，而不是让它被裁掉
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              m.latex,
              mathStyle: MathStyle.display,
              textStyle: AppFonts.body(size: baseSize, color: s.text),
              onErrorFallback: (FlutterMathException _) =>
                  _mathFallback(m.latex, s, baseSize),
            ),
          ),
        );

      case final _TableBlock b:
        return _TableView(
          block: b,
          surface: s,
          baseSize: baseSize,
          onOpenLink: onOpenLink,
        );

      case final _Heading h:
        final double size = switch (h.level) {
          1 => baseSize + 7,
          2 => baseSize + 4.5,
          3 => baseSize + 2.5,
          _ => baseSize + 1,
        };
        return Padding(
          padding: EdgeInsets.only(top: h.level <= 2 ? 14 : 10, bottom: 5),
          child: RichText(
            text: TextSpan(
              children: _inlineSpans(
                h.text,
                AppFonts.body(
                  size: size,
                  weight: FontWeight.w700,
                  color: s.text,
                  height: 1.35,
                ),
                inlineCode,
                s,
                onOpenLink,
              ),
            ),
          ),
        );

      case _Hr():
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(color: s.border, height: 0.8, thickness: 0.8),
        );

      case final _Quote q:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: s.border, width: 3),
              ),
            ),
            child: RichText(
              text: TextSpan(
                children: _inlineSpans(
                  q.text,
                  base.copyWith(color: s.muted),
                  inlineCode.copyWith(color: s.muted),
                  s,
                  onOpenLink,
                ),
              ),
            ),
          ),
        );

      case final _ListBlock lb:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lb.items.map((_Item it) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 4.0 + it.indent * 14.0,
                  top: 2.5,
                  bottom: 2.5,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 22,
                      child: Text(
                        it.marker,
                        style: AppFonts.body(
                          size: baseSize,
                          color: s.muted,
                          height: 1.62,
                        ),
                      ),
                    ),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: _inlineSpans(
                              it.text, base, inlineCode, s, onOpenLink),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );

      case final _Paragraph p:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: RichText(
            text: TextSpan(
              children:
                  _inlineSpans(p.text, base, inlineCode, s, onOpenLink),
            ),
          ),
        );
    }
  }
}

// ---------------------------------------------------------------- 行内解析

final RegExp _inlinePattern = RegExp(
  r'(\*\*(.+?)\*\*)' // 1,2 加粗
  r'|(`([^`]+?)`)' // 3,4 行内代码
  r'|(\[([^\]]+)\]\(([^)\s]+)\))' // 5,6,7 链接
  r'|(\*([^*\n]+?)\*)' // 8,9 斜体
  r'|(~~(.+?)~~)', // 10,11 删除线
);

/// 行内数学公式：`$...$` 或 `\(...\)`。
///
/// 用「开 `$` 后不能紧跟空白、闭 `$` 前不能是空白」这条通用规则，
/// 这样「价格是 $5 到 $10」不会被误判成公式。
/// 刻意不用 lookbehind —— Dart 的 RegExp 在各平台上对它的支持不一致。
final RegExp _inlineMathPattern = RegExp(
  r'\$(?!\s)((?:\\.|[^$\\\n])*?[^\s$\\])\$'
  r'|\\\(((?:\\.|[^\\\n])+?)\\\)',
);

/// 数学解析失败时的兜底：把原始 LaTeX 显示出来，而不是整块渲染崩掉。
Widget _mathFallback(String latex, AppSurface s, double size) {
  return Text(
    latex,
    style: AppFonts.code(size: size - 1, color: s.muted),
  );
}

List<InlineSpan> _inlineSpans(
  String src,
  TextStyle base,
  TextStyle code,
  AppSurface s,
  void Function(String url)? onOpenLink,
) {
  // 先按行内公式切分：公式段直接交给 KaTeX 渲染，
  // 其余段落再走常规的行内解析。这样公式里的 `*` `_` 不会被当成强调标记。
  if (!src.contains(r'$') && !src.contains(r'\(')) {
    return _plainInline(src, base, code, s, onOpenLink);
  }

  final List<InlineSpan> spans = <InlineSpan>[];
  int last = 0;

  for (final RegExpMatch m in _inlineMathPattern.allMatches(src)) {
    if (m.start > last) {
      spans.addAll(
          _plainInline(src.substring(last, m.start), base, code, s, onOpenLink));
    }

    final String latex = (m.group(1) ?? m.group(2) ?? '').trim();
    if (latex.isEmpty) {
      spans.add(TextSpan(text: src.substring(m.start, m.end), style: base));
    } else {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          latex,
          mathStyle: MathStyle.text,
          textStyle: base,
          onErrorFallback: (FlutterMathException _) =>
              _mathFallback(latex, s, base.fontSize ?? 15),
        ),
      ));
    }
    last = m.end;
  }

  if (last < src.length) {
    spans.addAll(_plainInline(src.substring(last), base, code, s, onOpenLink));
  }
  return spans;
}

/// 不含公式的常规行内解析
List<InlineSpan> _plainInline(
  String src,
  TextStyle base,
  TextStyle code,
  AppSurface s,
  void Function(String url)? onOpenLink,
) {
  final List<InlineSpan> spans = <InlineSpan>[];
  int last = 0;

  for (final RegExpMatch m in _inlinePattern.allMatches(src)) {
    if (m.start > last) {
      spans.add(TextSpan(text: src.substring(last, m.start), style: base));
    }

    if (m.group(2) != null) {
      spans.add(TextSpan(
        text: m.group(2),
        style: base.copyWith(fontWeight: FontWeight.w700),
      ));
    } else if (m.group(4) != null) {
      spans.add(TextSpan(text: ' ${m.group(4)} ', style: code));
    } else if (m.group(6) != null) {
      final String label = m.group(6)!;
      final String url = m.group(7)!;
      final TextStyle linkStyle = base.copyWith(
        color: AppColors.accent,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.accent.withValues(alpha: 0.4),
      );
      // 用 WidgetSpan 承载点击：在 StatelessWidget 里持有 TapGestureRecognizer
      // 没法可靠 dispose，会泄漏。
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: onOpenLink == null ? null : () => onOpenLink(url),
          child: Text(label, style: linkStyle),
        ),
      ));
    } else if (m.group(9) != null) {
      spans.add(TextSpan(
        text: m.group(9),
        style: base.copyWith(fontStyle: FontStyle.italic),
      ));
    } else if (m.group(11) != null) {
      spans.add(TextSpan(
        text: m.group(11),
        style: base.copyWith(decoration: TextDecoration.lineThrough),
      ));
    }

    last = m.end;
  }

  if (last < src.length) {
    spans.add(TextSpan(text: src.substring(last), style: base));
  }
  return spans;
}

// ---------------------------------------------------------------- 代码块

class _CodeBlockView extends StatelessWidget {
  const _CodeBlockView({required this.block, required this.surface});

  final _CodeBlock block;
  final AppSurface surface;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (block.lang.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 5),
              child: Text(
                block.lang,
                style: AppFonts.body(
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: surface.muted,
                  height: 1.2,
                ),
              ),
            ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: surface.codeBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: surface.border, width: 0.7),
            ),
            child: Stack(
              children: <Widget>[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 11, 46, 11),
                  child: Text(
                    block.code,
                    style: AppFonts.code(size: 13, color: surface.text),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    iconSize: 15,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    tooltip: '复制',
                    icon: Icon(Icons.copy_rounded, color: surface.muted),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: block.code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制'),
                          duration: Duration(milliseconds: 1200),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 表格

/// 表格渲染。
///
/// 手机上表格放不下是常态，所以：
///  · 整表可横向滚动；
///  · 单列宽度按内容估算并限幅，超长的单元格自动换行而不是把表格撑到天边。
class _TableView extends StatelessWidget {
  const _TableView({
    required this.block,
    required this.surface,
    required this.baseSize,
    this.onOpenLink,
  });

  final _TableBlock block;
  final AppSurface surface;
  final double baseSize;
  final void Function(String url)? onOpenLink;

  /// 粗估一段文本的像素宽度：CJK/全角按 1 em，其余按 0.56 em。
  /// 不需要精确——只用来给列定个合理宽度。
  static double _estimate(String text, double fontSize) {
    double w = 0;
    for (final int r in text.runes) {
      final bool wide = (r >= 0x1100 && r <= 0x115F) ||
          (r >= 0x2E80 && r <= 0xA4CF) ||
          (r >= 0xAC00 && r <= 0xD7A3) ||
          (r >= 0xF900 && r <= 0xFAFF) ||
          (r >= 0xFE30 && r <= 0xFE6F) ||
          (r >= 0xFF00 && r <= 0xFF60) ||
          (r >= 0xFFE0 && r <= 0xFFE6);
      w += fontSize * (wide ? 1.0 : 0.56);
    }
    return w;
  }

  List<double> _columnWidths() {
    final int cols = block.headers.length;
    final List<double> widths = List<double>.filled(cols, 0);

    for (int c = 0; c < cols; c++) {
      double w = _estimate(block.headers[c], baseSize - 1.5);
      for (final List<String> row in block.rows) {
        if (c < row.length) {
          final double rw = _estimate(row[c], baseSize - 1.5);
          if (rw > w) w = rw;
        }
      }
      // +20 是左右内边距，再夹在 [58, 240] 之间
      widths[c] = (w + 22).clamp(58.0, 240.0);
    }
    return widths;
  }

  @override
  Widget build(BuildContext context) {
    final List<double> widths = _columnWidths();
    final TextStyle headStyle = AppFonts.body(
      size: baseSize - 1.5,
      weight: FontWeight.w700,
      color: surface.text,
      height: 1.45,
    );
    final TextStyle cellStyle = AppFonts.body(
      size: baseSize - 1.5,
      color: surface.text,
      height: 1.45,
    );
    final TextStyle codeStyle = AppFonts.code(
      size: baseSize - 2.3,
      color: surface.text,
      height: 1.45,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: surface.border, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildRow(
                block.headers,
                widths,
                headStyle,
                codeStyle,
                isHeader: true,
              ),
              for (int i = 0; i < block.rows.length; i++)
                _buildRow(
                  block.rows[i],
                  widths,
                  cellStyle,
                  codeStyle,
                  isHeader: false,
                  isLast: i == block.rows.length - 1,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    List<String> cells,
    List<double> widths,
    TextStyle style,
    TextStyle codeStyle, {
    required bool isHeader,
    bool isLast = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isHeader ? surface.surface : null,
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: surface.border, width: 0.7),
              ),
      ),
      child: IntrinsicHeight(
        // 必须包一层 IntrinsicHeight：横向滚动容器里高度约束是无穷的，
        // 直接给 Row 用 CrossAxisAlignment.stretch 会触发
        // 「BoxConstraints forces an infinite height」。
        // IntrinsicHeight 先把行高算出来，再让各单元格等高。
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < widths.length; i++)
              Container(
                width: widths[i],
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: i == 0
                    ? null
                    : BoxDecoration(
                        border: Border(
                          left: BorderSide(color: surface.border, width: 0.7),
                        ),
                      ),
                child: RichText(
                  text: TextSpan(
                    children: _inlineSpans(
                      i < cells.length ? cells[i] : '',
                      style,
                      codeStyle,
                      surface,
                      onOpenLink,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 解析

sealed class _Block {
  const _Block();
}

class _Paragraph extends _Block {
  const _Paragraph(this.text);
  final String text;
}

class _Heading extends _Block {
  const _Heading(this.level, this.text);
  final int level;
  final String text;
}

class _CodeBlock extends _Block {
  const _CodeBlock(this.lang, this.code);
  final String lang;
  final String code;
}

/// 块级数学公式（`$$...$$` 或 `\[...\]`）
class _MathBlock extends _Block {
  const _MathBlock(this.latex);
  final String latex;
}

class _Quote extends _Block {
  const _Quote(this.text);
  final String text;
}

class _Hr extends _Block {
  const _Hr();
}

class _Item {
  const _Item(this.indent, this.marker, this.text);
  final int indent;
  final String marker;
  final String text;
}

class _ListBlock extends _Block {
  const _ListBlock(this.items);
  final List<_Item> items;
}

class _TableBlock extends _Block {
  const _TableBlock(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;
}

final RegExp _reFence = RegExp(r'^\s*```(.*)$');
final RegExp _reHeading = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _reHr = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
final RegExp _reList = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$');
final RegExp _reQuote = RegExp(r'^\s*>\s?(.*)$');
/// 表格分隔行：只由 | - : 空格组成，且至少有一个短横
final RegExp _reTableSep = RegExp(r'^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$');

bool _startsBlock(String line) {
  final String t = line.trimLeft();
  return t.startsWith('```') ||
      t.startsWith(r'$$') ||
      t.startsWith(r'\[') ||
      _reHeading.hasMatch(line) ||
      _reHr.hasMatch(line) ||
      _reList.hasMatch(line) ||
      t.startsWith('>');
}

/// 拆一行表格单元格，容忍首尾竖线可有可无
List<String> _splitTableRow(String line) {
  String s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').map((String c) => c.trim()).toList();
}

bool _isTableSeparator(String line) {
  final String s = line.trim();
  if (!s.contains('-')) return false;
  if (!s.contains('|') && !_reHr.hasMatch(s)) {
    // 没有竖线时只认 `---` 这种，避免把普通文本当分隔行
    return false;
  }
  return _reTableSep.hasMatch(s);
}

/// 判断第 [i] 行是否是一张表的开始（当前行有内容 + 下一行是分隔行）
bool _isTableStart(List<String> lines, int i) {
  if (i + 1 >= lines.length) return false;
  final String head = lines[i].trim();
  if (head.isEmpty) return false;
  if (!head.contains('|')) return false;
  return _isTableSeparator(lines[i + 1]);
}

List<_Block> _parseBlocks(String src) {
  final List<String> lines = src.replaceAll('\r\n', '\n').split('\n');
  final List<_Block> blocks = <_Block>[];
  int i = 0;

  while (i < lines.length) {
    final String line = lines[i];

    // 围栏代码块
    final RegExpMatch? fence = _reFence.firstMatch(line);
    if (fence != null) {
      final String lang = fence.group(1)!.trim();
      final List<String> buf = <String>[];
      i++;
      while (i < lines.length && !_reFence.hasMatch(lines[i])) {
        buf.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++; // 跳过收尾的 ```
      blocks.add(_CodeBlock(lang, buf.join('\n')));
      continue;
    }

    // 块级公式：$$ ... $$（可跨行）或 \[ ... \]
    final String trimmed = line.trim();
    if (trimmed.startsWith(r'$$') || trimmed.startsWith(r'\[')) {
      final bool dollar = trimmed.startsWith(r'$$');
      final String open = dollar ? r'$$' : r'\[';
      final String close = dollar ? r'$$' : r'\]';

      // 单行形式：$$x = 1$$
      if (trimmed.length > open.length + close.length &&
          trimmed.endsWith(close)) {
        blocks.add(_MathBlock(trimmed
            .substring(open.length, trimmed.length - close.length)
            .trim()));
        i++;
        continue;
      }

      // 多行形式：一直读到收尾标记
      final List<String> buf = <String>[];
      final String rest = trimmed.substring(open.length).trim();
      if (rest.isNotEmpty) buf.add(rest);
      i++;
      while (i < lines.length && !lines[i].trim().endsWith(close)) {
        buf.add(lines[i]);
        i++;
      }
      if (i < lines.length) {
        final String tail = lines[i].trim();
        final String inner =
            tail.substring(0, tail.length - close.length).trim();
        if (inner.isNotEmpty) buf.add(inner);
        i++;
      }
      blocks.add(_MathBlock(buf.join('\n').trim()));
      continue;
    }

    // 表格：必须排在段落之前，否则表头和分隔行会被当成两段普通文字
    if (_isTableStart(lines, i)) {
      final List<String> headers = _splitTableRow(lines[i]);
      i += 2; // 表头 + 分隔行
      final List<List<String>> rows = <List<String>>[];
      while (i < lines.length) {
        final String t = lines[i].trim();
        if (t.isEmpty || !t.contains('|')) break;
        // 遇到新的块级语法就停
        if (_reHeading.hasMatch(t) || _reFence.hasMatch(t)) break;
        rows.add(_splitTableRow(t));
        i++;
      }
      blocks.add(_TableBlock(headers, rows));
      continue;
    }

    final RegExpMatch? h = _reHeading.firstMatch(line);
    if (h != null) {
      blocks.add(_Heading(h.group(1)!.length, h.group(2)!.trim()));
      i++;
      continue;
    }

    if (_reHr.hasMatch(line)) {
      blocks.add(const _Hr());
      i++;
      continue;
    }

    // 列表：连续的行合并成一个列表块
    final RegExpMatch? l = _reList.firstMatch(line);
    if (l != null) {
      final List<_Item> items = <_Item>[];
      while (i < lines.length) {
        final RegExpMatch? m = _reList.firstMatch(lines[i]);
        if (m == null) break;
        final int indent = (m.group(1)!.length / 2).floor();
        final String token = m.group(2)!;
        final bool ordered = RegExp(r'^\d').hasMatch(token);
        items.add(_Item(
          indent,
          ordered ? token.replaceAll(')', '.').trim() : '·',
          m.group(3)!.trim(),
        ));
        i++;
      }
      blocks.add(_ListBlock(items));
      continue;
    }

    final RegExpMatch? q = _reQuote.firstMatch(line);
    if (q != null) {
      final List<String> buf = <String>[];
      while (i < lines.length) {
        final RegExpMatch? m = _reQuote.firstMatch(lines[i]);
        if (m == null) break;
        buf.add(m.group(1)!.trim());
        i++;
      }
      blocks.add(_Quote(buf.join(' ')));
      continue;
    }

    if (line.trim().isEmpty) {
      i++;
      continue;
    }

    // 普通段落：一直吃到空行或下一个块开始
    final List<String> buf = <String>[];
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !_startsBlock(lines[i]) &&
        !_isTableStart(lines, i)) {
      buf.add(lines[i].trim());
      i++;
    }
    if (buf.isNotEmpty) blocks.add(_Paragraph(buf.join(' ')));
  }

  return blocks;
}
