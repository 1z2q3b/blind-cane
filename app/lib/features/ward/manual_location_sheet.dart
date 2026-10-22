import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// 手动定位选中的坐标。
class PickedLocation {
  const PickedLocation(this.lng, this.lat);

  final double lng;
  final double lat;

  String get text => '${lng.toStringAsFixed(6)}, ${lat.toStringAsFixed(6)}';
}

/// 手动定位面板。
///
/// <h3>为什么不是「地图选点」</h3>
/// 真正的地图选点需要底图瓦片，而本项目在国内场景下只有高德可用（OSM 等境外瓦片
/// 在境内使用有合规风险，不能用）。高德 JS API 需要 Web 端 Key + 安全密钥，
/// 没配 Key 时硬接会得到一片灰屏——那才是"假可用"。
///
/// 所以这里做的是**坐标选择器**，三个入口都是真实生效的：
/// <ul>
///   <li><b>以手杖当前位置为基准微调</b>：老人此刻多半就在家附近，拖一下就能定位到
///       家所在的位置，换算关系是按米算的真实距离，不是随便画个点；</li>
///   <li><b>直接输入经纬度</b>：从任何渠道拿到的坐标都能精确录入，6 位小数约 0.1 米；</li>
///   <li><b>一键复制手杖位置</b>：家 = 老人当前所在地的常见情况，一步到位。</li>
/// </ul>
///
/// 拿到坐标后会写进 ward.home_lng / home_lat，参与「离家/到家判断」，
/// 也能作为围栏的默认中心——整条链路是通的，不是只存不用。
class ManualLocationSheet extends StatefulWidget {
  const ManualLocationSheet({
    super.key,
    this.initialLng,
    this.initialLat,
    this.deviceLng,
    this.deviceLat,
  });

  /// 已保存的住址坐标（编辑档案时带入）。
  final double? initialLng;
  final double? initialLat;

  /// 手杖当前位置（作为基准点与"复制"来源）。
  final double? deviceLng;
  final double? deviceLat;

  @override
  State<ManualLocationSheet> createState() => _ManualLocationSheetState();
}

class _ManualLocationSheetState extends State<ManualLocationSheet> {
  late final TextEditingController _lngCtrl;
  late final TextEditingController _latCtrl;

  /// 当前选中的坐标。
  double? _lng;
  double? _lat;

  /// 画布基准点（点击微调时的原点）。
  double? _anchorLng;
  double? _anchorLat;

  /// 视野跨度（米）。越大越"缩得远"。
  double _spanMeters = 500;

  static const double _canvasHeight = 240;

  @override
  void initState() {
    super.initState();
    _lng = widget.initialLng ?? widget.deviceLng;
    _lat = widget.initialLat ?? widget.deviceLat;
    _anchorLng = widget.deviceLng ?? _lng;
    _anchorLat = widget.deviceLat ?? _lat;
    _lngCtrl = TextEditingController(text: _lng == null ? '' : _lng!.toStringAsFixed(6));
    _latCtrl = TextEditingController(text: _lat == null ? '' : _lat!.toStringAsFixed(6));
  }

  @override
  void dispose() {
    _lngCtrl.dispose();
    _latCtrl.dispose();
    super.dispose();
  }

  bool get _hasDevice => widget.deviceLng != null && widget.deviceLat != null;

  bool get _hasValue => _lng != null && _lat != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('手动定位',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              _hasDevice
                  ? '以手杖当前位置为基准，在下方方框里点选家的方向与距离，'
                      '或直接填写经纬度。'
                  : '还没有收到手杖定位。请直接填写经纬度，'
                      '或先让手杖上报一次位置再回来。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // ---- 画布：点击微调 ----
            Container(
              height: _canvasHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant),
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: _anchorLng == null || _anchorLat == null
                  ? Center(
                      child: Text('缺少基准点，无法点选',
                          style: theme.textTheme.bodyMedium),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final metersPerPixel =
                            _spanMeters / math.min(constraints.maxWidth, constraints.maxHeight);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) => _onTap(
                            details.localPosition,
                            Size(constraints.maxWidth, constraints.maxHeight),
                            metersPerPixel,
                          ),
                          child: CustomPaint(
                            painter: _PickerPainter(
                              anchorLng: _anchorLng!,
                              anchorLat: _anchorLat!,
                              selectedLng: _lng,
                              selectedLat: _lat,
                              spanMeters: _spanMeters,
                              gridColor: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.6),
                              anchorColor: theme.colorScheme.primary,
                              selectedColor: AppTheme.critical,
                              textColor: theme.colorScheme.onSurfaceVariant,
                            ),
                            size: Size.infinite,
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),

            // ---- 视野档位 ----
            Row(
              children: [
                Text('视野', style: theme.textTheme.bodySmall),
                const SizedBox(width: 10),
                Expanded(
                  child: SegmentedButton<double>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: 200.0, label: Text('200m')),
                      ButtonSegment(value: 500.0, label: Text('500m')),
                      ButtonSegment(value: 2000.0, label: Text('2km')),
                      ButtonSegment(value: 5000.0, label: Text('5km')),
                    ],
                    selected: {_spanMeters},
                    onSelectionChanged: (s) =>
                        setState(() => _spanMeters = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---- 坐标输入 ----
            Row(
              children: [
                Expanded(child: _numberField(_lngCtrl, '经度', isLng: true)),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_latCtrl, '纬度', isLng: false)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _distanceText(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _hasValue
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 14),

            // ---- 快捷操作 ----
            OutlinedButton.icon(
              onPressed: _hasDevice ? _useDeviceLocation : null,
              icon: const Icon(Icons.my_location),
              label: Text(_hasDevice
                  ? '使用手杖当前位置（${widget.deviceLng!.toStringAsFixed(5)}, '
                      '${widget.deviceLat!.toStringAsFixed(5)}）'
                  : '手杖暂无定位，无法使用'),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _hasValue
                        ? () => Navigator.of(context)
                            .pop(PickedLocation(_lng!, _lat!))
                        : null,
                    child: const Text('使用此位置'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(TextEditingController ctrl, String label,
      {required bool isLng}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: isLng ? '113.600000' : '34.800000',
        isDense: true,
      ),
      onChanged: (text) {
        final value = double.tryParse(text);
        if (value == null) {
          return;
        }
        // 输入合法就同步到选中点，并把画布基准也挪过去：
        // 家属改完数字后，方框应该立刻显示新位置，而不是继续停留在旧基准上
        setState(() {
          if (isLng) {
            _lng = value;
          } else {
            _lat = value;
          }
          if (_lng != null && _lat != null) {
            _anchorLng = _lng;
            _anchorLat = _lat;
          }
        });
      },
    );
  }

  void _onTap(Offset position, Size size, double metersPerPixel) {
    // 点击位置相对画布中心在东西/南北方向的米数
    final dxMeters = position.dx - size.width / 2;
    final dyMeters = size.height / 2 - position.dy;
    final anchorLat = _anchorLat!;
    final anchorLng = _anchorLng!;

    // 纬度方向 1 度 ≈ 110540 米；经度方向随纬度收缩，必须乘 cos(lat)
    final newLat = anchorLat + dyMeters / 110540.0;
    final newLng = anchorLng +
        dxMeters / (111320.0 * math.cos(anchorLat * math.pi / 180.0));

    // 夹到合法范围，避免点在边角时算出越界坐标
    final clampedLng = newLng.clamp(-180.0, 180.0);
    final clampedLat = newLat.clamp(-90.0, 90.0);

    setState(() {
      _lng = clampedLng;
      _lat = clampedLat;
    });
    _lngCtrl.text = clampedLng.toStringAsFixed(6);
    _latCtrl.text = clampedLat.toStringAsFixed(6);
  }

  void _useDeviceLocation() {
    setState(() {
      _lng = widget.deviceLng;
      _lat = widget.deviceLat;
      _anchorLng = widget.deviceLng;
      _anchorLat = widget.deviceLat;
    });
    _lngCtrl.text = widget.deviceLng!.toStringAsFixed(6);
    _latCtrl.text = widget.deviceLat!.toStringAsFixed(6);
  }

  String _distanceText() {
    if (!_hasValue) {
      return '请先填写经纬度（或有手杖定位后点「使用手杖当前位置」）';
    }
    if (!_hasDevice) {
      return '已选：${_lng!.toStringAsFixed(6)}, ${_lat!.toStringAsFixed(6)}';
    }
    final meters = _distanceMeters(_lng!, _lat!, widget.deviceLng!, widget.deviceLat!);
    return '距手杖当前位置约 ${meters.round()} 米';
  }

  static double _distanceMeters(double lng1, double lat1, double lng2, double lat2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }
}

/// 画布绘制：等距网格 + 基准点 + 选中点。
///
/// 网格间距固定为视野的 1/8，标注实际米数，家属能据此判断"大概几百米"。
class _PickerPainter extends CustomPainter {
  _PickerPainter({
    required this.anchorLng,
    required this.anchorLat,
    required this.selectedLng,
    required this.selectedLat,
    required this.spanMeters,
    required this.gridColor,
    required this.anchorColor,
    required this.selectedColor,
    required this.textColor,
  });

  final double anchorLng;
  final double anchorLat;
  final double? selectedLng;
  final double? selectedLat;
  final double spanMeters;
  final Color gridColor;
  final Color anchorColor;
  final Color selectedColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final metersPerPixel = spanMeters / math.min(size.width, size.height);
    final stepMeters = spanMeters / 8;
    final stepPx = stepMeters / metersPerPixel;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // 以中心为原点画网格，保证基准点永远落在交叉点上
    for (double x = center.dx; x <= size.width; x += stepPx) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(size.width - x, 0),
          Offset(size.width - x, size.height), gridPaint);
    }
    for (double y = center.dy; y <= size.height; y += stepPx) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      canvas.drawLine(Offset(0, size.height - y),
          Offset(size.width, size.height - y), gridPaint);
    }

    // 中心十字（基准点）
    final crossPaint = Paint()
      ..color = anchorColor
      ..strokeWidth = 2;
    canvas.drawCircle(center, 5, Paint()..color = anchorColor);
    canvas.drawLine(Offset(center.dx - 12, center.dy),
        Offset(center.dx + 12, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy - 12),
        Offset(center.dx, center.dy + 12), crossPaint);

    _label(canvas, '基准', Offset(center.dx + 10, center.dy + 6), anchorColor);
    _label(
      canvas,
      '${stepMeters.round()}m / 格',
      const Offset(8, 6),
      textColor,
    );

    // 选中点
    final lng = selectedLng;
    final lat = selectedLat;
    if (lng == null || lat == null) {
      return;
    }
    final dxMeters = (lng - anchorLng) * 111320.0 * math.cos(anchorLat * math.pi / 180.0);
    final dyMeters = (lat - anchorLat) * 110540.0;
    final pin = Offset(center.dx + dxMeters / metersPerPixel,
        center.dy - dyMeters / metersPerPixel);

    // 超出画布时把标记贴在边上，并画一条指向线，避免"点了却没反应"的困惑
    final visible = pin.dx >= 0 && pin.dx <= size.width && pin.dy >= 0 && pin.dy <= size.height;
    final clamped = Offset(
      pin.dx.clamp(8.0, size.width - 8),
      pin.dy.clamp(8.0, size.height - 8),
    );

    canvas.drawLine(center, clamped,
        Paint()
          ..color = selectedColor.withValues(alpha: 0.55)
          ..strokeWidth = 2);
    canvas.drawCircle(clamped, 8, Paint()..color = selectedColor);
    canvas.drawCircle(
        clamped, 8, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    if (!visible) {
      _label(canvas, '在视野外', Offset(clamped.dx + 12, clamped.dy - 8), selectedColor);
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_PickerPainter old) {
    return old.anchorLng != anchorLng ||
        old.anchorLat != anchorLat ||
        old.selectedLng != selectedLng ||
        old.selectedLat != selectedLat ||
        old.spanMeters != spanMeters;
  }
}
