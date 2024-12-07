extension A on List<int> {
  List<int> padBitLeft(int desiredLength, int paddingBit) {
    if (length >= desiredLength) {
      return this; // No padding needed
    }

    if (paddingBit != 0 && paddingBit != 1) {
      throw ArgumentError("Padding bit must be 0 or 1.");
    }

    int paddingCount = desiredLength - length;
    List<int> padding = List.filled(paddingCount, paddingBit);
    return [...padding, ...this];
  }

  List<int> padBitRight(int desiredLength, int paddingBit) {
    if (length >= desiredLength) {
      return this; // No padding needed
    }

    if (paddingBit != 0 && paddingBit != 1) {
      throw ArgumentError("Padding bit must be 0 or 1.");
    }

    int paddingCount = desiredLength - length;
    List<int> padding = List.filled(paddingCount, paddingBit);
    return [...this, ...padding];
  }
}
