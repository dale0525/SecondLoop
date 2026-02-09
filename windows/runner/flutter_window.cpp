#include "flutter_window.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <limits>
#include <optional>
#include <string>
#include <vector>

#include <flutter/standard_method_codec.h>

#include <winrt/base.h>
#include <winrt/Windows.Data.Pdf.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.Streams.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

using winrt::Windows::Data::Pdf::PdfDocument;
using winrt::Windows::Data::Pdf::PdfPageRenderOptions;
using winrt::Windows::Globalization::ApplicationLanguages;
using winrt::Windows::Globalization::Language;
using winrt::Windows::Graphics::Imaging::BitmapAlphaMode;
using winrt::Windows::Graphics::Imaging::BitmapDecoder;
using winrt::Windows::Graphics::Imaging::BitmapEncoder;
using winrt::Windows::Graphics::Imaging::BitmapPixelFormat;
using winrt::Windows::Graphics::Imaging::SoftwareBitmap;
using winrt::Windows::Media::Ocr::OcrEngine;
using winrt::Windows::Storage::Streams::Buffer;
using winrt::Windows::Storage::Streams::DataReader;
using winrt::Windows::Storage::Streams::DataWriter;
using winrt::Windows::Storage::Streams::InMemoryRandomAccessStream;
using winrt::Windows::Storage::Streams::IRandomAccessStream;

constexpr char kCommonPdfOcrPreset[] = "common_ocr_v1";
constexpr int kCommonPdfOcrMaxPages = 10'000;
constexpr int kCommonPdfOcrDpi = 180;
constexpr uint32_t kPdfRenderMaxOutputWidth = 1536;
constexpr uint32_t kPdfRenderMaxOutputHeight = 20'000;
constexpr uint64_t kPdfRenderMaxOutputPixels = 20'000'000ULL;

struct PdfRenderPreset {
  std::string id;
  int max_pages;
  int dpi;
};

std::string Trim(std::string text) {
  auto is_space = [](unsigned char c) { return std::isspace(c) != 0; };
  text.erase(text.begin(),
             std::find_if(text.begin(), text.end(),
                          [&](unsigned char c) { return !is_space(c); }));
  text.erase(
      std::find_if(text.rbegin(), text.rend(),
                   [&](unsigned char c) { return !is_space(c); })
          .base(),
      text.end());
  return text;
}

std::string ToLowerAscii(std::string text) {
  std::transform(text.begin(), text.end(), text.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return text;
}

bool StartsWith(const std::string& value, const std::string& prefix) {
  return value.size() >= prefix.size() &&
         value.compare(0, prefix.size(), prefix) == 0;
}

std::string ResolveProfilePrimaryLanguageLower() {
  try {
    const auto languages = ApplicationLanguages::Languages();
    const uint32_t size = languages.Size();
    for (uint32_t index = 0; index < size; ++index) {
      auto tag = ToLowerAscii(winrt::to_string(languages.GetAt(index)));
      tag = Trim(tag);
      if (!tag.empty()) {
        return tag;
      }
    }
  } catch (...) {
  }
  return std::string();
}

std::wstring ResolvePreferredChineseTagFromProfile() {
  const auto primary = ResolveProfilePrimaryLanguageLower();
  if (primary.find("hant") != std::string::npos ||
      primary.find("zh-hk") != std::string::npos ||
      primary.find("zh-mo") != std::string::npos ||
      primary.find("zh-tw") != std::string::npos) {
    return L"zh-Hant";
  }
  return L"zh-Hans";
}

std::string TruncateUtf8(const std::string& text, size_t max_bytes) {
  if (text.size() <= max_bytes) {
    return text;
  }
  if (max_bytes == 0) {
    return std::string();
  }
  size_t end = max_bytes;
  while (end > 0 &&
         (static_cast<unsigned char>(text[end]) & 0xC0u) == 0x80u) {
    end--;
  }
  if (end == 0) {
    return std::string();
  }
  return text.substr(0, end);
}

int ClampPositiveInt(const flutter::EncodableMap* args, const char* key,
                     int fallback, int upper_bound) {
  if (args == nullptr) {
    return fallback;
  }
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) {
    return fallback;
  }
  int value = fallback;
  if (const auto* as_int = std::get_if<int32_t>(&it->second)) {
    value = *as_int;
  } else if (const auto* as_long = std::get_if<int64_t>(&it->second)) {
    value = static_cast<int>(*as_long);
  } else if (const auto* as_double = std::get_if<double>(&it->second)) {
    value = static_cast<int>(*as_double);
  }
  if (value < 1) {
    value = 1;
  }
  if (value > upper_bound) {
    value = upper_bound;
  }
  return value;
}

std::string ReadLanguageHints(const flutter::EncodableMap* args) {
  if (args == nullptr) {
    return "device_plus_en";
  }
  auto it = args->find(flutter::EncodableValue("language_hints"));
  if (it == args->end()) {
    return "device_plus_en";
  }
  const auto* value = std::get_if<std::string>(&it->second);
  if (value == nullptr) {
    return "device_plus_en";
  }
  auto trimmed = Trim(*value);
  if (trimmed.empty()) {
    return "device_plus_en";
  }
  return ToLowerAscii(trimmed);
}

std::optional<std::vector<uint8_t>> ReadBytesArg(
    const flutter::EncodableMap* args) {
  if (args == nullptr) {
    return std::nullopt;
  }
  auto it = args->find(flutter::EncodableValue("bytes"));
  if (it == args->end()) {
    return std::nullopt;
  }
  const auto* bytes = std::get_if<std::vector<uint8_t>>(&it->second);
  if (bytes == nullptr || bytes->empty()) {
    return std::nullopt;
  }
  return *bytes;
}

InMemoryRandomAccessStream BytesToStream(const std::vector<uint8_t>& bytes) {
  InMemoryRandomAccessStream stream;
  DataWriter writer(stream);
  writer.WriteBytes(winrt::array_view<const uint8_t>(bytes));
  writer.StoreAsync().get();
  writer.FlushAsync().get();
  writer.DetachStream();
  stream.Seek(0);
  return stream;
}

std::optional<SoftwareBitmap> DecodeBitmap(IRandomAccessStream const& stream) {
  try {
    auto decoder = BitmapDecoder::CreateAsync(stream).get();
    auto bitmap =
        decoder
            .GetSoftwareBitmapAsync(BitmapPixelFormat::Bgra8,
                                    BitmapAlphaMode::Premultiplied)
            .get();
    return bitmap;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<OcrEngine> CreateEngineFromHints(const std::string& hints) {
  auto try_language = [](const wchar_t* tag) -> std::optional<OcrEngine> {
    try {
      auto engine = OcrEngine::TryCreateFromLanguage(Language(tag));
      if (engine) {
        return engine;
      }
    } catch (...) {
    }
    return std::nullopt;
  };

  auto try_preferred_chinese = [&]() -> std::optional<OcrEngine> {
    const auto preferred = ResolvePreferredChineseTagFromProfile();
    if (auto engine = try_language(preferred.c_str())) {
      return engine;
    }
    const auto fallback = preferred == L"zh-Hant" ? L"zh-Hans" : L"zh-Hant";
    if (auto engine = try_language(fallback)) {
      return engine;
    }
    return std::nullopt;
  };

  if (hints == "zh_en") {
    if (auto engine = try_preferred_chinese()) return engine;
    if (auto engine = try_language(L"en-US")) return engine;
  } else if (hints == "zh_strict") {
    if (auto engine = try_preferred_chinese()) return engine;
  } else if (hints == "device_plus_en") {
    const auto preferred = ResolveProfilePrimaryLanguageLower();
    if (StartsWith(preferred, "zh")) {
      if (auto engine = try_preferred_chinese()) return engine;
      if (auto engine = try_language(L"en-US")) return engine;
    } else if (StartsWith(preferred, "ja")) {
      if (auto engine = try_language(L"ja-JP")) return engine;
      if (auto engine = try_language(L"en-US")) return engine;
    } else if (StartsWith(preferred, "ko")) {
      if (auto engine = try_language(L"ko-KR")) return engine;
      if (auto engine = try_language(L"en-US")) return engine;
    } else if (StartsWith(preferred, "fr")) {
      if (auto engine = try_language(L"fr-FR")) return engine;
      if (auto engine = try_language(L"en-US")) return engine;
    } else if (StartsWith(preferred, "de")) {
      if (auto engine = try_language(L"de-DE")) return engine;
      if (auto engine = try_language(L"en-US")) return engine;
    } else if (StartsWith(preferred, "es")) {
      if (auto engine = try_language(L"es-ES")) return engine;
      if (auto engine = try_language(L"en-US")) return engine;
    }
  } else if (hints == "ja_en") {
    if (auto engine = try_language(L"ja-JP")) return engine;
    if (auto engine = try_language(L"en-US")) return engine;
  } else if (hints == "ko_en") {
    if (auto engine = try_language(L"ko-KR")) return engine;
    if (auto engine = try_language(L"en-US")) return engine;
  } else if (hints == "fr_en") {
    if (auto engine = try_language(L"fr-FR")) return engine;
    if (auto engine = try_language(L"en-US")) return engine;
  } else if (hints == "de_en") {
    if (auto engine = try_language(L"de-DE")) return engine;
    if (auto engine = try_language(L"en-US")) return engine;
  } else if (hints == "es_en") {
    if (auto engine = try_language(L"es-ES")) return engine;
    if (auto engine = try_language(L"en-US")) return engine;
  } else if (hints == "en") {
    if (auto engine = try_language(L"en-US")) return engine;
  }

  try {
    auto user_engine = OcrEngine::TryCreateFromUserProfileLanguages();
    if (user_engine) {
      return user_engine;
    }
  } catch (...) {
  }
  return std::nullopt;
}


std::string ReadStringArg(const flutter::EncodableMap* args, const char* key) {
  if (args == nullptr) {
    return std::string();
  }
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) {
    return std::string();
  }
  const auto* value = std::get_if<std::string>(&it->second);
  if (value == nullptr) {
    return std::string();
  }
  return ToLowerAscii(Trim(*value));
}

PdfRenderPreset ResolvePdfRenderPreset(const flutter::EncodableMap* args) {
  const auto preset_id = ReadStringArg(args, "ocr_model_preset");
  if (preset_id == kCommonPdfOcrPreset) {
    return PdfRenderPreset{
        std::string(kCommonPdfOcrPreset),
        kCommonPdfOcrMaxPages,
        kCommonPdfOcrDpi,
    };
  }

  const int max_pages =
      ClampPositiveInt(args, "max_pages", kCommonPdfOcrMaxPages, 10'000);
  const int dpi = ClampPositiveInt(args, "dpi", kCommonPdfOcrDpi, 600);
  return PdfRenderPreset{
      preset_id.empty() ? std::string(kCommonPdfOcrPreset) : preset_id,
      max_pages,
      dpi,
  };
}

std::optional<std::vector<uint8_t>> CopySoftwareBitmapPixelsBgra(
    SoftwareBitmap bitmap) {
  try {
    if (bitmap.BitmapPixelFormat() != BitmapPixelFormat::Bgra8 ||
        bitmap.BitmapAlphaMode() != BitmapAlphaMode::Premultiplied) {
      bitmap = SoftwareBitmap::Convert(
          bitmap, BitmapPixelFormat::Bgra8, BitmapAlphaMode::Premultiplied);
    }

    const int width = bitmap.PixelWidth();
    const int height = bitmap.PixelHeight();
    if (width <= 0 || height <= 0) {
      return std::nullopt;
    }

    const uint64_t total_bytes =
        static_cast<uint64_t>(width) * static_cast<uint64_t>(height) * 4ULL;
    if (total_bytes == 0 || total_bytes > std::numeric_limits<uint32_t>::max()) {
      return std::nullopt;
    }

    Buffer buffer(static_cast<uint32_t>(total_bytes));
    buffer.Length(static_cast<uint32_t>(total_bytes));
    bitmap.CopyToBuffer(buffer);

    auto reader = DataReader::FromBuffer(buffer);
    std::vector<uint8_t> pixels(static_cast<size_t>(total_bytes));
    reader.ReadBytes(winrt::array_view<uint8_t>(pixels));
    return pixels;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<std::vector<uint8_t>> EncodeJpegFromBgra(
    const std::vector<uint8_t>& pixels, uint32_t width, uint32_t height) {
  try {
    if (width == 0 || height == 0 || pixels.empty()) {
      return std::nullopt;
    }

    InMemoryRandomAccessStream stream;
    auto encoder = BitmapEncoder::CreateAsync(
        BitmapEncoder::JpegEncoderId(), stream).get();
    encoder.SetPixelData(
        BitmapPixelFormat::Bgra8,
        BitmapAlphaMode::Ignore,
        width,
        height,
        96.0,
        96.0,
        winrt::array_view<const uint8_t>(pixels));
    encoder.FlushAsync().get();

    stream.Seek(0);
    const uint64_t out_size = stream.Size();
    if (out_size == 0 || out_size > std::numeric_limits<uint32_t>::max()) {
      return std::nullopt;
    }

    DataReader reader(stream);
    reader.LoadAsync(static_cast<uint32_t>(out_size)).get();
    std::vector<uint8_t> jpeg_bytes(static_cast<size_t>(out_size));
    reader.ReadBytes(winrt::array_view<uint8_t>(jpeg_bytes));
    return jpeg_bytes;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<flutter::EncodableMap> RunPdfRenderToLongImage(
    const std::vector<uint8_t>& bytes, int max_pages, int dpi) {
  try {
    auto stream = BytesToStream(bytes);
    auto document = PdfDocument::LoadFromStreamAsync(stream).get();
    const uint32_t page_count = document.PageCount();
    if (page_count == 0) {
      return std::nullopt;
    }

    const uint32_t target_pages =
        std::min(page_count, static_cast<uint32_t>(max_pages));

    std::vector<SoftwareBitmap> page_bitmaps;
    page_bitmaps.reserve(target_pages);

    uint32_t output_width = 0;
    uint32_t output_height = 0;
    uint32_t processed_pages = 0;

    for (uint32_t index = 0; index < target_pages; ++index) {
      auto page = document.GetPage(index);
      auto size = page.Size();

      const double scale =
          std::clamp(static_cast<double>(dpi) / 72.0, 1.0, 6.0);
      uint32_t width = std::max(
          1, static_cast<int32_t>(std::llround(size.Width * scale)));
      uint32_t height = std::max(
          1, static_cast<int32_t>(std::llround(size.Height * scale)));

      if (width > kPdfRenderMaxOutputWidth) {
        const double ratio =
            static_cast<double>(kPdfRenderMaxOutputWidth) / static_cast<double>(width);
        width = kPdfRenderMaxOutputWidth;
        height = std::max(
            1, static_cast<int32_t>(std::llround(static_cast<double>(height) * ratio)));
      }

      const uint32_t next_width = std::max(output_width, width);
      const uint64_t next_height =
          static_cast<uint64_t>(output_height) + static_cast<uint64_t>(height);
      if (next_height > kPdfRenderMaxOutputHeight) {
        break;
      }
      const uint64_t next_pixels =
          static_cast<uint64_t>(next_width) * static_cast<uint64_t>(next_height);
      if (next_pixels > kPdfRenderMaxOutputPixels) {
        break;
      }

      InMemoryRandomAccessStream image_stream;
      PdfPageRenderOptions options;
      options.DestinationWidth(width);
      options.DestinationHeight(height);
      page.RenderToStreamAsync(image_stream, options).get();
      image_stream.Seek(0);

      auto bitmap = DecodeBitmap(image_stream);
      if (!bitmap.has_value()) {
        continue;
      }

      const uint32_t bitmap_width = static_cast<uint32_t>(bitmap->PixelWidth());
      const uint32_t bitmap_height = static_cast<uint32_t>(bitmap->PixelHeight());
      if (bitmap_width == 0 || bitmap_height == 0) {
        continue;
      }

      const uint32_t actual_next_width = std::max(output_width, bitmap_width);
      const uint64_t actual_next_height =
          static_cast<uint64_t>(output_height) + static_cast<uint64_t>(bitmap_height);
      if (actual_next_height > kPdfRenderMaxOutputHeight) {
        break;
      }
      const uint64_t actual_next_pixels =
          static_cast<uint64_t>(actual_next_width) * actual_next_height;
      if (actual_next_pixels > kPdfRenderMaxOutputPixels) {
        break;
      }

      output_width = actual_next_width;
      output_height = static_cast<uint32_t>(actual_next_height);
      page_bitmaps.push_back(*bitmap);
      processed_pages += 1;
    }

    if (page_bitmaps.empty() || output_width == 0 || output_height == 0) {
      return std::nullopt;
    }

    const uint64_t canvas_bytes =
        static_cast<uint64_t>(output_width) * static_cast<uint64_t>(output_height) * 4ULL;
    if (canvas_bytes == 0 || canvas_bytes > std::numeric_limits<size_t>::max()) {
      return std::nullopt;
    }

    std::vector<uint8_t> canvas(static_cast<size_t>(canvas_bytes), 255);
    uint32_t y_offset = 0;
    for (const auto& bitmap : page_bitmaps) {
      const auto page_pixels = CopySoftwareBitmapPixelsBgra(bitmap);
      if (!page_pixels.has_value()) {
        continue;
      }

      const uint32_t width = static_cast<uint32_t>(bitmap.PixelWidth());
      const uint32_t height = static_cast<uint32_t>(bitmap.PixelHeight());
      if (width == 0 || height == 0 || y_offset >= output_height) {
        continue;
      }

      const uint32_t rows_to_copy =
          std::min(height, output_height - y_offset);
      const size_t src_row_bytes = static_cast<size_t>(width) * 4;

      for (uint32_t row = 0; row < rows_to_copy; ++row) {
        const size_t src_offset = static_cast<size_t>(row) * src_row_bytes;
        const size_t dst_offset =
            (static_cast<size_t>(y_offset + row) * static_cast<size_t>(output_width)) * 4;
        std::copy_n(
            page_pixels->data() + src_offset,
            src_row_bytes,
            canvas.data() + dst_offset);
      }

      y_offset = std::min(output_height, y_offset + height);
    }

    const auto jpeg_bytes = EncodeJpegFromBgra(canvas, output_width, output_height);
    if (!jpeg_bytes.has_value() || jpeg_bytes->empty()) {
      return std::nullopt;
    }

    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("image_bytes")] =
        flutter::EncodableValue(*jpeg_bytes);
    payload[flutter::EncodableValue("image_mime_type")] =
        flutter::EncodableValue(std::string("image/jpeg"));
    payload[flutter::EncodableValue("page_count")] =
        flutter::EncodableValue(static_cast<int32_t>(page_count));
    payload[flutter::EncodableValue("processed_pages")] =
        flutter::EncodableValue(static_cast<int32_t>(processed_pages));
    return payload;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<flutter::EncodableMap> RunImageOcr(
    const std::vector<uint8_t>& bytes, const std::string& language_hints) {
  try {
    auto stream = BytesToStream(bytes);
    auto bitmap = DecodeBitmap(stream);
    if (!bitmap.has_value()) {
      return std::nullopt;
    }
    auto engine = CreateEngineFromHints(language_hints);
    if (!engine.has_value()) {
      return std::nullopt;
    }

    auto result = engine->RecognizeAsync(*bitmap).get();
    std::string full = Trim(winrt::to_string(result.Text()));
    std::string full_truncated = TruncateUtf8(full, 256 * 1024);
    std::string excerpt = TruncateUtf8(full_truncated, 8 * 1024);

    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("ocr_text_full")] =
        flutter::EncodableValue(full_truncated);
    payload[flutter::EncodableValue("ocr_text_excerpt")] =
        flutter::EncodableValue(excerpt);
    payload[flutter::EncodableValue("ocr_engine")] =
        flutter::EncodableValue(std::string("windows_ocr"));
    payload[flutter::EncodableValue("ocr_is_truncated")] =
        flutter::EncodableValue(full_truncated != full);
    payload[flutter::EncodableValue("ocr_page_count")] =
        flutter::EncodableValue(static_cast<int32_t>(1));
    payload[flutter::EncodableValue("ocr_processed_pages")] =
        flutter::EncodableValue(static_cast<int32_t>(1));
    return payload;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<flutter::EncodableMap> RunPdfOcr(
    const std::vector<uint8_t>& bytes, int max_pages, int dpi,
    const std::string& language_hints) {
  try {
    auto stream = BytesToStream(bytes);
    auto document = PdfDocument::LoadFromStreamAsync(stream).get();
    uint32_t page_count = document.PageCount();
    if (page_count == 0) {
      return std::nullopt;
    }
    auto engine = CreateEngineFromHints(language_hints);
    if (!engine.has_value()) {
      return std::nullopt;
    }

    uint32_t target_pages = std::min(page_count, static_cast<uint32_t>(max_pages));
    std::string full;
    uint32_t processed_pages = 0;

    for (uint32_t index = 0; index < target_pages; ++index) {
      auto page = document.GetPage(index);
      auto size = page.Size();

      auto width =
          std::max(1, static_cast<int32_t>(size.Width * static_cast<float>(dpi) / 72.0f));
      auto height =
          std::max(1, static_cast<int32_t>(size.Height * static_cast<float>(dpi) / 72.0f));

      InMemoryRandomAccessStream image_stream;
      PdfPageRenderOptions options;
      options.DestinationWidth(static_cast<uint32_t>(width));
      options.DestinationHeight(static_cast<uint32_t>(height));
      page.RenderToStreamAsync(image_stream, options).get();
      image_stream.Seek(0);

      auto bitmap = DecodeBitmap(image_stream);
      if (!bitmap.has_value()) {
        continue;
      }
      auto result = engine->RecognizeAsync(*bitmap).get();
      std::string page_text = Trim(winrt::to_string(result.Text()));
      processed_pages += 1;
      if (!page_text.empty()) {
        if (!full.empty()) {
          full.append("\n\n");
        }
        full.append("[page ")
            .append(std::to_string(index + 1))
            .append("]\n")
            .append(page_text);
      }
    }

    std::string full_truncated = TruncateUtf8(full, 256 * 1024);
    std::string excerpt = TruncateUtf8(full_truncated, 8 * 1024);
    bool is_truncated =
        (processed_pages < page_count) || (full_truncated != full);

    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("ocr_text_full")] =
        flutter::EncodableValue(full_truncated);
    payload[flutter::EncodableValue("ocr_text_excerpt")] =
        flutter::EncodableValue(excerpt);
    payload[flutter::EncodableValue("ocr_engine")] =
        flutter::EncodableValue(std::string("windows_ocr"));
    payload[flutter::EncodableValue("ocr_is_truncated")] =
        flutter::EncodableValue(is_truncated);
    payload[flutter::EncodableValue("ocr_page_count")] =
        flutter::EncodableValue(static_cast<int32_t>(page_count));
    payload[flutter::EncodableValue("ocr_processed_pages")] =
        flutter::EncodableValue(static_cast<int32_t>(processed_pages));
    return payload;
  } catch (...) {
    return std::nullopt;
  }
}


}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  try {
    winrt::init_apartment(winrt::apartment_type::single_threaded);
  } catch (...) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetupOcrChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetupOcrChannel() {
  ocr_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "secondloop/ocr",
      &flutter::StandardMethodCodec::GetInstance());
  ocr_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HandleOcrMethodCall(call, std::move(result));
      });
}

void FlutterWindow::HandleOcrMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  auto maybe_bytes = ReadBytesArg(args);
  if (!maybe_bytes.has_value()) {
    result->Success(flutter::EncodableValue());
    return;
  }

  const std::string language_hints = ReadLanguageHints(args);
  const auto& method = method_call.method_name();
  if (method == "ocrImage") {
    auto payload = RunImageOcr(*maybe_bytes, language_hints);
    if (!payload.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }
    result->Success(flutter::EncodableValue(*payload));
    return;
  }

  if (method == "ocrPdf") {
    const int max_pages = ClampPositiveInt(args, "max_pages", 200, 10000);
    const int dpi = ClampPositiveInt(args, "dpi", 180, 600);
    auto payload = RunPdfOcr(*maybe_bytes, max_pages, dpi, language_hints);
    if (!payload.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }
    result->Success(flutter::EncodableValue(*payload));
    return;
  }

  if (method == "renderPdfToLongImage") {
    const auto preset = ResolvePdfRenderPreset(args);
    auto payload =
        RunPdfRenderToLongImage(*maybe_bytes, preset.max_pages, preset.dpi);
    if (!payload.has_value()) {
      result->Success(flutter::EncodableValue());
      return;
    }
    result->Success(flutter::EncodableValue(*payload));
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::OnDestroy() {
  ocr_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
