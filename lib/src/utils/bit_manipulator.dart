import 'dart:typed_data';

/// Check if a bit is set
bool checkBit(int value, int bit) => (value & (1 << bit)) != 0;

/// Get the value of the bit at a specific position
int getBit(int number, int position) => (number >> position) & 1;

int synchsafe(input) {
  int out = 0;

  int mask = 0x7F;
  while (mask ^ 0x7FFFFFFF == 0) {
    out = input & ~mask;
    out = out << 1;
    out = out | (input & mask);
    mask = ((mask + 1) << 8) - 1;
    input = out;
  }
  return out;
}

/// Transform an array of 1 byte into a Integer8
int getInt8(List<int> data) {
  return data[0];
}

/// Transform an array of 2 bytes into a Integer16
int getUint16(List<int> data) {
  return data[0] << 8 | data[1];
}

/// Transform an array of 3 bytes into a Integer24
int getUint24(List<int> data) {
  return data[0] << 16 | data[1] << 8 | data[2];
}

/// Transform an array of 4 bytes into a Integer32
int getUint32(List<int> data) {
  return data[0] << 24 | data[1] << 16 | data[2] << 8 | data[3];
}

/// Transform an array of Little-Endian 4 bytes into a Integer32
int getUint32LE(List<int> data) =>
    (data[0] & 0xFF) |
    ((data[1] & 0xFF) << 8) |
    ((data[2] & 0xFF) << 16) |
    ((data[3] & 0xFF) << 24);

int getUint64LE(List<int> data) =>
    data[0] |
    data[1] << 8 |
    data[2] << 16 |
    data[3] << 24 |
    data[4] << 32 |
    data[5] << 40 |
    data[6] << 48 |
    data[7] << 56;

int getUint64BE(List<int> data) =>
    data[7] |
    data[6] << 8 |
    data[5] << 16 |
    data[4] << 24 |
    data[3] << 32 |
    data[2] << 40 |
    data[1] << 48 |
    data[0] << 56;

int getIntFromArbitraryBits(int data, int offset, int length) {
  return (data >> (64 - offset - length)) & ((1 << length) - 1);
}

/// Transform an integer into a Big-Endian 2 bytes array
Uint8List intToUint16(int value) {
  Uint8List result = Uint8List(2);
  result[0] = (value >> 8) & 0xFF;
  result[1] = value & 0xFF;
  return result;
}

/// Transform an integer into a Big-Endian 3 bytes array
Uint8List intToUint24(int value) {
  Uint8List result = Uint8List(3);
  result[0] = (value >> 16) & 0xFF;
  result[1] = (value >> 8) & 0xFF;
  result[2] = value & 0xFF;
  return result;
}

/// Transform an integer into a Big-Endian 4 bytes array
Uint8List intToUint32(int value) {
  Uint8List result = Uint8List(4);
  result[0] = (value >> 24) & 0xFF;
  result[1] = (value >> 16) & 0xFF;
  result[2] = (value >> 8) & 0xFF;
  result[3] = value & 0xFF;
  return result;
}

/// Transform an integer into a Little-Endian 4 bytes array
Uint8List intToUint32LE(int value) {
  Uint8List result = Uint8List(4);
  result[3] = (value >> 24) & 0xFF;
  result[2] = (value >> 16) & 0xFF;
  result[1] = (value >> 8) & 0xFF;
  result[0] = value & 0xFF;
  return result;
}

/// Transform an integer into a Little-Endian 3 bytes array
Uint8List intToUint24LE(int value) {
  Uint8List result = Uint8List(4);
  result[2] = (value >> 16) & 0xFF;
  result[1] = (value >> 8) & 0xFF;
  result[0] = value & 0xFF;
  return result;
}
