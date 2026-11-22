part of 'gallery_app.dart';

extension _GalleryLiveArchive on _GalleryViewState {
  void _archiveNotice(String message, bool failed) => _toast(
    message,
    type: failed ? GalleryFeedbackType.error : GalleryFeedbackType.success,
  );
}
