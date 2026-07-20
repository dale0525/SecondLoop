import {
  Badge,
  Button,
  Callout,
  RadioCards,
  Select,
  Spinner,
  Text,
  TextArea,
  TextField,
} from "@radix-ui/themes";
import {
  Check,
  Cloud,
  ExternalLink,
  Layers3,
  RotateCcw,
  ShieldCheck,
  WandSparkles,
} from "lucide-react";

import type {
  CloudflareAccount,
  DeveloperControlStatus,
} from "../../developerAccessApi";
import type { DeveloperProviderDescriptor } from "../../devProvidersApi";
import type { ProviderSelection } from "../../developerProjectModel";
import { useI18n } from "../../i18n/I18nProvider";

type ProviderSelections = Readonly<{
  identity: ProviderSelection;
  entitlement: ProviderSelection;
  gateway: ProviderSelection;
}>;

export function DeveloperConnectionStep({
  accounts,
  busy,
  controlStatus,
  customClientId,
  customOauth,
  customScopeCatalog,
  entitlementProviders,
  gatewayProviders,
  identityProviders,
  onCancel,
  onChooseEntitlement,
  onChooseGateway,
  onChooseIdentity,
  onConnect,
  onCustomClientId,
  onCustomOauth,
  onCustomScopeCatalog,
  onSelectAccount,
  selections,
}: {
  accounts: readonly CloudflareAccount[];
  busy: string | null;
  controlStatus: DeveloperControlStatus | null;
  customClientId: string;
  customOauth: boolean;
  customScopeCatalog: string;
  entitlementProviders: readonly DeveloperProviderDescriptor[];
  gatewayProviders: readonly DeveloperProviderDescriptor[];
  identityProviders: readonly DeveloperProviderDescriptor[];
  onCancel: () => void;
  onChooseEntitlement: (descriptor: DeveloperProviderDescriptor) => void;
  onChooseGateway: (descriptor: DeveloperProviderDescriptor) => void;
  onChooseIdentity: (descriptor: DeveloperProviderDescriptor) => void;
  onConnect: () => void;
  onCustomClientId: (value: string) => void;
  onCustomOauth: (value: boolean) => void;
  onCustomScopeCatalog: (value: string) => void;
  onSelectAccount: (accountId: string) => void;
  selections: ProviderSelections;
}): JSX.Element {
  const { t } = useI18n();
  const phase = controlStatus?.authorization.phase ?? "disconnected";
  const publicOauthAvailable = controlStatus?.authorization.publicOauthClientAvailable ?? true;
  const useCustomOauth = customOauth || !publicOauthAvailable;

  return (
    <section className="release-step-content release-connection-step">
      <header className="release-step-heading release-quick-heading">
        <span><Cloud aria-hidden="true" size={22} /></span>
        <div>
          <Badge color="blue" size="1" variant="soft">
            <WandSparkles aria-hidden="true" size={12} />
            {t("developer.release.quickSetup")}
          </Badge>
          <h2>{t("developer.release.connectionTitle")}</h2>
          <p>{t("developer.release.connectionDescription")}</p>
        </div>
      </header>

      <RecommendedStack
        controlStatus={controlStatus}
        entitlementProviders={entitlementProviders}
        gatewayProviders={gatewayProviders}
        identityProviders={identityProviders}
        selections={selections}
      />

      <div className={`release-oauth-card release-oauth-card-primary is-${phase}`}>
        <div className="release-oauth-status">
          <span className={`release-provider-status-icon ${phase === "ready" ? "is-ready" : ""}`}>
            {phase === "ready"
              ? <Check aria-hidden="true" size={18} />
              : <ExternalLink aria-hidden="true" size={18} />}
          </span>
          <div>
            <strong>{oauthTitle(phase, t)}</strong>
            <Text as="p" color="gray" size="2">{oauthHint(phase, t)}</Text>
          </div>
          <Badge color={phase === "ready" ? "green" : phase === "expired" ? "red" : "blue"}>
            {t(`developer.release.oauth.${phase}.label`)}
          </Badge>
        </div>

        {phase === "disconnected" || phase === "expired" ? (
          <>
            {!useCustomOauth ? (
              <Button className="release-oauth-primary-action" disabled={busy !== null} onClick={onConnect} size="3">
                {busy === "oauth" ? <Spinner /> : <ExternalLink aria-hidden="true" size={16} />}
                {t("developer.release.continueWithCloudflare")}
              </Button>
            ) : null}

            <details
              className="release-advanced release-oauth-advanced"
              open={!publicOauthAvailable ? true : undefined}
            >
              <summary>{t("developer.release.customOauth")}</summary>
              <Text as="p" color="gray" size="1">
                {publicOauthAvailable
                  ? t("developer.release.customOauthHint")
                  : t("developer.release.publicOauthUnavailable")}
              </Text>
              {publicOauthAvailable ? (
                <label className="release-inline-toggle">
                  <input
                    checked={useCustomOauth}
                    onChange={(event) => onCustomOauth(event.target.checked)}
                    type="checkbox"
                  />
                  <span>
                    <strong>{t("developer.release.useCustomOauth")}</strong>
                    <small>{t("developer.release.useCustomOauthHint")}</small>
                  </span>
                </label>
              ) : null}
              {useCustomOauth ? (
                <div className="release-schema-fields">
                  <label className="release-field">
                    <Text size="2" weight="medium">{t("developer.release.oauthClientId")}</Text>
                    <TextField.Root
                      onChange={(event) => onCustomClientId(event.target.value)}
                      value={customClientId}
                    />
                  </label>
                  <label className="release-field">
                    <Text size="2" weight="medium">{t("developer.release.scopeCatalog")}</Text>
                    <TextArea
                      onChange={(event) => onCustomScopeCatalog(event.target.value)}
                      placeholder="Workers Scripts Read=scope-id"
                      value={customScopeCatalog}
                    />
                    <Text color="gray" size="1">{t("developer.release.scopeCatalogHint")}</Text>
                  </label>
                  <Button disabled={busy !== null} onClick={onConnect} size="3">
                    {busy === "oauth" ? <Spinner /> : <ExternalLink aria-hidden="true" size={16} />}
                    {t("developer.release.connectCustomCloudflare")}
                  </Button>
                </div>
              ) : null}
            </details>
          </>
        ) : null}

        {phase === "awaiting_callback" ? (
          <div className="release-oauth-waiting">
            <Spinner size="3" />
            <Button color="gray" disabled={busy !== null} onClick={onCancel} variant="soft">
              {busy === "cancel-oauth" ? <Spinner /> : <RotateCcw aria-hidden="true" size={16} />}
              {t("developer.release.cancelAuthorization")}
            </Button>
          </div>
        ) : null}

        {phase === "select_account" ? (
          accounts.length === 0 ? (
            <Callout.Root color="blue" size="1">
              <Spinner />
              <Callout.Text>{t("developer.release.loadingAccounts")}</Callout.Text>
            </Callout.Root>
          ) : accounts.length === 1 ? (
            <div className="release-oauth-waiting">
              <Callout.Root color="blue" size="1">
                {busy === "account" ? <Spinner /> : <Cloud aria-hidden="true" />}
                <Callout.Text>
                  {busy === "account"
                    ? t("developer.release.bindingOnlyAccount")
                    : t("developer.release.singleAccountFound")}
                </Callout.Text>
              </Callout.Root>
              <Button
                color="gray"
                disabled={busy !== null}
                onClick={() => onSelectAccount(accounts[0].accountId)}
                variant="soft"
              >
                {busy === "account" ? <Spinner /> : <RotateCcw aria-hidden="true" size={16} />}
                {t("developer.release.retryAccountBinding")}
              </Button>
            </div>
          ) : (
            <label className="release-field">
              <Text size="2" weight="medium">{t("developer.release.cloudflareAccount")}</Text>
              <Select.Root disabled={busy !== null || accounts.length === 0} onValueChange={onSelectAccount}>
                <Select.Trigger placeholder={t("developer.release.selectAccount")} />
                <Select.Content>{accounts.map((account) => (
                  <Select.Item key={account.accountId} value={account.accountId}>
                    {account.displayName ?? account.accountId}
                  </Select.Item>
                ))}</Select.Content>
              </Select.Root>
            </label>
          )
        ) : null}

        {phase === "ready" ? (
          <div className="release-connected-account">
            <ShieldCheck aria-hidden="true" size={18} />
            <div>
              <small>{t("developer.release.cloudflareAccount")}</small>
              <strong>{controlStatus?.authorization.accountId ?? "—"}</strong>
            </div>
            <Badge color="green" variant="soft">{t("developer.release.autoConfigured")}</Badge>
          </div>
        ) : null}
      </div>

      <details className="release-advanced release-stack-advanced">
        <summary>{t("developer.release.customizeStack")}</summary>
        <Text as="p" color="gray" size="1">{t("developer.release.customizeStackHint")}</Text>
        <ProviderGroup
          label={t("developer.release.identity")}
          onChoose={onChooseIdentity}
          providers={identityProviders}
          selected={selections.identity}
        />
        <ProviderGroup
          label={t("developer.release.entitlements")}
          onChoose={onChooseEntitlement}
          providers={entitlementProviders}
          selected={selections.entitlement}
        />
        <ProviderGroup
          label={t("developer.release.gateway")}
          onChoose={onChooseGateway}
          providers={gatewayProviders}
          selected={selections.gateway}
        />
      </details>
    </section>
  );
}

function RecommendedStack({
  controlStatus,
  entitlementProviders,
  gatewayProviders,
  identityProviders,
  selections,
}: {
  controlStatus: DeveloperControlStatus | null;
  entitlementProviders: readonly DeveloperProviderDescriptor[];
  gatewayProviders: readonly DeveloperProviderDescriptor[];
  identityProviders: readonly DeveloperProviderDescriptor[];
  selections: ProviderSelections;
}): JSX.Element {
  const { t } = useI18n();
  const entries = [
    [t("developer.release.identity"), providerName(identityProviders, selections.identity)],
    [t("developer.release.entitlements"), providerName(entitlementProviders, selections.entitlement)],
    [t("developer.release.gateway"), providerName(gatewayProviders, selections.gateway)],
  ];
  return (
    <div className="release-recommended-stack">
      <span><Layers3 aria-hidden="true" size={19} /></span>
      <div>
        <strong>{t("developer.release.recommendedStack")}</strong>
        <small>{t("developer.release.recommendedStackHint")}</small>
      </div>
      <div className="release-stack-pills">
        {entries.map(([label, value]) => (
          <span key={label}><small>{label}</small><strong>{value}</strong></span>
        ))}
      </div>
      <Badge color={controlStatus?.authorization.phase === "ready" ? "green" : "blue"} variant="soft">
        <WandSparkles aria-hidden="true" size={12} /> {t("developer.release.selectedAutomatically")}
      </Badge>
    </div>
  );
}

function ProviderGroup({ label, providers, selected, onChoose }: {
  label: string;
  providers: readonly DeveloperProviderDescriptor[];
  selected: ProviderSelection;
  onChoose: (descriptor: DeveloperProviderDescriptor) => void;
}): JSX.Element {
  return (
    <div className="release-provider-group">
      <strong>{label}</strong>
      <RadioCards.Root
        aria-label={label}
        className="release-provider-cards"
        onValueChange={(id) => {
          const descriptor = providers.find((item) => item.provider_id === id);
          if (descriptor) onChoose(descriptor);
        }}
        value={selected.id}
      >
        {providers.map((provider) => (
          <RadioCards.Item key={provider.provider_id} value={provider.provider_id}>
            <div className="release-provider-choice">
              <div>
                <strong>{provider.display_name}</strong>
                <Badge color="gray" size="1">v{provider.provider_version}</Badge>
              </div>
              <Text as="p" color="gray" size="2">{provider.description}</Text>
            </div>
          </RadioCards.Item>
        ))}
      </RadioCards.Root>
    </div>
  );
}

function providerName(
  providers: readonly DeveloperProviderDescriptor[],
  selection: ProviderSelection,
): string {
  return providers.find((provider) => provider.provider_id === selection.id)?.display_name
    ?? selection.id;
}

function oauthTitle(phase: string, t: (key: string) => string): string {
  return t(`developer.release.oauth.${phase}.title`);
}

function oauthHint(phase: string, t: (key: string) => string): string {
  return t(`developer.release.oauth.${phase}.hint`);
}
