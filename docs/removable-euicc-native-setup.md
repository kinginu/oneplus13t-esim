# Managing a removable eUICC (eSTK.me) from stock Settings

> **DRAFT** — menu paths below are approximate; the exact STK menu wording
> differs slightly on the card firmware used here. Screenshots to be added
> by the maintainer at the `![screenshot: …]` markers, and the menu steps
> corrected to match.

This is the **working** eSIM path on the OxygenOS-converted OnePlus 13T.
The internal eUICC does not work (see
[`esim-hardware-analysis.md`](esim-hardware-analysis.md)), but a **removable
eUICC card** (eSTK.me, 5ber, 9eSIM) in the physical SIM2 slot can be managed
**directly from the stock Settings eSIM screen** once the card advertises
the eUICC capability in its ATR.

Verified on device: after switching the eSTK.me ATR Mode to **eUICC**, the
card is reported as `mIsEuicc=true` with a valid `mEid`, and the stock Google
LPA (`Settings → Mobile network → SIM & eSIM settings → eSIM`, i.e.
`CurrentProfileListActivity`) lists and manages the card's profiles
(enable/disable/delete). **Downloading a new profile natively still fails**
(framework limitation, see below) — keep using EasyEUICC for downloads.

## What this achieves

| Before (Generic ATR) | After (eUICC ATR) |
|----------------------|-------------------|
| Card seen as a plain SIM (`mIsEuicc=false`, empty EID) | Card seen as an eUICC (`mIsEuicc=true`, EID present) |
| Stock Settings ignores the card | Stock Settings eSIM screen **lists and manages** the card's profiles |
| Profiles only via EasyEUICC / lpac | Native enable/disable/delete (EasyEUICC still works too) |

**Note:** native **downloading** of a *new* profile still does not work —
that stays on EasyEUICC. See "Limitation" below for why.

## Prerequisites

- This module (`oneplus13t-esim`) installed, so the eSIM entry exists in
  Settings, **plus** the camera module with the eSIM-HAL fix
  (see the main README).
- A **full** eSTK.me card. The cheap **ECO Lite** variant has ATR Mode
  **locked to Generic** and cannot do this.
- The card inserted in the **physical SIM2 slot** with at least one profile
  present (the STK menu appears once a profile is enabled).
- **Do NOT** touch the OPPO eSIM master toggle (the GPIO one) — that is for
  the dead internal eUICC and only disconnects SIM2.

## Step 1 — Open the eSTK.me STK menu

The card's configuration lives in the **SIM Toolkit** app for the SIM2 slot,
not in any companion app.

- App drawer → **SIM Toolkit** (the SIM2 instance), or
- `adb shell am start -n com.android.stk/.OplusStkLauncherActivity2`

You should land on the **ESTKme** menu: `Profiles / Download / Tools /
Settings / About`.

![screenshot: ESTKme STK main menu]

## Step 2 — Set ATR Mode to eUICC

Navigate to the ATR Mode setting.

> TODO(maintainer): correct the exact path — it was slightly different from
> `Settings → ATR Mode` on this firmware.

- Open **Settings** in the ESTKme menu.
- Find **ATR Mode**. The current value is marked with `<*>`.
- Select **eUICC** ("announce as a UICC with eUICC-related function").
- Leave **ISD-R Mode = Shared** (the default). Setting ATR=eUICC while
  ISD-R=Disabled makes some phones report the card as "corrupted".

![screenshot: Settings submenu with ATR Mode]

![screenshot: ATR Mode options — Generic vs eUICC]

## Step 3 — Reset the card so the new ATR is read

The ATR is only read at card reset. Apply the change with any of:

- ESTKme menu → **Tools → Reboot**, or
- reboot the phone, or
- eject / re-insert the SIM tray.

![screenshot: Tools → Reboot]

## Step 4 — Verify

The card should now report as an eUICC:

```
adb shell "su -c 'logcat -b all | grep \"UiccSlot: mActive\"'"
# expect on the SIM2 line:
#   mIsEuicc=true, ... mEid=<non-empty>, mCardState=CARDSTATE_PRESENT
```

Then open the stock eSIM screen:

```
adb shell am start -a android.telephony.euicc.action.MANAGE_EMBEDDED_SUBSCRIPTIONS
```

It should show the card's existing profiles and an **Add SIM** entry.

![screenshot: stock Settings eSIM screen listing eSTK.me profiles]

## Limitation: stock Settings can MANAGE but cannot DOWNLOAD

Confirmed on device. After ATR Mode → eUICC, the stock Google LPA lists,
enables, disables and deletes existing profiles, but **downloading a new
profile fails** with "Something went wrong". The card and network are fine —
EasyEUICC downloads to the same card without issue.

Root cause (from `EuiccGoogle` logs):

```
NetworkCache.getEidForSlot: preferred Euicc slotId is 1
NetworkCache.getEidForSlot: Cannot find EID for slotId: 1
EuiccServiceImpl.getEidFromSlotId: Failed to get EID for slotId: 1
  com.android.euicc.service.EuiccServiceException: Didn't find EID for slotId: 1 (Error Code=0x20009)
onGetDownloadableSubscriptionMetadata errorCode: 33554432   (ERROR_EUICC_MISSING / generic)
```

The download flow begins by reading the eUICC's **EID** (it is sent to the
SM-DP+). The Google LPA reads the EID from the framework's **public euicc
API cache** (`NetworkCache.getEidForSlot`, backed by `UiccSlotInfo.getEid()`),
**not** by a live APDU to the card. On this device:

- OPPO's internal telephony (`SMSVC` `UiccSlot`) **does** hold the EID
  (`mIsEuicc=true, mEid=<present>`), and OMAPI/EasyEUICC read it fine.
- But OPPO's framework **does not publish that EID into the public euicc
  API** that the Google LPA reads, so `getEidForSlot` returns "Cannot find
  EID" and the download aborts before contacting the SM-DP+.

This is a **framework-level limitation**, not a card or APDU problem:

- The card's **ISD-R Mode** (AUX vs GSMA) makes no difference — tested both,
  identical `0x20009`. AUX exposes ISD-R over OMAPI (app LPAs); GSMA exposes
  it over the baseband — but the failure is in the *EID lookup cache*, which
  neither changes. **Keep ISD-R Mode = AUX so EasyEUICC keeps working;**
  GSMA gains nothing here and can hide the card from OMAPI apps.
- The Google LPA already selects the removable slot (`preferred Euicc
  slotId is 1`), so the `*#*#4636#*#*` "Removable eSIM as default" toggle is
  not expected to help either.

This is the same reason OpenEUICC/EasyEUICC exist: Google's LPA does not
properly support removable eUICCs for downloads.

**Practical split:**

| Operation | Stock Settings (Google LPA) | EasyEUICC |
|-----------|-----------------------------|-----------|
| List / enable / disable / delete existing profiles | Yes | Yes |
| **Download a new profile** | **No** (`getEidForSlot` → 0x20009) | **Yes** |

So: **download with EasyEUICC, switch/manage with stock Settings.**

## ⚠️ Important caveats

- **Do not disable the eSIM from Android Settings casually.** Once the card
  advertises the eUICC ATR, Android treats it as a non-removable eUICC and
  **refuses to re-enable it like a normal SIM**. Recovery requires
  `adb shell pm clear com.android.providers.telephony`, **which wipes
  telephony data** (SMS, call log, APNs, per-SIM settings). Source:
  [EasyEUICC FAQ](https://easyeuicc.org/en/faq/).
- The change is **reversible**: set ATR Mode back to **Generic** and reset
  the card to return to plain-SIM behaviour.
- Enabling an eSIM profile still **disables physical SIM2** (they share the
  slot).
- To download new profiles you can use the stock **Add SIM** flow or keep
  using **EasyEUICC** — both operate on the same card.

## References

- eSTK.me docs — **ATR Mode (archived; original page removed)**:
  <https://web.archive.org/web/20250405073044/https://docs.estk.me/stk/settings/atr/>
- eSTK.me docs — ATR Mode (live, may be unavailable): <https://docs.estk.me/estk_me/stk/settings/atr-mode/index.html>
- eSTK.me docs — Android quickstart: <https://docs.estk.me/manual/quickstart/android/index.html>
- eSTK.me docs — PC quickstart (recommends ATR=eUICC): <https://docs.estk.me/manual/quickstart/pc/index.html>
- EasyEUICC FAQ (the "can't re-enable" trap): <https://easyeuicc.org/en/faq/>
- AOSP `AnswerToReset.isEuiccSupported()`: <https://android.googlesource.com/platform/frameworks/opt/telephony/+/refs/heads/main/src/java/com/android/internal/telephony/uicc/AnswerToReset.java>
- osmocom Known ATRs: <https://euicc-manual.osmocom.org/docs/lpa/known-atr/>
