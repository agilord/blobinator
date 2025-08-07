import 'dart:convert';
import 'dart:typed_data';

/// Encodes a key for use in HTTP URLs.
/// Uses UTF-8 encoding by default, but switches to base64 encoding if:
/// - The key contains invalid UTF-8 sequences
/// - The UTF-8 string starts with 'base64:'
String encodeKey(List<int> key) {
  final keyBytes = Uint8List.fromList(key);

  try {
    final utf8String = utf8.decode(keyBytes);
    // If the UTF-8 string starts with 'base64:', we must use base64 encoding
    if (utf8String.startsWith('base64:')) {
      return 'base64:${base64.encode(keyBytes)}';
    } else {
      // For UTF-8 strings, only encode characters that need it, preserve slashes
      return utf8String.split('/').map(Uri.encodeComponent).join('/');
    }
  } catch (_) {
    // If UTF-8 decoding fails, use base64 encoding
    return 'base64:${base64.encode(keyBytes)}';
  }
}

/// Decodes a key from a URL-encoded string.
/// Supports both UTF-8 and base64 encoded keys.
List<int> decodeKey(String encodedKey) {
  // URL decode first
  final urlDecoded = Uri.decodeComponent(encodedKey);

  if (urlDecoded.startsWith('base64:')) {
    // Remove 'base64:' prefix and decode as base64
    final base64Part = urlDecoded.substring(7);
    return base64.decode(base64Part);
  } else {
    // Decode as UTF-8
    return utf8.encode(urlDecoded);
  }
}

/// Parses a key parameter from command line input.
/// Supports both UTF-8 strings and base64 encoded strings (with 'base64:' prefix).
List<int> parseKeyParameter(String keyParam) {
  if (keyParam.startsWith('base64:')) {
    // Remove 'base64:' prefix and decode as base64
    final base64Part = keyParam.substring(7);
    return base64.decode(base64Part);
  } else {
    // Treat as UTF-8 string
    return utf8.encode(keyParam);
  }
}

/// Parses a byte amount string into an integer number of bytes.
///
/// Supports:
/// - Plain integers (treated as bytes)
/// - Decimal suffixes: k/kb (1000), m/mb (1000²), g/gb (1000³)
/// - Binary suffixes: kib (1024), mib (1024²), gib (1024³)
/// - Case insensitive matching
/// - Float numbers with rounding up to bytes
///
/// Throws [FormatException] for invalid input or negative numbers.
int parseBytesAmount(String value) {
  if (value.isEmpty) {
    throw FormatException('Empty input');
  }

  // Remove whitespace and convert to lowercase for parsing
  final cleaned = value.trim().toLowerCase();

  if (cleaned.isEmpty) {
    throw FormatException('Empty input after trimming');
  }

  // Try to parse as plain integer first
  final intValue = int.tryParse(cleaned);
  if (intValue != null) {
    if (intValue < 0) {
      throw FormatException('Negative values are not allowed: $intValue');
    }
    return intValue;
  }

  // Parse with suffixes
  final suffixMap = <String, int>{
    // Decimal (base 1000)
    'k': 1000,
    'kb': 1000,
    'm': 1000 * 1000,
    'mb': 1000 * 1000,
    'g': 1000 * 1000 * 1000,
    'gb': 1000 * 1000 * 1000,

    // Binary (base 1024)
    'kib': 1024,
    'mib': 1024 * 1024,
    'gib': 1024 * 1024 * 1024,
  };

  // Find matching suffix
  String? matchedSuffix;
  for (final suffix in suffixMap.keys) {
    if (cleaned.endsWith(suffix)) {
      matchedSuffix = suffix;
      break;
    }
  }

  if (matchedSuffix == null) {
    throw FormatException('Invalid format: $value');
  }

  // Extract number part
  final numberPart = cleaned.substring(
    0,
    cleaned.length - matchedSuffix.length,
  );
  if (numberPart.isEmpty) {
    throw FormatException('Missing number part: $value');
  }

  final number = double.tryParse(numberPart);
  if (number == null) {
    throw FormatException('Invalid number: $numberPart in $value');
  }

  if (number < 0) {
    throw FormatException('Negative values are not allowed: $number');
  }

  final multiplier = suffixMap[matchedSuffix]!;
  final result = (number * multiplier).ceil();

  return result;
}

/// Parses a duration string into a Duration object.
///
/// Supports:
/// - Plain integers (treated as seconds)
/// - Suffixes: s (seconds), m (minutes), h (hours), d (days) - case sensitive
/// - Double values with suffixes (e.g., 1.5h)
///
/// Throws [FormatException] for invalid input.
Duration parseDuration(String value) {
  if (value.isEmpty) {
    throw FormatException('Empty duration input');
  }

  final cleaned = value.trim();
  if (cleaned.isEmpty) {
    throw FormatException('Empty duration input after trimming');
  }

  // Try to parse as plain integer first (seconds)
  final intValue = int.tryParse(cleaned);
  if (intValue != null) {
    if (intValue < 0) {
      throw FormatException(
        'Negative duration values are not allowed: $intValue',
      );
    }
    return Duration(seconds: intValue);
  }

  // Parse with suffixes
  final suffixMap = <String, Duration Function(double)>{
    's': (value) => Duration(milliseconds: (value * 1000).round()),
    'm': (value) => Duration(milliseconds: (value * 60 * 1000).round()),
    'h': (value) => Duration(milliseconds: (value * 60 * 60 * 1000).round()),
    'd': (value) =>
        Duration(milliseconds: (value * 24 * 60 * 60 * 1000).round()),
  };

  // Find matching suffix (case sensitive)
  String? matchedSuffix;
  for (final suffix in suffixMap.keys) {
    if (cleaned.endsWith(suffix)) {
      matchedSuffix = suffix;
      break;
    }
  }

  if (matchedSuffix == null) {
    throw FormatException('Invalid duration format: $value');
  }

  // Extract number part
  final numberPart = cleaned.substring(
    0,
    cleaned.length - matchedSuffix.length,
  );
  if (numberPart.isEmpty) {
    throw FormatException('Missing number part in duration: $value');
  }

  final number = double.tryParse(numberPart);
  if (number == null) {
    throw FormatException('Invalid number in duration: $numberPart in $value');
  }

  if (number < 0) {
    throw FormatException('Negative duration values are not allowed: $number');
  }

  return suffixMap[matchedSuffix]!(number);
}
