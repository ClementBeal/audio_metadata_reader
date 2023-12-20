import 'dart:typed_data';

bool checkBit(int value, int bit) => (value & (1 << bit)) != 0;
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

int getInt8(Uint8List data) {
  return data[0];
}

int getUint16(Uint8List data) {
  return data[0] << 8 | data[1];
}

int getUint24(Uint8List data) {
  return data[0] << 16 | data[1] << 8 | data[2];
}

int getUint32(Uint8List data) {
  return data[0] << 24 | data[1] << 16 | data[2] << 8 | data[3];
}

int getUint32LE(Uint8List data) =>
    (data[0] & 0xFF) |
    ((data[1] & 0xFF) << 8) |
    ((data[2] & 0xFF) << 16) |
    ((data[3] & 0xFF) << 24);

int getIntFromArbitraryBits(int data, int offset, int length) {
  // int result = 0;

  // // 0000 1010 1100 0100 0100
  // for (var i = 0; i < length; i++) {
  //   // print(getBit(data, 64 - i - offset));
  //   result = result | (getBit(data, 64 - i - offset) << (length - i));
  //   print(result.toRadixString(2).padLeft(length, "0"));
  // }

  return (data >> (64 - offset - length)) & ((1 << length) - 1);
}

Uint8List intToUint24(int value) {
  Uint8List result = Uint8List(3);
  result[0] = (value >> 16) & 0xFF;
  result[1] = (value >> 8) & 0xFF;
  result[2] = value & 0xFF;
  return result;
}

Uint8List intToUint32(int value) {
  Uint8List result = Uint8List(4);
  result[0] = (value >> 24) & 0xFF;
  result[1] = (value >> 16) & 0xFF;
  result[2] = (value >> 8) & 0xFF;
  result[3] = value & 0xFF;
  return result;
}

Uint8List intToUint32LE(int value) {
  Uint8List result = Uint8List(4);
  result[3] = (value >> 24) & 0xFF;
  result[2] = (value >> 16) & 0xFF;
  result[1] = (value >> 8) & 0xFF;
  result[0] = value & 0xFF;
  return result;
}

Uint8List intToUint24LE(int value) {
  Uint8List result = Uint8List(4);
  result[2] = (value >> 16) & 0xFF;
  result[1] = (value >> 8) & 0xFF;
  result[0] = value & 0xFF;
  return result;
}
