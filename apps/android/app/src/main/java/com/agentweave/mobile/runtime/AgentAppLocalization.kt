package com.agentweave.mobile.runtime

import android.content.Context
import java.io.File
import org.json.JSONObject

data class AgentAppLocale(
  val id: String,
  val label: String,
  val messages: Map<String, String>,
)

data class AgentAppLocalization(
  val defaultLocale: String,
  val locales: List<AgentAppLocale>,
) {
  fun admittedLocale(localeId: String?): String =
    localeId?.takeIf { candidate -> locales.any { it.id.equals(candidate, ignoreCase = true) } }
      ?.let { candidate -> locales.first { it.id.equals(candidate, ignoreCase = true) }.id }
      ?: defaultLocale

  fun strings(localeId: String?): AppStrings {
    val locale = locales.firstOrNull { it.id == admittedLocale(localeId) } ?: locales.first()
    return AppStrings(locale.id, locale.messages)
  }
}

data class AppStrings(
  val locale: String,
  val messages: Map<String, String>,
) {
  fun text(key: String, values: Map<String, Any> = emptyMap()): String {
    val message = messages[key] ?: key
    return PLACEHOLDER.replace(message) { match ->
      values[match.groupValues[1]]?.toString() ?: match.value
    }
  }
}

class AndroidAgentAppLocalizationStore(private val context: Context) {
  val localization: AgentAppLocalization by lazy {
    AgentAppLocalizationLoader.load(installedAgentAppRoot(context.filesDir)) { locale ->
      runCatching {
        context.assets.open("i18n/host/$locale.json")
          .bufferedReader(Charsets.UTF_8)
          .use { it.readText() }
      }.getOrNull()
    }
  }

  fun selectedLocale(): String {
    val saved = preferences().getString(LOCALE_PREFERENCE, null)
    if (saved != null) return localization.admittedLocale(saved)
    return localization.defaultLocale
  }

  fun selectLocale(localeId: String): Boolean {
    if (localization.locales.none { it.id == localeId }) return false
    return preferences().edit().putString(LOCALE_PREFERENCE, localeId).commit()
  }

  private fun preferences() =
    context.getSharedPreferences(LOCALIZATION_PREFERENCES, Context.MODE_PRIVATE)
}

object AgentAppLocalizationLoader {
  fun load(
    installedRoot: File?,
    hostCatalog: (String) -> String?,
  ): AgentAppLocalization {
    val english = parseCatalog(hostCatalog("en"))
    val root = installedRoot?.takeIf(File::isDirectory)
    val manifest = root?.resolve("agent-app.json")
      ?.takeIf(File::isFile)
      ?.let { file -> runCatching { JSONObject(file.readText(Charsets.UTF_8)) }.getOrNull() }
    val localization = manifest?.optJSONObject("localization")
    val entries = localization?.optJSONArray("locales")
    val configured = if (entries == null) {
      listOf(
        Triple("en", "English", null),
        Triple("zh-CN", "简体中文", null),
      )
    } else {
      (0 until entries.length()).mapNotNull { index ->
        val entry = entries.optJSONObject(index) ?: return@mapNotNull null
        val id = entry.optString("id").takeIf(String::isNotBlank) ?: return@mapNotNull null
        val label = entry.optString("label").takeIf(String::isNotBlank) ?: id
        val resource = entry.optString("resource").takeIf(String::isNotBlank)
        Triple(id, label, resource)
      }
    }
    val locales = configured.map { (id, label, resource) ->
      val appMessages = if (root != null && resource != null) {
        confinedLocaleFile(root, resource)?.let { parseCatalog(it.readText(Charsets.UTF_8)) }.orEmpty()
      } else {
        emptyMap()
      }
      AgentAppLocale(
        id = id,
        label = label,
        messages = english + parseCatalog(hostCatalog(canonicalHostLocale(id))) + appMessages,
      )
    }.ifEmpty { listOf(AgentAppLocale("en", "English", english)) }
    val requestedDefault = localization?.optString("defaultLocale")?.takeIf(String::isNotBlank)
    val defaultLocale = requestedDefault?.takeIf { id -> locales.any { it.id == id } } ?: locales.first().id
    return AgentAppLocalization(defaultLocale, locales)
  }

  private fun parseCatalog(json: String?): Map<String, String> {
    val document = json?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return emptyMap()
    return document.keys().asSequence().mapNotNull { key ->
      document.optString(key).takeIf(String::isNotBlank)?.let { value -> key to value }
    }.toMap()
  }

  private fun confinedLocaleFile(root: File, relativePath: String): File? = runCatching {
    val canonicalRoot = root.canonicalFile
    val localesRoot = canonicalRoot.resolve("locales").canonicalFile
    canonicalRoot.resolve(relativePath).canonicalFile.takeIf { file ->
      file.isFile && file.toPath().startsWith(localesRoot.toPath())
    }
  }.getOrNull()

  private fun canonicalHostLocale(locale: String): String = when (locale.lowercase()) {
    "zh-cn" -> "zh-CN"
    else -> locale.substringBefore('-').lowercase()
  }
}

private val PLACEHOLDER = Regex("\\{([A-Za-z][A-Za-z0-9_]*)\\}")
private const val LOCALIZATION_PREFERENCES = "agentweave.localization.v1"
private const val LOCALE_PREFERENCE = "locale"
