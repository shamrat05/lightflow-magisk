package dev.lightflow.guard;

import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import java.lang.reflect.Method;
import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/** Zygisk-backed ART hook using the device's existing Vector runtime. */
public final class LightFlowGuard implements IXposedHookLoadPackage {
    private static final String TAG = "LightFlowGuard";
    private final PressurePolicy policy = new PressurePolicy();
    private long sampledAt = -1, reportedAt = -1, deferred, passed;
    private boolean allow = true;

    @Override public void handleLoadPackage(XC_LoadPackage.LoadPackageParam load) {
        if (!"android".equals(load.packageName) || Build.VERSION.SDK_INT != 35
                || !"RMX3741".equals(Build.MODEL)) return;
        install(load.classLoader, "com.android.server.am.OplusAthenaAmManager",
                "releaseMemory", int.class, false);
        install(load.classLoader, "com.android.server.am.OplusOsenseKillAction",
                "execute", boolean.class, true);
    }

    private void install(ClassLoader loader, String name, String methodName,
            Class<?> returnType, boolean atomic) {
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
                        String enabled = (String) XposedHelpers.callStaticMethod(
                                XposedHelpers.findClass("android.os.SystemProperties", null),
                                "get", "sys.lightflow.guard", "0");
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
            Log.i(TAG, "installed " + name + "." + methodName + "(Bundle); awaiting service enable");
        } catch (Throwable error) {
            Log.e(TAG, "NOT installed: " + name + "." + methodName + "; stock behavior retained", error);
        }
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
            if (reportedAt < 0 || now - reportedAt >= 60_000) {
                Log.i(TAG, "routine=" + (allow ? "stock-recovery" : "deferred")
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
        if (reportedAt < 0 || now - reportedAt >= 60_000) {
            Log.e(TAG, "stock recovery retained after " + target + " observation failure", error);
            reportedAt = now;
        }
    }
}
