package dev.lightflow.guard;

public final class PressurePolicyTest {
    private static final long RAM = 7723008, SWAP = 5767164;
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        PressurePolicy healthy = new PressurePolicy();
        check(!healthy.allowCleanup(0, RAM, 2174000, SWAP, 1400000, 0.1), "stock target is not real pressure");
        check(!healthy.allowCleanup(1000, RAM, 2300000, SWAP, 100000, 0.1), "high swap alone must not evict");
        check(healthy.allowCleanup(2000, RAM, 800000, SWAP, 1400000, 0.0), "critical RAM must pass immediately");
        check(healthy.allowCleanup(3000, RAM, 1300000, SWAP, 1400000, 0.2), "recovery stays latched");
        check(!healthy.allowCleanup(4000, RAM, 2000000, SWAP, 1400000, 0.1), "healthy recovery clears latch");
        PressurePolicy sustained = new PressurePolicy();
        check(!sustained.allowCleanup(0, RAM, 1200000, SWAP, 1400000, 2.5), "single PSI spike must not trigger");
        check(!sustained.allowCleanup(5000, RAM, 1200000, SWAP, 1400000, 2.5), "sustained interval not reached");
        check(sustained.allowCleanup(10000, RAM, 1200000, SWAP, 1400000, 2.5), "sustained low RAM plus stalls passes");
        PressurePolicy transientPressure = new PressurePolicy();
        transientPressure.allowCleanup(0, RAM, 1200000, SWAP, 1400000, 2.5);
        transientPressure.allowCleanup(9000, RAM, 2000000, SWAP, 1400000, 0.1);
        check(!transientPressure.allowCleanup(10000, RAM, 1200000, SWAP, 1400000, 2.5), "transient streak resets");
        check(transientPressure.allowCleanup(100000, RAM, 1200000, SWAP, 1400000, 2.5), "sparse low-RAM stalls fail open");
        check(transientPressure.allowCleanup(101000, RAM, 1200000, SWAP, 1400000, 2.5), "sparse recovery stays latched on the next request");
        check(new PressurePolicy().allowCleanup(0, RAM, 2100000, SWAP, 1400000, 10.0), "severe full stalls retain recovery even with spare RAM");
        PressurePolicy invalid = new PressurePolicy();
        check(invalid.allowCleanup(0, RAM, -1, SWAP, 1000000, 0), "missing RAM fails open");
        check(invalid.allowCleanup(0, RAM, 2000000, SWAP, SWAP + 1, 0), "invalid swap fails open");
        check(invalid.allowCleanup(0, RAM, 2000000, SWAP, 1000000, Double.NaN), "missing PSI fails open");
        check(invalid.allowCleanup(0, RAM, 2000000, SWAP, 1000000, Double.POSITIVE_INFINITY), "invalid PSI fails open");
        check(PressurePolicy.isRoutineType("cached"), "cached type");
        check(PressurePolicy.isRoutineType("smart-force"), "verified4010 type");
        for (String type : new String[]{null, "external_clear", "mem_leak", "speed", "unknown", "unforbid"})
            check(!PressurePolicy.isRoutineType(type), "unrecognized request stays stock: " + type);
        System.out.println("Pressure policy scenarios passed");
    }
}
