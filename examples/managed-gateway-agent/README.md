# Managed Gateway Agent

This reference App demonstrates the `app_managed` release path. The App declares public identity, entitlement, model, and Cloudflare deployment settings, while all developer credentials stay in the trusted Host or the selected provider.

The checked-in domains and Cloudflare account ID are placeholders. Open the App with AgentWeave Developer Tools, choose the installed provider plugins, replace the required public fields, authorize Cloudflare, enter each deployment secret once, and complete plan, apply, and authenticated verification.

Packaging is intentionally blocked until verification creates `.agentweave/deployment.lock`. That file records public deployment facts and hashes only; it is local developer state and is excluded from the release artifact.

Ordinary users see the branded sign-in flow and cannot edit the model endpoint or credentials. To build a BYOK product instead, start from `examples/minimal-agent` and select `user_configurable`.
