import 'stage_data.dart';

class StageValidationError {
	final String message;
	StageValidationError(this.message);
	@override
	String toString() => 'StageValidationError: $message';
}

class StageValidator {
	/// Validate a StageData object. Returns an empty list on success,
	/// otherwise a list of StageValidationError describing problems.
	static List<StageValidationError> validate(StageData stage) {
		final errors = <StageValidationError>[];

		// Basic dimensions
		if (stage.rows <= 0) errors.add(StageValidationError('rows must be > 0'));
		if (stage.columns <= 0) errors.add(StageValidationError('columns must be > 0'));

		// tiles presence
		final hasTiles = stage.tiles.isNotEmpty;

		// Check tileMap size
		if (stage.tileMap.length != stage.rows) {
			errors.add(StageValidationError('tileMap rows (${stage.tileMap.length}) != rows (${stage.rows})'));
		} else {
			for (var r = 0; r < stage.tileMap.length; r++) {
				if (stage.tileMap[r].length != stage.columns) {
					errors.add(StageValidationError('tileMap row $r length (${stage.tileMap[r].length}) != columns (${stage.columns})'));
				}
			}
		}

		// Check bedMap size
		if (stage.bedMap.length != stage.rows) {
			errors.add(StageValidationError('bedMap rows (${stage.bedMap.length}) != rows (${stage.rows})'));
		} else {
			for (var r = 0; r < stage.bedMap.length; r++) {
				if (stage.bedMap[r].length != stage.columns) {
					errors.add(StageValidationError('bedMap row $r length (${stage.bedMap[r].length}) != columns (${stage.columns})'));
				}
			}
		}

		// If any 0 (weighted spawn) in tileMap, tiles must exist
		bool hasWeightedSpawn = false;
		for (var row in stage.tileMap) {
			for (var v in row) {
				if (v == 0) {
					hasWeightedSpawn = true;
					break;
				}
			}
			if (hasWeightedSpawn) break;
		}
		if (hasWeightedSpawn && !hasTiles) {
			errors.add(StageValidationError('tileMap contains 0 (weighted spawn) entries but stage.tiles is empty'));
		}

		// Validate tile ids referenced are present when >=1
		final tileIds = stage.tiles.map((t) => t.id).toSet();
		for (var r = 0; r < stage.tileMap.length; r++) {
			for (var c = 0; c < stage.tileMap[r].length; c++) {
				final v = stage.tileMap[r][c];
				if (v > 0 && !tileIds.contains(v)) {
					errors.add(StageValidationError('tileMap references unknown tile id $v at [$r,$c]'));
				}
			}
		}

		// Validate weights > 0 when tiles present
		for (var t in stage.tiles) {
			if (t.weight <= 0) {
				errors.add(StageValidationError('tile id ${t.id} has non-positive weight ${t.weight}'));
			}
		}

		// bedTypes: ensure bed ids referenced in bedMap are within bedTypes
		// -1 = void bed (no bed rendered) - valid
		// 0 = default bed - valid (may or may not be in bedTypes)
		// >=1 = bed type id - must be in bedTypes
		final bedTypeIds = stage.bedTypes.map((b) => b.id).toSet();
		for (var r = 0; r < stage.bedMap.length; r++) {
			for (var c = 0; c < stage.bedMap[r].length; c++) {
				final b = stage.bedMap[r][c];
				// Only validate if bed id is positive (>=1) - allow -1 (void) and 0 (default)
				if (b > 0 && !bedTypeIds.contains(b)) {
					errors.add(StageValidationError('bedMap references unknown bed id $b at [$r,$c]'));
				}
			}
		}

		return errors;
	}
}

