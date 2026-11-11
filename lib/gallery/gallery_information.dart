part of 'gallery_app.dart';

extension _GalleryInformation on _GalleryViewState {
  void _openInformationPage(GalleryPage page) {
    _linkError = null;
    c.navigate(page);
  }

  Future<void> _copyContact(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) _toast('$label已复制到剪贴板');
  }

  Widget _informationHero(Widget icon, String title, String subtitle) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: Column(
          children: [
            icon,
            _gap(16),
            _text(
              title,
              size: 25,
              weight: FontWeight.w600,
              align: TextAlign.center,
            ),
            _gap(6),
            _text(
              subtitle,
              role: GalleryTypography.label,
              color: t.muted,
              align: TextAlign.center,
            ),
          ],
        ),
      );

  Widget _informationIcon(IconData icon) => Container(
    width: 88,
    height: 88,
    decoration: BoxDecoration(
      color: t.tone,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Icon(icon, size: 42, color: t.onTone),
  );

  Widget _contactRow(
    String title,
    String value,
    IconData icon, {
    String? link,
    String? copyLabel,
    String? copyValue,
    bool email = false,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    leading: Icon(icon, color: t.onTone),
    title: _text(title, role: GalleryTypography.body, weight: FontWeight.w500),
    subtitle: _text(value, role: GalleryTypography.caption, color: t.muted),
    // 仅在显式指定 copyLabel 时提供复制按键；反馈与隐私政策等入口不再展示。
    trailing: copyLabel == null
        ? null
        : IconButton(
            tooltip: '复制$copyLabel',
            icon: const Icon(Icons.copy_outlined, size: 19),
            onPressed: () => _copyContact(copyValue ?? link ?? value, copyLabel),
          ),
    onTap: _openingLink == null
        ? () => _openContact(link ?? value, email: email)
        : null,
  );

  List<Widget> _contactError() => [
    if (_linkError != null) ...[
      _gap(12),
      _panel(_text(_linkError!, role: GalleryTypography.label, color: t.warn)),
    ],
  ];

  Widget _about() => _list([
    _header('关于', back: true),
    _informationHero(
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset('assets/icon/app_icon.png', width: 96, height: 96),
      ),
      AppInfo.appName,
      '版本 ${AppInfo.version} (${AppInfo.buildNumber})',
    ),
    _text(
      '只读交通卡读取与分析工具',
      role: GalleryTypography.body,
      color: t.muted,
      align: TextAlign.center,
    ),
    _gap(24),
    _panel(
      Column(
        children: [
          ListTile(
            leading: Icon(Icons.person_outline, color: t.onTone),
            title: _text('作者', size: 14),
            subtitle: _text(
              AppInfo.author,
              role: GalleryTypography.caption,
              color: t.muted,
            ),
          ),
          const Divider(),
          _settingRow(
            '致谢',
            () => _openInformationPage(GalleryPage.acknowledgements),
            subtitle: '感谢读卡识途及数据贡献者',
            icon: Icons.volunteer_activism_outlined,
          ),
          const Divider(),
          _settingRow(
            '开放源代码许可',
            () => _openInformationPage(GalleryPage.licenses),
            subtitle: '查看本应用使用的开源软件与许可',
            icon: Icons.code_rounded,
          ),
          const Divider(),
          _contactRow(
            '隐私政策',
            '了解数据与隐私保护',
            Icons.privacy_tip_outlined,
            link: AppSupport.privacy,
          ),
        ],
      ),
      padding: EdgeInsets.zero,
    ),
    ..._contactError(),
    _gap(28),
    _text(
      AppInfo.copyright,
      role: GalleryTypography.caption,
      color: t.muted,
      align: TextAlign.center,
    ),
  ]);

  Widget _feedback() => _list([
    _header('问题反馈', back: true),
    _informationHero(
      _informationIcon(Icons.forum_outlined),
      '一起改进 TrafArch',
      '使用中遇到问题，或有新的建议？\n可以通过以下渠道联系我们。',
    ),
    _panel(
      Column(
        children: [
          _contactRow(
            'QQ 群',
            AppSupport.qqGroup,
            Icons.groups_outlined,
            link: AppSupport.qqJoin,
          ),
          const Divider(),
          _contactRow(
            '邮箱',
            AppSupport.email,
            Icons.email_outlined,
            email: true,
          ),
        ],
      ),
      padding: EdgeInsets.zero,
    ),
    _gap(18),
    _button(
      _openingLink == AppSupport.survey ? '正在打开问卷…' : '填写反馈问卷',
      _openingLink == null ? () => _openContact(AppSupport.survey) : null,
      primary: true,
      icon: Icons.edit_note_outlined,
    ),
    _gap(8),
    _text(
      '问卷在 Edge 或 Chrome 的应用内浏览器中打开',
      role: GalleryTypography.caption,
      color: t.muted,
      align: TextAlign.center,
    ),
    ..._contactError(),
    _sectionTitle('描述问题时可以提供'),
    _panel(
      _text(
        '出现问题的页面、操作步骤和期望结果。\n如需附上截图或日志，请先遮挡卡号与行程等个人信息。',
        role: GalleryTypography.label,
        color: t.muted,
      ),
    ),
  ]);

  Widget _acknowledgements() => _list([
    _header('致谢', back: true),
    _informationHero(
      _informationIcon(Icons.volunteer_activism_outlined),
      '感谢每一份贡献',
      '城市与站点资料来自公开数据和社区整理',
    ),
    _panel(
      _text(
        '本应用的城市站点参考数据使用已冻结的本地来源，包括读卡识途（Trip Reader）公开发布的数据集。感谢 domosekai、HaoTian22 及其他数据贡献者共同采集、维护线路与站点资料。',
        role: GalleryTypography.body,
      ),
    ),
    _gap(14),
    _panel(
      Column(
        children: [
          _contactRow(
            '读卡识途数据源',
            AppSupport.tripReader,
            Icons.public,
            copyLabel: '项目地址',
          ),
          const Divider(),
          _contactRow(
            'HaoTian22 社区补充数据',
            AppSupport.community,
            Icons.public,
            copyLabel: '社区项目地址',
          ),
        ],
      ),
      padding: EdgeInsets.zero,
    ),
    ..._contactError(),
    _gap(20),
    _text(
      '数据以 CC BY 4.0（知识共享署名 4.0 国际）许可协议开放使用。\n资料由开发者按城市整理后随应用提供，保留原始编码与来源。',
      role: GalleryTypography.caption,
      color: t.muted,
    ),
  ]);

  Widget _licensePage() {
    final licenses = _licenses ??= LicenseRegistry.licenses.toList();
    return FutureBuilder<List<LicenseEntry>>(
      future: licenses,
      builder: (context, snapshot) => _list([
        _header('开放源代码许可', back: true),
        _text(
          '${AppInfo.appName} ${AppInfo.version}',
          role: GalleryTypography.body,
          color: t.muted,
        ),
        _gap(16),
        if (snapshot.hasError)
          _button('重新加载许可', _reloadLicenses)
        else if (!snapshot.hasData)
          const Center(child: CircularProgressIndicator())
        else
          for (final (index, license) in snapshot.data!.indexed)
            _expand('license:$index', license.packages.join(', '), [
              for (final paragraph in license.paragraphs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(
                    paragraph.text,
                    style: GalleryTypography.caption.copyWith(color: t.muted),
                  ),
                ),
            ]),
      ]),
    );
  }
}
