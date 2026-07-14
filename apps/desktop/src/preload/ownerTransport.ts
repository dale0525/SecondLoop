import {
  OWNER_REQUEST_CHANNEL,
  type OwnerIpcRequest,
  type OwnerOperation,
} from "../shared/ownerRequest";

type OwnerTransportOptions = {
  invoke(channel: string, request: OwnerIpcRequest): Promise<unknown>;
};

export { normalizeOwnerRequest } from "../shared/ownerRequest";

export function createOwnerTransport({ invoke }: OwnerTransportOptions) {
  const request = (operation: OwnerOperation, input?: unknown) => invoke(
    OWNER_REQUEST_CHANNEL,
    { operation, ...(input === undefined ? {} : { input }) },
  );
  return Object.freeze({
    principal: () => request("principal"),
    listSkills: () => request("listSkills"),
    skillDetail: (packageId: string) => request("skillDetail", { packageId }),
    createDraft: (draft: unknown) => request("createDraft", { draft }),
    updateDraft: (revisionId: string, files: unknown) => request("updateDraft", { files, revisionId }),
    validateDraft: (revisionId: string) => request("validateDraft", { revisionId }),
    requestActivation: (revisionId: string) => request("requestActivation", { revisionId }),
    rollback: (packageId: string, revisionId: string) => request("rollback", { packageId, revisionId }),
    disable: (packageId: string) => request("disable", { packageId }),
    requestRemoval: (packageId: string) => request("requestRemoval", { packageId }),
  });
}
