import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/utils/myanmar.dart';
import '../../../core/utils/qty.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/money_text.dart';
import '../../auth/data/session.dart';
import '../domain/sale.dart';

/// Width of the receipt image in logical pixels (BUG-40). It is the same on
/// every phone and at every system text size, so a shared receipt looks the same.
const double receiptImageWidth = 360;

/// Pixels per logical pixel in the PNG (360 × 3 = 1080 px wide).
const double receiptImagePixelRatio = 3;

const receiptShareText = 'ပြေစာ ပို့မယ်';
const receiptSaveText = 'ပုံ သိမ်းမယ်';
const receiptSavedText = 'သိမ်းပြီးပါပြီ';
const receiptSaveDeniedText = 'ဓာတ်ပုံထဲ သိမ်းခွင့် မရပါ။ ဖုန်းရဲ့ ဆက်တင်ထဲက ZayPOS → ဓာတ်ပုံများ မှာ ခွင့်ပြုပေးပါ။';
const receiptSaveFailedText = 'ပုံ သိမ်းလို့ မရပါ။ ထပ်ကြိုးစားပါ။';
const receiptShareFailedText = 'ပြေစာ ပို့လို့ မရပါ။ ထပ်ကြိုးစားပါ။';

/// The receipt card: dashed border, shop, lines, total, cash and change.
/// The receipt screen shows it, and [renderReceiptPng] draws it into the image.
class ReceiptCard extends StatelessWidget {
  const ReceiptCard({super.key, required this.sale, required this.shop});

  final Sale sale;
  final String shop;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      color: AppColors.inputBorder,
      strokeWidth: 1,
      radius: 18,
      background: AppColors.surface,
      padding: const EdgeInsets.all(20),
      child: _ReceiptBody(sale: sale, shop: shop, date: mmReceiptDate(sale.createdAt)),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.sale, required this.shop, required this.date});

  final Sale sale;
  final String shop;
  final String date;

  @override
  Widget build(BuildContext context) {
    Widget divider() => Container(height: 1, color: AppColors.border);
    Widget gap() => const SizedBox(height: 10);
    Widget small(String l, String r) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l, style: AppText.s(13, color: AppColors.textSecondary)),
        Text(r, style: AppText.s(13, color: AppColors.textSecondary)),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          shop,
          textAlign: TextAlign.center,
          style: AppText.s(16, weight: AppText.w700),
        ),
        Text(
          'ပြေစာ #${sale.no} · $date',
          textAlign: TextAlign.center,
          style: AppText.s(12, color: AppColors.muted),
        ),
        gap(),
        divider(),
        for (final l in sale.lines) ...[
          gap(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('${l.name} × ${Qty.format(l.qtyMilli)}', style: AppText.s(14))),
              const SizedBox(width: 12),
              Text(formatMoney(l.total), style: AppText.s(14, weight: AppText.w600)),
            ],
          ),
        ],
        gap(),
        divider(),
        gap(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('စုစုပေါင်း', style: AppText.s(17, weight: AppText.w700)),
            MoneyText(sale.total, size: 17),
          ],
        ),
        if (sale.method == PaymentMethod.cash && sale.received != null) ...[
          gap(),
          small('ငွေသား လက်ခံ', formatMoney(sale.received!)),
          gap(),
          small('ပြန်အမ်း', formatMoney(sale.change! < 0 ? 0 : sale.change!)),
        ],
        const SizedBox(height: 14),
        Text(
          'ကျေးဇူးတင်ပါတယ်',
          textAlign: TextAlign.center,
          style: AppText.s(12, color: AppColors.muted),
        ),
      ],
    );
  }
}

/// Draws [ReceiptCard] off screen at [receiptImageWidth] on a white background
/// and returns it as PNG bytes. The system text size is ignored (scale 1.0), so
/// the image never overflows or changes with the phone's settings.
Future<Uint8List> renderReceiptPng(
  ui.FlutterView view, {
  required Sale sale,
  required String shop,
  double width = receiptImageWidth,
  double pixelRatio = receiptImagePixelRatio,
}) async {
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.topCenter, child: boundary),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tightFor(width: width, height: 20000),
      physicalConstraints: BoxConstraints.tightFor(width: width * pixelRatio, height: 20000 * pixelRatio),
      devicePixelRatio: pixelRatio,
    ),
  );
  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();

  final buildOwner = BuildOwner(focusManager: FocusManager());
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.noScaling),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: width,
          child: ColoredBox(
            color: AppColors.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ReceiptCard(sale: sale, shop: shop),
            ),
          ),
        ),
      ),
    ),
  ).attachToRenderTree(buildOwner);
  try {
    buildOwner
      ..buildScope(root)
      ..finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    // Unmount the off-screen tree.
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary).attachToRenderTree(buildOwner, root);
    buildOwner.finalizeTree();
  }
}

enum ReceiptSaveResult { saved, denied, failed }

/// Where the receipt image goes: the share sheet and Photos. Tests replace it.
abstract class ReceiptOutlet {
  /// Opens the system share sheet with the PNG (Viber is one of the targets).
  Future<void> share(Uint8List png, String fileName, {Rect? origin});

  /// Saves the PNG to Photos, asking for permission first if needed.
  Future<ReceiptSaveResult> saveToPhotos(Uint8List png, String name);
}

class PlatformReceiptOutlet implements ReceiptOutlet {
  const PlatformReceiptOutlet();

  @override
  Future<void> share(Uint8List png, String fileName, {Rect? origin}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png', name: fileName)],
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Future<ReceiptSaveResult> saveToPhotos(Uint8List png, String name) async {
    try {
      if (!await Gal.hasPermission() && !await Gal.requestPermission()) return ReceiptSaveResult.denied;
      await Gal.putImageBytes(png, name: name);
      return ReceiptSaveResult.saved;
    } on GalException catch (e) {
      return e.type == GalExceptionType.permissionDenied ? ReceiptSaveResult.denied : ReceiptSaveResult.failed;
    } catch (_) {
      return ReceiptSaveResult.failed;
    }
  }
}

final receiptOutletProvider = Provider<ReceiptOutlet>((_) => const PlatformReceiptOutlet());

/// Renders the receipt of [sale] off screen (so it works from the sale screen,
/// which does not show the receipt).
typedef ReceiptRenderer = Future<Uint8List> Function(ui.FlutterView view, Sale sale, String shop);

final receiptRendererProvider = Provider<ReceiptRenderer>(
  (_) =>
      (view, sale, shop) => renderReceiptPng(view, sale: sale, shop: shop),
);

String receiptFileName(Sale sale) => 'ZayPOS-receipt-${sale.no}.png';

Rect? _originOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
}

/// "ပြေစာ ပို့မယ်": the share sheet with the receipt PNG.
Future<void> shareReceipt(BuildContext context, WidgetRef ref, Sale sale) async {
  final shop = ref.read(sessionProvider).shopName;
  final outlet = ref.read(receiptOutletProvider);
  final render = ref.read(receiptRendererProvider);
  final origin = _originOf(context);
  try {
    final png = await render(View.of(context), sale, shop);
    await outlet.share(png, receiptFileName(sale), origin: origin);
  } catch (_) {
    if (context.mounted) _snack(context, receiptShareFailedText);
  }
}

/// "ပုံ သိမ်းမယ်": the receipt PNG into Photos, with a Burmese message.
Future<void> saveReceipt(BuildContext context, WidgetRef ref, Sale sale) async {
  final shop = ref.read(sessionProvider).shopName;
  final outlet = ref.read(receiptOutletProvider);
  final render = ref.read(receiptRendererProvider);
  ReceiptSaveResult result;
  try {
    final png = await render(View.of(context), sale, shop);
    result = await outlet.saveToPhotos(png, 'ZayPOS-receipt-${sale.no}');
  } catch (_) {
    result = ReceiptSaveResult.failed;
  }
  if (!context.mounted) return;
  _snack(context, switch (result) {
    ReceiptSaveResult.saved => receiptSavedText,
    ReceiptSaveResult.denied => receiptSaveDeniedText,
    ReceiptSaveResult.failed => receiptSaveFailedText,
  });
}
