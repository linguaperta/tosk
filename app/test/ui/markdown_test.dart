import 'package:tosk/ui/common/markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMarkdown', () {
    test('headings, paragraphs, lists, quotes, code, rules', () {
      final blocks = parseMarkdown('''
# Title
Some text
continued here.

- one
- two
  more

1. first
2. second

> quoted

```
code block
```

---
''');
      expect(blocks[0], isA<MdHeading>().having((h) => h.level, 'level', 1).having((h) => h.text, 'text', 'Title'));
      expect(blocks[1], isA<MdParagraph>().having((p) => p.text, 'text', 'Some text continued here.'));
      expect(
        blocks[2],
        isA<MdList>().having((l) => l.items, 'items', ['one', 'two more']).having((l) => l.ordered, 'ordered', false),
      );
      expect(blocks[3], isA<MdList>().having((l) => l.ordered, 'ordered', true).having((l) => l.items.length, 'n', 2));
      expect(blocks[4], isA<MdQuote>().having((q) => q.text, 'text', 'quoted'));
      expect(blocks[5], isA<MdCode>().having((c) => c.text, 'text', 'code block'));
      expect(blocks[6], isA<MdRule>());
      expect(blocks.length, 7);
    });

    test('pipe tables', () {
      final blocks = parseMarkdown('| Person | Ending |\n| --- | :---: |\n| io | -o |\n| tu |\n');
      final t = blocks.single as MdTable;
      expect(t.header, ['Person', 'Ending']);
      expect(t.rows, [
        ['io', '-o'],
        ['tu', ''],
      ]);
    });
  });

  group('parseInline', () {
    test('bold, italic, code, strike', () {
      final spans = parseInline('a **b** *c* `d` ~~e~~ _f_');
      String styled(MdStyle s) => spans.where((x) => x.styles.contains(s)).map((x) => x.text).join();
      expect(styled(MdStyle.bold), 'b');
      expect(styled(MdStyle.italic), 'cf');
      expect(styled(MdStyle.code), 'd');
      expect(styled(MdStyle.strike), 'e');
      expect(spans.map((s) => s.text).join(), 'a b c d e f');
    });

    test('nested and unmatched markers', () {
      final spans = parseInline('**bold *both***');
      expect(spans.any((s) => s.styles.containsAll({MdStyle.bold, MdStyle.italic}) && s.text == 'both'), isTrue);
      expect(parseInline('2 * 3 = 6').map((s) => s.text).join(), '2 * 3 = 6');
      expect(parseInline('snake_case_word').single.styles, isEmpty);
      expect(parseInline(r'\*literal\*').single.text, '*literal*');
    });
  });

  testWidgets('MarkdownView renders every block type', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MarkdownView(
              '# Head\n\nText **bold**\n\n- item\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n> q\n\n```\nx\n```\n\n---',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Head'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
