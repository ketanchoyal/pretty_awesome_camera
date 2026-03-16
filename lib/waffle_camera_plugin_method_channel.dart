import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'src/camera_description.dart';
import 'src/camera_exception.dart';
import 'src/recording_state.dart';
import 'src/resolution_preset.dart';
import 'waffle_camera_plugin_platform_interface.dart';

/// An implementation of [WaffleCameraPluginPlatform] that uses method channels.
class MethodChannelWaffleCameraPlugin extends WaffleCameraPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('waffle_camera_plugin');

  /// Event channel for recording state changes.
  late EventChannel _recordingStateEventChannel;

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<List<CameraDescription>> getAvailableCameras() async {
    try {
      final result = await methodChannel.invokeMethod<List<dynamic>>(
        'getAvailableCameras',
      );
      if (result == null) {
        return [];
      }
      return result
          .map(
            (camera) => CameraDescription.fromJson(
              Map<dynamic, dynamic>.from(camera as Map),
            ),
          )
          .toList();
    } on PlatformException catch (e) {
      throw CameraException(
        code: e.code,
        message: e.message ?? 'Failed to get available cameras',
      );
    }
  }

  @override
  Future<int> createCamera(
    CameraDescription camera,
    ResolutionPreset preset,
  ) async {
    try {
      final cameraId = await methodChannel.invokeMethod<int>('createCamera', {
        'camera': camera.toJson(),
        'preset': preset.name,
      });
      if (cameraId == null) {
        throw CameraException(
          code: 'invalid_response',
          message: 'Platform returned null camera ID',
        );
      }
      return cameraId;
    } on PlatformException catch (e) {
      throw CameraException(
        code: e.code,
        message: e.message ?? 'Failed to create camera',
      );
    }
  }

  @override
  Future<void> initializeCamera(int cameraId) async {
    try {
      await methodChannel.invokeMethod<void>('initializeCamera', {
        'cameraId': cameraId,
      });
    } on PlatformException catch (e) {
      throw CameraException(
        code: e.code,
        message: e.message ?? 'Failed to initialize camera',
      );
    }
  }

  @override
  Future<void> startRecording(int cameraId) async {
    try {
      await methodChannel.invokeMethod<void>('startRecording', {
        'cameraId': cameraId,
      });
    } on PlatformException catch (e) {
      throw CameraException(
        code: e.code,
        message: e.message ?? 'Failed to start recording',
      );
    }
  }

  @override
  Future<String> stopRecording(int cameraId) async {
    try {
      final filePath = await methodChannel.invokeMethod<String>(
        'stopRecording',
        {'cameraId': cameraId},
      );
      if (filePath == null) {
        throw CameraException(
          code: 'invalid_response',
          message: 'Platform returned null file path',
        );
      }
      return filePath;
    } on PlatformException catch (e) {
      throw CameraException(
        code: e.code,
        message: e.message ?? 'Failed to stop recording',
      );
    }
  }

  @override
  Future<void> pauseRecording(int cameraId) async {
    try {
      await methodChannel.invokeMethod<void>('pauseRecording', {
        'cameraId': cameraId,
      });
    } on PlatformException catch (e) {
      throw CameraException(
        code: e.code,
        message: e.message ?? 'Failed to pause recording',
      );
    }
  }

  @override
  Future<void> resumeRecording(int cameraId) async {
    try {
      await methodChannel.invokeMethod<void>('resumeRecording', {
        'cameraId': cameraId,
      });
    } on PlatformException catch (e) {
      throw CameraException(
        code: e.code,
        message: e.message ?? 'Failed to resume recording',
      );
    }
  }

  @override
  Future<void> disposeCamera(int cameraId) async {
    try {
      await methodChannel.invokeMethod<void>('disposeCamera', {
        'cameraId': cameraId,
      });
    } on PlatformException catch (e) {
      throw CameraException(
        code: e.code,
        message: e.message ?? 'Failed to dispose camera',
      );
    }
  }

  @override
  Stream<RecordingState> onRecordingStateChanged(int cameraId) {
    _recordingStateEventChannel = EventChannel(
      'waffle_camera_plugin/recording_state_$cameraId',
    );
    return _recordingStateEventChannel
        .receiveBroadcastStream()
        .map((state) {
          return RecordingState.values.firstWhere(
            (e) => e.name == state as String,
          );
        })
        .handleError((error) {
          throw CameraException(
            code: 'stream_error',
            message: error.toString(),
          );
        });
  }
}
