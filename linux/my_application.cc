#include "my_application.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <optional>
#include <string>
#include <vector>
#include <unistd.h>

#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef SECONDLOOP_HAS_POPPLER
#include <poppler/glib/poppler.h>
#endif

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kOcrChannelName[] = "secondloop/ocr";

#ifdef SECONDLOOP_HAS_POPPLER
constexpr char kCommonPdfOcrPreset[] = "common_ocr_v1";
constexpr int kCommonPdfOcrMaxPages = 10000;
constexpr int kCommonPdfOcrDpi = 180;
constexpr int kPdfRenderMaxOutputWidth = 1536;
constexpr int kPdfRenderMaxOutputHeight = 20000;
constexpr int64_t kPdfRenderMaxOutputPixels = 20000000;

struct PdfRenderPreset {
  int max_pages;
  int dpi;
};

int clamp_positive_int(int value, int fallback, int upper_bound) {
  if (value <= 0) {
    value = fallback;
  }
  if (value < 1) {
    value = 1;
  }
  if (value > upper_bound) {
    value = upper_bound;
  }
  return value;
}

int read_positive_int_arg(FlValue* args, const char* key, int fallback,
                          int upper_bound) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* raw = fl_value_lookup_string(args, key);
  if (raw == nullptr) {
    return fallback;
  }
  int value = fallback;
  switch (fl_value_get_type(raw)) {
    case FL_VALUE_TYPE_INT:
      value = static_cast<int>(fl_value_get_int(raw));
      break;
    case FL_VALUE_TYPE_FLOAT:
      value = static_cast<int>(fl_value_get_float(raw));
      break;
    default:
      value = fallback;
      break;
  }
  return clamp_positive_int(value, fallback, upper_bound);
}

std::string read_string_arg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return std::string();
  }
  FlValue* raw = fl_value_lookup_string(args, key);
  if (raw == nullptr || fl_value_get_type(raw) != FL_VALUE_TYPE_STRING) {
    return std::string();
  }
  const gchar* value = fl_value_get_string(raw);
  if (value == nullptr) {
    return std::string();
  }
  return std::string(value);
}

PdfRenderPreset resolve_pdf_render_preset(FlValue* args) {
  const auto preset_id = read_string_arg(args, "ocr_model_preset");
  if (g_ascii_strcasecmp(preset_id.c_str(), kCommonPdfOcrPreset) == 0) {
    return PdfRenderPreset{
        kCommonPdfOcrMaxPages,
        kCommonPdfOcrDpi,
    };
  }

  return PdfRenderPreset{
      read_positive_int_arg(args, "max_pages", kCommonPdfOcrMaxPages, 10000),
      read_positive_int_arg(args, "dpi", kCommonPdfOcrDpi, 600),
  };
}

std::string trim_ascii(std::string text) {
  while (!text.empty() &&
         g_ascii_isspace(static_cast<guchar>(text.front())) != 0) {
    text.erase(text.begin());
  }
  while (!text.empty() &&
         g_ascii_isspace(static_cast<guchar>(text.back())) != 0) {
    text.pop_back();
  }
  return text;
}

std::string truncate_utf8(const std::string& text, size_t max_bytes) {
  if (text.size() <= max_bytes) {
    return text;
  }
  if (max_bytes == 0) {
    return std::string();
  }
  size_t end = max_bytes;
  while (end > 0 && (static_cast<unsigned char>(text[end]) & 0xC0u) == 0x80u) {
    end -= 1;
  }
  if (end == 0) {
    return std::string();
  }
  return text.substr(0, end);
}

FlValue* build_ocr_payload(const std::string& full_text, const char* engine,
                           int page_count, int processed_pages,
                           bool force_truncated) {
  const auto full = truncate_utf8(full_text, 256 * 1024);
  const auto excerpt = truncate_utf8(full, 8 * 1024);
  const bool is_truncated =
      force_truncated || full != full_text || processed_pages < page_count;

  FlValue* payload = fl_value_new_map();
  fl_value_set_string_take(payload, "ocr_text_full",
                           fl_value_new_string(full.c_str()));
  fl_value_set_string_take(payload, "ocr_text_excerpt",
                           fl_value_new_string(excerpt.c_str()));
  fl_value_set_string_take(payload, "ocr_engine", fl_value_new_string(engine));
  fl_value_set_string_take(payload, "ocr_is_truncated",
                           fl_value_new_bool(is_truncated));
  fl_value_set_string_take(payload, "ocr_page_count",
                           fl_value_new_int(page_count));
  fl_value_set_string_take(payload, "ocr_processed_pages",
                           fl_value_new_int(processed_pages));
  return payload;
}

bool has_tesseract_binary() {
  static bool checked = false;
  static bool available = false;
  if (!checked) {
    gchar* found = g_find_program_in_path("tesseract");
    available = found != nullptr;
    g_free(found);
    checked = true;
  }
  return available;
}

const uint8_t* read_bytes_arg(FlValue* args, size_t* out_len) {
  if (out_len != nullptr) {
    *out_len = 0;
  }
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* bytes_value = fl_value_lookup_string(args, "bytes");
  if (bytes_value == nullptr ||
      fl_value_get_type(bytes_value) != FL_VALUE_TYPE_UINT8_LIST) {
    return nullptr;
  }
  const size_t bytes_len = fl_value_get_length(bytes_value);
  if (bytes_len == 0) {
    return nullptr;
  }
  if (out_len != nullptr) {
    *out_len = bytes_len;
  }
  return fl_value_get_uint8_list(bytes_value);
}

std::optional<std::string> create_temp_file_path(const char* prefix) {
  gchar* template_path =
      g_strdup_printf("%s/%sXXXXXX", g_get_tmp_dir(), prefix);
  if (template_path == nullptr) {
    return std::nullopt;
  }
  const int fd = g_mkstemp(template_path);
  if (fd < 0) {
    g_free(template_path);
    return std::nullopt;
  }
  close(fd);
  std::string path(template_path);
  g_free(template_path);
  return path;
}

bool write_bytes_to_file(const std::string& path, const uint8_t* bytes,
                         size_t length) {
  if (bytes == nullptr || length == 0) {
    return false;
  }
  GError* error = nullptr;
  gboolean ok = g_file_set_contents(
      path.c_str(), reinterpret_cast<const gchar*>(bytes),
      static_cast<gssize>(length), &error);
  if (error != nullptr) {
    g_error_free(error);
  }
  return ok == TRUE;
}

bool save_pixbuf_as_png(GdkPixbuf* pixbuf, const std::string& path) {
  if (pixbuf == nullptr) {
    return false;
  }
  GError* error = nullptr;
  gboolean ok = gdk_pixbuf_save(pixbuf, path.c_str(), "png", &error, nullptr);
  if (error != nullptr) {
    g_error_free(error);
  }
  return ok == TRUE;
}

std::string resolve_tesseract_lang(const std::string& language_hints_raw) {
  std::string hints = trim_ascii(language_hints_raw);
  std::transform(hints.begin(), hints.end(), hints.begin(),
                 [](unsigned char c) {
                   return static_cast<char>(g_ascii_tolower(c));
                 });

  auto lang_for_primary_locale = []() -> std::string {
    const gchar* const* locales = g_get_language_names();
    if (locales == nullptr || locales[0] == nullptr) {
      return "eng";
    }
    std::string primary = trim_ascii(locales[0]);
    std::transform(primary.begin(), primary.end(), primary.begin(),
                   [](unsigned char c) {
                     return static_cast<char>(g_ascii_tolower(c));
                   });
    if (g_str_has_prefix(primary.c_str(), "zh")) {
      return "chi_sim+eng";
    }
    if (g_str_has_prefix(primary.c_str(), "ja")) {
      return "jpn+eng";
    }
    if (g_str_has_prefix(primary.c_str(), "ko")) {
      return "kor+eng";
    }
    if (g_str_has_prefix(primary.c_str(), "fr")) {
      return "fra+eng";
    }
    if (g_str_has_prefix(primary.c_str(), "de")) {
      return "deu+eng";
    }
    if (g_str_has_prefix(primary.c_str(), "es")) {
      return "spa+eng";
    }
    return "eng";
  };

  if (hints == "zh_en") return "chi_sim+eng";
  if (hints == "zh_strict") return "chi_sim";
  if (hints == "ja_en") return "jpn+eng";
  if (hints == "ko_en") return "kor+eng";
  if (hints == "fr_en") return "fra+eng";
  if (hints == "de_en") return "deu+eng";
  if (hints == "es_en") return "spa+eng";
  if (hints == "en") return "eng";
  if (hints.empty() || hints == "device_plus_en") {
    return lang_for_primary_locale();
  }
  return "eng";
}

std::optional<std::string> run_tesseract_file(const std::string& input_path,
                                              const std::string& language,
                                              int dpi) {
  if (!has_tesseract_binary()) {
    return std::nullopt;
  }

  std::string dpi_value = std::to_string(clamp_positive_int(dpi, 180, 600));
  gchar* argv[] = {
      const_cast<gchar*>("tesseract"),
      const_cast<gchar*>(input_path.c_str()),
      const_cast<gchar*>("stdout"),
      const_cast<gchar*>("-l"),
      const_cast<gchar*>(language.c_str()),
      const_cast<gchar*>("--dpi"),
      const_cast<gchar*>(dpi_value.c_str()),
      nullptr,
  };

  gchar* stdout_text = nullptr;
  gchar* stderr_text = nullptr;
  gint wait_status = 0;
  GError* spawn_error = nullptr;
  gboolean spawned = g_spawn_sync(
      nullptr, argv, nullptr, G_SPAWN_SEARCH_PATH, nullptr, nullptr,
      &stdout_text, &stderr_text, &wait_status, &spawn_error);
  if (!spawned) {
    if (spawn_error != nullptr) {
      g_error_free(spawn_error);
    }
    g_free(stdout_text);
    g_free(stderr_text);
    return std::nullopt;
  }

  GError* wait_error = nullptr;
  gboolean exited_ok = g_spawn_check_wait_status(wait_status, &wait_error);
  if (!exited_ok) {
    if (wait_error != nullptr) {
      g_error_free(wait_error);
    }
    g_free(stdout_text);
    g_free(stderr_text);
    return std::nullopt;
  }

  std::string text = stdout_text == nullptr ? std::string()
                                            : std::string(stdout_text);
  g_free(stdout_text);
  g_free(stderr_text);
  return trim_ascii(text);
}

GdkPixbuf* decode_image_bytes_to_pixbuf(const uint8_t* bytes, size_t bytes_len) {
  if (bytes == nullptr || bytes_len == 0) {
    return nullptr;
  }
  GdkPixbufLoader* loader = gdk_pixbuf_loader_new();
  if (loader == nullptr) {
    return nullptr;
  }

  GError* error = nullptr;
  gboolean wrote = gdk_pixbuf_loader_write(
      loader, bytes, static_cast<gsize>(bytes_len), &error);
  if (!wrote || error != nullptr) {
    if (error != nullptr) {
      g_error_free(error);
    }
    g_object_unref(loader);
    return nullptr;
  }

  gboolean closed = gdk_pixbuf_loader_close(loader, &error);
  if (!closed || error != nullptr) {
    if (error != nullptr) {
      g_error_free(error);
    }
    g_object_unref(loader);
    return nullptr;
  }

  GdkPixbuf* pixbuf = gdk_pixbuf_loader_get_pixbuf(loader);
  if (pixbuf != nullptr) {
    g_object_ref(pixbuf);
  }
  g_object_unref(loader);
  return pixbuf;
}

FlValue* run_image_ocr_with_tesseract(FlValue* args) {
  size_t bytes_len = 0;
  const uint8_t* bytes = read_bytes_arg(args, &bytes_len);
  if (bytes == nullptr || bytes_len == 0) {
    return nullptr;
  }

  g_autoptr(GdkPixbuf) pixbuf = decode_image_bytes_to_pixbuf(bytes, bytes_len);
  if (pixbuf == nullptr) {
    return nullptr;
  }

  const auto temp_path = create_temp_file_path("secondloop_img_ocr_");
  if (!temp_path.has_value()) {
    return nullptr;
  }

  if (!save_pixbuf_as_png(pixbuf, *temp_path)) {
    g_remove(temp_path->c_str());
    return nullptr;
  }

  std::string language_hints = read_string_arg(args, "language_hints");
  if (language_hints.empty()) {
    language_hints = "device_plus_en";
  }
  const auto text = run_tesseract_file(
      *temp_path, resolve_tesseract_lang(language_hints), 180);
  g_remove(temp_path->c_str());
  if (!text.has_value()) {
    return nullptr;
  }

  return build_ocr_payload(
      *text, "linux_tesseract_image", 1, 1,
      false);
}

FlValue* run_pdf_ocr_with_tesseract(FlValue* args) {
  size_t bytes_len = 0;
  const uint8_t* bytes = read_bytes_arg(args, &bytes_len);
  if (bytes == nullptr || bytes_len == 0) {
    return nullptr;
  }
  if (!has_tesseract_binary()) {
    return nullptr;
  }

  const int max_pages =
      read_positive_int_arg(args, "max_pages", 200, 10000);
  const int dpi = read_positive_int_arg(args, "dpi", 180, 600);
  std::string language_hints = read_string_arg(args, "language_hints");
  if (language_hints.empty()) {
    language_hints = "device_plus_en";
  }
  const std::string tesseract_lang = resolve_tesseract_lang(language_hints);

  gchar* pdf_buffer = static_cast<gchar*>(g_malloc(bytes_len));
  if (pdf_buffer == nullptr) {
    return nullptr;
  }
  std::memcpy(pdf_buffer, bytes, bytes_len);

  GError* error = nullptr;
  PopplerDocument* document = poppler_document_new_from_data(
      pdf_buffer, static_cast<int>(bytes_len), nullptr, &error);
  g_free(pdf_buffer);

  if (error != nullptr) {
    g_error_free(error);
    return nullptr;
  }
  if (document == nullptr) {
    return nullptr;
  }

  const int page_count = poppler_document_get_n_pages(document);
  if (page_count <= 0) {
    g_object_unref(document);
    return nullptr;
  }

  const int target_pages = std::min(page_count, max_pages);
  std::string merged_text;
  int processed_pages = 0;

  for (int index = 0; index < target_pages; ++index) {
    PopplerPage* page = poppler_document_get_page(document, index);
    if (page == nullptr) {
      continue;
    }

    double page_width = 0.0;
    double page_height = 0.0;
    poppler_page_get_size(page, &page_width, &page_height);
    if (page_width <= 0.0 || page_height <= 0.0) {
      g_object_unref(page);
      continue;
    }

    double scale = static_cast<double>(dpi) / 72.0;
    if (scale < 1.0) {
      scale = 1.0;
    }
    if (scale > 6.0) {
      scale = 6.0;
    }

    int render_width =
        std::max(1, static_cast<int>(std::llround(page_width * scale)));
    int render_height =
        std::max(1, static_cast<int>(std::llround(page_height * scale)));

    if (render_width > kPdfRenderMaxOutputWidth) {
      const double ratio =
          static_cast<double>(kPdfRenderMaxOutputWidth) /
          static_cast<double>(render_width);
      render_width = kPdfRenderMaxOutputWidth;
      render_height =
          std::max(1, static_cast<int>(std::llround(render_height * ratio)));
    }

    cairo_surface_t* page_surface = cairo_image_surface_create(
        CAIRO_FORMAT_RGB24, render_width, render_height);
    if (page_surface == nullptr ||
        cairo_surface_status(page_surface) != CAIRO_STATUS_SUCCESS) {
      if (page_surface != nullptr) {
        cairo_surface_destroy(page_surface);
      }
      g_object_unref(page);
      continue;
    }

    cairo_t* context = cairo_create(page_surface);
    cairo_set_source_rgb(context, 1.0, 1.0, 1.0);
    cairo_paint(context);

    const double scale_x = static_cast<double>(render_width) / page_width;
    const double scale_y = static_cast<double>(render_height) / page_height;
    cairo_scale(context, scale_x, scale_y);
    poppler_page_render(page, context);
    cairo_destroy(context);

    g_autoptr(GdkPixbuf) pixbuf = gdk_pixbuf_get_from_surface(
        page_surface, 0, 0, render_width, render_height);
    cairo_surface_destroy(page_surface);
    g_object_unref(page);
    if (pixbuf == nullptr) {
      continue;
    }

    const auto temp_path = create_temp_file_path("secondloop_pdf_ocr_");
    if (!temp_path.has_value()) {
      continue;
    }
    if (!save_pixbuf_as_png(pixbuf, *temp_path)) {
      g_remove(temp_path->c_str());
      continue;
    }

    const auto page_text = run_tesseract_file(*temp_path, tesseract_lang, dpi);
    g_remove(temp_path->c_str());
    if (!page_text.has_value()) {
      continue;
    }

    processed_pages += 1;
    if (!page_text->empty()) {
      if (!merged_text.empty()) {
        merged_text.append("\n\n");
      }
      merged_text.append("[page ");
      merged_text.append(std::to_string(index + 1));
      merged_text.append("]\n");
      merged_text.append(*page_text);
    }
  }

  g_object_unref(document);
  if (processed_pages <= 0) {
    return nullptr;
  }
  return build_ocr_payload(
      merged_text, "linux_tesseract_pdf", page_count, processed_pages,
      false);
}

FlValue* run_render_pdf_to_long_image(FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }

  FlValue* bytes_value = fl_value_lookup_string(args, "bytes");
  if (bytes_value == nullptr ||
      fl_value_get_type(bytes_value) != FL_VALUE_TYPE_UINT8_LIST) {
    return nullptr;
  }

  const size_t bytes_len = fl_value_get_length(bytes_value);
  if (bytes_len == 0) {
    return nullptr;
  }
  const uint8_t* bytes = fl_value_get_uint8_list(bytes_value);
  if (bytes == nullptr) {
    return nullptr;
  }

  const auto preset = resolve_pdf_render_preset(args);

  gchar* pdf_buffer = static_cast<gchar*>(g_malloc(bytes_len));
  if (pdf_buffer == nullptr) {
    return nullptr;
  }
  std::memcpy(pdf_buffer, bytes, bytes_len);

  GError* error = nullptr;
  PopplerDocument* document = poppler_document_new_from_data(
      pdf_buffer, static_cast<int>(bytes_len), nullptr, &error);
  g_free(pdf_buffer);

  if (error != nullptr) {
    g_error_free(error);
    return nullptr;
  }
  if (document == nullptr) {
    return nullptr;
  }

  const int page_count = poppler_document_get_n_pages(document);
  if (page_count <= 0) {
    g_object_unref(document);
    return nullptr;
  }

  const int target_pages = std::min(page_count, preset.max_pages);
  GPtrArray* page_surfaces =
      g_ptr_array_new_with_free_func(reinterpret_cast<GDestroyNotify>(cairo_surface_destroy));

  int output_width = 0;
  int output_height = 0;
  int processed_pages = 0;

  for (int index = 0; index < target_pages; ++index) {
    PopplerPage* page = poppler_document_get_page(document, index);
    if (page == nullptr) {
      continue;
    }

    double page_width = 0.0;
    double page_height = 0.0;
    poppler_page_get_size(page, &page_width, &page_height);
    if (page_width <= 0.0 || page_height <= 0.0) {
      g_object_unref(page);
      continue;
    }

    double scale = static_cast<double>(preset.dpi) / 72.0;
    if (scale < 1.0) {
      scale = 1.0;
    }
    if (scale > 6.0) {
      scale = 6.0;
    }

    int render_width = std::max(1, static_cast<int>(std::llround(page_width * scale)));
    int render_height =
        std::max(1, static_cast<int>(std::llround(page_height * scale)));

    if (render_width > kPdfRenderMaxOutputWidth) {
      const double ratio = static_cast<double>(kPdfRenderMaxOutputWidth) /
                           static_cast<double>(render_width);
      render_width = kPdfRenderMaxOutputWidth;
      render_height =
          std::max(1, static_cast<int>(std::llround(render_height * ratio)));
    }

    const int next_width = std::max(output_width, render_width);
    const int next_height = output_height + render_height;
    if (next_height > kPdfRenderMaxOutputHeight) {
      g_object_unref(page);
      break;
    }
    const int64_t next_pixels =
        static_cast<int64_t>(next_width) * static_cast<int64_t>(next_height);
    if (next_pixels > kPdfRenderMaxOutputPixels) {
      g_object_unref(page);
      break;
    }

    cairo_surface_t* page_surface =
        cairo_image_surface_create(CAIRO_FORMAT_RGB24, render_width, render_height);
    if (page_surface == nullptr ||
        cairo_surface_status(page_surface) != CAIRO_STATUS_SUCCESS) {
      if (page_surface != nullptr) {
        cairo_surface_destroy(page_surface);
      }
      g_object_unref(page);
      continue;
    }

    cairo_t* context = cairo_create(page_surface);
    cairo_set_source_rgb(context, 1.0, 1.0, 1.0);
    cairo_paint(context);

    const double scale_x = static_cast<double>(render_width) / page_width;
    const double scale_y = static_cast<double>(render_height) / page_height;
    cairo_scale(context, scale_x, scale_y);
    poppler_page_render(page, context);
    cairo_destroy(context);

    output_width = next_width;
    output_height = next_height;
    processed_pages += 1;
    g_ptr_array_add(page_surfaces, page_surface);
    g_object_unref(page);
  }

  g_object_unref(document);

  if (processed_pages <= 0 || output_width <= 0 || output_height <= 0) {
    g_ptr_array_unref(page_surfaces);
    return nullptr;
  }

  cairo_surface_t* merged_surface =
      cairo_image_surface_create(CAIRO_FORMAT_RGB24, output_width, output_height);
  if (merged_surface == nullptr ||
      cairo_surface_status(merged_surface) != CAIRO_STATUS_SUCCESS) {
    if (merged_surface != nullptr) {
      cairo_surface_destroy(merged_surface);
    }
    g_ptr_array_unref(page_surfaces);
    return nullptr;
  }

  cairo_t* merged_context = cairo_create(merged_surface);
  cairo_set_source_rgb(merged_context, 1.0, 1.0, 1.0);
  cairo_paint(merged_context);

  int y_offset = 0;
  for (guint index = 0; index < page_surfaces->len; ++index) {
    cairo_surface_t* page_surface =
        static_cast<cairo_surface_t*>(g_ptr_array_index(page_surfaces, index));
    if (page_surface == nullptr) {
      continue;
    }

    const int width = cairo_image_surface_get_width(page_surface);
    const int height = cairo_image_surface_get_height(page_surface);
    if (width <= 0 || height <= 0) {
      continue;
    }

    cairo_set_source_surface(merged_context, page_surface, 0.0,
                             static_cast<double>(y_offset));
    cairo_rectangle(merged_context, 0.0, static_cast<double>(y_offset),
                    static_cast<double>(width), static_cast<double>(height));
    cairo_fill(merged_context);

    y_offset += height;
    if (y_offset >= output_height) {
      break;
    }
  }
  cairo_destroy(merged_context);
  g_ptr_array_unref(page_surfaces);

  GdkPixbuf* pixbuf =
      gdk_pixbuf_get_from_surface(merged_surface, 0, 0, output_width, output_height);
  cairo_surface_destroy(merged_surface);
  if (pixbuf == nullptr) {
    return nullptr;
  }

  gchar* jpeg_buffer = nullptr;
  gsize jpeg_buffer_size = 0;
  error = nullptr;
  const gboolean encoded = gdk_pixbuf_save_to_buffer(
      pixbuf, &jpeg_buffer, &jpeg_buffer_size, "jpeg", &error, "quality", "82",
      nullptr);
  g_object_unref(pixbuf);
  if (!encoded || error != nullptr || jpeg_buffer == nullptr || jpeg_buffer_size == 0) {
    if (error != nullptr) {
      g_error_free(error);
    }
    g_free(jpeg_buffer);
    return nullptr;
  }

  FlValue* payload = fl_value_new_map();
  fl_value_set_string_take(
      payload, "image_bytes",
      fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(jpeg_buffer),
                              jpeg_buffer_size));
  fl_value_set_string_take(payload, "image_mime_type",
                           fl_value_new_string("image/jpeg"));
  fl_value_set_string_take(payload, "page_count", fl_value_new_int(page_count));
  fl_value_set_string_take(payload, "processed_pages",
                           fl_value_new_int(processed_pages));

  g_free(jpeg_buffer);
  return payload;
}
#else
FlValue* run_image_ocr_with_tesseract(FlValue* args) {
  (void)args;
  return nullptr;
}

FlValue* run_pdf_ocr_with_tesseract(FlValue* args) {
  (void)args;
  return nullptr;
}

FlValue* run_render_pdf_to_long_image(FlValue* args) {
  (void)args;
  return nullptr;
}
#endif

void ocr_method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                        gpointer user_data) {
  (void)channel;
  (void)user_data;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "renderPdfToLongImage") == 0) {
    g_autoptr(FlValue) payload = run_render_pdf_to_long_image(args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(payload));
  } else if (g_strcmp0(method, "ocrPdf") == 0) {
    g_autoptr(FlValue) payload = run_pdf_ocr_with_tesseract(args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(payload));
  } else if (g_strcmp0(method, "ocrImage") == 0) {
    g_autoptr(FlValue) payload = run_image_ocr_with_tesseract(args);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(payload));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send OCR response: %s", error->message);
  }
}

void create_channels(MyApplication* self, FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  self->ocr_channel =
      fl_method_channel_new(messenger, kOcrChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->ocr_channel,
                                            ocr_method_call_cb, self, nullptr);
}

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* ocr_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "SecondLoop");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "SecondLoop");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project,
                                                self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  create_channels(self, view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->ocr_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->ocr_channel = nullptr;
}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
