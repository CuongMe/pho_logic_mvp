import '../../utils/json_helpers.dart';

class Objective {
  final String type; // "collect", "clear", etc.
  final int? tileId; // For collect objectives
  final int target; // Target count

  Objective({required this.type, this.tileId, required this.target});

  factory Objective.fromJson(Map<String, dynamic> j) {
    return Objective(
      type: j['type'] as String,
      tileId: j['tileId'] as int?,
      target: j['target'] as int,
    );
  }
}

class TileDef {
  final int id;
  final String file;
  final int weight;
  final String?
      sfxType; // Sound effect identifier (e.g., 'banhMiCrunch', 'phoBowl')

  TileDef(
      {required this.id,
      required this.file,
      required this.weight,
      this.sfxType});

  factory TileDef.fromJson(Map<String, dynamic> j) {
    return TileDef(
      id: j['id'] as int,
      file: j['file'] as String,
      weight: j['weight'] as int,
      sfxType: j['sfxType'] as String?,
    );
  }
}

class BedType {
  final int id;
  final String file;
  final bool destructible;
  final int hp;

  BedType(
      {required this.id,
      required this.file,
      required this.destructible,
      required this.hp});

  factory BedType.fromJson(Map<String, dynamic> j) {
    return BedType(
      id: j['id'] as int,
      file: j['file'] as String,
      destructible: j['destructible'] as bool? ?? false,
      hp: j['hp'] as int? ?? 0,
    );
  }
}

class BlockerDef {
  final int id;
  final String name;
  final String file;
  final String? clearedBy;

  BlockerDef(
      {required this.id,
      required this.name,
      required this.file,
      this.clearedBy});

  factory BlockerDef.fromJson(Map<String, dynamic> j) {
    return BlockerDef(
      id: j['id'] as int,
      name: j['name'] as String,
      file: j['file'] as String,
      clearedBy: j['clearedBy'] as String?,
    );
  }
}

class StageData {
  final String stageKey;
  final String name;
  final int rows;
  final int columns;
  final GridRect? gridRect;
  final List<TileDef> tiles;
  final List<BedType> bedTypes;
  final List<BlockerDef> blockerTypes;
  final List<List<int>>
      tileMap; // values: 0 = weighted random spawn, -1 = no tile (void/empty), -2 = blocker, >=1 = fixed tile id
  final List<List<int>>
      bedMap; // bed type ids per cell: -1 = void bed (no bed), 0 = default bed, >=1 bed type id
  final int moves;
  final bool allowInitialMatches;
  final List<Objective> objectives;

  StageData({
    required this.stageKey,
    required this.name,
    required this.rows,
    required this.columns,
    required this.tiles,
    this.gridRect, // Optional - moved to gameplay UI JSON
    required this.bedTypes,
    required this.blockerTypes,
    required this.tileMap,
    required this.bedMap,
    required this.moves,
    required this.allowInitialMatches,
    required this.objectives,
  });

  factory StageData.fromJson(Map<String, dynamic> j) {
    final grid = j['grid'] as Map<String, dynamic>?;
    final rows = grid != null ? (grid['rows'] as int? ?? 8) : 8;
    final columns = grid != null ? (grid['columns'] as int? ?? 8) : 8;

    final tilesJson = j['tiles'] as List<dynamic>? ?? [];
    final tiles = tilesJson
        .map((e) => TileDef.fromJson(e as Map<String, dynamic>))
        .toList();

    final bedTypesJson = j['bedTypes'] as List<dynamic>? ?? [];
    final bedTypes = bedTypesJson
        .map((e) => BedType.fromJson(e as Map<String, dynamic>))
        .toList();

    final blockerTypesJson = j['blockerTypes'] as List<dynamic>? ?? [];
    final blockerTypes = blockerTypesJson
        .map((e) => BlockerDef.fromJson(e as Map<String, dynamic>))
        .toList();

    List<List<int>> parseGridArray(dynamic arr, int r, int c) {
      if (arr == null) return List.generate(r, (_) => List.filled(c, 0));
      final rowsList = (arr as List)
          .map<List<int>>(
              (row) => (row as List).map<int>((v) => v as int).toList())
          .toList();
      return rowsList;
    }

    final tileMapCells = (j['tileMap']?['cells']) ?? j['tileMap'];
    final tileMap = parseGridArray(tileMapCells, rows, columns);

    final bedMapArr = j['bedMap'];
    final bedMap = parseGridArray(bedMapArr, rows, columns);

    final gridRectJson = j['gridRect'] as Map<String, dynamic>?;
    final gridRect =
        gridRectJson != null ? GridRect.fromJson(gridRectJson) : null;

    final spawnRules = j['spawnRules'] as Map<String, dynamic>?;
    final allowInitialMatches =
        spawnRules?['allowInitialMatches'] as bool? ?? true;

    final moves = j['moves'] as int? ?? 0;

    final objectivesJson = j['objectives'] as List<dynamic>? ?? [];
    final objectives = objectivesJson
        .map((e) => Objective.fromJson(e as Map<String, dynamic>))
        .toList();

    return StageData(
      stageKey:
          j['stageKey']?.toString() ?? j['stageId']?.toString() ?? 'unknown',
      name: j['name']?.toString() ?? 'stage',
      rows: rows,
      columns: columns,
      gridRect: gridRect,
      tiles: tiles,
      bedTypes: bedTypes,
      blockerTypes: blockerTypes,
      tileMap: tileMap,
      bedMap: bedMap,
      moves: moves,
      allowInitialMatches: allowInitialMatches,
      objectives: objectives,
    );
  }

  Map<String, dynamic> toJson() => {
        'stageKey': stageKey,
        'name': name,
        'rows': rows,
        'columns': columns,
        // gridRect removed - now in gameplay UI JSON
        'tiles': tiles
            .map((t) => {
                  'id': t.id,
                  'file': t.file,
                  'weight': t.weight,
                  if (t.sfxType != null) 'sfxType': t.sfxType,
                })
            .toList(),
        'bedTypes': bedTypes
            .map((b) => {
                  'id': b.id,
                  'file': b.file,
                  'destructible': b.destructible,
                  'hp': b.hp
                })
            .toList(),
        'tileMap': tileMap,
        'bedMap': bedMap,
        'moves': moves,
        'spawnRules': {'allowInitialMatches': allowInitialMatches},
        'objectives': objectives
            .map((o) => {
                  'type': o.type,
                  if (o.tileId != null) 'tileId': o.tileId,
                  'target': o.target,
                })
            .toList(),
      };
}

class GridRect {
  final double x;
  final double y;
  final double w;
  final double h;

  GridRect(
      {required this.x, required this.y, required this.w, required this.h});

  factory GridRect.fromJson(Map<String, dynamic> j) {
    return GridRect(
      x: parseDouble(j['x']),
      y: parseDouble(j['y']),
      w: parseDouble(j['w']),
      h: parseDouble(j['h']),
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};
}
