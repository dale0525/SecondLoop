package com.agentweave.mobile.runtime

fun androidMvpCapabilities(): List<String> =
  listOf(
    "network.http",
    "filesystem.app_data",
    "secure_storage",
    "model.http_provider",
    "memory-provider",
    "provenance",
    "retention-policy",
    "reversible-history",
    "durable-actions",
    "approval-engine",
    "credential-vault",
    "mail-connector",
    "scheduler",
    "host-tools",
  )
