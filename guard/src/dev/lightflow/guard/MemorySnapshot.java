package dev.lightflow.guard;

import java.io.BufferedReader;
import java.io.FileReader;

/** Bounded procfs reads, performed on demand, never by a polling thread. */
final class MemorySnapshot {
    long totalKb = -1, availableKb = -1, swapTotalKb = -1, swapFreeKb = -1;
    double fullAvg10 = Double.NaN;

    static MemorySnapshot read() throws Exception {
        MemorySnapshot snapshot = new MemorySnapshot();
        try (BufferedReader reader = new BufferedReader(new FileReader("/proc/meminfo"))) {
            String line;
            for (int i = 0; i < 128 && (line = reader.readLine()) != null; i++) {
                if (line.startsWith("MemTotal:")) snapshot.totalKb = value(line);
                else if (line.startsWith("MemAvailable:")) snapshot.availableKb = value(line);
                else if (line.startsWith("SwapTotal:")) snapshot.swapTotalKb = value(line);
                else if (line.startsWith("SwapFree:")) snapshot.swapFreeKb = value(line);
            }
        }
        try (BufferedReader reader = new BufferedReader(new FileReader("/proc/pressure/memory"))) {
            String line;
            for (int i = 0; i < 8 && (line = reader.readLine()) != null; i++) {
                if (!line.startsWith("full ")) continue;
                for (String part : line.split(" +")) {
                    if (part.startsWith("avg10=")) {
                        snapshot.fullAvg10 = Double.parseDouble(part.substring(6));
                    }
                }
                break;
            }
        }
        return snapshot;
    }

    private static long value(String line) {
        return Long.parseLong(line.substring(line.indexOf(':') + 1).trim().split(" +")[0]);
    }
}
