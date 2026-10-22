enum LeCorrectionTiming { beforeContinuation, afterContinuation }

/// Compatibility profiles deliberately retain the existing protocol families'
/// 6100, 6C00, CLA, 6700 and retry-order differences.
class ExchangePolicy {
  const ExchangePolicy({
    this.follow6100 = false,
    this.correct6c00 = false,
    this.retry6700 = false,
    this.correctContinuationLe = false,
    this.continuationCla,
    this.correctionTiming = LeCorrectionTiming.beforeContinuation,
    this.strictLength = false,
    this.zeroLeIsOpenLength = true,
    this.maxContinuations = 32,
    this.maxExchanges = 68,
    this.maxResponseBytes = 1024 * 1024,
  });

  final bool follow6100;
  final bool correct6c00;
  final bool retry6700;
  final bool correctContinuationLe;

  /// Null preserves the original CLA; EMV uses the interindustry CLA 00.
  final int? continuationCla;
  final LeCorrectionTiming correctionTiming;
  final bool strictLength;
  final bool zeroLeIsOpenLength;
  final int maxContinuations;
  final int maxExchanges;

  /// Cumulative physical response bytes, including discarded retry responses.
  final int maxResponseBytes;

  static const local = ExchangePolicy(
    correct6c00: true,
    retry6700: true,
    correctionTiming: LeCorrectionTiming.afterContinuation,
  );
  static const transit = ExchangePolicy();
  static const emv = ExchangePolicy(
    follow6100: true,
    correct6c00: true,
    correctContinuationLe: true,
    continuationCla: 0,
  );

  ExchangePolicy withStrictLength(bool strict) => ExchangePolicy(
    follow6100: follow6100,
    correct6c00: correct6c00,
    retry6700: retry6700,
    correctContinuationLe: correctContinuationLe,
    continuationCla: continuationCla,
    correctionTiming: correctionTiming,
    strictLength: strict,
    zeroLeIsOpenLength: zeroLeIsOpenLength,
    maxContinuations: maxContinuations,
    maxExchanges: maxExchanges,
    maxResponseBytes: maxResponseBytes,
  );
}
