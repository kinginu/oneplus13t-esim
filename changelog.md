## v0.3 (2026-08-20)

* Complete rework: exposes the native eSIM management entry by setting ro.vendor.oplus.esim.support=2 (system.prop + resetprop fallback), the actual gate in OplusSimSettings (EuiccDemand.getEsimDisplayType).
* Removed the old esim ndk -> eid bind mount; the stock esim HAL must run untouched (requires oneplus13t-fix-camera with the eSIM HAL fix).
* Added docs/: SN220U hardware analysis and the removable-eUICC (eSTK.me) native-setup guide, including the stock-LPA download limitation.

## 0.2 (2025-06-15)

- Fixed github workflow.