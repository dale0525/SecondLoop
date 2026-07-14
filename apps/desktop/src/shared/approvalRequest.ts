export const APPROVAL_REQUEST_CHANNEL = "agentweave:approval:request";

export type ApprovalRequest = Readonly<{
  approvalId?: string;
  decision?: "approve" | "reject";
  operation: "approval" | "principal" | "resolve";
}>;
