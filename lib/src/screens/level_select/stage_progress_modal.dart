import 'package:flutter/material.dart';
import '../../game/progress/stage_progress_repository.dart';
import '../../widgets/styled_button.dart';

class StageProgressModal extends StatelessWidget {
  final Map<int, StageResult> progressByStage;
  final VoidCallback onClose;

  const StageProgressModal({
    super.key,
    required this.progressByStage,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final stageIds = progressByStage.keys.toList()..sort();
    final screen = MediaQuery.of(context).size;
    final modalWidth = (screen.width * 0.9).clamp(320.0, 680.0);
    final modalHeight = (screen.height * 0.78).clamp(420.0, 820.0);

    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Container(
          width: modalWidth,
          height: modalHeight,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF6E7CF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF7A4E2C),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                'Level Progress',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Colors.brown.shade900,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: stageIds.isEmpty
                    ? Center(
                        child: Text(
                          'No level result recorded yet.',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.brown.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: stageIds.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 16,
                          color: Colors.brown.shade200,
                        ),
                        itemBuilder: (context, index) {
                          final stageId = stageIds[index];
                          final result = progressByStage[stageId]!;
                          return _StageProgressRow(
                            stageId: stageId,
                            result: result,
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              StyledButton.brown(
                label: 'Close',
                onPressed: onClose,
                width: modalWidth * 0.44,
                height: 50,
                fontSize: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageProgressRow extends StatelessWidget {
  final int stageId;
  final StageResult result;

  const _StageProgressRow({
    required this.stageId,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final isCleared = result == StageResult.cleared;
    final iconColor = isCleared ? Colors.green.shade700 : Colors.red.shade700;
    final statusText = result.label;

    return Row(
      children: [
        SizedBox(
          width: 42,
          height: 52,
          child: Image.asset(
            'assets/world/world_001/lanterns/lantern_$stageId.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              decoration: BoxDecoration(
                color: Colors.brown.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '$stageId',
                style: TextStyle(
                  color: Colors.brown.shade800,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(
          isCleared ? Icons.check_circle : Icons.cancel,
          color: iconColor,
          size: 24,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Stage $stageId - $statusText',
            style: TextStyle(
              fontSize: 19,
              color: Colors.brown.shade900,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
