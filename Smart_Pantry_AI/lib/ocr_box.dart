import 'dart:math' as math;

class OCRBox {
  final String text;
  final List<List<double>> points;

  const OCRBox(this.text, this.points);

  double get left => points.map((point) => point[0]).reduce(math.min);
  double get right => points.map((point) => point[0]).reduce(math.max);
  double get top => points.map((point) => point[1]).reduce(math.min);
  double get bottom => points.map((point) => point[1]).reduce(math.max);
  double get centerX =>
      points.map((point) => point[0]).reduce((a, b) => a + b) / points.length;
  double get centerY =>
      points.map((point) => point[1]).reduce((a, b) => a + b) / points.length;
  double get height =>
      points.map((point) => point[1]).reduce(math.max) -
      points.map((point) => point[1]).reduce(math.min);
}
