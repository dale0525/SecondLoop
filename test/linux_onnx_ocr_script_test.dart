import 'package:flutter_test/flutter_test.dart';
import 'package:secondloop/features/attachments/linux_onnx_ocr_script.dart';

void main() {
  test('Linux ONNX OCR bridge script does not perform pip install', () {
    expect(
      kLinuxOnnxOcrBridgeScript.contains('pip install'),
      isFalse,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('--break-system-packages'),
      isFalse,
    );
  });

  test('Linux ONNX OCR bridge script supports external model directory', () {
    expect(
      kLinuxOnnxOcrBridgeScript.contains('SECONDLOOP_OCR_MODEL_DIR'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('resolve_rapidocr_kwargs'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('ch_PP-OCRv4_det_infer.onnx'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('latin_PP-OCRv3_rec_infer.onnx'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('latin_dict.txt'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('select_rec_model_keys'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('rec_keys_path'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('locale.getlocale'),
      isTrue,
    );
  });

  test('device_plus_en uses pdf content auto detect and emits model engine',
      () {
    expect(
      kLinuxOnnxOcrBridgeScript.contains('if hint == "device_plus_en":'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('use_pdf_auto_detect'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('auto_detect_pdf_rec_model_key'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('probe_pages = min(target_pages, 1)'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript
          .contains('ordered_keys = [preferred, "zh_hans", "latin"]'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('score_text_for_model'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript.contains('"ocr_engine": engine'),
      isTrue,
    );
    expect(
      kLinuxOnnxOcrBridgeScript
          .contains('engine_label = f"onnx_ocr+{selected_key}+auto"'),
      isTrue,
    );
  });
}
