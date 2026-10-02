// 从一张源图生成全部密度的启动器图标。
//
// **不是测试** —— 它只是借 flutter_test 的渲染/解码环境跑一次。
// 文件名刻意不带 `_test` 后缀，所以 `flutter test` 不会自动执行它；
// 需要时显式跑：
//
//   flutter test test/tool_gen_icons.dart
//
// 为什么用 Dart 而不是 PowerShell + System.Drawing：
// **GDI+ 不支持 WebP**。而 Flutter 引擎自带 WebP 解码器，
// 顺手还能精确缩放，不需要额外装什么图像库。
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show FilterQuality, Paint, Rect, Canvas;

import 'package:flutter_test/flutter_test.dart';

/// 源图。换成别的图只需要改这一行。
///
/// 本地留了一份副本在 `D:\pj3\icon\`（仓库外）—— 附件目录是临时的，
/// 过一阵就没了，而这张图是图标的**唯一来源**，丢了就没法重新生成。
/// 支持 PNG / JPEG / **WebP**（后者正是因为 GDI+ 解不了才用 Dart 做）。
const String _source = r'D:\pj3\icon\bead_pattern_v2.webp';

const String _resDir =
    r'D:\pj3\dsh_agent\android\app\src\main\res';

/// 自适应图标的**背景层**：铺满 108dp 画布。
const Map<String, int> _adaptive = <String, int>{
  'mdpi': 108,
  'hdpi': 162,
  'xhdpi': 216,
  'xxhdpi': 324,
  'xxxhdpi': 432,
};

/// 传统图标（API < 26）：48dp 基准。
const Map<String, int> _legacy = <String, int>{
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

Future<void> _writePng(List<int> bytes, int size, String outPath) async {
  final ui.Codec codec = await ui.instantiateImageCodec(
    Uint8List.fromList(bytes),
  );
  final ui.FrameInfo frame = await codec.getNextFrame();
  final ui.Image img = frame.image;

  // **不能直接 `targetWidth` + `targetHeight`。**
  //
  // 那样会**拉伸**：源图 836×797 不是正方形，直接指定 432×432 会把画面
  // 纵向拉长约 5%，像素画的方格会变成竖长方形。
  //
  // 用 Canvas 做"等比铺满 + 居中裁切"（BoxFit.cover）：
  // 按较紧的一边缩放，多出来的部分对称裁掉。任何长宽比都不会变形。
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final double side = size.toDouble();
  final double scale = math.max(side / img.width, side / img.height);
  final double w = img.width * scale;
  final double h = img.height * scale;

  canvas.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    Rect.fromLTWH((side - w) / 2, (side - h) / 2, w, h),
    Paint()..filterQuality = FilterQuality.high,
  );

  final ui.Image out =
      await recorder.endRecording().toImage(size, size);
  final ByteData? png = await out.toByteData(format: ui.ImageByteFormat.png);

  // `frame.image` 和 `img` 是**同一个对象**，只能 dispose 一次
  // （dispose 两次会触发 Image.dispose 的断言）。
  img.dispose();
  out.dispose();
  codec.dispose();
  if (png == null) throw StateError('编码 PNG 失败：$outPath');

  final File f = File(outPath);
  await f.parent.create(recursive: true);
  await f.writeAsBytes(png.buffer.asUint8List());
}

void main() {
  test('生成各密度的启动器图标', () async {
    final File src = File(_source);
    expect(await src.exists(), isTrue, reason: '源图不存在：$_source');
    final List<int> bytes = await src.readAsBytes();

    for (final MapEntry<String, int> e in _adaptive.entries) {
      await _writePng(
        bytes,
        e.value,
        '$_resDir\\mipmap-${e.key}\\ic_launcher_photo.png',
      );
    }
    for (final MapEntry<String, int> e in _legacy.entries) {
      await _writePng(
        bytes,
        e.value,
        '$_resDir\\mipmap-${e.key}\\ic_launcher.png',
      );
      await _writePng(
        bytes,
        e.value,
        '$_resDir\\mipmap-${e.key}\\ic_launcher_round.png',
      );
    }
  });
}
