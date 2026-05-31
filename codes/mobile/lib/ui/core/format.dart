/// Truncate a 0x address for display: `0x1234…abcd`. Length-guarded so a short
/// or malformed value can't throw RangeError.
String shortAddr(String a) {
  if (a.length <= 12) return a;
  return '${a.substring(0, 6)}…${a.substring(a.length - 4)}';
}
