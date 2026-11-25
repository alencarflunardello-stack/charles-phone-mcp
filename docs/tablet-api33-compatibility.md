# API 33 compatibility checkpoint
The real Samsung SM-T875 (Android 13/API 33) connected to the 0.19.1 relay but both app launch and parallel recovery failed. The manifest minimum (30) is not the separate-session minimum. SessionEngineManager.start and VirtualEngine.startInternal both require API 34; VirtualEngine also verifies a trusted owned display group and independent keyguard. The same source requires per-display task ownership and gesture guards. Do not lower the guards to make an eligibility check pass. Do not fall back to primary display.

Use `python3 scripts/check-isolation-compatibility.py --device-api 33 --require-separate` before any new tablet distribution. The current baseline must exit 1. An API-eligible result is not real-device certification. The owner build at a0733689 remains a historical signed baseline, not a working Android 13 isolated engine.

## CP-034 / CP-035 — no new third-party installation
The owner rejected another series of experimental third-party installations. Agent-VScreen and Virtual Screen are research references only. Do not install, connect or distribute them as part of this migration.

### Pinned AOSP source comparison
Compared the complete DisplayManager.java, Display.java, DisplayContent.java, RootWindowContainer.java and config.xml sources at the android-13.0.0_r24 and android-14.0.0_r1 tags of aosp-mirror/platform_frameworks_base. Android 13 contains trusted displays, own display groups and secondary-display activity support, but lacks the per-virtual-display OWN_FOCUS and STEAL_TOP_FOCUS_DISABLED flags used by the existing VirtualEngine. Android 14 defines both and implements corresponding focus policy in DisplayContent. Both source tags default the older device-wide config_perDisplayFocusEnabled resource to false.

Sources:
- https://github.com/aosp-mirror/platform_frameworks_base/blob/android-13.0.0_r24/core/java/android/hardware/display/DisplayManager.java
- https://github.com/aosp-mirror/platform_frameworks_base/blob/android-14.0.0_r1/core/java/android/hardware/display/DisplayManager.java
- https://github.com/aosp-mirror/platform_frameworks_base/blob/android-14.0.0_r1/services/core/java/com/android/server/wm/DisplayContent.java
- https://github.com/aosp-mirror/platform_frameworks_base/blob/android-13.0.0_r24/core/res/res/values/config.xml
- https://source.android.com/docs/core/display/multi_display/displays

This comparison is evidence of a framework difference, not a test of Samsung's firmware. The real SM-T875 is blocked by the current engine's API guards. Removing the guards or setting unknown numeric flags would not provide evidence of focus isolation. Android's documentation specifically cautions against enabling the legacy global multi-focus configuration on ordinary devices. Do not alter that configuration, the ROM, lock-screen policy or primary-screen routing.

### Decision
Preserve the signed installed APK, the authenticated plugin, and the relay. Do not start a new build merely to change the version check. Native isolated operation remains blocked until a supported device capability equivalent to independent focus and no focus theft is demonstrated. Any future candidate needs device-specific evidence, synthetic local foreground-input and secondary-display isolation testing, explicit local stop, cleanup, and no fallback to the primary display. A static SDK check is not that evidence. Existing structured connectors may satisfy individual non-Android tasks without installing another device-control application. No functional port is claimed.
