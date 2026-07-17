void main() {
  final coordStr = '74.123,15.456,10 74.234,15.567,10 74.345,15.678,10';
  final regExp = RegExp(r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)');
  final matches = regExp.allMatches(coordStr);
  
  for (final match in matches) {
    print(match.group(1));
    print(match.group(2));
  }
}
