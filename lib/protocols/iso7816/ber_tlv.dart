import 'dart:typed_data';

enum TlvDiagnosticKind { malformed, truncated, resourceLimit }

class TlvDiagnostic {
  const TlvDiagnostic(this.kind, this.message, this.offset);
  final TlvDiagnosticKind kind;
  final String message;

  /// Absolute byte offset in the original input, also for nested templates.
  final int offset;
}

class TlvPolicy {
  const TlvPolicy({
    this.maxLengthBytes = 4,
    this.rejectLongFormForShortLength = false,
    this.retainMalformedChildren = false,
    this.maxDepth = 8,
    this.maxNodes = 4096,
    this.maxInputBytes = 1024 * 1024,
    this.maxDecodedValueBytes = 8 * 1024 * 1024,
    this.maxTagBytes = 5,
  });
  final int maxLengthBytes;
  // Preserve the bank decoder's actual rule, without adding a new rejection
  // of leading-zero long lengths that its existing implementation accepted.
  final bool rejectLongFormForShortLength;
  final bool retainMalformedChildren;
  final int maxDepth;
  final int maxNodes;
  final int maxInputBytes;
  final int maxDecodedValueBytes;
  final int maxTagBytes;

  static const discovery = TlvPolicy();
  static const bank = TlvPolicy(
    maxLengthBytes: 3,
    rejectLongFormForShortLength: true,
    retainMalformedChildren: true,
  );
}

/// A raw BER tree node. Views share one immutable input buffer, so nested
/// templates do not repeatedly copy their entire encoded children.
class RawBerTlv {
  RawBerTlv._({
    required this.tagHex,
    required this.offset,
    required this.valueOffset,
    required this.declaredLength,
    required this.isConstructed,
    required this.raw,
    required this.value,
    required List<RawBerTlv> children,
    required List<TlvDiagnostic> diagnostics,
  }) : children = List<RawBerTlv>.unmodifiable(children),
       diagnostics = List<TlvDiagnostic>.unmodifiable(diagnostics);
  final String tagHex;
  final int offset;
  final int valueOffset;
  final int declaredLength;
  final bool isConstructed;
  final Uint8List raw;
  final Uint8List value;
  final List<RawBerTlv> children;
  final List<TlvDiagnostic> diagnostics;
  bool get isComplete => diagnostics.isEmpty && value.length == declaredLength;
}

class TlvParseResult {
  TlvParseResult._(
    this.raw,
    List<RawBerTlv> roots,
    List<TlvDiagnostic> diagnostics,
    this.fatalDiagnostic,
  ) : roots = List<RawBerTlv>.unmodifiable(roots),
      diagnostics = List<TlvDiagnostic>.unmodifiable(diagnostics);
  final Uint8List raw;
  final List<RawBerTlv> roots;
  final List<TlvDiagnostic> diagnostics;
  final TlvDiagnostic? fatalDiagnostic;
  bool get accepted => fatalDiagnostic == null;

  void throwIfInvalid() {
    if (!accepted) throw BerTlvFormatException(this);
  }
}

class BerTlvFormatException extends FormatException {
  BerTlvFormatException(this.result)
    : super(
        result.fatalDiagnostic!.message,
        result.raw,
        result.fatalDiagnostic!.offset,
      );
  final TlvParseResult result;
}

abstract final class BerTlvParser {
  static TlvParseResult parse(
    List<int> bytes, {
    TlvPolicy policy = TlvPolicy.discovery,
  }) {
    if (policy.maxDepth < 0 ||
        policy.maxNodes < 1 ||
        policy.maxInputBytes < 0 ||
        policy.maxDecodedValueBytes < 0 ||
        policy.maxTagBytes < 1 ||
        policy.maxLengthBytes < 1 ||
        policy.maxLengthBytes > 4) {
      throw ArgumentError('Invalid BER-TLV budget');
    }
    if (bytes.any((b) => b < 0 || b > 255)) {
      throw const FormatException('TLV 输入包含非法字节');
    }
    final raw = Uint8List.fromList(bytes).asUnmodifiableView();
    return _TlvReader(raw, policy).parse();
  }
}

class _TlvReader {
  _TlvReader(this.bytes, this.policy);
  final Uint8List bytes;
  final TlvPolicy policy;
  final diagnostics = <TlvDiagnostic>[];
  var nodeCount = 0;
  var decodedBytes = 0;
  TlvDiagnostic? fatal;

  TlvDiagnostic issue(TlvDiagnosticKind kind, String message, int offset) {
    final diagnostic = TlvDiagnostic(kind, message, offset);
    diagnostics.add(diagnostic);
    if (kind == TlvDiagnosticKind.resourceLimit) fatal ??= diagnostic;
    return diagnostic;
  }

  TlvParseResult parse() {
    final roots = <RawBerTlv>[];
    if (bytes.length > policy.maxInputBytes) {
      issue(TlvDiagnosticKind.resourceLimit, 'TLV 输入字节数超限', 0);
    } else {
      final error = readRange(0, bytes.length, 0, roots);
      fatal ??= error;
    }
    return TlvParseResult._(bytes, roots, diagnostics, fatal);
  }

  Uint8List view(int start, int end) =>
      Uint8List.sublistView(bytes, start, end).asUnmodifiableView();

  TlvDiagnostic? readRange(int start, int end, int depth, List<RawBerTlv> out) {
    if (start < end && depth > policy.maxDepth) {
      return issue(TlvDiagnosticKind.resourceLimit, 'TLV 嵌套深度超限', start);
    }
    var offset = start;
    while (offset < end) {
      if (bytes[offset] == 0 || bytes[offset] == 0xFF) {
        offset++;
        continue;
      }
      if (++nodeCount > policy.maxNodes) {
        return issue(TlvDiagnosticKind.resourceLimit, 'TLV 节点数超限', offset);
      }
      final nodeStart = offset;
      final diagnosticStart = diagnostics.length;
      final first = bytes[offset++];
      if ((first & 0x1F) == 0x1F) {
        while (true) {
          if (offset >= end) {
            return issue(TlvDiagnosticKind.truncated, '多字节标签被截断', offset);
          }
          if (offset - nodeStart >= policy.maxTagBytes) {
            return issue(TlvDiagnosticKind.malformed, 'TLV 标签过长', nodeStart);
          }
          if ((bytes[offset++] & 0x80) == 0) break;
        }
      }
      final tag = bytes
          .sublist(nodeStart, offset)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      if (offset >= end) {
        return issue(TlvDiagnosticKind.truncated, 'TLV 缺少长度字段', offset);
      }
      final firstLength = bytes[offset++];
      var length = firstLength;
      if ((firstLength & 0x80) != 0) {
        final count = firstLength & 0x7F;
        if (count == 0 || count > policy.maxLengthBytes) {
          return issue(
            TlvDiagnosticKind.malformed,
            '不支持或无效的 TLV 长度编码',
            offset - 1,
          );
        }
        if (offset + count > end) {
          return issue(TlvDiagnosticKind.truncated, 'TLV 长度字段被截断', offset);
        }
        length = 0;
        for (var i = 0; i < count; i++) {
          length = (length << 8) | bytes[offset++];
        }
        if (policy.rejectLongFormForShortLength && length < 128) {
          return issue(
            TlvDiagnosticKind.malformed,
            'TLV 长度编码不规范（非最短形式）',
            offset - count - 1,
          );
        }
      }
      final constructed = (first & 0x20) != 0;
      final children = <RawBerTlv>[];
      TlvDiagnostic? error;
      final availableEnd = length > end - offset ? end : offset + length;
      if (length > end - offset) {
        error = issue(TlvDiagnosticKind.truncated, 'TLV 值超出输入数据边界', offset);
      } else if ((decodedBytes += length) > policy.maxDecodedValueBytes) {
        error = issue(TlvDiagnosticKind.resourceLimit, 'TLV 累计值字节数超限', offset);
      } else if (constructed && length > 0) {
        error = readRange(offset, availableEnd, depth + 1, children);
        if (error != null &&
            policy.retainMalformedChildren &&
            error.kind != TlvDiagnosticKind.resourceLimit) {
          // Compatibility: a malformed child tree is opaque, with a visible
          // diagnostic. Never swallow shared depth/node/byte exhaustion.
          children.clear();
          error = null;
        }
      }
      out.add(
        RawBerTlv._(
          tagHex: tag,
          offset: nodeStart,
          valueOffset: offset,
          declaredLength: length,
          isConstructed: constructed,
          raw: view(nodeStart, availableEnd),
          value: view(offset, availableEnd),
          children: children,
          diagnostics: diagnostics.sublist(diagnosticStart),
        ),
      );
      if (error != null) return error;
      offset = availableEnd;
    }
    return null;
  }
}
