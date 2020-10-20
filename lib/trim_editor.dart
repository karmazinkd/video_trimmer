import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_trimmer/thumbnail_viewer.dart';
import 'package:video_trimmer/video_trimmer.dart';

VideoPlayerController videoPlayerController;

class TrimEditor extends StatefulWidget {
  final double viewerWidth;

  final double viewerHeight;

  final Duration maxDuration;

  final Duration minDuration;

  final Color scrubberPaintColor;

  final int thumbnailQuality;

  final bool showDuration;

  final TextStyle durationTextStyle;

  final Function(double startValue) onChangeStart;

  final Function(double endValue) onChangeEnd;

  final Function(bool isPlaying) onChangePlaybackState;

  ///The max width of selection area in relation to viewerWidth, in percent. Value between 0.0 and 1.0, default - 0.8
  final double maxSelectionAreaPortion;

  TrimEditor({
    @required this.viewerWidth,
    @required this.viewerHeight,
    @required this.maxDuration,
    @required this.minDuration,
    this.scrubberPaintColor = Colors.white,
    this.thumbnailQuality = 75,
    this.showDuration = true,
    this.durationTextStyle = const TextStyle(color: Colors.white),
    this.onChangeStart,
    this.onChangeEnd,
    this.onChangePlaybackState,
    this.maxSelectionAreaPortion = 0.8,
  })
      : assert(viewerWidth != null),
        assert(viewerHeight != null),
        assert(scrubberPaintColor != null),
        assert(thumbnailQuality != null),
        assert(showDuration != null),
        assert(durationTextStyle != null),
        assert(maxSelectionAreaPortion != null);

  @override
  _TrimEditorState createState() => _TrimEditorState();
}

class _TrimEditorState extends State<TrimEditor> with TickerProviderStateMixin {
  File _videoFile;

  double _videoStartPos = 0.0; //Time when the video starts, in ms
  double _videoEndPos = 0.0; //Time when the video ends, in ms

  int _videoDuration = 0; //Video duration
  int _currentPosition = 0;

  int _numberOfThumbnails = 0; //Number of thumbnails generated

  double _minLengthPixels;

  double _start; //position of the left slider
  double _end; //position of the right slider
  double _sliderLength = 10.0; //width of the slider

  double _arrivedLeft; //The slider reaches the leftmost position, in px
  double _arrivedRight; //The slider reaches the rightmost position, in px
  double _sidePortion = 0.1;

  ThumbnailViewer thumbnailWidget;

  Animation<double> _scrubberAnimation;
  AnimationController _animationController;
  Tween<double> _linearTween;

  ScrollController controller; //Thumbnail scroll controller

  double _maxRegion; //Maximum distance between sliders, in px

  double _fraction; //how many milliseconds is in 1 px
  double _offset = 0; // distance scrolled from 0

  Future<void> _initializeVideoController() async {
    if (_videoFile != null) {
      videoPlayerController.addListener(() {
        final bool isPlaying = videoPlayerController.value.isPlaying;

        if (isPlaying) {
          widget.onChangePlaybackState(true);
          setState(() {
            _currentPosition = videoPlayerController.value.position.inMilliseconds;

            if (_currentPosition > _videoEndPos.toInt()) {
              widget.onChangePlaybackState(false);
              videoPlayerController.pause();
              _animationController.stop();
            } else {
              if (!_animationController.isAnimating) {
                widget.onChangePlaybackState(true);
                _animationController.forward();
              }
            }
          });
        } else {
          if (videoPlayerController.value.initialized) {
            if (_animationController != null) {
              if ((_scrubberAnimation.value).toInt() == (_end).toInt()) {
                _animationController.reset();
              }
              _animationController.stop();
              widget.onChangePlaybackState(false);
            }
          }
        }
      });

      videoPlayerController.setVolume(1.0);

      _videoDuration = videoPlayerController.value.duration.inMilliseconds;

      _videoStartPos = 0.0;
      widget.onChangeStart(_videoStartPos);

      _videoEndPos = widget.maxDuration.inMilliseconds.toDouble();
      if (videoPlayerController.value.duration <= widget.maxDuration)
        _videoEndPos = videoPlayerController.value.duration.inMilliseconds.toDouble();

      widget.onChangeEnd(_videoEndPos);
    }
  }

  _scrollerListener() {
    controller.addListener(() async {
      setState(() {
        _offset = controller.offset;
        _videoStartPos = (_start - _arrivedLeft + controller.offset) * _fraction;
        _videoEndPos = (_end - _arrivedLeft + controller.offset) * _fraction;

        _linearTween.begin = _start + _sliderLength;
        _linearTween.end = _end;
        _animationController.duration =
            Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
        _animationController.reset();

        widget.onChangeStart(_videoStartPos);
        widget.onChangeEnd(_videoEndPos);
      });

      await videoPlayerController.pause();
      await videoPlayerController.seekTo(Duration(milliseconds: _videoStartPos.toInt()));
    });
  }

  @override
  void initState() {
    super.initState();
    controller = ScrollController();
    _scrollerListener();

    _maxRegion = widget.viewerWidth * widget.maxSelectionAreaPortion;
    double sidePortion = (1.0 - widget.maxSelectionAreaPortion) /
        2.0; //for ex.: (1-0.8)/2 = 0.1 - foremost side offset

    _arrivedLeft = _start = widget.viewerWidth * sidePortion; //*0.1 - left slider foremost position
    _arrivedRight = _end =
        widget.viewerWidth * (1.0 - sidePortion); //*0.9 - rigth slider foremost position

    _videoFile = Trimmer.currentVideoFile;

    _initializeVideoController();

    if (_videoDuration > widget.maxDuration.inMilliseconds) {
      _fraction = widget.maxDuration.inMilliseconds / _maxRegion;
    } else {
      _fraction = _videoDuration / _maxRegion;
    }

    _initThumbnailViewer();

    _minLengthPixels =
        (widget.minDuration.inMilliseconds / widget.maxDuration.inMilliseconds) * _maxRegion;
    if (Duration(milliseconds: _videoDuration).inSeconds <= widget.minDuration.inSeconds)
      _minLengthPixels = _maxRegion; //Can't drag

    // Defining the tween points
    _linearTween = Tween(begin: _start + _sliderLength, end: _end);

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt()),
    );

    _scrubberAnimation = _linearTween.animate(_animationController)
      ..addListener(() {
        setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _animationController.stop();
        }
      });
  }

  void _initThumbnailViewer(){
    /*
    //The default maxDuration corresponds to 10 thumbnails
    _numberOfThumbnails = ((_videoDuration / widget.maxDuration.inMilliseconds) * 10).toInt();
    double _thumbnailWidth = _maxRegion / 10;

    if (_numberOfThumbnails <= 10) { //The uploaded video duration is not greater than the maximum duration
      _numberOfThumbnails = 10;
      _thumbnailWidth = _maxRegion / 10;
    }
*/

    double _thumbnailWidth = widget.viewerHeight;
    double lengthOfAllThumbs = _videoDuration / _fraction;
    _numberOfThumbnails = (lengthOfAllThumbs / _thumbnailWidth).round();

    final ThumbnailViewer _thumbnailWidget = ThumbnailViewer(
      videoFile: _videoFile,
      videoDuration: _videoDuration,
      thumbnailHeight: widget.viewerHeight,
      thumbnailWidth: _thumbnailWidth,
      numberOfThumbnails: _numberOfThumbnails,
      quality: widget.thumbnailQuality,
      startSpace: _start,
      endSpace: widget.viewerWidth - _end,
      controller: controller,
    );
    thumbnailWidget = _thumbnailWidget;
  }

  @override
  void dispose() {
    videoPlayerController.pause();
    widget.onChangePlaybackState(false);
    if (_videoFile != null) {
      videoPlayerController.setVolume(0.0);
      videoPlayerController.pause();
      videoPlayerController.dispose();
      widget.onChangePlaybackState(false);
    }
    controller?.dispose();
    super.dispose();
  }

  Duration _formatTime(Duration duration) {
    String str = duration.toString();

    int p = int.parse(str.split('.')[1].substring(0, 1));

    int seconds = duration.inSeconds;

    if (p >= 5) seconds = seconds + 1;

    return Duration(seconds: seconds);
  }

  String _showTime(String type) {
    Duration _sd = _formatTime(Duration(milliseconds: _videoStartPos.toInt()));
    Duration _ed = _formatTime(Duration(milliseconds: _videoEndPos.toInt()));
    Duration _id = _ed - _sd;

    if (type == 'start') return _sd.toString().split('.')[0];
    if (type == 'end') return _ed.toString().split('.')[0];
    if (type == 'duration') return _id.toString().split('.')[0];

    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        widget.showDuration
            ? Container(
          width: widget.viewerWidth,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                Text(
                  _showTime('start'),
                  style: widget.durationTextStyle,
                ),
                Text(
                  _showTime('duration'),
                  style: widget.durationTextStyle,
                ),
                Text(
                  _showTime('end'),
                  style: widget.durationTextStyle,
                ),
              ],
            ),
          ),
        )
            : Container(),
        Stack(
          children: [
            Container(
              height: widget.viewerHeight,
              width: widget.viewerWidth,
              child: thumbnailWidget == null ? Column() : thumbnailWidget,
            ),
            _leftSlider(),
            _rightSlider(),
            Positioned(
              top: 0,
              left: _start + _sliderLength,
              right: widget.viewerWidth - _end,
              child: Container(height: 1, color: Colors.white),
            ),
            Positioned(
              left: _start + _sliderLength,
              right: widget.viewerWidth - _end,
              bottom: 0,
              child: Container(height: 1, color: Colors.white),
            ),
            Positioned(
              left: _scrubberAnimation.value,
              top: 0,
              bottom: 0,
              child: Container(
                width: 2,
                color: _scrubberAnimation.value <= (_start + _sliderLength + 1)
                    ? Colors.transparent
                    : videoPlayerController.value.isPlaying
                    ? Colors.yellow
                    : Colors.yellow,
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _dragLeft = false;

  Widget _leftSlider() {
    Widget current = Container(
      height: 50,
      width: _sliderLength,
      color: _dragLeft ? Colors.yellow : Colors.white,
    );

    current = GestureDetector(
      onHorizontalDragStart: (details) {
        setState(() {
          _dragLeft = true;
        });
      },
      onHorizontalDragEnd: (details) {
        setState(() {
          _dragLeft = false;
        });
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) async {
        if (_start + details.delta.dx < _arrivedLeft) {
          setState(() {
            _start = _arrivedLeft;
          });

          return;
        }

        if (_end - _start - details.delta.dx < _minLengthPixels) return;

        setState(() {
          _start = _start + details.delta.dx;
          _videoStartPos = _fraction * (_start + _offset - _arrivedLeft);
          widget.onChangeStart(_videoStartPos);
        });

        await videoPlayerController.pause();
        await videoPlayerController.seekTo(Duration(milliseconds: _videoStartPos.toInt()));

        _linearTween.begin = _start + _sliderLength;
        _animationController.duration =
            Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
        _animationController.reset();
      },
      child: current,
    );

    return Positioned(left: _start, child: current);
  }

  bool _dragRight = false;

  Widget _rightSlider() {
    Widget current = Container(
      height: 50,
      width: _sliderLength,
      color: _dragRight ? Colors.yellow : Colors.white,
    );

    current = GestureDetector(
      onHorizontalDragStart: (details) {
        setState(() {
          _dragRight = true;
        });
      },
      onHorizontalDragEnd: (details) {
        setState(() {
          _dragRight = false;
        });
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) async {
        if (_end + details.delta.dx > _arrivedRight) {
          setState(() {
            _end = _arrivedRight;
            _videoEndPos = _fraction * (_end + _offset + -_arrivedLeft);
          });

          return;
        }

        if (_end - _start + details.delta.dx < _minLengthPixels) return;

        setState(() {
          _end = _end + details.delta.dx;
          _videoEndPos = _fraction * (_end + _offset - _arrivedLeft);

          widget.onChangeEnd(_videoEndPos);
        });

        await videoPlayerController.pause();
        await videoPlayerController.seekTo(Duration(milliseconds: _videoStartPos.toInt()));

        _linearTween.end = _end;
        _animationController.duration =
            Duration(milliseconds: (_videoEndPos - _videoStartPos).toInt());
        _animationController.reset();
      },
      child: current,
    );

    return Positioned(left: _end, child: current);
  }
}
