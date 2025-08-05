import 'package:blobinator/src/utils.dart';
import 'package:test/test.dart';

void main() {
  group('parseLimit', () {
    test('parses plain numbers', () {
      expect(parseLimit('100'), equals(100));
      expect(parseLimit('0'), equals(0));
      expect(parseLimit('999999'), equals(999999));
    });

    test('parses thousands (k)', () {
      expect(parseLimit('1k'), equals(1000));
      expect(parseLimit('5k'), equals(5000));
      expect(parseLimit('100k'), equals(100000));
      expect(parseLimit('1K'), equals(1000)); // Case insensitive
    });

    test('parses millions (m)', () {
      expect(parseLimit('1m'), equals(1000000));
      expect(parseLimit('5m'), equals(5000000));
      expect(parseLimit('100m'), equals(100000000));
      expect(parseLimit('1M'), equals(1000000)); // Case insensitive
    });

    test('parses billions (b)', () {
      expect(parseLimit('1b'), equals(1000000000));
      expect(parseLimit('2b'), equals(2000000000));
      expect(parseLimit('1B'), equals(1000000000)); // Case insensitive
    });

    test('handles whitespace', () {
      expect(parseLimit(' 100 '), equals(100));
      expect(parseLimit(' 5k '), equals(5000));
      expect(parseLimit(' 2m '), equals(2000000));
    });

    test('throws on invalid input', () {
      expect(() => parseLimit(''), throwsArgumentError);
      expect(() => parseLimit('abc'), throwsArgumentError);
      expect(() => parseLimit('1x'), throwsArgumentError);
      expect(() => parseLimit('-1'), throwsArgumentError);
      expect(() => parseLimit('-5k'), throwsArgumentError);
    });
  });

  group('parseAge', () {
    test('parses plain numbers as seconds', () {
      expect(parseAge('30'), equals(Duration(seconds: 30)));
      expect(parseAge('0'), equals(Duration(seconds: 0)));
      expect(parseAge('3600'), equals(Duration(seconds: 3600)));
    });

    test('parses seconds (s)', () {
      expect(parseAge('30s'), equals(Duration(seconds: 30)));
      expect(parseAge('120s'), equals(Duration(seconds: 120)));
      expect(
        parseAge('30S'),
        equals(Duration(seconds: 30)),
      ); // Case insensitive
    });

    test('parses minutes (m)', () {
      expect(parseAge('5m'), equals(Duration(minutes: 5)));
      expect(parseAge('30m'), equals(Duration(minutes: 30)));
      expect(parseAge('5M'), equals(Duration(minutes: 5))); // Case insensitive
    });

    test('parses hours (h)', () {
      expect(parseAge('2h'), equals(Duration(hours: 2)));
      expect(parseAge('24h'), equals(Duration(hours: 24)));
      expect(parseAge('2H'), equals(Duration(hours: 2))); // Case insensitive
    });

    test('parses days (d)', () {
      expect(parseAge('1d'), equals(Duration(days: 1)));
      expect(parseAge('7d'), equals(Duration(days: 7)));
      expect(parseAge('1D'), equals(Duration(days: 1))); // Case insensitive
    });

    test('handles whitespace', () {
      expect(parseAge(' 30s '), equals(Duration(seconds: 30)));
      expect(parseAge(' 5m '), equals(Duration(minutes: 5)));
      expect(parseAge(' 2h '), equals(Duration(hours: 2)));
    });

    test('throws on invalid input', () {
      expect(() => parseAge(''), throwsArgumentError);
      expect(() => parseAge('abc'), throwsArgumentError);
      expect(() => parseAge('1x'), throwsArgumentError);
      expect(() => parseAge('-1'), throwsArgumentError);
      expect(() => parseAge('-5m'), throwsArgumentError);
    });
  });
}
