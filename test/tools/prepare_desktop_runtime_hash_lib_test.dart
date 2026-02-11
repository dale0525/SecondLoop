import 'package:flutter_test/flutter_test.dart';

import '../../tools/prepare_desktop_runtime_hash_lib.dart';
import '../../tools/prepare_desktop_runtime.dart' as runtime;

void main() {
  test('extractSha256FromCommandOutput parses sha256sum output', () {
    const output =
        '4f7b047a284a4b7499341821c0844c8d6c69668d28df9a06df4d6ea393a307d1  runtime.tar.gz\n';

    expect(
      extractSha256FromCommandOutput(output),
      '4f7b047a284a4b7499341821c0844c8d6c69668d28df9a06df4d6ea393a307d1',
    );
  });

  test('extractSha256FromCommandOutput parses certutil grouped output', () {
    const output = '''
SHA256 hash of runtime.tar.gz:
4f 7b 04 7a 28 4a 4b 74 99 34 18 21 c0 84 4c 8d 6c 69 66 8d 28 df 9a 06 df 4d 6e a3 93 a3 07 d1
CertUtil: -hashfile command completed successfully.
''';

    expect(
      extractSha256FromCommandOutput(output),
      '4f7b047a284a4b7499341821c0844c8d6c69668d28df9a06df4d6ea393a307d1',
    );
  });

  test(
    'extractSha256FromCommandOutput tolerates leading backslash before digest',
    () {
      const output =
          '\\4f7b047a284a4b7499341821c0844c8d6c69668d28df9a06df4d6ea393a307d1\n';

      expect(
        extractSha256FromCommandOutput(output),
        '4f7b047a284a4b7499341821c0844c8d6c69668d28df9a06df4d6ea393a307d1',
      );
    },
  );

  test('extractSha256FromCommandOutput returns null when digest missing', () {
    expect(extractSha256FromCommandOutput('no digest\n'), isNull);
  });

  test('basenameFromAnyPathForTest parses mixed Windows path separators', () {
    expect(
      runtime.basenameFromAnyPathForTest(
        r'assets/ocr/desktop_runtime.tmp-12345\models\onnxruntime.dll',
      ),
      'onnxruntime.dll',
    );
  });

  test('basenameFromAnyPathForTest parses pure Windows path separators', () {
    expect(
      runtime.basenameFromAnyPathForTest(
        r'D:\a\SecondLoop\assets\ocr\desktop_runtime\models\ch_PP-OCRv5_mobile_det.onnx',
      ),
      'ch_PP-OCRv5_mobile_det.onnx',
    );
  });
}
