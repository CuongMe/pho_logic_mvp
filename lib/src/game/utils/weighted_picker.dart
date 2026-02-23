import 'dart:math';

/// Simple weighted picker.
/// Items are represented by their weights; pickIndex returns an index
/// chosen according to weights distribution.
class WeightedPicker {
  final List<int> _weights;
  final int _total;
  final Random _rng;

  WeightedPicker(List<int> weights, [Random? rng])
      : _weights = List<int>.from(weights),
        _rng = rng ?? Random(),
        _total = weights.fold(0, (a, b) => a + b) {
    if (_weights.any((w) => w < 0)) throw ArgumentError('weights must be non-negative');
    if (_total == 0) throw ArgumentError('total weight must be > 0');
  }

  /// Return the selected index according to weights.
  int pickIndex() {
    int r = _rng.nextInt(_total);
    int acc = 0;
    for (int i = 0; i < _weights.length; i++) {
      acc += _weights[i];
      if (r < acc) return i;
    }
    return _weights.length - 1;
  }
}