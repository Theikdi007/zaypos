// QA round 14 — TC-UX-NEW-11: dead-control sweep on the iOS simulator (round-13 TC-UX-NEW-10 approach, applied to every
// tappable the app shows). Runs the real app UI (ZayPosApp, real router, real screens) on the in-memory fake repositories
// with the design's sample data, so destructive taps (void, delete, sign out) cannot touch shop A's real data; every tap that
// changed something is followed by a fresh app (fresh seed) so the next tap starts from the same state.
//
// A "tappable" is every GestureDetector with an onTap (InkWell / buttons / chips / tiles / switches build one) whose centre
// the hit test actually reaches (covered or off-screen controls are not counted until scrolled into view). The main
// vertical list is scrolled to the end in 70 % steps so controls below the fold are found too.
// A tap "reacts" when, 1.2 s (real time) after it, any of these changed: the route, the semantics tree (labels, values,
// hints, checked / selected / toggled / focused / expanded / enabled — i.e. what is on screen and what VoiceOver reads),
// the number of routes / dialogs / sheets / snackbars, or the recorded platform actions (share, Photos, dialer, photo picker,
// camera scanner: replaced by recorders here; the real plugins are checked in r14_debt_actions_test / r14_bug45_voided_test).
// Any tap that opens a dialog or bottom sheet is followed one level deeper: every tappable inside it is tapped the same way.
//
// QA_PHASE = comma list of screen names (or "all"). Output: one `QA_NOTE:SWEEP|screen|level|id|result|detail` per tap and a
// final `QA_NOTE:SWEEP_DEAD …` list. The test fails if any control is NOTHING (except the screen background).
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:async' show unawaited;
import 'dart:ui' show CheckedState, Tristate;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zaypos_app/app/fake_overrides.dart';
import 'package:zaypos_app/app/fake_seed.dart';
import 'package:zaypos_app/core/db/app_database.dart';
import 'package:zaypos_app/core/db/database_provider.dart';
import 'package:zaypos_app/core/router/app_router.dart';
import 'package:zaypos_app/core/router/routes.dart';
import 'package:zaypos_app/core/storage/secure_store.dart';
import 'package:zaypos_app/core/utils/ids.dart';
import 'package:zaypos_app/core/widgets/app_icons.dart';
import 'package:zaypos_app/core/widgets/common.dart';
import 'package:zaypos_app/features/auth/data/boot_state.dart';
import 'package:zaypos_app/features/customers/application/customer_service.dart';
import 'package:zaypos_app/features/customers/data/customer_providers.dart';
import 'package:zaypos_app/features/customers/presentation/debt_actions.dart';
import 'package:zaypos_app/features/pos/domain/cart.dart';
import 'package:zaypos_app/features/products/data/product_photos.dart';
import 'package:zaypos_app/features/products/data/product_providers.dart';
import 'package:zaypos_app/features/sales/presentation/receipt_image.dart';
import 'package:zaypos_app/features/scan/barcode_scanner.dart';
import 'package:zaypos_app/main.dart';

import 'qa_harness.dart';

const phase = String.fromEnvironment('QA_PHASE', defaultValue: 'all');

final platformEvents = <String>[];

class _RecReceipt implements ReceiptOutlet {
  @override
  Future<void> share(Uint8List png, String fileName, {Rect? origin}) async => platformEvents.add('receipt.share $fileName');
  @override
  Future<ReceiptSaveResult> saveToPhotos(Uint8List png, String name) async {
    platformEvents.add('receipt.save $name');
    return ReceiptSaveResult.saved;
  }
}

class _RecDebt implements DebtOutlet {
  @override
  Future<bool> call(Uri uri) async {
    platformEvents.add('debt.call $uri');
    return true;
  }

  @override
  Future<void> shareText(String text, {Rect? origin}) async => platformEvents.add('debt.share ${text.length} chars');
}

class _RecPicker implements PhotoPicker {
  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    platformEvents.add('photo.pick $source');
    return null; // cancelled
  }
}

class _RecScanner implements BarcodeScanner {
  @override
  Future<String?> scan(BuildContext context, {String title = ''}) async {
    platformEvents.add('scanner.open "$title"');
    return null; // closed without a code
  }
}

enum _Auth { unlocked, signedOut }

class _Screen {
  const _Screen(this.name, this.route, {this.auth = _Auth.unlocked, this.setup});
  final String name;
  final String route;
  final _Auth auth;
  final Future<void> Function(WidgetTester tester, ProviderContainer c)? setup;
}

Future<void> _addToCart(WidgetTester tester, ProviderContainer c) async {
  final list = c.read(productsProvider).value ?? const [];
  c.read(cartProvider.notifier).addProduct(list.firstWhere((p) => p.product.price > 0).product);
  await settle(tester);
}

Future<void> _tapIfThere(WidgetTester tester, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) return;
  await tester.ensureVisible(f.first);
  await settle(tester);
  await tester.tap(f.first, warnIfMissed: false);
  await settle(tester, max: const Duration(seconds: 2));
}

final screens = <_Screen>[
  _Screen('dashboard', Routes.dashboard),
  _Screen('pos_quick', Routes.pos),
  _Screen('pos_products', Routes.pos, setup: (t, c) => _tapIfThere(t, 'ပစ္စည်းများ')),
  _Screen('pos_cart', Routes.pos, setup: (t, c) async {
    await _tapIfThere(t, 'ပစ္စည်းများ');
    await _addToCart(t, c);
  }),
  // Checkout is pushed from POS (dashboard → POS → checkout), as in the app, so its back button has POS behind it.
  _Screen('checkout_cash', Routes.pos, setup: (t, c) async {
    await _addToCart(t, c);
    unawaited(c.read(appRouterProvider).push(Routes.checkout));
    await settle(t);
  }),
  for (final m in ['KBZPay', 'WavePay', 'အကြွေး'])
    _Screen('checkout_$m', Routes.pos, setup: (t, c) async {
      await _addToCart(t, c);
      unawaited(c.read(appRouterProvider).push(Routes.checkout));
      await settle(t);
      await _tapIfThere(t, m);
    }),
  _Screen('sales', Routes.sales),
  _Screen('sale_detail', Routes.sale(SeedIds.sale1032)),
  _Screen('sale_detail_voided', Routes.sale(SeedIds.sale1031), setup: (t, c) => _tapIfThere(t, 'ပယ်ဖျက်မယ်')),
  _Screen('receipt', Routes.receipt(SeedIds.sale1032)),
  _Screen('reports', Routes.reports),
  _Screen('products', Routes.products),
  _Screen('products_noprice', Routes.productsNeedingPrice),
  _Screen('products_low', Routes.productsLowStock),
  _Screen('add_product', Routes.addProduct),
  _Screen('edit_product', Routes.editProduct(SeedIds.rice)),
  _Screen('customers', Routes.customers),
  _Screen('add_customer', Routes.addCustomer),
  _Screen('debtor', Routes.customer(SeedIds.zawMin)),
  _Screen('debtor_nophone', Routes.customer(SeedIds.zawMin), setup: (t, c) async {
    await t.runAsync(() async {
      final zaw = (c.read(customersProvider).value ?? const []).firstWhere((x) => x.id == SeedIds.zawMin);
      await c.read(customerServiceProvider).update(zaw.copyWith(phone: ''));
    });
    await settle(t);
  }),
  _Screen('edit_customer', Routes.editCustomer(SeedIds.zawMin)),
  _Screen('settings', Routes.settingsFeatures),
  _Screen('sync_review', Routes.syncReview),
  _Screen('devices', Routes.devices),
  _Screen('register_template', Routes.register),
  _Screen('login', Routes.login, auth: _Auth.signedOut),
  _Screen('register', Routes.register, auth: _Auth.signedOut),
  _Screen('pin_reset', Routes.pinReset, auth: _Auth.signedOut),
];

class _Cand {
  _Cand(this.id, this.ro, this.rect);
  final String id;
  final RenderBox ro;
  final Rect rect;
}

void main() {
  qaBinding();

  testWidgets('TC-UX-NEW-11 every reachable tappable reacts (sweep: $phase)', timeout: Timeout.none, (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final sem = tester.ensureSemantics();
    final view = tester.view;
    final screenRect = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final errors = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
    addTearDown(() => FlutterError.onError = old);

    ProviderContainer? current;
    AppDatabase? currentDb;
    Future<ProviderContainer> boot(_Screen s) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      current?.dispose();
      await currentDb?.close();
      final db = AppDatabase(NativeDatabase.memory());
      final c = ProviderContainer(overrides: [
        ...fakeOverrides(
            boot: s.auth == _Auth.unlocked ? null : BootState(deviceId: newId())),
        appDatabaseProvider.overrideWithValue(db),
        secureStoreProvider.overrideWithValue(MemorySecureStore()),
        receiptOutletProvider.overrideWithValue(_RecReceipt()),
        debtOutletProvider.overrideWithValue(_RecDebt()),
        photoPickerProvider.overrideWithValue(_RecPicker()),
        barcodeScannerProvider.overrideWithValue(_RecScanner()),
      ]);
      current = c;
      currentDb = db;
      c.listen(productsProvider, (_, _) {});
      c.listen(customersProvider, (_, _) {});
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const ZayPosApp()));
      await settle(tester);
      final r = c.read(appRouterProvider);
      const tabRoots = {Routes.dashboard, Routes.products, Routes.customers, Routes.reports, Routes.login};
      if (tabRoots.contains(s.route) || s.route.startsWith('${Routes.products}?') || s.auth != _Auth.unlocked) {
        r.go(s.route);
      } else {
        // The app pushes these screens (context.push), so the back button has a page to return to.
        unawaited(r.push(s.route));
      }
      await settle(tester);
      if (s.setup != null) await s.setup!(tester, c);
      await wait(tester, const Duration(milliseconds: 400));
      return c;
    }

    String loc(ProviderContainer c) => c.read(appRouterProvider).routerDelegate.currentConfiguration.uri.toString();

    String sig(ProviderContainer c) {
      final b = StringBuffer('route=${loc(c)}\nbarriers=${find.byType(ModalBarrier).evaluate().length}\n'
          'snack=${find.byType(SnackBar).evaluate().length}\nplatform=${platformEvents.length}\n');
      final root = tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
      void dump(SemanticsNode n) {
        final d = n.getSemanticsData();
        final f = d.flagsCollection;
        if (d.label.isNotEmpty || d.value.isNotEmpty || d.hint.isNotEmpty) {
          b.writeln('${d.label}|${d.value}|${d.hint}|${f.isChecked.name}${f.isSelected.name}${f.isToggled.name}'
              '${f.isFocused.name}${f.isExpanded.name}${f.isEnabled.name}');
        }
        n.visitChildren((ch) {
          dump(ch);
          return true;
        });
      }

      if (root != null) dump(root);
      return b.toString();
    }

    bool hits(RenderBox ro, Offset p) {
      if (!screenRect.deflate(1).contains(p)) return false;
      final r = HitTestResult();
      tester.binding.hitTestInView(r, p, view.viewId);
      return r.path.any((e) => e.target == ro);
    }

    /// The control is a tab / segment / chip that is already the selected one (tapping it again changes nothing by design).
    bool isSelected(RenderObject ro) {
      RenderObject? r = ro;
      for (var i = 0; i < 8 && r != null; i++) {
        final n = r.debugSemantics;
        if (n != null) {
          final f = n.getSemanticsData().flagsCollection;
          if (f.isSelected == Tristate.isTrue || f.isChecked == CheckedState.isTrue || f.isToggled == Tristate.isTrue) {
            return true;
          }
        }
        r = r.parent;
      }
      return false;
    }

    String describe(Element e) {
      final parts = <String>[];
      void collect(Element x, bool underText) {
        final w = x.widget;
        var under = underText;
        if (w is Text) {
          parts.add(w.data ?? w.textSpan?.toPlainText() ?? '');
          under = true;
        } else if (w is RichText && !underText) {
          parts.add(w.text.toPlainText());
        } else if (w is EditableText) {
          parts.add('[field "${w.controller.text}"]');
        } else if (w is AppInput && w.semanticLabel != null) {
          parts.add('[input ${w.semanticLabel}]');
        } else if (w is Semantics && (w.properties.label ?? '').isNotEmpty) {
          parts.add('{${w.properties.label}}');
        } else if (w is AppIcon && (w.semanticLabel ?? '').isNotEmpty) {
          parts.add('<${w.semanticLabel}>');
        }
        x.visitChildElements((ch) => collect(ch, under));
      }

      collect(e, false);
      if (parts.where((p) => p.trim().isNotEmpty).isEmpty) {
        var n = 0;
        e.visitAncestorElements((a) {
          final w = a.widget;
          if (w is Semantics && (w.properties.label ?? '').isNotEmpty) parts.add('{${w.properties.label}}');
          if (w is Tooltip && (w.message ?? '').isNotEmpty) parts.add('(tip ${w.message})');
          if (w is AppIconButton) parts.add('{${w.semanticLabel}}');
          return parts.isEmpty && ++n < 8;
        });
      }
      final s = parts.where((p) => p.trim().isNotEmpty).join(' ').replaceAll('\n', ' ');
      return s.length > 90 ? s.substring(0, 90) : s;
    }

    List<_Cand> enumerate() {
      final byRect = <Rect, _Cand>{};
      void visit(Element e) {
        final w = e.widget;
        if (w is ModalBarrier) return; // its detector is "tap outside"
        if (w is Offstage && w.offstage) return;
        if (w is TickerMode && !w.enabled) return;
        if (w is GestureDetector && w.onTap != null) {
          final ro = e.findRenderObject();
          if (ro is RenderBox && ro.attached && ro.hasSize && ro.size.width > 1 && ro.size.height > 1) {
            final rect = ro.localToGlobal(Offset.zero) & ro.size;
            final vis = rect.intersect(screenRect);
            if (!vis.isEmpty && hits(ro, vis.center)) {
              var id = describe(e);
              if (id.isEmpty) id = 'unlabelled@${rect.left.round()},${rect.top.round()} ${rect.width.round()}x${rect.height.round()}';
              byRect[rect] = _Cand(id, ro, vis); // nested detector with the same box: the inner one wins
            }
          }
        }
        e.visitChildElements(visit);
      }

      tester.binding.rootElement!.visitChildElements(visit);
      final seen = <String>{};
      return [
        for (final c in byRect.values)
          if (seen.add(c.id)) c,
      ];
    }

    ScrollableState? mainScrollable() {
      ScrollableState? best;
      double area = 0;
      for (final s in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
        if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
        final ro = s.context.findRenderObject();
        if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
        final r = (ro.localToGlobal(Offset.zero) & ro.size).intersect(screenRect);
        if (r.isEmpty) continue;
        if (r.width * r.height > area) {
          area = r.width * r.height;
          best = s;
        }
      }
      return best;
    }

    Future<void> scrollTo(double px) async {
      final s = mainScrollable();
      if (s == null || px == 0) return;
      s.position.jumpTo(px.clamp(0, s.position.maxScrollExtent));
      await settle(tester, max: const Duration(seconds: 1));
    }

    /// Screen-reader audit: nodes announced as an enabled button that have no tap action (VoiceOver / TalkBack
    /// "activate" has nothing to call).
    final semaDead = <String>{};
    void semaAudit(String screen) {
      final root = tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
      void visit(SemanticsNode n) {
        final d = n.getSemanticsData();
        final f = d.flagsCollection;
        if (f.isButton && f.isEnabled != Tristate.isFalse && !d.hasAction(SemanticsAction.tap) && !n.isInvisible) {
          final key = '$screen › ${d.label.replaceAll('\n', ' ')}';
          if (semaDead.add(key)) note('SEMA|$screen|${d.label.replaceAll('\n', ' ')}|button without tap action');
        }
        n.visitChildren((ch) {
          visit(ch);
          return true;
        });
      }

      if (root != null) visit(root);
    }

    /// (id, scroll offset) of every tappable on the current screen.
    Future<List<(String, double)>> collectAll(String screen) async {
      final out = <(String, double)>[];
      final ids = <String>{};
      double px = 0;
      for (var step = 0; step < 25; step++) {
        semaAudit(screen);
        for (final c in enumerate()) {
          if (ids.add(c.id)) out.add((c.id, px));
        }
        final s = mainScrollable();
        if (s == null || s.position.pixels >= s.position.maxScrollExtent - 1) break;
        px = (s.position.pixels + s.position.viewportDimension * 0.7).clamp(0, s.position.maxScrollExtent);
        s.position.jumpTo(px);
        await settle(tester, max: const Duration(seconds: 1));
        px = s.position.pixels;
      }
      return out;
    }

    final dead = <String>[];
    final lost = <String>[];
    var taps = 0;

    /// Taps [id] (must be on screen now) and reports whether anything changed.
    Future<(bool, bool)> tapOne(ProviderContainer c, String screen, String level, String id) async {
      final cand = enumerate().where((x) => x.id == id).firstOrNull;
      if (cand == null) {
        note('SWEEP|$screen|$level|$id|LOST|not on screen when replayed');
        lost.add('$screen › $id');
        return (false, false);
      }
      final selected0 = isSelected(cand.ro);
      final s0 = sig(c);
      await wait(tester, const Duration(milliseconds: 250));
      final s0b = sig(c);
      final unstable = s0 != s0b;
      final barriers0 = find.byType(ModalBarrier).evaluate().length;
      final loc0 = loc(c);
      final p0 = platformEvents.length;
      final e0 = errors.length;
      await tester.tapAt(cand.rect.center);
      taps++;
      await wait(tester, const Duration(milliseconds: 1200));
      final s1 = sig(c);
      final changed = s1 != s0b;
      final opened = find.byType(ModalBarrier).evaluate().length > barriers0 && loc(c) == loc0;
      final a = s0b.split('\n').toSet(), z = s1.split('\n').toSet();
      final added = z.difference(a).take(3).join(' ⏎ ');
      final removed = a.difference(z).take(2).join(' ⏎ ');
      final detail = [
        if (loc(c) != loc0) 'route $loc0 → ${loc(c)}',
        if (opened) 'opened dialog/sheet',
        if (platformEvents.length > p0) 'platform: ${platformEvents.sublist(p0).join('; ')}',
        if (changed && added.isNotEmpty) '+[$added]',
        if (changed && removed.isNotEmpty) '−[$removed]',
        if (unstable) '(screen was changing by itself)',
        if (errors.length > e0) 'ERRORS: ${errors.sublist(e0).toSet().join(' / ')}',
      ].join(' ; ');
      final bg = cand.rect.width * cand.rect.height > screenRect.width * screenRect.height * 0.5;
      final result = changed
          ? 'reacts'
          : bg
              ? 'NOTHING-background'
              : selected0
                  ? 'NOTHING-already-selected'
                  : 'NOTHING';
      note('SWEEP|$screen|$level|$id|$result|${cand.rect.left.round()},${cand.rect.top.round()} '
          '${cand.rect.width.round()}x${cand.rect.height.round()}|$detail');
      if (!changed && !bg && !selected0) {
        dead.add('$screen › $level › $id');
        await shot(tester, 'r14_sweep_DEAD_${screen}_$taps');
      }
      return (changed, opened);
    }

    final selected = phase == 'all' ? screens : screens.where((s) => phase.split(',').contains(s.name)).toList();
    expect(selected, isNotEmpty, reason: 'QA_PHASE names no screen');
    for (final s in selected) {
      var c = await boot(s);
      note('SCREEN ${s.name} at ${loc(c)}');
      await shot(tester, 'r14_sweep_screen_${s.name}');
      final all = await collectAll(s.name);
      note('SCREEN ${s.name}: ${all.length} tappables: ${all.map((e) => e.$1).join(' | ')}');
      var dirty = true;
      for (final (id, px) in all) {
        if (dirty) {
          c = await boot(s);
          dirty = false;
        }
        await scrollTo(px);
        final (changed, opened) = await tapOne(c, s.name, 'L1', id);
        if (changed) dirty = true;
        if (!opened) continue;
        // One level deeper: every tappable inside the dialog / sheet.
        semaAudit('${s.name} › $id');
        final inner = enumerate().map((x) => x.id).toList();
        note('SWEEP|${s.name}|L2-open|$id|${inner.length} tappables inside: ${inner.join(' | ')}');
        var innerDirty = false;
        for (final j in inner) {
          if (innerDirty) {
            c = await boot(s);
            await scrollTo(px);
            final (ch, op) = await tapOne(c, s.name, 'L1-replay', id);
            if (!ch || !op) {
              note('SWEEP|${s.name}|L2|$j|LOST|could not reopen "$id"');
              lost.add('${s.name} › $id › $j');
              continue;
            }
          }
          final (ch2, _) = await tapOne(c, '${s.name} › $id', 'L2', j);
          innerDirty = ch2;
        }
        dirty = true;
      }
    }

    note('SWEEP_DONE taps=$taps dead=${dead.length} lost=${lost.length}');
    note('SWEEP_DEAD ${dead.isEmpty ? 'none' : dead.join(' || ')}');
    note('SWEEP_LOST ${lost.isEmpty ? 'none' : lost.join(' || ')}');
    note('SEMA_DEAD ${semaDead.length}: ${semaDead.join(' || ')}');
    note('SWEEP_ERRORS ${errors.isEmpty ? 'none' : errors.toSet().join(' / ')}');
    await tester.pumpWidget(const SizedBox());
    current?.dispose();
    await currentDb?.close();
    sem.dispose();
    FlutterError.onError = old;
    expect(dead, isEmpty, reason: 'controls that do nothing: $dead');
  });
}
