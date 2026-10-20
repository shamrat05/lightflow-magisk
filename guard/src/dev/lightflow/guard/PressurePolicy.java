package dev.lightflow.guard;

/** No Android dependency: decide whether a routine OEM cleanup may proceed. */
public final class PressurePolicy {
    private boolean pressured;
    private long stallSince = -1;
    private long previousTime = -1;
    private int stallSamples;

    public synchronized boolean allowCleanup(long now, long totalKb, long availableKb,
            long swapTotalKb, long swapFreeKb, double fullAvg10) {
        // Unknown or inconsistent observations never suppress stock recovery.
        if (now < 0 || totalKb <= 0 || availableKb < 0 || availableKb > totalKb
                || swapTotalKb < 0 || swapFreeKb < 0 || swapFreeKb > swapTotalKb
                || Double.isNaN(fullAvg10) || Double.isInfinite(fullAvg10)
                || fullAvg10 < 0 || fullAvg10 > 100) {
            stallSince = -1;
            return true;
        }
        boolean sparse = previousTime >= 0 && now - previousTime > 15_000;
        if (previousTime > now || sparse) {
            pressured = false;
            stallSince = -1;
            stallSamples = 0;
        }
        previousTime = now;

        // Match the observed stock CriticalMemThres=880 MiB on this 8 GB ROM.
        long criticalKb = 880L * 1024;
        if (availableKb <= criticalKb || fullAvg10 >= 10.0) {
            pressured = true;
            stallSince = -1;
            return true;
        }
        boolean swapNearlyFull = swapTotalKb > 0 && swapFreeKb * 100 <= swapTotalKb * 10;
        boolean stalled = availableKb < criticalKb * 3 / 2
                && (fullAvg10 >= 2.0 || swapNearlyFull);
        // With no recent observation, do not delay a new low-RAM stall on the
        // assumption that the intervening period was healthy.
        if (stalled && sparse) {
            pressured = true;
            return true;
        }
        if (stalled) {
            if (stallSince < 0) stallSince = now;
            stallSamples = Math.min(3, stallSamples + 1);
            if (stallSamples >= 3 && now - stallSince >= 10_000) pressured = true;
        } else {
            stallSince = -1;
            stallSamples = 0;
        }
        // Once recovery is needed, do not oscillate at the entry boundary.
        if (pressured && availableKb >= criticalKb * 2 && fullAvg10 < 0.5
                && !swapNearlyFull) pressured = false;
        return pressured;
    }

    public static boolean isRoutineType(String type) {
        // These exact types were verified in the current OEM DEX, not guessed.
        return "cached".equals(type) || "smart-force".equals(type);
    }
}
