import { Badge, Callout, RadioCards, Select, Text, TextField } from "@radix-ui/themes";
import {
  Database,
  KeyRound,
  LockKeyhole,
  Route,
  ShieldCheck,
  WandSparkles,
} from "lucide-react";

import type { DeveloperProviderDescriptor } from "../../devProvidersApi";
import {
  updateProviderConfig,
  type ManagedProjectDraft,
  type ProviderSelection,
} from "../../developerProjectModel";
import { useI18n } from "../../i18n/I18nProvider";
import { ProviderSchemaForm, SensitiveSchemaFields } from "./ProviderSchemaForm";

const OPENAI_BASE_URL = "https://api.openai.com";

export function DeveloperConfigurationStep({
  configuredSlots,
  draft,
  entitlementDescriptor,
  gatewayDescriptor,
  identityDescriptor,
  onDraft,
  onSecret,
  secretValues,
}: {
  configuredSlots: ReadonlySet<string>;
  draft: ManagedProjectDraft;
  entitlementDescriptor: DeveloperProviderDescriptor;
  gatewayDescriptor: DeveloperProviderDescriptor;
  identityDescriptor: DeveloperProviderDescriptor;
  onDraft: (draft: ManagedProjectDraft) => void;
  onSecret: (slot: string, value: string) => void;
  secretValues: Readonly<Record<string, string>>;
}): JSX.Element {
  const { t } = useI18n();
  const modelPreset = detectModelPreset(draft);
  const updateIdentity = (identity: ProviderSelection) => onDraft({
    ...draft,
    providers: { ...draft.providers, identity },
  });
  const updateGateway = (gateway: ProviderSelection) => onDraft({
    ...draft,
    providers: { ...draft.providers, gateway },
  });
  const updateEntitlement = (entitlement: ProviderSelection) => onDraft({
    ...draft,
    providers: { ...draft.providers, entitlement },
  });
  const setProfile = (field: "endpointType" | "modelName", value: string) => onDraft({
    ...draft,
    modelAccess: {
      ...draft.modelAccess,
      profile: { ...draft.modelAccess.profile, [field]: value },
    },
  });
  const chooseModelPreset = (preset: string) => {
    if (preset !== "openai") {
      let gateway = updateProviderConfig(draft.providers.gateway, "upstreamBaseUrl", "");
      gateway = updateProviderConfig(gateway, "upstreamAuthentication", "");
      onDraft({
        ...draft,
        providers: { ...draft.providers, gateway },
      });
      return;
    }
    let gateway = updateProviderConfig(
      draft.providers.gateway,
      "upstreamBaseUrl",
      OPENAI_BASE_URL,
    );
    gateway = updateProviderConfig(gateway, "upstreamAuthentication", "bearer");
    onDraft({
      ...draft,
      providers: { ...draft.providers, gateway },
      modelAccess: {
        ...draft.modelAccess,
        profile: {
          ...draft.modelAccess.profile,
          endpointType: "responses",
        },
      },
    });
  };

  return (
    <section className="release-step-content release-configuration-step">
      <header className="release-step-heading release-quick-heading">
        <span><Route aria-hidden="true" size={22} /></span>
        <div>
          <Badge color="blue" size="1" variant="soft">
            <WandSparkles aria-hidden="true" size={12} />
            {t("developer.release.defaultsApplied")}
          </Badge>
          <h2>{t("developer.release.configurationTitle")}</h2>
          <p>{t("developer.release.configurationDescription")}</p>
        </div>
      </header>

      <section className="release-config-section" aria-labelledby="release-identity-config-title">
        <SectionHeading
          description={t("developer.release.identityConnectionHint")}
          icon={<LockKeyhole aria-hidden="true" size={19} />}
          title={t("developer.release.identityConnection")}
          titleId="release-identity-config-title"
        />
        <ProviderSchemaForm
          descriptor={identityDescriptor}
          excludeFieldIds={["scopes", "redirectUri"]}
          onChange={updateIdentity}
          selection={draft.providers.identity}
        />
        <details className="release-advanced release-auto-fields">
          <summary>{t("developer.release.automaticLoginSettings")}</summary>
          <Text as="p" color="gray" size="1">{t("developer.release.automaticLoginSettingsHint")}</Text>
          <ProviderSchemaForm
            descriptor={identityDescriptor}
            fieldIds={["scopes", "redirectUri"]}
            onChange={updateIdentity}
            selection={draft.providers.identity}
          />
          <ProviderSchemaForm
            advanced
            descriptor={identityDescriptor}
            onChange={updateIdentity}
            selection={draft.providers.identity}
          />
        </details>
      </section>

      <section className="release-config-section" aria-labelledby="release-model-service-title">
        <SectionHeading
          description={t("developer.release.modelServiceHint")}
          icon={<KeyRound aria-hidden="true" size={19} />}
          title={t("developer.release.modelService")}
          titleId="release-model-service-title"
        />
        <RadioCards.Root
          className="release-model-presets"
          onValueChange={chooseModelPreset}
          value={modelPreset}
        >
          <RadioCards.Item value="openai">
            <PresetChoice
              badge={t("developer.release.oneClickPreset")}
              description={t("developer.release.openAiPresetHint")}
              title={t("developer.release.openAiPreset")}
            />
          </RadioCards.Item>
          <RadioCards.Item value="custom">
            <PresetChoice
              description={t("developer.release.customModelPresetHint")}
              title={t("developer.release.customModelPreset")}
            />
          </RadioCards.Item>
        </RadioCards.Root>

        {modelPreset === "openai" ? (
          <div className="release-autofill-note">
            <ShieldCheck aria-hidden="true" size={18} />
            <div>
              <strong>{t("developer.release.endpointAutofilled")}</strong>
              <code>{OPENAI_BASE_URL}</code>
            </div>
          </div>
        ) : (
          <ProviderSchemaForm
            descriptor={gatewayDescriptor}
            fieldIds={["upstreamBaseUrl", "upstreamAuthentication"]}
            onChange={updateGateway}
            selection={draft.providers.gateway}
          />
        )}

        <div className="release-schema-fields release-two-columns">
          <label className="release-field">
            <Text size="2" weight="medium">{t("developer.release.endpointType")}</Text>
            <Select.Root
              onValueChange={(value) => setProfile("endpointType", value)}
              value={draft.modelAccess.profile.endpointType}
            >
              <Select.Trigger />
              <Select.Content>
                <Select.Item value="responses">Responses API</Select.Item>
                <Select.Item value="chat_completions">Chat Completions</Select.Item>
                <Select.Item value="completion">Completions</Select.Item>
              </Select.Content>
            </Select.Root>
          </label>
          <label className="release-field">
            <span className="release-field-label">
              <Text size="2" weight="medium">{t("developer.release.modelName")}</Text>
              <Badge color="gray" size="1">{t("developer.release.required")}</Badge>
            </span>
            <TextField.Root
              aria-invalid={!draft.modelAccess.profile.modelName.trim()}
              onChange={(event) => setProfile("modelName", event.target.value)}
              placeholder={t("developer.release.modelNamePlaceholder")}
              required
              value={draft.modelAccess.profile.modelName}
            />
            {!draft.modelAccess.profile.modelName.trim() ? (
              <Text color="red" role="alert" size="1">
                {t("developer.release.modelNameRequired")}
              </Text>
            ) : null}
          </label>
        </div>

        <details className="release-advanced">
          <summary>{t("developer.release.gatewaySafetyDefaults")}</summary>
          <ProviderSchemaForm
            descriptor={gatewayDescriptor}
            fieldIds={["maxBodyBytes", "maxOutputTokens"]}
            onChange={updateGateway}
            selection={draft.providers.gateway}
          />
          <ProviderSchemaForm
            advanced
            descriptor={gatewayDescriptor}
            onChange={updateGateway}
            selection={draft.providers.gateway}
          />
        </details>
      </section>

      <section className="release-config-section" aria-labelledby="release-entitlement-title">
        <SectionHeading
          description={t("developer.release.entitlementServiceHint")}
          icon={<Database aria-hidden="true" size={19} />}
          title={t("developer.release.entitlementService")}
          titleId="release-entitlement-title"
        />
        <ProviderSchemaForm
          descriptor={entitlementDescriptor}
          onChange={updateEntitlement}
          selection={draft.providers.entitlement}
        />
        <ProviderSchemaForm
          advanced
          descriptor={entitlementDescriptor}
          onChange={updateEntitlement}
          selection={draft.providers.entitlement}
        />
      </section>

      <section className="release-config-section release-secret-section" aria-labelledby="release-secrets-title">
        <SectionHeading
          description={t("developer.release.secretsHint")}
          icon={<ShieldCheck aria-hidden="true" size={19} />}
          title={t("developer.release.secrets")}
          titleId="release-secrets-title"
        />
        <Callout.Root color="gray" size="1">
          <KeyRound aria-hidden="true" />
          <Callout.Text>{t("developer.release.secretManualReason")}</Callout.Text>
        </Callout.Root>
        <div className="release-secret-grid">
          <SensitiveSchemaFields
            configured={configuredSlots}
            fields={gatewayDescriptor.configuration_schema.sensitive_fields.map((field) => ({
              ...field,
              id: `gateway.${field.id}`,
            }))}
            onChange={onSecret}
            values={secretValues}
          />
          <SensitiveSchemaFields
            configured={configuredSlots}
            fields={entitlementDescriptor.configuration_schema.sensitive_fields.map((field) => ({
              ...field,
              id: `entitlement.${field.id}`,
            }))}
            onChange={onSecret}
            values={secretValues}
          />
        </div>
      </section>
    </section>
  );
}

function SectionHeading({
  description,
  icon,
  title,
  titleId,
}: {
  description: string;
  icon: JSX.Element;
  title: string;
  titleId: string;
}): JSX.Element {
  return (
    <header className="release-config-section-heading">
      <span>{icon}</span>
      <div><h3 id={titleId}>{title}</h3><p>{description}</p></div>
    </header>
  );
}

function PresetChoice({
  badge,
  description,
  title,
}: {
  badge?: string;
  description: string;
  title: string;
}): JSX.Element {
  return (
    <div className="release-preset-choice">
      <div>
        <strong>{title}</strong>
        {badge ? <Badge color="blue" size="1" variant="soft">{badge}</Badge> : null}
      </div>
      <Text as="p" color="gray" size="2">{description}</Text>
    </div>
  );
}

function detectModelPreset(draft: ManagedProjectDraft): "openai" | "custom" {
  return draft.providers.gateway.publicConfig.upstreamBaseUrl === OPENAI_BASE_URL
    && draft.providers.gateway.publicConfig.upstreamAuthentication === "bearer"
    ? "openai"
    : "custom";
}
