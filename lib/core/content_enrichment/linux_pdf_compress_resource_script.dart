const kLinuxPdfCompressBridgeScript = r'''
#!/usr/bin/env python3
import argparse
import os
import sys


def _import_module(name):
    try:
        __import__(name)
        return True
    except Exception:
        return False


def run(input_path, output_path, dpi):
    if not _import_module("pypdfium2"):
        return 2
    if not _import_module("PIL"):
        return 3

    import pypdfium2 as pdfium
    from PIL import Image

    doc = pdfium.PdfDocument(input_path)
    page_count = len(doc)
    if page_count <= 0:
        return 4

    scale = max(150, min(200, int(dpi))) / 72.0
    rendered_images = []

    try:
        for index in range(page_count):
            page = doc[index]
            bitmap = page.render(scale=scale)
            pil_image = bitmap.to_pil()
            try:
                rgb = pil_image.convert("RGB")
                rendered_images.append(rgb)
            finally:
                try:
                    pil_image.close()
                except Exception:
                    pass
                try:
                    bitmap.close()
                except Exception:
                    pass
                try:
                    page.close()
                except Exception:
                    pass

        if not rendered_images:
            return 5

        first, *rest = rendered_images
        first.save(
            output_path,
            format="PDF",
            save_all=True,
            append_images=rest,
            resolution=float(max(150, min(200, int(dpi)))),
            quality=70,
            optimize=True,
        )
        return 0
    finally:
        for image in rendered_images:
            try:
                image.close()
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--dpi", type=int, default=180)
    args = parser.parse_args()

    input_path = os.path.abspath(args.input)
    output_path = os.path.abspath(args.output)

    if not os.path.exists(input_path):
        return 10

    try:
        rc = run(input_path, output_path, args.dpi)
    except Exception:
        return 11

    if rc != 0:
        return rc
    if not os.path.exists(output_path):
        return 12
    if os.path.getsize(output_path) <= 0:
        return 13
    return 0


if __name__ == "__main__":
    sys.exit(main())
''';
