import 'package:flutter/foundation.dart';

/// Tracks whether any open document has unsaved edits, so closing the
/// Windows window can warn instead of silently discarding them.
class UnsavedChanges {
  static final hasUnsaved = ValueNotifier<bool>(false);
}
