import { fail } from "./errors.js";

function changes(result) {
  return Number(result?.meta?.changes ?? result?.changes ?? 0);
}

function rows(result) {
  return Array.isArray(result?.results) ? result.results : [];
}

function unavailable() {
  fail(503, "commerce_store_unavailable", "Subscription information is temporarily unavailable.");
}

export class CommerceStore {
  constructor(database, { appId, environment, nowSeconds = () => Math.floor(Date.now() / 1000) }) {
    this.database = database;
    this.appId = appId;
    this.environment = environment;
    this.nowSeconds = nowSeconds;
  }

  async customerForSubject(subjectRef) {
    try {
      return await this.database.prepare(`
        SELECT customer_id
        FROM commerce_subjects
        WHERE app_id = ?1 AND environment = ?2 AND subject_ref = ?3 AND status = 'active'
      `).bind(this.appId, this.environment, subjectRef).first();
    } catch {
      unavailable();
    }
  }

  async subscriptionForSubject(subjectRef, now = this.nowSeconds()) {
    try {
      const result = await this.database.prepare(`
        SELECT subscription_id, customer_id, product_id, plan_id, normalized_status,
          current_period_start, current_period_end, paid_through, provider_updated_at,
          revoked_at, projection_revision
        FROM commerce_subscriptions
        WHERE app_id = ?1 AND environment = ?2 AND subject_ref = ?3
        ORDER BY CASE
          WHEN revoked_at IS NULL
            AND normalized_status NOT IN ('expired', 'unpaid', 'refunded', 'disputed')
            AND paid_through > ?4
          THEN 0 ELSE 1
        END ASC, provider_updated_at DESC, subscription_id ASC
        LIMIT 2
      `).bind(this.appId, this.environment, subjectRef, now).all();
      return rows(result);
    } catch {
      unavailable();
    }
  }

  async subscriptionById(subscriptionId) {
    try {
      return await this.database.prepare(`
        SELECT subscription_id, subject_ref, customer_id, product_id, plan_id,
          normalized_status, current_period_start, current_period_end, paid_through,
          provider_updated_at, revoked_at, projection_revision
        FROM commerce_subscriptions
        WHERE subscription_id = ?1 AND app_id = ?2 AND environment = ?3
      `).bind(subscriptionId, this.appId, this.environment).first();
    } catch {
      unavailable();
    }
  }

  async eventById(eventId) {
    try {
      return await this.database.prepare(`
        SELECT event_id, body_hash, outcome FROM commerce_events WHERE event_id = ?1
      `).bind(eventId).first();
    } catch {
      unavailable();
    }
  }

  async recordVerification(capability) {
    if (!new Set(["signed_webhook_v1", "customer_portal_v1"]).has(capability)) {
      fail(500, "commerce_store_invalid_operation", "Subscription verification is invalid.");
    }
    try {
      await this.database.prepare(`
        INSERT INTO commerce_verifications (app_id, environment, capability, verified_at)
        VALUES (?1, ?2, ?3, ?4)
        ON CONFLICT (app_id, environment, capability) DO UPDATE SET
          verified_at = MAX(commerce_verifications.verified_at, excluded.verified_at)
      `).bind(this.appId, this.environment, capability, this.nowSeconds()).run();
    } catch {
      unavailable();
    }
  }

  async consumeNonce(subjectRef, operation, nonceHash, ttlSeconds = 300) {
    const now = this.nowSeconds();
    let results;
    try {
      results = await this.database.batch([
        this.database.prepare(`
          DELETE FROM commerce_request_nonces WHERE expires_at <= ?1
        `).bind(now),
        this.database.prepare(`
          INSERT INTO commerce_request_nonces (
            app_id, environment, subject_ref, operation, nonce_hash, created_at, expires_at
          ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
          ON CONFLICT DO NOTHING
        `).bind(this.appId, this.environment, subjectRef, operation, nonceHash, now, now + ttlSeconds),
      ]);
    } catch {
      unavailable();
    }
    if (changes(results?.[1]) !== 1) {
      fail(409, "commerce_request_replayed", "This billing request was already used.");
    }
  }

  async recordCheckout({ requestId, subjectRef, productId, planId, requestHash }) {
    const now = this.nowSeconds();
    let result;
    try {
      result = await this.database.prepare(`
        INSERT INTO commerce_checkout_requests (
          request_id, app_id, environment, subject_ref, product_id, plan_id,
          request_hash, created_at, last_attempt_at
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8)
        ON CONFLICT (request_id) DO UPDATE SET last_attempt_at = excluded.last_attempt_at
        WHERE commerce_checkout_requests.app_id = excluded.app_id
          AND commerce_checkout_requests.environment = excluded.environment
          AND commerce_checkout_requests.subject_ref = excluded.subject_ref
          AND commerce_checkout_requests.product_id = excluded.product_id
          AND commerce_checkout_requests.plan_id = excluded.plan_id
          AND commerce_checkout_requests.request_hash = excluded.request_hash
      `).bind(
        requestId,
        this.appId,
        this.environment,
        subjectRef,
        productId,
        planId,
        requestHash,
        now,
      ).run();
    } catch {
      unavailable();
    }
    if (changes(result) !== 1) {
      fail(409, "commerce_idempotency_conflict", "This billing request ID was already used.");
    }
  }

  async applyEvent(event) {
    const now = this.nowSeconds();
    const fact = event.fact;
    const hasBinding = Boolean(event.subjectRef && event.customerId);
    const revoked = fact?.revokedAt !== null && fact?.revokedAt !== undefined;
    const eventInsert = this.database.prepare(`
      INSERT INTO commerce_events (
        event_id, environment, event_type, body_hash, provider_created_at,
        processed_at, outcome, projection_revision
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
      ON CONFLICT (event_id) DO NOTHING
    `).bind(
      event.eventId,
      this.environment,
      event.eventType,
      event.bodyHash,
      event.providerCreatedAt,
      now,
      event.outcome,
      fact?.revision ?? null,
    );
    const statements = [eventInsert];
    if (hasBinding) {
      statements.push(this.database.prepare(`
        INSERT INTO commerce_subjects (
          app_id, environment, subject_ref, customer_id, status, first_seen, last_seen
        ) SELECT ?1, ?2, ?3, ?4, 'active', ?5, ?5
        WHERE EXISTS (
          SELECT 1 FROM commerce_events WHERE event_id = ?6 AND body_hash = ?7
        )
        ON CONFLICT (app_id, environment, subject_ref) DO UPDATE SET
          last_seen = excluded.last_seen
        WHERE commerce_subjects.customer_id = excluded.customer_id
          AND commerce_subjects.status = 'active'
      `).bind(
        this.appId,
        this.environment,
        event.subjectRef,
        event.customerId,
        now,
        event.eventId,
        event.bodyHash,
      ));
    }
    if (fact) {
      statements.push(this.database.prepare(`
        INSERT INTO commerce_subscriptions (
          subscription_id, app_id, environment, subject_ref, customer_id, product_id, plan_id,
          normalized_status, current_period_start, current_period_end, paid_through,
          provider_updated_at, last_paid_transaction_id, revoked_at,
          projection_revision, updated_at
        ) SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16
        WHERE EXISTS (
          SELECT 1 FROM commerce_events WHERE event_id = ?17 AND body_hash = ?18
        ) AND EXISTS (
          SELECT 1 FROM commerce_subjects
          WHERE app_id = ?2 AND environment = ?3 AND subject_ref = ?4
            AND customer_id = ?5 AND status = 'active'
        )
        ON CONFLICT (subscription_id) DO UPDATE SET
          normalized_status = excluded.normalized_status,
          current_period_start = excluded.current_period_start,
          current_period_end = excluded.current_period_end,
          paid_through = excluded.paid_through,
          provider_updated_at = excluded.provider_updated_at,
          last_paid_transaction_id = excluded.last_paid_transaction_id,
          revoked_at = excluded.revoked_at,
          projection_revision = excluded.projection_revision,
          updated_at = excluded.updated_at
        WHERE commerce_subscriptions.app_id = excluded.app_id
          AND commerce_subscriptions.environment = excluded.environment
          AND commerce_subscriptions.subject_ref = excluded.subject_ref
          AND commerce_subscriptions.customer_id = excluded.customer_id
          AND commerce_subscriptions.product_id = excluded.product_id
          AND commerce_subscriptions.plan_id = excluded.plan_id
          AND (excluded.revoked_at IS NOT NULL
            OR excluded.provider_updated_at >= commerce_subscriptions.provider_updated_at)
      `).bind(
        fact.subscriptionId,
        this.appId,
        this.environment,
        event.subjectRef,
        fact.customerId,
        fact.productId,
        fact.planId,
        fact.status,
        fact.periodStart,
        fact.periodEnd,
        fact.paidThrough,
        fact.providerUpdatedAt,
        fact.lastPaidTransactionId,
        fact.revokedAt,
        fact.revision,
        now,
        event.eventId,
        event.bodyHash,
      ));
      if (revoked) {
        statements.push(this.database.prepare(`
          INSERT INTO commerce_revocations (
            event_id, subscription_id, subject_ref, reason, effective_at
          ) SELECT ?1, ?2, ?3, ?4, ?5
          WHERE EXISTS (
            SELECT 1 FROM commerce_events WHERE event_id = ?1 AND body_hash = ?6
          )
          ON CONFLICT (event_id) DO NOTHING
        `).bind(
          event.eventId,
          fact.subscriptionId,
          event.subjectRef,
          fact.revokeReason,
          fact.revokedAt,
          event.bodyHash,
        ));
      }
    }
    try {
      await this.database.batch(statements);
      const stored = await this.eventById(event.eventId);
      if (!stored || stored.body_hash !== event.bodyHash) {
        fail(409, "commerce_event_conflict", "The webhook event conflicts with existing data.");
      }
      if (hasBinding) {
        const binding = await this.customerForSubject(event.subjectRef);
        if (!binding || binding.customer_id !== event.customerId) {
          fail(409, "commerce_subject_conflict", "The billing account binding conflicts with existing data.");
        }
      }
      return stored;
    } catch (error) {
      if (error?.code?.startsWith?.("commerce_")) throw error;
      unavailable();
    }
  }

  async reconciliationCandidates(limit = 50) {
    try {
      const result = await this.database.prepare(`
        SELECT subscription_id
        FROM commerce_subscriptions
        WHERE app_id = ?1 AND environment = ?2
          AND normalized_status NOT IN ('expired', 'unpaid', 'refunded', 'disputed')
        ORDER BY provider_updated_at ASC, subscription_id ASC
        LIMIT ?3
      `).bind(this.appId, this.environment, limit).all();
      return rows(result).map((row) => row.subscription_id);
    } catch {
      unavailable();
    }
  }
}
