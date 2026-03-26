import 'package:flutter/material.dart';

/// A widget that displays a camera preview using a Flutter Texture.
///
/// The [cameraId] is the texture ID obtained from the platform when
/// initializing the camera.
///
/// Example usage:
/// ```dart
/// CameraPreview(
///   cameraId: textureId,
/// )
/// ```
class CameraPreview extends StatelessWidget {
  /// The texture ID for the camera preview.
  final int cameraId;

  /// Portrait preview aspect ratio used by the native camera feed.
  static const double _previewAspectRatio = 9 / 16;

  const CameraPreview({super.key, required this.cameraId});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 9,
          height: 16,
          child: AspectRatio(
            aspectRatio: _previewAspectRatio,
            child: Texture(
              textureId: cameraId,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}

/// A stateful widget that handles camera initialization and displays
/// a preview with loading and error states.
///
/// Example usage:
/// ```dart
/// CameraPreviewWithState(
///   cameraIdFuture: initializeCamera(),
/// )
/// ```
class CameraPreviewWithState extends StatefulWidget {
  /// A future that resolves to the camera texture ID.
  final Future<int> cameraIdFuture;

  const CameraPreviewWithState({super.key, required this.cameraIdFuture});

  @override
  State<CameraPreviewWithState> createState() => _CameraPreviewWithStateState();
}

class _CameraPreviewWithStateState extends State<CameraPreviewWithState> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: widget.cameraIdFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: Colors.black,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Camera error: ${snapshot.error ?? "Unknown error"}',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return CameraPreview(cameraId: snapshot.data!);
      },
    );
  }
}
