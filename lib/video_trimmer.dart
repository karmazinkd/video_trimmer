library video_trimmer;

import 'dart:io';
import 'package:path/path.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_trimmer/file_formats.dart';
import 'package:video_trimmer/storage_dir.dart';
import 'package:video_trimmer/trim_editor.dart';

/// Helps in loading video from file, saving trimmed video to a file
/// and gives video playback controls. Some of the helpful methods
/// are:
/// * [loadVideo()]
/// * [saveTrimmedVideo()]
/// * [videPlaybackControl()]
class Trimmer {
  static File currentVideoFile;

  /// Loads a video using the path provided.
  ///
  /// Returns the duration of the video file.
  Future<Duration> loadVideo({@required File videoFile}) async {
    if (videoFile == null)
      throw ArgumentError("videoFile must not be null");

    if (videoPlayerController == null) {
      currentVideoFile = videoFile;

      videoPlayerController = VideoPlayerController.file(currentVideoFile);
      await videoPlayerController.initialize();
    }
    return videoPlayerController.value.duration;
  }

  Future<String> _createFolderInAppDocDir(String folderName,
      StorageDir storageDir,) async {
    Directory _directory;

    if (storageDir == null) {
      _directory = await getApplicationDocumentsDirectory();
    } else {
      switch (storageDir.toString()) {
        case 'temporaryDirectory':
          _directory = await getTemporaryDirectory();
          break;

        case 'applicationDocumentsDirectory':
          _directory = await getApplicationDocumentsDirectory();
          break;

        case 'externalStorageDirectory':
          _directory = await getExternalStorageDirectory();
          break;
      }
    }

    // Directory + folder name
    final Directory _directoryFolder = Directory('${_directory.path}/$folderName/');

    if (await _directoryFolder.exists()) {
      // If folder already exists return path
      print('Exists');
      return _directoryFolder.path;
    } else {
      print('Creating');
      // If folder does not exists create folder and then return its path
      final Directory _directoryNewFolder = await _directoryFolder.create(recursive: true);
      return _directoryNewFolder.path;
    }
  }

  /// For getting the video controller state, to know whether the
  /// video is playing or paused currently.
  ///
  /// The two required parameters are [startValue] & [endValue]
  ///
  /// * [startValue] is the current starting point of the video.
  /// * [endValue] is the current ending point of the video.
  ///
  /// Returns a `Future<bool>`, if `true` then video is playing
  /// otherwise paused.
  Future<bool> videPlaybackControl({
    @required double startValue,
    @required double endValue,
  }) async {
    if (videoPlayerController.value.isPlaying) {
      await videoPlayerController.pause();
      return false;
    } else {
      if (videoPlayerController.value.position.inMilliseconds >= endValue.toInt()) {
        await videoPlayerController.seekTo(Duration(milliseconds: startValue.toInt()));
        await videoPlayerController.play();
        return true;
      } else {
        await videoPlayerController.play();
        return true;
      }
    }
  }

  File getVideoFile() {
    return currentVideoFile;
  }

  ///Disposes [videoPlayerController] and clears [currentVideoFile].
  Future<void> dispose() async {
    if (videoPlayerController != null) {
      await videoPlayerController.setVolume(0.0);
      await videoPlayerController.pause();
      await videoPlayerController.dispose();
      videoPlayerController = null;
    }
    currentVideoFile = null;
    return;
  }
}
