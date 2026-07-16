import type {
  FoundationMailConfiguration,
  FoundationMailConfigurationInput,
} from "../shared/sidecarApi";
import { requestServer } from "./trustedServerRequest";

export type {
  FoundationMailConfiguration,
  FoundationMailConfigurationInput,
  FoundationMailTlsMode,
} from "../shared/sidecarApi";

export async function listMailAccountConfigurations(): Promise<FoundationMailConfiguration[]> {
  return requestServer(
    "mail.configuration.list",
    undefined,
    "/foundation/mail/account-configurations",
    { method: "GET" },
  );
}

export async function getMailAccountConfiguration(
  id: string,
): Promise<FoundationMailConfiguration> {
  return requestServer(
    "mail.configuration.get",
    { id },
    `/foundation/mail/account-configurations/${encodeURIComponent(id)}`,
    { method: "GET" },
  );
}

export async function putMailAccountConfiguration(
  input: FoundationMailConfigurationInput,
): Promise<FoundationMailConfiguration> {
  const { id, ...body } = input;
  return requestServer(
    "mail.configuration.put",
    input,
    `/foundation/mail/account-configurations/${encodeURIComponent(id)}`,
    { body: JSON.stringify(body), method: "PUT" },
  );
}

export async function deleteMailAccountConfiguration(
  id: string,
): Promise<{ deleted: boolean }> {
  return requestServer(
    "mail.configuration.delete",
    { id },
    `/foundation/mail/account-configurations/${encodeURIComponent(id)}`,
    { method: "DELETE" },
  );
}
