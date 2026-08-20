# eSIM on the OnePlus 13T (OxygenOS conversion) — hardware & software analysis

This document records what the internal eSIM stack of the OnePlus 13T
(China, `PKX110` / `CPH2723`) actually is, why the internal eUICC does not
work after converting to OxygenOS (13s firmware), and what the practical
alternatives are. It is written from on-device investigation on a rooted
unit plus public sources. Findings are tagged **[device]** (observed on the
unit) or **[public]** (external source, cited) so they can be re-verified.

## TL;DR

- The eSIM silicon is part of the **NXP SN220U**, a single-chip
  **NFC controller + secure element + eUICC** combo. The chip is
  physically present (NFC works), so this is not a "no hardware at all"
  situation. **[device] [public]**
- The **AP/ROM-side** software gates (feature flag, Google LPA, privileged
  permissions, the Settings entry) can all be added from a Magisk/KernelSU
  module — that is what this repo does.
- The **internal eUICC still does not come online**: when the OPPO eSIM
  toggle flips the GPIO mux to route the SIM2 line to the internal eUICC,
  the modem reads the card and gets `CARDSTATE_ABSENT` with an empty
  ATR/EID. **[device]**
- Public reports show the same class of failure on **China OnePlus models
  flashed to global ROM** — the internal eUICC behaves "as if removed."
  This points to the eUICC being disabled/unprovisioned **below the AP**
  (modem firmware / NV, or a CN-board SN220 variant that is not
  personalized with an EID + keys), which **no AP-side module can fix.**
  **[public]**
- **Removable eUICC cards (eSTK.me / 5ber / 9eSIM) are the working path.**
  EasyEUICC installs profiles today. Stock-Settings management is possible
  if the card advertises the eUICC capability in its **ATR**.

## The hardware: NXP SN220U

**[public]** NXP's SN220 is a monolithic single-chip solution that
integrates an NFC controller, a secure element (eSE), and an **eSIM
(eUICC)**. NXP press:
<https://media.nxp.com/news-releases/news-release-details/nxp-ushers-new-era-esim-enabled-devices-5g-and-iot-industrys/>
The Common Criteria Security Target for JCOP 6.2 on SN220 describes a
"broker API which forwards eSIM/SIM/UICC/ISIM commands to an eUICC plugin
library":
<https://www.commoncriteriaportal.org/files/epfiles/NSCIB-CC-0428888-1m1-STlite_v1.1.pdf>

**[public]** OPLUS devices are confirmed to use `SN220U` as the NFC
chipset (`/proc/oplus_nfc/chipset` reads `SN220U` on OnePlus 12R / Ace 3):
<https://github.com/nfcgate/nfcgate/issues/182>

**[device]** On this unit the NXP secure-element stack is alive:
- `init.svc.vendor.secure_element: running` (QTI SE HAL
  `android.hardware.secure_element-service.qti`)
- `init.svc.vendor.weaver_nxp: running`
  (`android.hardware.weaver-service.nxp`) — Weaver is the NXP eSE gatekeeper
  applet, so the SE chip is functional.
- OMAPI (`com.android.se`) exposes terminals `SIM1`, `SIM2`, **`eSE1`**
  (the SPI-connected secure element).
- `eSE1` ARA access rules include GlobalPlatform security-domain AIDs —
  CASD-type (`A00000015153504341534400`, "SPCASD"), CRS
  (`A00000015143525300`, "CRS"), a Google eSE applet
  (`A0000003965453...`), and NXP JCOP SSDs. These are the payment/eSE
  applets; they confirm the SE is provisioned for NFC/payments but are
  **not** direct proof of the eUICC (the eUICC is reached over the modem
  line, not this OMAPI eSE path).

**[device]** The ROM knows about the SN220 eSIM. `my_product`'s
`com.oplus.oplus-feature.xml` declares:
```
<oplus-feature name="oplus.software.radio.esim_support"/>
<oplus-feature name="oplus.software.radio.esim_support_sn220u"/>
```
**[public]** The same `esim_support_sn220u` feature appears in other OPLUS
dumps (e.g. Realme GT7, with the engineer comment "2024/12/25, add for
esim"):
<https://github.com/Jasxh-Dumps/realme-GT7_Dump/blob/main/my_product/etc/permissions/oplus.features.network.xml>
ColorOS porting scripts strip the quartet
`android.hardware.telephony.euicc` + `esim_support` + `esim_support_sn220u`
+ `keyguard_support_esimcard` on devices without EuiccGoogle:
<https://github.com/toraidl/coloros_port/blob/COS16/OOS16/port.sh>

## How the internal eSIM is wired: a GPIO mux on the SIM2 line

**[device]** The internal eUICC is **not** a fully independent slot. It
shares the SIM2 reader line through an electrical multiplexer controlled by
a GPIO:
- `persist.vendor.oplus.radio.esim.gpio.status` — 0 = SIM2 → physical slot,
  1 = SIM2 → internal eUICC.
- Toggling eSIM ON in Settings runs OPPO's `EsimTaskImpl`:
  `handleESimMasterSwitchEnable → syncSwitchGPIO → setUimPower:0`
  (powers the SIM2 UIM down) then flips the GPIO. Observed transition
  `getEsimGpio:0 → getEsimGpio:1`, and SIM2 goes `CARDSTATE_ABSENT` during
  the switch.

**[public]** This matches GSMArena's "Nano-SIM + Nano-SIM + eSIM (max 2 at
a time)" and community reports that enabling the eSIM disables physical
SIM2 on the India OnePlus 13:
<https://www.gsmarena.com/oneplus_13s_5g-13818.php>

**Consequence:** the eSIM toggle should stay **OFF** on the converted 13T —
turning it ON only disconnects the physical SIM2 and reaches a
non-responding internal eUICC.

## Why the internal eUICC does not work after conversion

**[device]** With the GPIO switched to the internal eUICC, the modem's
`GET_SIM_STATUS` on the internal line returns:
```
IccCardState { CARDSTATE_ABSENT, atr=, eid=, SlotPortMapping={physicalSlotIndex=1,...} }
```
Empty ATR and empty EID = the eUICC applet is not answering.

**[public]** This is consistent with a well-known pattern on China OPPO/
OnePlus models: flashing global/other-region ROM does **not** produce a
working internal eSIM — users report the eUICC behaves "as if it were
physically removed":
<https://www.v2ex.com/t/1099448>
The China OnePlus 13T is officially dual-Nano-SIM with **no eSIM**
(<https://www.oneplus.com/cn/13t/specs>); mainland-China carrier eSIM only
reached commercial trials in Sept–Oct 2025, and the first domestic Android
phone with carrier eSIM was the OPPO Find X9 Pro satellite edition
(late 2025), not any OnePlus. So a China-market 13T is not expected to ship
a personalized, carrier-usable internal eUICC.

**Interpretation.** The eSIM failure is **below the application processor**.
Either (a) the China-board SN220 variant is not populated/personalized with
an eUICC identity (EID + EUM keys), or (b) the modem firmware/NV on this
build does not bring the eUICC online. Both are outside what a Magisk/
KernelSU module (which only edits `/system`, `/odm` overlays and props) can
influence.

### Note on EDL / lower-level access (open question, not attempted)

- **EDL (Qualcomm Sahara/Firehose)** reads/writes the host **UFS flash**
  (modem, boot, NV/EFS partitions). It does **not** reach the NXP SN220 —
  the eUICC lives inside a separate secure element on the SPI/ISO7816 bus,
  not in UFS. EDL cannot read or write the eUICC's contents.
- An eUICC's identity (EID + EUM certificate/keys) is provisioned at
  manufacture under the eUICC-Manufacturer PKI. It **cannot** be injected
  into a blank/absent eUICC without the EUM private keys (held by NXP/OEM),
  by design (GSMA SAS-UP / Common Criteria).
- What EDL/fastboot *could* in principle change is the **modem NV/EFS**.
  IF the eUICC were personalized and only the modem routing were missing,
  flashing an India-13s modem image might bring it online. Given the CN→
  global-flash reports above, success is unlikely, but this is the only
  lower-level avenue and is left as an **open item, deliberately not
  attempted here.**

## What works: removable eUICC cards

A removable eUICC (eSTK.me / 5ber / 9eSIM) in the physical SIM2 slot is the
practical path.

- **EasyEUICC (`im.angry.easyeuicc`)**: installs and manages profiles today
  via OMAPI — independent of the internal eUICC and of the ATR bit.
  Confirmed working on this unit's card.
- **Stock Settings (System LPA)**: possible if the card advertises the
  **eUICC capability in its ATR** so Android sets `mIsEuicc=true`. On this
  unit the card currently reports `mIsEuicc=false, mEid=` (a plain SIM), so
  stock Settings does not yet treat it as an eUICC. **[device]**
  **[public]** XDA reports that on eSIM-enabled OxygenOS the stock Settings
  manages removable eUICCs directly (slot 2, no extra app), whereas ColorOS
  requires the card vendor's LPA app:
  <https://xdaforums.com/t/using-esims-on-chinese-op15.4785770/>,
  <https://xdaforums.com/t/e-sim-in-oneplus-13.4768260/>
  The AOSP mechanism behind this is `*#*#4636#*#*` →
  `UiccController.setRemovableEsimAsDefaultEuicc` (Android 13+), plus the
  card presenting the eUICC bit in its ATR:
  <https://github.com/GrapheneOS/platform_packages_services_Telephony/blob/main/src/com/android/phone/settings/RadioInfo.java>

## Capability matrix (this unit)

| Target                    | Stock Settings (System LPA)                 | EasyEUICC |
|---------------------------|---------------------------------------------|-----------|
| Internal eUICC (SN220U)   | No — modem returns CARDSTATE_ABSENT         | No        |
| Removable eUICC (eSTK.me) | Likely yes once card advertises eUICC ATR   | Yes       |

## Key device facts to re-verify

```
# eSIM support level (this module sets it to 2; intl OnePlus 11 also shows 2)
getprop ro.vendor.oplus.esim.support

# internal eUICC GPIO mux (0 = physical SIM2, 1 = internal eUICC)
getprop persist.vendor.oplus.radio.esim.gpio.status

# NXP secure element services
getprop init.svc.vendor.secure_element
getprop init.svc.vendor.weaver_nxp

# per-slot eUICC recognition (mIsEuicc / mEid) — from SMSVC UiccSlot logs
logcat -b all | grep 'UiccSlot: mActive'
```

**[public]** `ro.vendor.oplus.esim.support=2` together with
`init.svc.oplus.esim-1-0: running` is documented on the international
OnePlus 11 (CPH2451):
<https://github.com/oxygen-updater/build-props/blob/master/op11/intl/CPH2451_11_A.06.getprop>
