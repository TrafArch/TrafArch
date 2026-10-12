import 'package:flutter/material.dart';
import '../../core/analysis/analysis_models.dart';
import '../../core/transit/tunion/tunion_models.dart';
import '../../core/ui_constants.dart';
import '../../state/app_state.dart';
import '../settings/settings_action_button.dart';

class TripsPage extends StatefulWidget {
  final AppState app;
  const TripsPage({super.key, required this.app});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  @override
  void initState() {
    super.initState();
    widget.app.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.app.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final trips = widget.app.analysis?.trips ?? const <TransitTrip>[];
    // 0x1A 记录 1 / 记录 2（城市轨道 / 公共汽电车应用信息记录）：解析完成时
    // 在列表顶部加入进出站 / 上下车卡片（最近一次乘车过程信息），样式与
    // 行程卡保持一致；卡片同时存在对应行业（应用分类码匹配）的 0x1E
    // 记录时以 0x1E 为准（AppState.railTransitRecord / busTransitRecord
    // 返回 null），不产出对应卡片。
    final railRecord = widget.app.railTransitRecord;
    final busRecord = widget.app.busTransitRecord;
    final cardCount =
        (railRecord == null ? 0 : 1) + (busRecord == null ? 0 : 1);
    return SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('行程'),
            actions: [SettingsActionButton(app: widget.app)],
          ),
          if (trips.isEmpty && cardCount == 0)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(
                  bottom: UiConstants.floatingNavBarClearance,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.route,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无行程记录',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '刷卡后自动解析生成',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                12,
                0,
                12,
                UiConstants.floatingNavBarClearance,
              ),
              sliver: SliverList.builder(
                itemCount: trips.length + cardCount,
                itemBuilder: (context, i) {
                  var index = i;
                  if (railRecord != null) {
                    if (index == 0) {
                      return _RailRecordCard(
                        record: railRecord,
                        app: widget.app,
                      );
                    }
                    index -= 1;
                  }
                  if (busRecord != null) {
                    if (index == 0) {
                      return _BusRecordCard(record: busRecord, app: widget.app);
                    }
                    index -= 1;
                  }
                  return _TripCard(trip: trips[index]);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  final TransitTrip trip;
  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 0 元交易与进站记录（0x1E 入站类记录或 0x1A 记录 1/2 进站信息）
    // 配对命中（trip.isEntry）时按进站展示："时间"改显"进站时间"，
    // 站点/线路取自配对数据（未收录时保持隐藏，不猜测）。
    final isEntry = trip.isEntry && trip.amountFen == 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.typeName} · 序号 ${trip.sequence}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  trip.amountText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: trip.isConsume
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _kv(context, isEntry ? '进站时间' : '时间', trip.timeText),
            if (trip.cityName != null) _kv(context, '城市', trip.cityName!),
            if (trip.lineLabel != null) _kv(context, '线路', trip.lineLabel!),
            if (trip.stationLabel != null)
              _kv(context, '站点', trip.stationLabel!),
            if (trip.stationType != null)
              _kv(context, '类型', trip.stationType!),
            if (trip.appTypeName != null)
              _kv(context, '行业', trip.appTypeName!),
            if (trip.balanceAfterText != null)
              _kv(context, '交易后余额', trip.balanceAfterText!),
            // 仅消费类交易提示终端未匹配：充值等非消费交易无线路/站点属正常。
            if (trip.isConsume && !trip.hasLocation)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '未匹配终端解码规则（终端 ${trip.terminalId}），'
                  '线路/站点待 assets/data/terminal_rules.json 补充',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 键值行（行程卡与 0x1A 进出站卡片共用）：label 定宽 + 值自动换行。
Widget _kv(BuildContext context, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(k, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );

/// 0x1A 记录 1（城市轨道应用信息记录）进出站卡片：展示解析完成的状态、
/// 进/出站时间、出闸城市、出闸站点与进/出站钱包余额，样式与行程卡一致；
/// 金额口径为分，展示层 ÷100 后为元。
class _RailRecordCard extends StatelessWidget {
  final TransitRecord record;
  final AppState app;

  const _RailRecordCard({required this.record, required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entryBalance = record.entryBalanceFen;
    final exitAmount = record.exitAmountFen;
    // 出站钱包余额：0x1A 格式未独立存储，按“进站钱包余额 − 出闸交易金额”
    // 推算（与 0x1E 交易后余额口径一致）；已出站且两项均解析成功时展示。
    final exitBalance =
        record.exitTime != null && entryBalance != null && exitAmount != null
            ? entryBalance - exitAmount
            : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '城市轨道交通 · 进出站记录',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _kv(context, '状态', record.statusName),
            if (record.entryTime != null)
              _kv(context, '进站时间', _timeText(record.entryTime!)),
            if (record.exitTime != null)
              _kv(context, '出站时间', _timeText(record.exitTime!)),
            if (record.exitCityCode != null)
              _kv(context, '出闸城市', _cityText(app, record.exitCityCode!)),
            if (record.exitStationId != null)
              _kv(context, '出闸站点', record.exitStationId!),
            if (entryBalance != null)
              _kv(context, '进站钱包余额', _fenText(entryBalance)),
            if (exitBalance != null)
              _kv(context, '出站钱包余额', _fenText(exitBalance)),
          ],
        ),
      ),
    );
  }
}

/// 0x1A 记录 2（公共汽电车应用信息记录）上下车卡片：展示解析完成的状态、
/// 上/下车时间、下车城市、下车站点、方向、交易金额与乘车里程，样式与行程卡
/// 一致；金额口径为分，展示层 ÷100 后为元。
class _BusRecordCard extends StatelessWidget {
  final BusTransitRecord record;
  final AppState app;

  const _BusRecordCard({required this.record, required this.app});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '公共汽电车 · 上下车记录',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _kv(context, '状态', record.statusName),
            if (record.entryTime != null)
              _kv(context, '上车时间', _timeText(record.entryTime!)),
            if (record.exitTime != null)
              _kv(context, '下车时间', _timeText(record.exitTime!)),
            if (record.exitCityCode != null)
              _kv(context, '下车城市', _cityText(app, record.exitCityCode!)),
            if (record.exitStationCode != null)
              _kv(context, '下车站点', record.exitStationCode!),
            _kv(context, '方向', record.directionName),
            if (record.transactionAmountFen != null)
              _kv(context, '交易金额', _fenText(record.transactionAmountFen!)),
            if (record.mileage != null)
              _kv(context, '乘车里程', record.mileage!.toString()),
          ],
        ),
      ),
    );
  }
}

/// 元金额文本（分 ÷100），0x1A 卡片共用。
String _fenText(int fen) => '¥${(fen / 100).toStringAsFixed(2)}';

/// 城市代码查询知识库城市名；未收录时回退展示原始代码。
String _cityText(AppState app, String code) => app.cityNameOf(code) ?? code;

/// `yyyy-MM-dd HH:mm:ss` 时间文本，0x1A 卡片共用。
String _timeText(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} '
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String _two(int v) => v.toString().padLeft(2, '0');
