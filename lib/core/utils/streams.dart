import 'dart:async';

/// Combines several streams into one that emits whenever any source emits,
/// yielding a list of the latest value from every source once all of them
/// have produced at least one value.
///
/// Subscriptions are cancelled automatically when the returned stream is
/// cancelled (e.g. when a Riverpod [StreamProvider] is disposed).
///
/// Implemented with a plain [StreamController] (not an `async*` generator)
/// because canceling an `async*` that is suspended at an inner `await for`
/// can deadlock: the inner subscription's teardown never resumes the
/// generator into its `finally` block.
Stream<List<T>> combineLatest<T>(Iterable<Stream<T>> streams) {
  final sources = streams.toList();
  late final StreamController<List<T>> controller;
  final subscriptions = <StreamSubscription<T>>[];
  final latest = List<T?>.filled(sources.length, null);
  final hasValue = List<bool>.filled(sources.length, false);

  void emitIfComplete() {
    if (hasValue.every((value) => value)) {
      controller.add(latest.cast<T>());
    }
  }

  controller = StreamController<List<T>>(
    onListen: () {
      for (var i = 0; i < sources.length; i++) {
        subscriptions.add(
          sources[i].listen((value) {
            latest[i] = value;
            hasValue[i] = true;
            emitIfComplete();
          }, onError: controller.addError),
        );
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );

  return controller.stream;
}

/// Maps the combined latest values from [sources] through [map], emitting a
/// value on every source change.
///
/// Returns an immediately-cancellable single-subscription stream (unlike an
/// `async*` generator, which only observes cancellation at a `yield`: a
/// generator passivated at an `await for` over a never-ending stream leaks its
/// underlying subscriptions until the next value arrives).
Stream<R> mapLatest<T, R>(
  Iterable<Stream<T>> sources,
  R Function(List<T> values) map,
) {
  late final StreamController<R> controller;
  StreamSubscription<List<T>>? combined;

  controller = StreamController<R>(
    onListen: () {
      combined = combineLatest<T>(sources).listen((values) {
        if (controller.hasListener) {
          controller.add(map(values));
        }
      }, onError: controller.addError);
    },
    onCancel: () {
      final subscription = combined;
      combined = null;
      return subscription?.cancel();
    },
  );

  return controller.stream;
}
