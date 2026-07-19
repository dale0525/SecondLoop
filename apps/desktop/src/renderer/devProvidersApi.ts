import { requestServer } from "./trustedServerRequest";

export type DeveloperProviderKind = "identity" | "entitlement" | "gateway_deployment";

export type DeveloperConfigFieldType =
  | "string"
  | "integer"
  | "boolean"
  | "https_url"
  | "url"
  | "string_list"
  | "string_map"
  | "integer_map";

export type DeveloperConfigField = Readonly<{
  id: string;
  label: string;
  description: string;
  field_type: DeveloperConfigFieldType;
  required: boolean;
  default_value: unknown | null;
  allowed_values: readonly unknown[];
  minimum_length: number | null;
  maximum_length: number | null;
  advanced: boolean;
  visible_when?: Readonly<{ field_id: string; equals: string }> | null;
}>;

export type DeveloperSensitiveField = Readonly<{
  id: string;
  label: string;
  description: string;
  required: boolean;
  purpose: string;
  rotation_supported: boolean;
}>;

export type DeveloperProviderDescriptor = Readonly<{
  schema_version: number;
  package_id: string;
  provider_id: string;
  provider_version: string;
  kind: DeveloperProviderKind;
  display_name: string;
  description: string;
  documentation_url: string;
  risk_notice: string;
  platforms: readonly string[];
  capabilities: readonly string[];
  configuration_schema: Readonly<{
    schema_version: number;
    migration_version: number;
    public_fields: readonly DeveloperConfigField[];
    sensitive_fields: readonly DeveloperSensitiveField[];
    cross_field_rules?: readonly unknown[];
  }>;
  developer_authorization_schema?: Readonly<{
    schema_version: number;
    migration_version: number;
    public_fields: readonly DeveloperConfigField[];
    sensitive_fields: readonly DeveloperSensitiveField[];
    cross_field_rules?: readonly unknown[];
  }>;
}>;

export async function listDeveloperProviders(): Promise<DeveloperProviderDescriptor[]> {
  return requestServer<DeveloperProviderDescriptor[]>(
    "devProviders.list",
    undefined,
    "/dev/providers",
    { method: "GET" },
  );
}
