package com.agentweave.mobile.runtime

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidCapabilitiesTest {
  @Test
  fun androidMvpCapabilitiesContainOnlyMobileSafeCoreCapabilities() {
    val capabilities = androidMvpCapabilities()

    assertEquals(14, capabilities.size)
    assertTrue(capabilities.contains("network.http"))
    assertTrue(capabilities.contains("memory-provider"))
    assertTrue(capabilities.contains("approval-engine"))
    assertTrue(capabilities.contains("scheduler"))
    assertFalse(capabilities.contains("task-provider"))
    assertTrue(capabilities.contains("mail-connector"))
    assertTrue(capabilities.contains("host-tools"))
    assertFalse(capabilities.contains("shell.process"))
    assertFalse(capabilities.contains("browser.headless"))
  }
}
