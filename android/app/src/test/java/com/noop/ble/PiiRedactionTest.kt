package com.noop.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Strap-log PII redaction ([redactStrapLogPii]).
 *
 * Regression guard for #421: the MAC scrubber regex has exactly two capture groups (first + last
 * octet), so the replacement must reference $1/$2. A stray `$3` made `replace()` throw
 * IndexOutOfBoundsException("No group 3") the instant a raw MAC was logged — which happened the
 * moment a generic-HR strap (Polar H10 etc.) was activated, since StandardHrSource logs
 * `device.address`. The thrown exception aborted the strap's activation, so the strap never streamed.
 */
class PiiRedactionTest {

    @Test fun masksMacKeepingFirstAndLastOctet() {
        // The exact line that triggered #421 (a generic-HR strap's address being logged).
        val out = redactStrapLogPii("HR-strap: connecting to A1:B2:C3:D4:E5:F6")
        assertEquals("HR-strap: connecting to A1:••:••:••:••:F6", out)
    }

    @Test fun doesNotThrowOnAnyMac() {
        // The whole bug was a thrown exception, not a wrong string — assert it completes.
        for (mac in listOf("00:11:22:33:44:55", "AA:bb:CC:dd:EE:ff", "de:ad:be:ef:12:34")) {
            val out = redactStrapLogPii("connecting to $mac now")
            assertFalse("middle octets must be masked: $out", out.contains(mac))
        }
    }

    @Test fun masksWhoopSerial() {
        assertEquals("Discovered WHOOP <serial> (rssi -63)",
            redactStrapLogPii("Discovered WHOOP 4C1594026 (rssi -63)"))
    }

    @Test fun leavesModelNamesAndPlainTextAlone() {
        // "WHOOP 4.0" is a dotted model name, not a serial — must not be scrubbed.
        assertEquals("Auto-reconnecting to your saved WHOOP 4.0…",
            redactStrapLogPii("Auto-reconnecting to your saved WHOOP 4.0…"))
        assertEquals("Backfill: session ended — reason=HISTORY_COMPLETE",
            redactStrapLogPii("Backfill: session ended — reason=HISTORY_COMPLETE"))
    }

    /**
     * Regression for #453: a WHOOP 5/MG reconnect logs a frame line containing a MAC; redaction must
     * mask it WITHOUT throwing. The $3 bug here crashed the whole app on every Bluetooth-on reconnect.
     */
    @Test fun frameLineWithMacIsRedactedNotCrashed() {
        val out = redactStrapLogPii("handleFrame from AA:BB:CC:DD:EE:FF — 24 bytes")
        assertEquals("handleFrame from AA:••:••:••:••:FF — 24 bytes", out)
    }

    /** Defense-in-depth (#453): redaction is TOTAL — it never throws, on any input, ever. */
    @Test fun neverThrowsOnAdversarialInput() {
        val nasty = listOf(
            "", "no pii here",
            "literal dollar \$3 and \${0} and \\1 in the text",
            "AA:BB:CC:DD:EE:FF WHOOP 4C1594026 mixed $ \\ ${'$'}{",
            "x".repeat(20000),
            "00:11:22:33:44:55 ".repeat(500),
        )
        for (s in nasty) {
            // The contract is "returns a String, never throws" — assert it completes for every input.
            val out = redactStrapLogPii(s)
            assertTrue("must return a value, got null", out.isNotEmpty() || s.isEmpty())
        }
    }
}
