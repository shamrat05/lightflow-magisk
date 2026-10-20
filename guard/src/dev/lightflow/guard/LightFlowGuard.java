package dev.lightflow.guard;

import android.os.Binder;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import java.io.FileDescriptor;
import java.io.PrintWriter;
import java.lang.reflect.Method;
import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/** Zygisk-backed ART hook using the device's existing Vector runtime. */
public final class LightFlowGuard implements IXposedHookLoadPackage {
    private static final String TAG = "LightFlowGuard";
    private static final String CALLER_EXTRA = "lightflow.diagnostic.previousCaller";
    private final PressurePolicy policy = new PressurePolicy();
    private final ThreadLocal<Integer> diagnosticCaller = new ThreadLocal<>();
    private long sampledAt = -1, reportedAt = -1, deferred, passed;
    private long errorReportedAt = -1, lastErrorAt = -1;
    private MemorySnapshot lastObservation;
    private String lastError = "none";
    private volatile int installedTargets;
    private volatile boolean diagnosticsInstalled;
    private boolean allow = true;

    @Override public void handleLoadPackage(XC_LoadPackage.LoadPackageParam load) {
        if (!"android".equals(load.packageName)) return;
        persistentInfo("bootstrap model=" + Build.MODEL + " sdk=" + Build.VERSION.SDK_INT);
        if (Build.VERSION.SDK_INT != 35 || !"RMX3741".equals(Build.MODEL)) {
            persistentInfo("skipped unsupported device; stock behavior retained");
            return;
        }
        install(load.classLoader, "com.android.server.am.OplusAthenaAmManager",
                "releaseMemory", int.class, false, 1);
        install(load.classLoader, "com.android.server.am.OplusOsenseKillAction",
                "execute", boolean.class, true, 2);
        installDiagnostics(load.classLoader);
        persistentInfo("ready installedTargets=" + installedTargets
                + "/3 diagnostics=" + diagnosticsInstalled + "; awaiting service enable");
    }

    private void install(ClassLoader loader, String name, String methodName,
            Class<?> returnType, boolean atomic, int targetBit) {
        try {
            Class<?> target = XposedHelpers.findClass(name, loader);
            Method method = target.getDeclaredMethod(methodName, Bundle.class);
            if (method.getReturnType() != returnType) throw new NoSuchMethodException("return type");
            XposedBridge.hookMethod(method, new XC_MethodHook() {
                @Override protected void beforeHookedMethod(MethodHookParam param) {
                    try {
                        Bundle request = (Bundle) param.args[0];
                        if (request == null || !PressurePolicy.isRoutineType(request.getString("type"))
                                || specialRecovery(request)) return;
                        if (atomic) {
                            for (String field : new String[]{"mQuickBoot", "mSpecialMode"}) {
                                Object state = XposedHelpers.getObjectField(param.thisObject, field);
                                if (!(state instanceof java.util.concurrent.atomic.AtomicBoolean)) return;
                                if (((java.util.concurrent.atomic.AtomicBoolean) state).get()) return;
                            }
                        }
                        String enabled = enabledProperty();
                        if (!"1".equals(enabled)) return;
                        if (!mayClean()) {
                            // Return success at the entry, before jobs/kill bookkeeping.
                            // Atomic false would trigger the alternate Athena cleaner.
                            param.setResult(atomic ? (Object) Boolean.TRUE : Integer.valueOf(0));
                        }
                    } catch (Throwable error) {
                        // Preserve the stock call and every exception it normally raises.
                        reportError(methodName, error);
                    }
                }
            });
            installedTargets |= targetBit;
            persistentInfo("installed " + name + "." + methodName + "(Bundle)");
        } catch (Throwable error) {
            installationFailure(name + "." + methodName, error);
        }
    }

    private void installDiagnostics(ClassLoader loader) {
        try {
            // AMS clears Binder identity before forwarding the Athena dump.
            // Remember only an authorized caller of this exact diagnostic.
            Class<?> ams = XposedHelpers.findClass("com.android.server.am.ActivityManagerService", loader);
            Method doDump = ams.getDeclaredMethod("doDump", FileDescriptor.class,
                    PrintWriter.class, String[].class, boolean.class);
            if (doDump.getReturnType() != void.class) throw new NoSuchMethodException("return type");
            XposedBridge.hookMethod(doDump, new XC_MethodHook() {
                @Override protected void beforeHookedMethod(MethodHookParam param) {
                    param.setObjectExtra(CALLER_EXTRA, diagnosticCaller.get());
                    diagnosticCaller.remove();
                    if (isDiagnosticArgs(param.args[2])) {
                        int uid = Binder.getCallingUid();
                        if (uid == 0 || uid == 2000) diagnosticCaller.set(uid);
                    }
                }

                @Override protected void afterHookedMethod(MethodHookParam param) {
                    Object previous = param.getObjectExtra(CALLER_EXTRA);
                    if (previous instanceof Integer) diagnosticCaller.set((Integer) previous);
                    else diagnosticCaller.remove();
                }
            });
            Class<?> target = XposedHelpers.findClass(
                    "com.android.server.am.OplusAthenaAmManager", loader);
            Method method = target.getDeclaredMethod("dumpAthena", PrintWriter.class, String[].class);
            if (method.getReturnType() != void.class) throw new NoSuchMethodException("return type");
            XposedBridge.hookMethod(method, new XC_MethodHook() {
                @Override protected void beforeHookedMethod(MethodHookParam param) {
                    if (!(param.args[0] instanceof PrintWriter) || !isDiagnosticArgs(param.args[1])) return;
                    int uid = Binder.getCallingUid();
                    Integer originalUid = diagnosticCaller.get();
                    if (uid != 0 && uid != 2000
                            && (originalUid == null || (originalUid != 0 && originalUid != 2000))) return;
                    // This diagnostic never calls either cleanup entry point.
                    param.setResult(null);
                    PrintWriter writer = (PrintWriter) param.args[0];
                    try {
                        dumpDiagnostics(writer);
                    } catch (Throwable error) {
                        writer.println("LightFlow diagnostics unavailable: " + error);
                        reportError("diagnostic", error);
                    }
                }
            });
            diagnosticsInstalled = true;
            persistentInfo("installed root/shell diagnostic: dumpsys activity athena lightflow");
        } catch (Throwable error) {
            installationFailure("dumpAthena diagnostic", error);
        }
    }

    private static boolean isDiagnosticArgs(Object value) {
        if (!(value instanceof String[])) return false;
        String[] args = (String[]) value;
        return args.length >= 2 && "athena".equals(args[0]) && "lightflow".equals(args[1]);
    }

    private void dumpDiagnostics(PrintWriter writer) {
        String observed, counters, error;
        synchronized (this) {
            counters = "routine deferred=" + deferred + " passed=" + passed;
            observed = lastObservation == null ? "none" : "elapsedMs=" + sampledAt
                    + " " + memorySummary(lastObservation)
                    + " decision=" + (allow ? "stock-recovery" : "deferred");
            error = "elapsedMs=" + lastErrorAt + " " + lastError;
        }
        writer.println("LightFlow System Guard (read-only diagnostic)");
        writer.println("installedTargets=" + installedTargets
                + " expected=3 (Athena=1 Atomic=2) diagnostics=" + diagnosticsInstalled);
        writer.println(counters);
        writer.println("lastObservation=" + observed);
        writer.println("lastError=" + error);
        try {
            writer.println("enabled=" + enabledProperty());
        } catch (Throwable failure) {
            writer.println("enabled=unavailable: " + failure);
        }
        try {
            writer.println("currentMemory=" + memorySummary(MemorySnapshot.read()));
        } catch (Throwable failure) {
            writer.println("currentMemory=unavailable: " + failure);
        }
        writer.println("policySelfCheck=" + (policySelfCheck() ? "PASS" : "FAIL")
                + " (isolated synthetic policy; no cleanup invoked)");
    }

    private static boolean policySelfCheck() {
        PressurePolicy check = new PressurePolicy();
        long totalKb = 8L * 1024 * 1024, swapKb = 5L * 1024 * 1024;
        boolean healthyDefers = !check.allowCleanup(0, totalKb, totalKb / 2,
                swapKb, swapKb, 0.0);
        boolean criticalPasses = check.allowCleanup(1000, totalKb, 800L * 1024,
                swapKb, swapKb, 0.0);
        boolean recoveredDefers = !check.allowCleanup(2000, totalKb, totalKb / 2,
                swapKb, swapKb, 0.0);
        return healthyDefers && criticalPasses && recoveredDefers;
    }

    private static String enabledProperty() {
        return (String) XposedHelpers.callStaticMethod(
                XposedHelpers.findClass("android.os.SystemProperties", null),
                "get", "sys.lightflow.guard", "0");
    }

    private static String memorySummary(MemorySnapshot sample) {
        return "totalKb=" + sample.totalKb + " availableKb=" + sample.availableKb
                + " swapTotalKb=" + sample.swapTotalKb + " swapFreeKb=" + sample.swapFreeKb
                + " fullAvg10=" + sample.fullAvg10;
    }

    private static void persistentInfo(String message) {
        Log.i(TAG, message);
        persistentLog(message);
    }

    private static void persistentLog(String message) {
        try {
            XposedBridge.log(TAG + ": " + message);
        } catch (Throwable error) {
            // A diagnostic sink must never alter cleanup or bootstrap behavior.
            Log.w(TAG, "persistent diagnostic log unavailable", error);
        }
    }

    private synchronized void installationFailure(String target, Throwable error) {
        lastErrorAt = SystemClock.elapsedRealtime();
        lastError = target + ": " + error;
        Log.e(TAG, "NOT installed: " + target + "; stock behavior retained", error);
        persistentLog("NOT installed: " + target + "; " + error);
    }

    private static boolean specialRecovery(Bundle request) {
        if (request.getBoolean("qbmode", false) || request.getBoolean("requestFromQbPolicy", false)
                || request.getInt("purposeFreeMB", -1) > 0) return true;
        for (String name : new String[]{"thirdAppPidList", "sysAppPidList"}) {
            java.util.ArrayList<Integer> pids = request.getIntegerArrayList(name);
            if (pids != null && !pids.isEmpty()) return true;
        }
        String scene = request.getString("scene");
        return scene != null && (scene.startsWith("BgLimit")
                || "SCENE_BIGAPP_RUNTIME".equals(scene)
                || "SCENE_NOTIFY_FROM_CAM".equals(scene)
                || "SCENE_BIG_APP_SWITCH".equals(scene));
    }

    private synchronized boolean mayClean() throws Exception {
        long now = SystemClock.elapsedRealtime();
        // No dumpsys, Binder queries, subprocesses, process scans or timers.
        if (sampledAt < 0 || now - sampledAt >= 1000) {
            MemorySnapshot sample = MemorySnapshot.read();
            allow = policy.allowCleanup(now, sample.totalKb, sample.availableKb,
                    sample.swapTotalKb, sample.swapFreeKb, sample.fullAvg10);
            sampledAt = now;
            lastObservation = sample;
            if (reportedAt < 0 || now - reportedAt >= 60_000) {
                persistentInfo("routine=" + (allow ? "stock-recovery" : "deferred")
                        + " availableKb=" + sample.availableKb + " fullAvg10=" + sample.fullAvg10
                        + " deferred=" + deferred + " passed=" + passed);
                reportedAt = now;
            }
        }
        if (allow) passed++; else deferred++;
        return allow;
    }

    private synchronized void reportError(String target, Throwable error) {
        long now = SystemClock.elapsedRealtime();
        lastErrorAt = now;
        lastError = target + ": " + error;
        if (errorReportedAt < 0 || now - errorReportedAt >= 60_000) {
            Log.e(TAG, "stock recovery retained after " + target + " observation failure", error);
            persistentLog("stock recovery retained after " + target + "; " + error);
            errorReportedAt = now;
        }
    }
}
