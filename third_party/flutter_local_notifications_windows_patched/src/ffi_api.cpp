#include <windows.h>  // <-- This must be the first Windows header
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Xml.Dom.h>

#include "ffi_api.h"
#include "plugin.hpp"
#include "utils.hpp"

using winrt::Windows::Data::Xml::Dom::XmlDocument;

bool hasPackageIdentity() {
  if (!IsWindows8OrGreater()) return false;
  uint32_t length = 0;
  int error = GetCurrentPackageFullName(&length, nullptr);
  return error != APPMODEL_ERROR_NO_PACKAGE;
}

namespace {
void deleteRegistryTreeIfExists(HKEY rootKey, const string& subKeyPath) {
  const auto result = RegDeleteTreeA(rootKey, subKeyPath.c_str());
  if (result == ERROR_FILE_NOT_FOUND || result == ERROR_PATH_NOT_FOUND) {
    return;
  }
  winrt::check_win32(result);
}

bool isIgnorableNotificationHistoryError(const winrt::hresult_error& error) {
  return error.code() == E_INVALIDARG;
}
}

NativePlugin* createPlugin() { return new NativePlugin(); }

void disposePlugin(NativePlugin* plugin) { delete plugin; }

bool init(
  NativePlugin* plugin, char* appName, char* aumId, char* guid, char* iconPath,
  NativeNotificationCallback callback
) {
  try {
    string icon;
    if (iconPath != nullptr) icon = string(iconPath);

    const auto didRegister = plugin->registerApp(aumId, appName, guid, icon, callback);
    if (!didRegister) return false;

    plugin->hasIdentity = hasPackageIdentity();
    plugin->aumid = winrt::to_hstring(aumId);
    plugin->notifier = plugin->hasIdentity
      ? ToastNotificationManager::CreateToastNotifier()
      : ToastNotificationManager::CreateToastNotifier(plugin->aumid);

    plugin->history = ToastNotificationManager::History();
    plugin->isReady = true;
    return true;
  } catch (...) {
    return false;
  }
}

bool isValidXml(char* xml) {
  XmlDocument doc = XmlDocument();
  try {
    doc.LoadXml(winrt::to_hstring(xml));
    return true;
  } catch (winrt::hresult_error error) {
    return false;
  }
}

bool showNotification(NativePlugin* plugin, int id, char* xml, NativeStringMap bindings) {
  if (!plugin->isReady) return false;
  try {
    XmlDocument doc;
    doc.LoadXml(winrt::to_hstring(xml));
    ToastNotification notification(doc);
    const auto data = dataFromMap(bindings);
    notification.Tag(winrt::to_hstring(id));
    notification.Data(data);
    plugin->notifier.value().Show(notification);
    return true;
  } catch (...) {
    return false;
  }
}

bool scheduleNotification(NativePlugin* plugin, int id, char* xml, int time) {
  if (!plugin->isReady) return false;
  try {
    XmlDocument doc;
    doc.LoadXml(winrt::to_hstring(xml));
    ScheduledToastNotification notification(doc, winrt::clock::from_time_t(time));
    notification.Tag(winrt::to_hstring(id));
    plugin->notifier.value().AddToSchedule(notification);
    return true;
  } catch (...) {
    return false;
  }
}

NativeUpdateResult updateNotification(NativePlugin* plugin, int id, NativeStringMap bindings) {
  if (!plugin->isReady) return NativeUpdateResult::failed;
  try {
    const auto tag = winrt::to_hstring(id);
    const auto data = dataFromMap(bindings);
    const auto result = plugin->notifier.value().Update(data, tag);
    return (NativeUpdateResult) result;
  } catch (...) {
    return NativeUpdateResult::failed;
  }
}

void cancelAll(NativePlugin* plugin) {
  if (!plugin->isReady) return;

  try {
    if (plugin->hasIdentity) {
      plugin->history.value().Clear();
    } else {
      plugin->history.value().Clear(plugin->aumid);
    }
  } catch (...) {
    // Keep cancellation best-effort at the FFI boundary.
  }

  try {
    for (const auto notification : plugin->notifier.value().GetScheduledToastNotifications()) {
      plugin->notifier.value().RemoveFromSchedule(notification);
    }
  } catch (...) {
    return;
  }
}

void cancelNotification(NativePlugin* plugin, int id) {
  if (!plugin->isReady) return;
  const auto tag = winrt::to_hstring(id);

  try {
    if (plugin->hasIdentity) {
      plugin->history.value().Remove(tag);
    } else {
      plugin->history.value().Remove(tag, winrt::hstring(), plugin->aumid);
    }
  } catch (const winrt::hresult_error& error) {
    if (!isIgnorableNotificationHistoryError(error)) {
      // Keep cancellation best-effort at the FFI boundary.
    }
  } catch (...) {
    // ignore history removal failures
  }

  try {
    for (const auto notification : plugin->notifier.value().GetScheduledToastNotifications()) {
      if (notification.Tag() == tag) {
        plugin->notifier.value().RemoveFromSchedule(notification);
        return;
      }
    }
  } catch (...) {
    return;
  }
}

void cleanupAumidArtifacts(char* aumid) {
  if (aumid == nullptr || aumid[0] == '\0') {
    return;
  }

  const auto targetAumid = winrt::to_hstring(aumid);
  try {
    auto history = ToastNotificationManager::History();
    history.Clear(targetAumid);

    auto notifier = ToastNotificationManager::CreateToastNotifier(targetAumid);
    for (const auto notification : notifier.GetScheduledToastNotifications()) {
      notifier.RemoveFromSchedule(notification);
    }
  } catch (...) {
    // ignore cleanup failures for legacy artifacts
  }

  try {
    deleteRegistryTreeIfExists(
      HKEY_CURRENT_USER,
      string("Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications\\Backup\\") +
        aumid
    );
  } catch (...) {
    // ignore cleanup failures for legacy artifacts
  }

  try {
    deleteRegistryTreeIfExists(
      HKEY_CURRENT_USER,
      string("Software\\Classes\\AppUserModelId\\") + aumid
    );
  } catch (...) {
    // ignore cleanup failures for legacy artifacts
  }
}

NativeNotificationDetails* getActiveNotifications(NativePlugin* plugin, int* size) {
  // TODO: Get more details here
  if (!plugin->isReady) {
    *size = 0;
    return nullptr;
  }
  try {
    const auto active = plugin->hasIdentity
      ? plugin->history.value().GetHistory()
      : plugin->history.value().GetHistory(plugin->aumid);
    vector<int> notificationIds;
    notificationIds.reserve(active.Size());
    for (const auto notification : active) {
      int notificationId = 0;
      // Legacy or foreign toast entries can carry non-integer tags.
      // Skip them instead of crashing the host process.
      if (!tryParseNotificationId(notification.Tag(), &notificationId)) {
        continue;
      }
      notificationIds.push_back(notificationId);
    }

    *size = static_cast<int>(notificationIds.size());
    if (*size == 0) {
      return nullptr;
    }

    const auto result = new NativeNotificationDetails[*size];
    for (int index = 0; index < *size; index++) {
      result[index].id = notificationIds[index];
    }
    return result;
  } catch (...) {
    *size = 0;
    return nullptr;
  }
}

NativeNotificationDetails* getPendingNotifications(NativePlugin* plugin, int* size) {
  // TODO: Get more details here
  if (!plugin->isReady) {
    *size = 0;
    return nullptr;
  }
  try {
    const auto pending = plugin->notifier.value().GetScheduledToastNotifications();
    vector<int> notificationIds;
    notificationIds.reserve(pending.Size());
    for (const auto notification : pending) {
      int notificationId = 0;
      if (!tryParseNotificationId(notification.Tag(), &notificationId)) {
        continue;
      }
      notificationIds.push_back(notificationId);
    }

    *size = static_cast<int>(notificationIds.size());
    if (*size == 0) {
      return nullptr;
    }

    const auto result = new NativeNotificationDetails[*size];
    for (int index = 0; index < *size; index++) {
      result[index].id = notificationIds[index];
    }
    return result;
  } catch (...) {
    *size = 0;
    return nullptr;
  }
}

void freeDetailsArray(NativeNotificationDetails* ptr) { delete[] ptr; }

void freeLaunchDetails(NativeLaunchDetails details) {
  if (details.payload != nullptr) delete[] details.payload;
  for (int index = 0; index < details.data.size; index++) {
    const auto pair = details.data.entries[index];
    delete pair.key;
    delete pair.value;
  }
  if (details.data.entries != nullptr) delete[] details.data.entries;
}
