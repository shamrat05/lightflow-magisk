# Ahead of Modern Time camera profile

This companion module targets the installed OEM camera package (`com.oplus.camera` on the tested realme device). It performs only a targeted `speed-profile` compilation, either from its Magisk action button or automatically after boot when the phone is charging and below 42 °C. It does not rewrite private OEM preferences, sensor calibration, thermal limits, permissions, or codec libraries.

## Balanced capture presets

These are reliable starting points for quality, smoothness, heat, and storage. The exact labels can differ in the realme camera app.

- Photos in daylight: 1× main camera, HDR Auto, AI/beauty off unless wanted, full-resolution mode only for still subjects.
- Photos at night: 1× main camera, Night mode, hold steady, avoid digital zoom and moving subjects.
- Video with motion: 1080p/60 when light is good and stabilization is needed.
- Video with detail: 4K/30 in good light when heat and storage are acceptable.
- Video in low light or long sessions: 1080p/30; it is usually cleaner, cooler, and more reliable than 4K.
- Keep stabilization enabled for handheld video; use the main 1× lens for the best low-light result.

The module cannot create sensor detail that the hardware does not capture. The best quality comes from choosing the correct lens, light level, frame rate, and stabilization mode for each shot.
