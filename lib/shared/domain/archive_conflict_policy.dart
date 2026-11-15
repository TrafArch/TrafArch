/// 同一指纹的卡片已有档案时的保存策略。
enum ArchiveConflictPolicy {
  skip('跳过'),
  overwrite('覆盖'),
  ask('每次询问');

  const ArchiveConflictPolicy(this.label);
  final String label;

  static ArchiveConflictPolicy parse(String? raw) => values.firstWhere(
    (value) => value.name == raw,
    orElse: () => ArchiveConflictPolicy.overwrite,
  );
}
