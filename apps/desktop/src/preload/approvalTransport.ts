import {
  APPROVAL_REQUEST_CHANNEL,
  type ApprovalRequest,
} from "../shared/approvalRequest";

type ApprovalDecision = "approve" | "reject";

export function createApprovalTransport(
  invoke: (channel: string, request: ApprovalRequest) => Promise<unknown>,
) {
  const request = (value: ApprovalRequest) => invoke(APPROVAL_REQUEST_CHANNEL, value);
  return Object.freeze({
    principal: () => request({ operation: "principal" }),
    approval: (approvalId: string) => request({ approvalId, operation: "approval" }),
    resolve: (approvalId: string, decision: ApprovalDecision) => request({
      approvalId,
      decision,
      operation: "resolve",
    }),
  });
}
