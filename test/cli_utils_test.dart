import 'package:blobinator/src/cli_utils.dart';
import 'package:test/test.dart';

void main() {
  group('parseBytesAmount', () {
    group('plain integers', () {
      test('should parse zero', () {
        expect(parseBytesAmount('0'), equals(0));
      });

      test('should parse positive integers', () {
        expect(parseBytesAmount('123'), equals(123));
        expect(parseBytesAmount('1000'), equals(1000));
        expect(parseBytesAmount('999999'), equals(999999));
      });

      test('should handle whitespace', () {
        expect(parseBytesAmount(' 123 '), equals(123));
        expect(parseBytesAmount('\t456\n'), equals(456));
      });

      test('should reject negative integers', () {
        expect(() => parseBytesAmount('-1'), throwsFormatException);
        expect(() => parseBytesAmount('-123'), throwsFormatException);
      });
    });

    group('decimal suffixes', () {
      test('should parse k suffix (1000 bytes)', () {
        expect(parseBytesAmount('1k'), equals(1000));
        expect(parseBytesAmount('2k'), equals(2000));
        expect(parseBytesAmount('1.5k'), equals(1500));
        expect(parseBytesAmount('1.1k'), equals(1100));
      });

      test('should parse kb suffix (1000 bytes)', () {
        expect(parseBytesAmount('1kb'), equals(1000));
        expect(parseBytesAmount('2kb'), equals(2000));
        expect(parseBytesAmount('1.5kb'), equals(1500));
      });

      test('should parse m suffix (1000² bytes)', () {
        expect(parseBytesAmount('1m'), equals(1000000));
        expect(parseBytesAmount('2m'), equals(2000000));
        expect(parseBytesAmount('1.5m'), equals(1500000));
      });

      test('should parse mb suffix (1000² bytes)', () {
        expect(parseBytesAmount('1mb'), equals(1000000));
        expect(parseBytesAmount('2mb'), equals(2000000));
        expect(parseBytesAmount('1.5mb'), equals(1500000));
      });

      test('should parse g suffix (1000³ bytes)', () {
        expect(parseBytesAmount('1g'), equals(1000000000));
        expect(parseBytesAmount('2g'), equals(2000000000));
        expect(parseBytesAmount('1.5g'), equals(1500000000));
      });

      test('should parse gb suffix (1000³ bytes)', () {
        expect(parseBytesAmount('1gb'), equals(1000000000));
        expect(parseBytesAmount('2gb'), equals(2000000000));
        expect(parseBytesAmount('1.5gb'), equals(1500000000));
      });
    });

    group('binary suffixes', () {
      test('should parse kib suffix (1024 bytes)', () {
        expect(parseBytesAmount('1kib'), equals(1024));
        expect(parseBytesAmount('2kib'), equals(2048));
        expect(parseBytesAmount('1.5kib'), equals(1536));
      });

      test('should parse mib suffix (1024² bytes)', () {
        expect(parseBytesAmount('1mib'), equals(1048576));
        expect(parseBytesAmount('2mib'), equals(2097152));
        expect(parseBytesAmount('1.5mib'), equals(1572864));
      });

      test('should parse gib suffix (1024³ bytes)', () {
        expect(parseBytesAmount('1gib'), equals(1073741824));
        expect(parseBytesAmount('2gib'), equals(2147483648));
        expect(parseBytesAmount('1.5gib'), equals(1610612736));
      });
    });

    group('case insensitive', () {
      test('should handle uppercase suffixes', () {
        expect(parseBytesAmount('1K'), equals(1000));
        expect(parseBytesAmount('1KB'), equals(1000));
        expect(parseBytesAmount('1M'), equals(1000000));
        expect(parseBytesAmount('1MB'), equals(1000000));
        expect(parseBytesAmount('1G'), equals(1000000000));
        expect(parseBytesAmount('1GB'), equals(1000000000));
        expect(parseBytesAmount('1KIB'), equals(1024));
        expect(parseBytesAmount('1MIB'), equals(1048576));
        expect(parseBytesAmount('1GIB'), equals(1073741824));
      });

      test('should handle mixed case suffixes', () {
        expect(parseBytesAmount('1Kb'), equals(1000));
        expect(parseBytesAmount('1kB'), equals(1000));
        expect(parseBytesAmount('1Kib'), equals(1024));
        expect(parseBytesAmount('1kiB'), equals(1024));
      });
    });

    group('float rounding', () {
      test('should round up fractional bytes', () {
        expect(parseBytesAmount('1.1k'), equals(1100));
        expect(parseBytesAmount('1.9k'), equals(1900));
        expect(parseBytesAmount('1.01k'), equals(1010));
        expect(parseBytesAmount('1.99k'), equals(1990));
      });

      test('should round up fractional results', () {
        // 1.1 * 1024 = 1126.4 -> should round up to 1127
        expect(parseBytesAmount('1.1kib'), equals(1127));
        // 1.9 * 1024 = 1945.6 -> should round up to 1946
        expect(parseBytesAmount('1.9kib'), equals(1946));
      });

      test('should handle decimal places correctly', () {
        expect(parseBytesAmount('0.5k'), equals(500));
        expect(parseBytesAmount('0.1k'), equals(100));
        expect(parseBytesAmount('0.01k'), equals(10));
      });
    });

    group('error cases', () {
      test('should reject empty input', () {
        expect(() => parseBytesAmount(''), throwsFormatException);
        expect(() => parseBytesAmount('   '), throwsFormatException);
      });

      test('should reject invalid suffixes', () {
        expect(() => parseBytesAmount('1tb'), throwsFormatException);
        expect(() => parseBytesAmount('1xyz'), throwsFormatException);
        expect(() => parseBytesAmount('1kbb'), throwsFormatException);
      });

      test('should reject missing number part', () {
        expect(() => parseBytesAmount('k'), throwsFormatException);
        expect(() => parseBytesAmount('kb'), throwsFormatException);
        expect(() => parseBytesAmount('mib'), throwsFormatException);
      });

      test('should reject invalid number parts', () {
        expect(() => parseBytesAmount('abc123'), throwsFormatException);
        expect(() => parseBytesAmount('1.2.3k'), throwsFormatException);
        expect(() => parseBytesAmount('1..2k'), throwsFormatException);
      });

      test('should reject negative numbers with suffixes', () {
        expect(() => parseBytesAmount('-1k'), throwsFormatException);
        expect(() => parseBytesAmount('-1.5mb'), throwsFormatException);
        expect(() => parseBytesAmount('-0.1kib'), throwsFormatException);
      });

      test('should reject completely invalid input', () {
        expect(() => parseBytesAmount('not-a-number'), throwsFormatException);
        expect(() => parseBytesAmount('123abc'), throwsFormatException);
        expect(() => parseBytesAmount(r'!@#$%'), throwsFormatException);
      });
    });

    group('edge cases', () {
      test('should handle zero with suffixes', () {
        expect(parseBytesAmount('0k'), equals(0));
        expect(parseBytesAmount('0mb'), equals(0));
        expect(parseBytesAmount('0kib'), equals(0));
      });

      test('should handle very small decimal values', () {
        expect(parseBytesAmount('0.001k'), equals(1)); // rounds up
        expect(parseBytesAmount('0.0001k'), equals(1)); // rounds up
      });

      test('should handle whitespace around suffixed values', () {
        expect(parseBytesAmount(' 1k '), equals(1000));
        expect(parseBytesAmount('\t2mb\n'), equals(2000000));
      });
    });
  });

  group('parseDuration', () {
    test('should parse plain integers as seconds', () {
      expect(parseDuration('30'), equals(Duration(seconds: 30)));
      expect(parseDuration('0'), equals(Duration.zero));
      expect(parseDuration('3600'), equals(Duration(seconds: 3600)));
    });

    test('should parse seconds with suffix', () {
      expect(parseDuration('30s'), equals(Duration(seconds: 30)));
      expect(parseDuration('1s'), equals(Duration(seconds: 1)));
      expect(parseDuration('1.5s'), equals(Duration(milliseconds: 1500)));
    });

    test('should parse minutes with suffix', () {
      expect(parseDuration('1m'), equals(Duration(minutes: 1)));
      expect(parseDuration('30m'), equals(Duration(minutes: 30)));
      expect(parseDuration('1.5m'), equals(Duration(milliseconds: 90000)));
    });

    test('should parse hours with suffix', () {
      expect(parseDuration('1h'), equals(Duration(hours: 1)));
      expect(parseDuration('24h'), equals(Duration(hours: 24)));
      expect(parseDuration('1.5h'), equals(Duration(milliseconds: 5400000)));
    });

    test('should parse days with suffix', () {
      expect(parseDuration('1d'), equals(Duration(days: 1)));
      expect(parseDuration('7d'), equals(Duration(days: 7)));
      expect(parseDuration('1.5d'), equals(Duration(milliseconds: 129600000)));
    });

    test('should handle decimal values correctly', () {
      expect(parseDuration('0.5s'), equals(Duration(milliseconds: 500)));
      expect(parseDuration('2.5m'), equals(Duration(milliseconds: 150000)));
      expect(parseDuration('0.25h'), equals(Duration(minutes: 15)));
    });

    test('should be case sensitive', () {
      expect(() => parseDuration('30S'), throwsA(isA<FormatException>()));
      expect(() => parseDuration('1M'), throwsA(isA<FormatException>()));
      expect(() => parseDuration('1H'), throwsA(isA<FormatException>()));
      expect(() => parseDuration('1D'), throwsA(isA<FormatException>()));
    });

    test('should throw FormatException for invalid formats', () {
      expect(() => parseDuration(''), throwsA(isA<FormatException>()));
      expect(() => parseDuration('  '), throwsA(isA<FormatException>()));
      expect(() => parseDuration('abc'), throwsA(isA<FormatException>()));
      expect(() => parseDuration('30x'), throwsA(isA<FormatException>()));
      expect(() => parseDuration('s30'), throwsA(isA<FormatException>()));
      expect(
        () => parseDuration('30 seconds'),
        throwsA(isA<FormatException>()),
      );
    });

    test('should throw FormatException for negative values', () {
      expect(() => parseDuration('-30'), throwsA(isA<FormatException>()));
      expect(() => parseDuration('-1s'), throwsA(isA<FormatException>()));
      expect(() => parseDuration('-1.5h'), throwsA(isA<FormatException>()));
    });

    test('should handle edge cases', () {
      expect(parseDuration('0s'), equals(Duration.zero));
      expect(parseDuration('0.0s'), equals(Duration.zero));
      expect(parseDuration('0.1s'), equals(Duration(milliseconds: 100)));
    });
  });
}
