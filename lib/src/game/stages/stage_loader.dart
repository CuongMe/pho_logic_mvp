import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../utils/weighted_picker.dart';
import 'stage_data.dart';

class StageLoader {
	/// Load a stage JSON from assets and return a StageData with 0 (weighted spawn) cells resolved
	/// according to the `tiles` weights. Honors bedMap void cells.
	static Future<StageData> loadFromAsset(String assetPath) async {
		final raw = await rootBundle.loadString(assetPath);
		final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
		final StageData stage = StageData.fromJson(json);

		// Prepare weighted picker based on tiles list
		final tileIds = stage.tiles.map((t) => t.id).toList();
		final weights = stage.tiles.map((t) => t.weight).toList();
		bool hasWeightedSpawn = false;
		for (int r = 0; r < stage.tileMap.length; r++) {
			for (int c = 0; c < stage.tileMap[r].length; c++) {
				final val = stage.tileMap[r][c];
				// 0 = weighted random spawn (standardized)
				if (val == 0) {
					hasWeightedSpawn = true;
					break;
				}
			}
			if (hasWeightedSpawn) break;
		}
		if (hasWeightedSpawn && tileIds.isEmpty) {
			throw ArgumentError('Stage contains 0 (weighted spawn) cells but `tiles` is empty.');
		}
		final picker = hasWeightedSpawn ? WeightedPicker(weights) : null;

		// Fill tileMap: replace 0 (weighted spawn) with a weighted choice among tileIds
		for (int r = 0; r < stage.tileMap.length; r++) {
			for (int c = 0; c < stage.tileMap[r].length; c++) {
				final val = stage.tileMap[r][c];
				final bedId = (r < stage.bedMap.length && c < stage.bedMap[r].length)
						? stage.bedMap[r][c]
						: 0;
				final isVoid = bedId == -1;
				if (isVoid) {
					// Void cell - normalize to -1 (no tile)
					stage.tileMap[r][c] = -1;
					continue;
				}
				// 0 = weighted random spawn (standardized)
				if (val == 0) {
					final idx = picker!.pickIndex();
					stage.tileMap[r][c] = tileIds[idx];
				}
			}
		}

		return stage;
	}
}
