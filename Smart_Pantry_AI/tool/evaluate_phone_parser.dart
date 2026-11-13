import 'dart:convert';
import 'dart:io';

import 'package:smart_pantry_ai/ocr_service.dart';

Future<void> main(List<String> arguments) async {
  final input = _argument(arguments, '--input');
  final output = _argument(arguments, '--output') ?? input;
  if (input == null || output == null) {
    stderr.writeln('Usage: dart run tool/evaluate_phone_parser.dart '
        '--input <json> [--output <json>]');
    exitCode = 64;
    return;
  }

  final file = File(input);
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Evaluation JSON must contain an object.');
  }
  final images = decoded['images'];
  if (images is List) {
    for (final item in images) {
      if (item is! Map<String, dynamic> || item['status'] != 'ok') continue;
      final text = item['text'];
      final detections = item['detections'];
      if (text is! String || detections is! List) continue;
      item['parser_output'] = OCRService.extractBackDetailsFromOCR(
        text,
        detections,
      );
    }
  }

  final temporary = File('$output.tmp');
  await temporary.writeAsString(
    const JsonEncoder.withIndent('  ').convert(decoded),
  );
  await temporary.rename(output);
}

String? _argument(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}
