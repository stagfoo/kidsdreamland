/// Getting pixels out of a PNG.
///
/// The thin layer that touches `dart:ui`, kept apart from the tracer so
/// the tracer stays plain Dart and testable against pixel grids written
/// by hand.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// A decoded image, plus the bytes the tracer wants.
class DecodedImage {
  const DecodedImage(this.image, this.rgba, this.width, this.height);

  /// Kept for the editor to paint behind its overlay — seeing the original
  /// under the traced result is the whole way you tell whether the trace
  /// is right.
  final ui.Image image;

  /// Row-major, four bytes per pixel, straight-alpha.
  final Uint8List rgba;

  final int width, height;

  void dispose() => image.dispose();
}

/// Decodes a PNG, shrinking anything enormous on the way in.
///
/// A drawing app exports at whatever the tablet's canvas was, which can be
/// four thousand pixels square — sixty-four megabytes of RGBA to hold and
/// re-walk on every slider drag. Capping the long edge costs nothing that
/// survives simplification.
///
/// The cap is generous rather than tight because this resample averages,
/// and averaging is what thins a pencil line until it breaks. The tracer
/// does its own downsampling from here using the *most* opaque pixel in
/// each cell, which keeps the line solid. Two stages, because only the
/// first one can happen in native code.
Future<DecodedImage> decodeImageForTracing(
  Uint8List bytes, {
  int maxEdge = 1024,
}) async {
  final descriptor = await ui.ImageDescriptor.encoded(
    await ui.ImmutableBuffer.fromUint8List(bytes),
  );

  final longEdge = descriptor.width > descriptor.height
      ? descriptor.width
      : descriptor.height;
  final scale = longEdge > maxEdge ? maxEdge / longEdge : 1.0;

  final codec = await descriptor.instantiateCodec(
    targetWidth: (descriptor.width * scale).round().clamp(1, 1 << 16),
    targetHeight: (descriptor.height * scale).round().clamp(1, 1 << 16),
  );
  descriptor.dispose();

  final frame = await codec.getNextFrame();
  codec.dispose();
  final image = frame.image;

  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) {
    image.dispose();
    throw const ImageDecodeException('the image could not be read');
  }

  return DecodedImage(
    image,
    data.buffer.asUint8List(),
    image.width,
    image.height,
  );
}

class ImageDecodeException implements Exception {
  const ImageDecodeException(this.message);
  final String message;

  @override
  String toString() => 'ImageDecodeException: $message';
}
