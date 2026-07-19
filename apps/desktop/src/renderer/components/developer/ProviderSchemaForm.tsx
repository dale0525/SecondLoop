import {
  Badge,
  Checkbox,
  Select,
  Text,
  TextArea,
  TextField,
} from "@radix-ui/themes";

import type {
  DeveloperConfigField,
  DeveloperProviderDescriptor,
  DeveloperSensitiveField,
} from "../../devProvidersApi";
import type { ProviderSelection } from "../../developerProjectModel";
import { updateProviderConfig } from "../../developerProjectModel";
import { useI18n } from "../../i18n/I18nProvider";

export function ProviderSchemaForm({
  descriptor,
  selection,
  onChange,
  advanced = false,
}: {
  descriptor: DeveloperProviderDescriptor;
  selection: ProviderSelection;
  onChange: (selection: ProviderSelection) => void;
  advanced?: boolean;
}): JSX.Element {
  const fields = descriptor.configuration_schema.public_fields.filter((field) => (
    field.advanced === advanced && isVisible(field, selection.publicConfig)
  ));
  if (fields.length === 0) return <></>;
  return (
    <div className="release-schema-fields">
      {fields.map((field) => (
        <SchemaField
          field={field}
          key={field.id}
          onChange={(value) => onChange(updateProviderConfig(selection, field.id, value))}
          value={selection.publicConfig[field.id]}
        />
      ))}
    </div>
  );
}

export function SensitiveSchemaFields({
  fields,
  values,
  configured,
  onChange,
}: {
  fields: readonly DeveloperSensitiveField[];
  values: Readonly<Record<string, string>>;
  configured: ReadonlySet<string>;
  onChange: (field: string, value: string) => void;
}): JSX.Element {
  const { t } = useI18n();
  return (
    <div className="release-schema-fields">
      {fields.map((field) => (
        <label className="release-field" key={field.id}>
          <span className="release-field-label">
            <Text size="2" weight="medium">{field.label}</Text>
            {field.required ? <Badge color="gray" size="1">{t("developer.release.required")}</Badge> : null}
            {configured.has(field.id) ? <Badge color="green" size="1">{t("developer.release.stored")}</Badge> : null}
          </span>
          <TextField.Root
            autoComplete="off"
            onChange={(event) => onChange(field.id, event.target.value)}
            placeholder={configured.has(field.id)
              ? t("developer.release.secretRotatePlaceholder")
              : t("developer.release.secretPlaceholder")}
            type="password"
            value={values[field.id] ?? ""}
          />
          <Text color="gray" size="1">{field.description}</Text>
        </label>
      ))}
    </div>
  );
}

function SchemaField({
  field,
  value,
  onChange,
}: {
  field: DeveloperConfigField;
  value: unknown;
  onChange: (value: unknown) => void;
}): JSX.Element {
  const { t } = useI18n();
  const label = (
    <span className="release-field-label">
      <Text size="2" weight="medium">{field.label}</Text>
      {field.required ? <Badge color="gray" size="1">{t("developer.release.required")}</Badge> : null}
    </span>
  );
  const description = <Text color="gray" size="1">{field.description}</Text>;
  if (field.field_type === "boolean") {
    return (
      <label className="release-field release-field-check">
        <Checkbox
          checked={value === true}
          onCheckedChange={(checked) => onChange(checked === true)}
        />
        <span>{label}{description}</span>
      </label>
    );
  }
  if (field.allowed_values.length > 0) {
    return (
      <label className="release-field">
        {label}
        <Select.Root
          onValueChange={(next) => onChange(next)}
          value={typeof value === "string" ? value : String(field.default_value ?? "")}
        >
          <Select.Trigger />
          <Select.Content>
            {field.allowed_values.map((option) => (
              <Select.Item key={String(option)} value={String(option)}>{labelFor(option)}</Select.Item>
            ))}
          </Select.Content>
        </Select.Root>
        {description}
      </label>
    );
  }
  if (field.field_type === "string_list"
    || field.field_type === "string_map"
    || field.field_type === "integer_map") {
    return (
      <label className="release-field">
        {label}
        <TextArea
          onChange={(event) => onChange(parseCollection(field.field_type, event.target.value))}
          placeholder={field.field_type === "string_list"
            ? t("developer.release.listPlaceholder")
            : t("developer.release.mapPlaceholder")}
          resize="vertical"
          value={formatCollection(field.field_type, value)}
        />
        {description}
      </label>
    );
  }
  return (
    <label className="release-field">
      {label}
      <TextField.Root
        min={field.field_type === "integer" ? 0 : undefined}
        onChange={(event) => onChange(field.field_type === "integer"
          ? optionalInteger(event.target.value)
          : event.target.value)}
        type={field.field_type === "integer" ? "number" : "text"}
        value={typeof value === "string" || typeof value === "number" ? String(value) : ""}
      />
      {description}
    </label>
  );
}

function isVisible(field: DeveloperConfigField, config: Record<string, unknown>): boolean {
  const condition = field.visible_when;
  return !condition || config[condition.field_id] === condition.equals;
}

function optionalInteger(value: string): number | undefined {
  if (value.trim() === "") return undefined;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : undefined;
}

function formatCollection(type: DeveloperConfigField["field_type"], value: unknown): string {
  if (type === "string_list") return Array.isArray(value) ? value.join("\n") : "";
  if (!value || typeof value !== "object" || Array.isArray(value)) return "";
  return Object.entries(value as Record<string, unknown>)
    .map(([key, item]) => `${key}=${String(item)}`)
    .join("\n");
}

function parseCollection(type: DeveloperConfigField["field_type"], value: string): unknown {
  const lines = value.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  if (type === "string_list") return lines;
  return Object.fromEntries(lines.map((line) => {
    const separator = line.indexOf("=");
    const key = separator < 0 ? line : line.slice(0, separator).trim();
    const item = separator < 0 ? "" : line.slice(separator + 1).trim();
    return [key, type === "integer_map" ? Number(item) : item];
  }));
}

function labelFor(value: unknown): string {
  return String(value).replaceAll("_", " ").replace(/^./, (letter) => letter.toUpperCase());
}
