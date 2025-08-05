int parseLimit(String value) {
  final trimmed = value.trim();

  if (trimmed.isEmpty) {
    throw ArgumentError('Limit value cannot be empty');
  }

  final lowerValue = trimmed.toLowerCase();

  if (lowerValue.endsWith('b')) {
    final numPart = trimmed.substring(0, trimmed.length - 1);
    final number = int.tryParse(numPart);

    if (number == null || number < 0) {
      throw ArgumentError('Invalid limit number: $numPart');
    }

    return number * 1000000000; // billions
  } else if (lowerValue.endsWith('m')) {
    final numPart = trimmed.substring(0, trimmed.length - 1);
    final number = int.tryParse(numPart);

    if (number == null || number < 0) {
      throw ArgumentError('Invalid limit number: $numPart');
    }

    return number * 1000000; // millions
  } else if (lowerValue.endsWith('k')) {
    final numPart = trimmed.substring(0, trimmed.length - 1);
    final number = int.tryParse(numPart);

    if (number == null || number < 0) {
      throw ArgumentError('Invalid limit number: $numPart');
    }

    return number * 1000; // thousands
  } else {
    final number = int.tryParse(trimmed);
    if (number == null || number < 0) {
      throw ArgumentError('Invalid limit value: $trimmed');
    }
    return number;
  }
}

Duration parseAge(String value) {
  final trimmed = value.trim();

  if (trimmed.isEmpty) {
    throw ArgumentError('Age value cannot be empty');
  }

  final lastChar = trimmed[trimmed.length - 1].toLowerCase();

  if (RegExp(r'[dhms]').hasMatch(lastChar)) {
    final numPart = trimmed.substring(0, trimmed.length - 1);
    final number = int.tryParse(numPart);

    if (number == null || number < 0) {
      throw ArgumentError('Invalid age number: $numPart');
    }

    switch (lastChar) {
      case 'd':
        return Duration(days: number);
      case 'h':
        return Duration(hours: number);
      case 'm':
        return Duration(minutes: number);
      case 's':
        return Duration(seconds: number);
      default:
        throw ArgumentError('Invalid age unit: $lastChar');
    }
  } else {
    final number = int.tryParse(trimmed);
    if (number == null || number < 0) {
      throw ArgumentError('Invalid age value: $trimmed');
    }
    return Duration(seconds: number);
  }
}
