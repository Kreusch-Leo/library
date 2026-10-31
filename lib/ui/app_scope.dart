import 'package:flutter/widgets.dart';

import '../services/library_controller.dart';

/// Makes the [LibraryController] available to the widget tree and rebuilds
/// dependents when it notifies.
class AppScope extends InheritedNotifier<LibraryController> {
  const AppScope({
    super.key,
    required LibraryController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Returns the controller and subscribes [context] to its changes.
  static LibraryController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Returns the controller without subscribing to changes.
  static LibraryController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
