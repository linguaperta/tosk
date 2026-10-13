/// A tiny markdown renderer for grammar notes: headings, paragraphs, bullet and
/// numbered lists, block quotes, fenced code, tables, horizontal rules, and inline
/// **bold**, *italic*, `code` and ~~strike~~. No dependency, no HTML, no links
/// (notes are bundled offline content).
library;

import 'package:flutter/material.dart';

// ------------------------------------------------------------------ model

sealed class MdBlock {
  const MdBlock();
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.text);
  final int level;
  final String text;
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.text);
  final String text;
}

class MdList extends MdBlock {
  const MdList(this.items, {this.ordered = false, this.start = 1});
  final List<String> items;
  final bool ordered;
  final int start;
}

class MdQuote extends MdBlock {
  const MdQuote(this.text);
  final String text;
}

class MdCode extends MdBlock {
  const MdCode(this.text);
  final String text;
}

class MdTable extends MdBlock {
  const MdTable(this.header, this.rows);
  final List<String> header;
  final List<List<String>> rows;
}

class MdRule extends MdBlock {
  const MdRule();
}

enum MdStyle { bold, italic, code, strike }

class MdSpan {
  const MdSpan(this.text, [this.styles = const {}]);
  final String text;
  final Set<MdStyle> styles;
  @override
  String toString() => styles.isEmpty ? text : '$text$styles';
}

// ------------------------------------------------------------------ parsing

final _heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
final _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
final _ordered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
final _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
final _tableSep = RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');

List<MdBlock> parseMarkdown(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MdBlock>[];
  final para = <String>[];

  void flushPara() {
    if (para.isNotEmpty) {
      blocks.add(MdParagraph(para.join(' ')));
      para.clear();
    }
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      flushPara();
      i++;
      continue;
    }
    if (trimmed.startsWith('```')) {
      flushPara();
      final code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        code.add(lines[i]);
        i++;
      }
      i++; // closing fence (or end)
      blocks.add(MdCode(code.join('\n')));
      continue;
    }
    final h = _heading.firstMatch(trimmed);
    if (h != null) {
      flushPara();
      blocks.add(MdHeading(h.group(1)!.length, h.group(2)!));
      i++;
      continue;
    }
    if (_rule.hasMatch(trimmed)) {
      flushPara();
      blocks.add(const MdRule());
      i++;
      continue;
    }
    if (trimmed.startsWith('|') && i + 1 < lines.length && _tableSep.hasMatch(lines[i + 1])) {
      flushPara();
      final header = _cells(trimmed);
      final rows = <List<String>>[];
      i += 2;
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final r = _cells(lines[i].trim());
        rows.add([for (var c = 0; c < header.length; c++) c < r.length ? r[c] : '']);
        i++;
      }
      blocks.add(MdTable(header, rows));
      continue;
    }
    if (trimmed.startsWith('>')) {
      flushPara();
      final quote = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        quote.add(lines[i].trim().substring(1).trim());
        i++;
      }
      blocks.add(MdQuote(quote.join(' ')));
      continue;
    }
    final b = _bullet.firstMatch(line);
    final o = _ordered.firstMatch(line);
    if (b != null || o != null) {
      flushPara();
      final ordered = b == null;
      final start = ordered ? int.parse(o!.group(1)!) : 1;
      final items = <String>[];
      while (i < lines.length) {
        final l = lines[i];
        final bm = _bullet.firstMatch(l);
        final om = _ordered.firstMatch(l);
        if (!ordered && bm != null) {
          items.add(bm.group(1)!);
        } else if (ordered && om != null) {
          items.add(om.group(2)!);
        } else if (l.trim().isNotEmpty && l.startsWith(RegExp(r'\s{2,}')) && items.isNotEmpty) {
          items[items.length - 1] = '${items.last} ${l.trim()}'; // continuation line
        } else {
          break;
        }
        i++;
      }
      blocks.add(MdList(items, ordered: ordered, start: start));
      continue;
    }
    para.add(trimmed);
    i++;
  }
  flushPara();
  return blocks;
}

List<String> _cells(String row) {
  var r = row.trim();
  if (r.startsWith('|')) r = r.substring(1);
  if (r.endsWith('|')) r = r.substring(0, r.length - 1);
  return [for (final c in r.split('|')) c.trim()];
}

/// Splits inline markdown into styled spans. Unmatched markers stay literal.
List<MdSpan> parseInline(String text) {
  final out = <MdSpan>[];
  final buf = StringBuffer();

  void emit(Set<MdStyle> styles) {
    if (buf.isEmpty) return;
    final s = buf.toString();
    buf.clear();
    if (out.isNotEmpty && _sameStyles(out.last.styles, styles)) {
      out[out.length - 1] = MdSpan(out.last.text + s, styles);
    } else {
      out.add(MdSpan(s, styles));
    }
  }

  void walk(String t, Set<MdStyle> styles) {
    var i = 0;
    while (i < t.length) {
      final ch = t[i];
      if (ch == r'\' && i + 1 < t.length) {
        buf.write(t[i + 1]);
        i += 2;
        continue;
      }
      if (ch == '`') {
        final end = t.indexOf('`', i + 1);
        if (end > i) {
          emit(styles);
          buf.write(t.substring(i + 1, end));
          emit({...styles, MdStyle.code});
          i = end + 1;
          continue;
        }
      }
      String? marker;
      MdStyle? style;
      if (t.startsWith('**', i) || t.startsWith('__', i)) {
        marker = t.substring(i, i + 2);
        style = MdStyle.bold;
      } else if (t.startsWith('~~', i)) {
        marker = '~~';
        style = MdStyle.strike;
      } else if (ch == '*' || (ch == '_' && (i == 0 || !_isWordChar(t[i - 1])))) {
        marker = ch;
        style = MdStyle.italic;
      }
      if (marker != null) {
        final end = _findClose(t, marker, i + marker.length);
        if (end > i + marker.length) {
          emit(styles);
          walk(t.substring(i + marker.length, end), {...styles, style!});
          i = end + marker.length;
          continue;
        }
      }
      buf.write(ch);
      i++;
    }
    emit(styles);
  }

  walk(text, const {});
  return out;
}

int _findClose(String t, String marker, int from) {
  var j = from;
  while (true) {
    final k = t.indexOf(marker, j);
    if (k < 0) return -1;
    // '***' closing '**': the inner '*' closes first, so take the last two.
    if (marker.length == 2) {
      var end = k;
      while (end + marker.length < t.length && t[end + marker.length] == marker[0]) {
        end++;
      }
      return end;
    }
    // A single '*' must not match the first half of '**'.
    if (marker.length == 1 && k + 1 < t.length && t[k + 1] == marker) {
      j = k + 2;
      continue;
    }
    if (marker == '_' && k + 1 < t.length && _isWordChar(t[k + 1])) {
      j = k + 1;
      continue;
    }
    return k;
  }
}

bool _isWordChar(String c) => RegExp(r'[A-Za-z0-9À-ɏ]').hasMatch(c);

bool _sameStyles(Set<MdStyle> a, Set<MdStyle> b) => a.length == b.length && a.containsAll(b);

// ------------------------------------------------------------------ rendering

/// Renders [data] as a column of blocks. Put it in a scrollable parent.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data, {super.key});
  final String data;

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkdown(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == blocks.length - 1 ? 0 : 10),
            child: _block(context, blocks[i]),
          ),
      ],
    );
  }

  Widget _block(BuildContext context, MdBlock b) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    switch (b) {
      case MdHeading(:final level, text: final t):
        final style = switch (level) {
          1 => text.titleLarge,
          2 => text.titleMedium,
          _ => text.titleSmall,
        };
        return Text.rich(inlineSpan(context, t, style?.copyWith(fontWeight: FontWeight.w700)));
      case MdParagraph(text: final t):
        return Text.rich(inlineSpan(context, t, text.bodyMedium));
      case MdList(:final items, :final ordered, :final start):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 24, child: Text(ordered ? '${start + i}.' : '•', style: text.bodyMedium)),
                    Expanded(child: Text.rich(inlineSpan(context, items[i], text.bodyMedium))),
                  ],
                ),
              ),
          ],
        );
      case MdQuote(text: final t):
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          child: Text.rich(inlineSpan(context, t, text.bodyMedium?.copyWith(fontStyle: FontStyle.italic))),
        );
      case MdCode(text: final t):
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(t, style: text.bodySmall?.copyWith(fontFamily: 'monospace')),
          ),
        );
      case MdTable(:final header, :final rows):
        final border = theme.colorScheme.outlineVariant;
        Widget cell(String s, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text.rich(
            inlineSpan(context, s, head ? text.bodyMedium?.copyWith(fontWeight: FontWeight.w700) : text.bodyMedium),
          ),
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: border, borderRadius: BorderRadius.circular(6)),
            children: [
              TableRow(
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh),
                children: [for (final h in header) cell(h, head: true)],
              ),
              for (final r in rows) TableRow(children: [for (final c in r) cell(c)]),
            ],
          ),
        );
      case MdRule():
        return const Divider();
    }
  }
}

/// Builds a [TextSpan] from inline markdown.
TextSpan inlineSpan(BuildContext context, String text, TextStyle? base) {
  final scheme = Theme.of(context).colorScheme;
  return TextSpan(
    style: base,
    children: [
      for (final s in parseInline(text))
        TextSpan(
          text: s.text,
          style: TextStyle(
            fontWeight: s.styles.contains(MdStyle.bold) ? FontWeight.w700 : null,
            fontStyle: s.styles.contains(MdStyle.italic) ? FontStyle.italic : null,
            decoration: s.styles.contains(MdStyle.strike) ? TextDecoration.lineThrough : null,
            fontFamily: s.styles.contains(MdStyle.code) ? 'monospace' : null,
            backgroundColor: s.styles.contains(MdStyle.code) ? scheme.surfaceContainerHighest : null,
          ),
        ),
    ],
  );
}
