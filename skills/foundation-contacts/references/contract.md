# Contacts Connector v1

Resolve returns bounded candidates with stable contact IDs, display names, typed channel identities, optional organization, relationship context, provider reference, and version.

The v1 tool contract is:

- `contacts_resolve` returns bounded candidates and never chooses among ambiguous matches.
- `contact_get` reads one authoritative record and optimistic version.
- `contact_update_preview` canonicalizes a version-checked replacement without changing provider state.
- `contact_update_apply` applies one approved immutable preview.

Downstream Mail, Calendar, and Messaging actions must bind the selected stable identity. A display name alone is not a resolved recipient.

Contact mutation uses an immutable preview and optimistic version. Externally visible or synchronized changes require host approval.

The Host persists an update as a `contacts.contact.update` Foundation Action. Its envelope binds the connector and operation, account, stable contact ID, expected version, idempotency key, canonical replacement, payload hash, and approval details. Only the Host may exchange an approved envelope for a one-shot `contact_update_apply` grant.

App, tenant, and user scope comes from trusted Host context. A model-supplied account ID must match the account selected by that context when one is present. Provider IDs are preserved by the connector and cannot be replaced by model arguments. Reusing an idempotency key with different replacement data fails closed.

The host owns account scope, credentials, privacy policy, authorization, synchronization, and audit.
