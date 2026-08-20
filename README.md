# OnePlus 13T eSIM Settings Enabler (OxygenOS)

A Magisk/KernelSU module that exposes the native **eSIM management entry**
(Settings > Mobile network > SIM & eSIM settings > eSIM) on a OnePlus 13T
converted to OxygenOS (13s firmware).

Works with the 13T's internal eUICC as well as eUICC-enabled physical SIM
cards (5ber, eSTK.me, etc.).

<a href="https://www.buymeacoffee.com/kinginu" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 220px !important;" ></a>

## Background

The OxygenOS 13s builds already ship the entire AOSP/Google eSIM stack:
the `android.hardware.telephony.euicc` feature is declared in
`/my_product/etc/permissions/com.oplus.android-features.xml`, the Google LPA
(`com.google.android.euicc`, EuiccGoogle) is preinstalled as a privileged
product app, and `EuiccController` is up. The stack is fully functional —
`am start -a android.telephony.euicc.action.MANAGE_EMBEDDED_SUBSCRIPTIONS`
opens the LPA and reaches the QR download screen.

The only thing missing is the Settings UI entry. OplusSimSettings
(in TeleService / `com.android.phone`) gates the "eSIM" preference on the
vendor prop `ro.vendor.oplus.esim.support` (`EuiccDemand.getEsimDisplayType`):

| value | meaning |
|-------|---------|
| 0 / undefined | entry hidden (OxygenOS 13s default) |
| 1 | eSIM shares the SIM2 slot via GPIO switching (ColorOS 13T style) |
| 2 | independent eUICC, no slot sharing |

This module simply sets `ro.vendor.oplus.esim.support=2` via `system.prop`
(with a `resetprop` fallback in `post-fs-data.sh`). No files are mounted.

## Requirements

- OnePlus 13T converted to OxygenOS (13s), rooted (Magisk or KernelSU).
- **[oneplus13t-fix-camera](https://github.com/kinginu/oneplus13t-fix-camera)
  with the eSIM HAL fix** (the version that no longer masks
  `vendor.oplus.hardware.esim@1.0-service` with the eid binary).
  The Settings enable flow talks to the stock `IOplusEsim` HAL; older
  fix-camera versions bind-mounted a replacement binary from /data, which
  init can never exec (`nosuid_transition` denial), leaving the HAL in a
  crash loop and the eSIM screen stuck on "Enabling...".

## Notes

- If the eSIM toggle ever misbehaves with `2`, try `1` (GPIO switching
  variant used by ColorOS on the 13T).
- If a future OxygenOS update defines `ro.vendor.oplus.esim.support` by
  itself, this module becomes unnecessary.
