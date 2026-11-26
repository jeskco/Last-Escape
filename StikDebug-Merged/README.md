# StikDebug + VPN (ARMSX2 look)

StikDebug with the LocalDevVPN loopback tunnel built in, restyled to look like ARMSX2.
One app instead of two: no separate LocalDevVPN needed.

## Two builds (made by the same workflow)

| File | What it is | Needs |
|---|---|---|
| `StikDebug-VPN.ipa` | StikDebug + built-in VPN extension | A signer that keeps the **Network Extension** entitlement |
| `StikDebug-NoVPN.ipa` | StikDebug with the new look, no extension | Uses the external LocalDevVPN app, as before |

Try `StikDebug-VPN.ipa` first. If it won't install, or the app says "Built-in VPN unavailable",
use `StikDebug-NoVPN.ipa`.

## Build it
1. Create a new GitHub repository and upload everything in this folder.
   (If the hidden `.github` folder doesn't upload, use *Add file → Create new file*, name it
   `.github/workflows/build.yml` and paste in the contents.)
2. Open the **Actions** tab → **Build IPAs** → **Run workflow**.
3. When it finishes, download the `StikDebug-IPAs` artifact, then sign/install with your usual service.
4. If it fails, download the `build-logs` artifact (or copy the red error lines) and send them over.

## Using it
Open the app, tap **Connect** on the VPN card at the top of Home, then enable JIT for ARMSX2 as usual.
ARMSX2's "Auto-open StikDebug" setting keeps working (same `stikdebug://` links).
Delete the old StikDebug first, or install this over it (same bundle ID, keeps your pairing file).
If you also have the LocalDevVPN app, turn its VPN off — iOS only runs one VPN at a time.

## Not tested
This was written without access to Xcode or a device, so it has never been compiled or run.
Expect to fix a few build errors on the first runs.
