import 'package:flutter/material.dart';

/// 悬浮底栏滚动显隐过滤器。
///
/// - 普通页面（首页/行程页）的直接滚动通知 depth 为 0，总是放行；
/// - 专家页为 NestedScrollView：正文 ListView 经 TabBarView 的 PageView 与
///   外层两个视口，通知 depth ≥ 1，同样放行以驱动长滑动时的隐藏/回显，
///   但有两类通知需拦截：
///   1) 正文的 ScrollStart：正文停在顶部（pixels == minScrollExtent）时会
///      命中 showAtStart 的强制回显，与"收起标题栏时隐藏底栏"的动作相悖；
///   2) 外层的 ScrollEnd：fling 起手瞬间外层会先结算出一条"伪结束"通知
///      （此时正文仍在惯性滚动），放行会让底栏提前回显，故正文未停时忽略。
bool bottomBarScrollPredicate(ScrollNotification notification) {
  if (notification.depth > 0) {
    return notification is! ScrollStartNotification;
  }
  if (notification is ScrollEndNotification) {
    final nested = notification.context
        ?.findAncestorStateOfType<NestedScrollViewState>();
    if (nested != null &&
        nested.innerController.positions.any(
          (position) => position.isScrollingNotifier.value,
        )) {
      return false;
    }
  }
  return true;
}
