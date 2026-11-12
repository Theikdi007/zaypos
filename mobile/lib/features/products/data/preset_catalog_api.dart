import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../auth/application/auth_controller.dart';

/// One starter item of a shop template (`GET /api/v1/catalog/presets`).
class PresetItem {
  const PresetItem({
    required this.name,
    required this.category,
    required this.unit,
    this.barcode,
    this.suggestedPrice,
    this.sortOrder = 0,
  });

  final String name;
  final String category;
  final String unit;
  final String? barcode;

  /// Kyats; informative only — imported products start without prices.
  final int? suggestedPrice;
  final int sortOrder;

  factory PresetItem.fromJson(Map<String, dynamic> j) => PresetItem(
        name: j['name'] as String,
        category: j['category'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        barcode: j['barcode'] as String?,
        suggestedPrice: (j['suggestedPrice'] as num?)?.toInt(),
        sortOrder: (j['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

abstract interface class PresetCatalogApi {
  /// The template's starter catalog, in display order. Throws [ApiError].
  Future<List<PresetItem>> fetch(String templateId);
}

class DioPresetCatalogApi implements PresetCatalogApi {
  DioPresetCatalogApi(this.dio);

  /// Authenticated dio.
  final Dio dio;

  @override
  Future<List<PresetItem>> fetch(String templateId) async {
    try {
      final r = await dio.get<dynamic>('/api/v1/catalog/presets', queryParameters: {'template': templateId});
      final items = ((r.data as Map)['items'] as List).map((e) => PresetItem.fromJson((e as Map).cast<String, dynamic>()));
      return items.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    } on DioException catch (e) {
      throw e.error is ApiError ? e.error! as ApiError : ApiError.fromDio(e);
    }
  }
}

final presetCatalogApiProvider = Provider<PresetCatalogApi>((ref) => DioPresetCatalogApi(ref.watch(apiDioProvider)));
