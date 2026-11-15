/// Contributors shown by the settings About section and its bottom sheet.
/// Avatars are bundled locally; entries without a verified homepage stay
/// text-only so the sheet never shows a dead link.
class GalleryContributor {
  const GalleryContributor({
    required this.name,
    required this.role,
    required this.initial,
    this.asset,
    this.url,
  });

  final String name;
  final String role;
  final String initial;
  final String? asset;
  final String? url;
}

const galleryContributors = <GalleryContributor>[
  GalleryContributor(
    name: 'kajolno',
    role: 'TrafArch 发起人、主开发者',
    initial: 'K',
    asset: 'assets/contributors/kajolno.jpg',
    url: 'https://github.com/kajolno',
  ),
  GalleryContributor(
    name: 'Nightingale0504',
    role: 'TrafArch 主开发者',
    initial: 'N',
    asset: 'assets/contributors/nightingale0504.jpg',
    url: 'https://github.com/Nightingale0504',
  ),
  GalleryContributor(
    name: '林天仪',
    role: '钻石级赞助商，为我们提供大量的token用于开发！',
    initial: '林',
    asset: 'assets/contributors/lintianyi.jpg',
  ),
  GalleryContributor(
    name: 'mitkimi',
    role: '钻石级赞助商，澳门通与岭南通模块开发者',
    initial: 'M',
    asset: 'assets/contributors/mitkimi.jpg',
    url: 'https://www.mitkimi.com/',
  ),
  GalleryContributor(
    name: 'Makitoid',
    role: '2.0 UI 主设计者、主开发者',
    initial: 'M',
    asset: 'assets/contributors/makitoid.jpg',
    url: 'https://makitoid.github.io/',
  ),
  GalleryContributor(
    name: '鳄鱼宝宝',
    role: '热心网友，为 2.0 界面设计提供指导',
    initial: '鳄',
    asset: 'assets/contributors/eyu.jpg',
  ),
  GalleryContributor(
    name: 'DearVa',
    role: '全能开发者，为 2.0 新界面提供指导',
    initial: 'D',
    asset: 'assets/contributors/dearva.jpg',
    url: 'https://makitoid.github.io/',
  ),
];
