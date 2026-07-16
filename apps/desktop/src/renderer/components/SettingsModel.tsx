import { useEffect, useState } from "react";

import { testModelConnection } from "../api";
import {
  clearSavedModelApiKey,
  initialModelSettings,
  loadModelSettings,
  saveModelSettings
} from "../modelSettings";
import { EndpointType, ModelSettings } from "../types";
import { useI18n } from "../i18n/I18nProvider";
import type { TranslationValues } from "../i18n/types";

const endpointOptions: Array<{ labelKey: string; value: EndpointType }> = [
  { labelKey: "model.responses", value: "responses" },
  { labelKey: "model.chatCompletions", value: "chat_completions" },
  { labelKey: "model.completion", value: "completion" }
];

type ConnectionStatus =
  | { key: string; values?: TranslationValues }
  | { raw: string };

export function SettingsModel(): JSX.Element {
  const { t } = useI18n();
  const [settings, setSettings] = useState<ModelSettings>(initialModelSettings);
  const [apiKeyConfigured, setApiKeyConfigured] = useState(false);
  const [connectionStatus, setConnectionStatus] = useState<ConnectionStatus>({ key: "model.notTested" });
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isTestingConnection, setIsTestingConnection] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void loadModelSettings()
      .then((snapshot) => {
        if (cancelled) return;
        setSettings(snapshot.settings);
        setApiKeyConfigured(snapshot.apiKeyConfigured);
      })
      .catch((error: unknown) => {
        if (cancelled) return;
        const message = error instanceof Error ? error.message : "Unknown error";
        setConnectionStatus({ key: "model.storageFailed", values: { message } });
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const updateSetting = <Key extends keyof ModelSettings>(
    key: Key,
    value: ModelSettings[Key]
  ) => {
    setSettings((currentSettings) => ({ ...currentSettings, [key]: value }));
  };

  const persistSettings = async (nextSettings = settings) => {
    setIsSaving(true);
    try {
      const snapshot = await saveModelSettings(nextSettings);
      setApiKeyConfigured(snapshot.apiKeyConfigured);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      setConnectionStatus({ key: "model.storageFailed", values: { message } });
    } finally {
      setIsSaving(false);
    }
  };

  const testConnection = async () => {
    setIsTestingConnection(true);
    setConnectionStatus({ key: "model.testing" });

    try {
      const snapshot = await saveModelSettings(settings);
      setApiKeyConfigured(snapshot.apiKeyConfigured);
      const response = await testModelConnection(settings);
      setConnectionStatus(
        response.message === "Connection succeeded"
          ? { key: "model.connectionSucceeded" }
          : { raw: response.message }
      );
      if (settings.apiKey) setSettings({ ...settings, apiKey: "" });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      setConnectionStatus({ key: "model.failed", values: { message } });
    } finally {
      setIsTestingConnection(false);
    }
  };

  const clearApiKey = async () => {
    setIsSaving(true);
    try {
      const snapshot = await clearSavedModelApiKey({ ...settings, apiKey: "" });
      setApiKeyConfigured(snapshot.apiKeyConfigured);
      setSettings(snapshot.settings);
      setConnectionStatus({ key: "model.keyCleared" });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      setConnectionStatus({ key: "model.storageFailed", values: { message } });
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <section className="settings-panel" aria-labelledby="settings-model-title">
      <div className="settings-panel-heading">
        <h2 id="settings-model-title">{t("model.title")}</h2>
        <p>{t("model.description")}</p>
      </div>

      <fieldset className="settings-fieldset">
        <legend>{t("model.endpointType")}</legend>
        <div className="endpoint-selector">
          {endpointOptions.map((option) => (
            <button
              aria-pressed={settings.endpointType === option.value}
              className="endpoint-option"
              key={option.value}
              disabled={isLoading || isSaving}
              onClick={() => {
                const next = { ...settings, endpointType: option.value };
                setSettings(next);
                void persistSettings(next);
              }}
              type="button"
            >
              {t(option.labelKey)}
            </button>
          ))}
        </div>
      </fieldset>

      <div className="settings-form-grid">
        <label className="settings-field">
          <span>{t("model.baseUrl")}</span>
          <input
            disabled={isLoading}
            onChange={(event) => updateSetting("baseUrl", event.target.value)}
            onBlur={() => void persistSettings()}
            type="url"
            value={settings.baseUrl}
          />
        </label>

        <label className="settings-field">
          <span>{t("model.apiKey")}</span>
          <input
            autoComplete="off"
            disabled={isLoading}
            onChange={(event) => updateSetting("apiKey", event.target.value)}
            onBlur={() => {
              if (settings.apiKey) void persistSettings();
            }}
            placeholder={apiKeyConfigured ? t("model.storedPlaceholder") : t("model.optionalPlaceholder")}
            type="password"
            value={settings.apiKey}
          />
        </label>

        <label className="settings-field">
          <span>{t("model.modelName")}</span>
          <input
            disabled={isLoading}
            onChange={(event) => updateSetting("modelName", event.target.value)}
            onBlur={() => void persistSettings()}
            type="text"
            value={settings.modelName}
          />
        </label>
      </div>

      <div className="settings-actions">
        <button
          className="settings-primary-action"
          disabled={isLoading || isTestingConnection}
          onClick={testConnection}
          type="button"
        >
          {t("model.testConnection")}
        </button>
        {apiKeyConfigured ? (
          <button
            className="settings-secondary-action"
            disabled={isLoading || isSaving || isTestingConnection}
            onClick={() => void clearApiKey()}
            type="button"
          >
            {t("model.clearStoredKey")}
          </button>
        ) : null}
        <p className="settings-secret-status" role="status">
          {isLoading
            ? t("model.loadingSecureSettings")
            : apiKeyConfigured
              ? t("model.keyStored")
              : t("model.noKeyStored")}
        </p>
        <p className="settings-status">
          {t("model.connection", {
            status: "raw" in connectionStatus
              ? connectionStatus.raw
              : t(connectionStatus.key, connectionStatus.values)
          })}
        </p>
      </div>
    </section>
  );
}
