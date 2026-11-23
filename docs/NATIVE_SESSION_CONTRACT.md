# Android native session and channel contract

Task 5, approved refactor dated 2026-10-20; integration keys confirmed with the parent on 2026-10-21.
The install package identity is applicationId `com.kajolno.TrafArch`, which is also the Kotlin
namespace. The NFC wire interface, permissions, Dart protocol, APDU construction,
and response interpretation remain unchanged. The Application class additionally
owns the separate memory adaptation described below.

## NFC wire interface

Memory adaptation uses a separate `transit_card_analyzer/memory` channel. It does
not change the NFC methods, payload keys, session IDs, or physical-close contract.
On HONOR KILL, Dart invalidates its acquisition generation and requests stop,
but the memory reply has its own 2.4-second native deadline and does not wait for
the NFC close barrier. A successful memory reply means the continuation file and
accepted persistence completed; it does not acknowledge physical NFC closure.
Restored data never reconnects an old session. See `ARCHITECTURE.md` for the
memory channel and private recovery-file lifecycle.

Channel: **`transit_card_analyzer/nfc`**. All existing method names remain unchanged.

| Method | Session-aware arguments | Legacy arguments | Success |
|---|---|---|---|
| `scanOnce` | `{'sessionId': String}` | no arguments / null | Existing tag metadata map plus `sessionId: String` |
| `transceive` | `{'sessionId': String, 'apdu': Uint8List or List<int>}` | Direct Uint8List or List<int> | Uint8List containing the unchanged ISO-DEP response, including SW1/SW2 |
| `transceiveFelica` | `{'sessionId': String, 'frame': Uint8List or List<int>}` | Direct Uint8List or List<int> | Uint8List containing the unchanged complete NFC-F response, including LEN |
| `stopScan` | `{'sessionId': String}` | no arguments / null | null, after the requested session's physical close work has finished successfully |

The exact payload keys are **`apdu`** and **`frame`**, not `data`. Both payload types
are accepted in either form. A map may omit `sessionId` for legacy active-session
selection. Payload bytes are copied when accepted; numeric list conversion keeps
the existing low-byte conversion. No framing, status handling, Le correction,
retry, APDU filtering or FeliCa parsing occurs in native transport.

Generate a fresh UUID string in Dart **before invoking `scanOnce`**. Native registers
it synchronously when it receives the method call, before enabling discovery or
queuing connection work. Echoed IDs are identical strings. This allows cancellation
while the discovery future is pending. IDs must be nonblank strings and must never
be reused; a duplicate ID during a controller lifetime is rejected without replacing
the current session. If omitted, native generates a UUID and returns it in the scan
response. The caller cannot target that generated ID before receiving the response.

Legacy calls resolve the active session at **method acceptance**, then capture that
session and connection for queued work. Native never re-reads a global connection
when that work executes. A legacy `stopScan()` still means "stop whichever session is
active when the request arrives"; native cannot infer which old Dart attempt sent it.
The parent must use IDs for all new transports and cleanup paths.

### Dedicated NFC-F entry point

Channel **`transit_card_analyzer/octopus_nfc`** accepts `scanOnce`,
`transceiveFelica`, and `stopScan` with the session-aware arguments and success
results above. Each call requires an explicit nonblank `sessionId`. `scanOnce`
captures NFC-F reader mode and `FLAG_READER_SKIP_NDEF_CHECK` for that session.
The dedicated reader supplies `EXTRA_READER_PRESENCE_CHECK_DELAY = 500` ms,
retained for the local Octopus balance reader. The Dart balance flow does not
run network waits or periodic keep-alive exchanges. Other readers keep their
existing options. Pause and resume retain these settings. The FeliCa exchange uses `frame` and
returns the complete NFC-F response including LEN. The Dart adapter propagates
platform errors and treats a missing or empty exchange response as a failure.

Both channels share the controller, ID history, active session, command queue,
and retirement barrier. A scan on either channel retires the previous active
session. An ID-scoped stop joins retirement for that ID, even after a later
scan has been accepted. The Octopus coordinator owns card identity, command
authorization, and cleanup. The controller skips raw frame logging for its
NFC-F-only sessions.

`NfcDiscoveryLifecycle` starts dedicated NFC-F discovery with a guarded
`disableReaderMode` → `enableReaderMode` sequence. It checks active-session,
foreground and stopped state before disabling and again before enabling. This
reset applies only to the dedicated reader; ordinary reader activation and the
shared physical-close barrier keep their existing behavior. A callback without
`android.nfc.tech.NfcF` is ignored before claiming `DISCOVERING`, so an incompatible
old tag cannot consume the dedicated session's one discovery response.

The dedicated session has a **55-second native discovery deadline**, starting
when the session is registered. Its callback acts only on that same active,
unstopped session in `WAITING` or `DISCOVERING`; success, stop, replacement or
disposal makes the callback inert. Expiry returns `NFC_DISCOVERY_TIMEOUT` with
`sessionId` and the fixed `details.discoveryPhase` value, then retires the session:

| `discoveryPhase` | Native state | Meaning |
|---|---|---|
| `waiting_for_tag` | `WAITING` | No acceptable NFC-F tag has been claimed; an incompatible callback may have been ignored |
| `connecting` | `DISCOVERING` | A tag was claimed, but metadata/connection publication has not completed |

The deadline continues while a waiting session is paused. Dart keeps its
**60-second fallback** and uses the same error code if native does not complete;
that fallback does not invent a native discovery phase. Neither timeout proves
physical release: Dart still performs ID-scoped cleanup and observes the existing
close acknowledgement. Only the two fixed phase values may enter sanitized
diagnostics; arbitrary error details, identifiers and payloads do not.

The reset is informed by [AOSP `NfcService.java`](https://android.googlesource.com/platform/packages/modules/Nfc/+/refs/heads/main/NfcNci/src/com/android/nfc/NfcService.java):
the zero-flags reader-mode branch calls `StopPresenceChecking`, while
`applyRouting` can defer reconfiguration when a tag remains present. The supplied
APK's `com.octopus.f1MOT.F1Detector` uses `ignore(tag, 1, ...)` on some mode switches;
`com.octopus.f1.F1Detector` disables/enables reader mode on pause/resume. These are
comparison evidence, not proof of this device's failure point. TrafArch does not
copy `ignore` or the vendor's complete mode-switching policy.

## Dart ownership and cancellation

```dart
const channel = MethodChannel('transit_card_analyzer/nfc');
// Allocate once per attempt, before invoking native. Never reuse this value.
final String attemptId = createUuid();
final scanFuture = channel.invokeMapMethod<String, dynamic>(
  'scanOnce', <String, Object>{'sessionId': attemptId},
);
// Cancellation can happen here, before scanFuture completes:
// await channel.invokeMethod<void>('stopScan', {'sessionId': attemptId});

try {
  final metadata = await scanFuture;
  if (!isCurrentAttempt(attemptId)) return;
  if (metadata?['sessionId'] != attemptId) {
    throw StateError('Native NFC session mismatch');
  }
  final response = await channel.invokeMethod<Uint8List>(
    'transceive', {'sessionId': attemptId, 'apdu': commandBytes},
  );
  // FeliCa uses 'transceiveFelica' and {'sessionId': attemptId, 'frame': frameBytes}.
  if (!isCurrentAttempt(attemptId)) return;
  // Retain raw bytes and partial results under this immutable attempt ID.
} finally {
  // The captured ID stays valid for idempotent cleanup of this attempt, even if
  // another attempt has started. Do not read a mutable "current ID" here.
  try {
    await channel.invokeMethod<void>('stopScan', {'sessionId': attemptId});
  } on PlatformException catch (error) {
    recordCloseOutcome(attemptId, error); // Preserve any earlier read failure/data.
  }
}
```

This is integration pseudocode, not an executed test. Install a handler on the scan
future immediately so its `NFC_STOPPED` cancellation is consumed. Use independent
failure handling for read and close so cleanup cannot erase an earlier error or
partial evidence. The parent owns the Dart adapter/controller edits.

The coordinator alone closes a session. Parsers borrow immutable session-bound
transport functions. Carry the same attempt guard through awaits, progress,
parsing, publication and archive dispatch; a native guard does not protect later
Dart state updates. Already delivered bytes/metadata belong to their attempt and
must survive a later transport error. Cancellation suppresses not-yet-delivered
native results; it does not manufacture an empty successful response.

## Lifecycle and ordering

Native states are `WAITING`, `DISCOVERING`, `CONNECTED`, `METADATA_ONLY`, `CLOSED`.
Reader callbacks capture the registering session. The main looper claims only the
first discovery for that same active waiting session. The worker registers every
technology handle before connecting, including the existing optional MIFARE probe.
Connection/metadata publication checks identity again on the main looper.

Normal NFC work is FIFO on one process-wide worker: metadata probes, connects and
transceives. At most **64 uncompleted transceives per session** are accepted, counting
the running command and responses waiting for main-loop delivery. No command can
overtake a previous command on that connection. Process-wide scheduling also keeps
old retirement work ahead of a replacement Activity/engine's later connection work.

Retirement detaches and marks a session closed first, replaces its reader mode
with the foreground idle reader (or disables it outside the foreground) on the
main looper, completes its pending scan/commands with `NFC_STOPPED`, and removes
its queued work. A separate background close worker can interrupt the exact old
technology while its I/O is blocked; no monitor is held across that I/O. A FIFO
retirement barrier waits off-main for abort and the old worker, then sweeps remaining
handles. This second sweep is intentional: cancellation may have closed a handle
just before an already-entered `connect()` completed. **A successor cannot connect
until this sweep finishes**, and background cleanup never disables successor reader
mode or reads successor handles. No tag `connect`, `transceive`, `readBlock` or
`close` runs on the main looper.

Repeated close of a known retired ID joins the same retirement or returns its
recorded outcome. It never performs another close or touches the current session.
Unknown/stale IDs return `STALE_SESSION` without disabling reader mode. Retired IDs
and duplicate prevention are scoped to the native controller lifetime; Dart IDs
must remain unique across Activity/engine recreation as well.

Close success is an actual completion acknowledgement, not a timeout interpreted
as success. After **10 seconds**, an unfinished close replies `NFC_CLOSE_FAILED`
with `details.closing == true` and `reason == 'close_timeout'`. The physical close
continues, and the successor connection still waits behind the retirement barrier.
Repeating close while that timeout persists returns the same unfinished outcome;
after retirement completes, a repeated close returns its final outcome. Each
individual MethodChannel request receives at most one final reply. Read/discovery
requests cancelled by stop are completed immediately, independently of close time.
The parent's old one-second Dart stop timeout must not be treated as proof of release.

Pause only disables discovery in `WAITING`; resume re-enables the captured waiting
session. An accepted discovery/connected read remains alive while backgrounded,
preserving the existing policy. Starting a scan while paused waits for resume.
Destroy/engine cleanup disposes every handler idempotently and cancels its pending
replies. NFC retirement barriers drain on the shared scheduler; its idle threads
expire without shutting down another controller's scheduler.

While the Activity is foreground and no scan session is active, reader mode stays
enabled with an empty callback and no platform sounds. Accidental tags on other
pages are ignored by the app instead of being dispatched to Android's tag prompt.
Starting a scan replaces that callback with the session-bound discovery callback;
retirement returns to the empty callback. Pausing or disposing the Activity removes
idle reader mode, so the system handles tags normally outside the app. Discovery
and connected reads keep the pause behavior described above.

## Tag metadata compatibility

Existing response keys and meanings are retained:

```text
uid, technologies, atqa, sak, ats, historicalBytes, hiLayerResponse,
nfcBApplicationData, nfcBProtocolInfo, nfcFSystemCode, nfcFManufacturer,
nfcVDsfId, nfcVResponseFlags, mifareType, mifareSize, mifareSectorCount,
mifareBlockCount, mifareManufacturerBlock, mifareBccValid, cardType,
atsDescription, maxTransceiveLength, tagDescription, isoDepConnected,
felicaConnected, timestamp
```

`sessionId` is additive. Optional `metadataIssues` is a list of maps containing
`stage`, `exception` (Java class name) and nullable `message`; failed optional probes
do not discard the other metadata. `ats` remains an alias of historical bytes and
is **not** the full ATS. Existing uppercase spaced-hex encoding and card descriptions
are retained. ISO-DEP remains preferred; NFC-F is connected only if ISO-DEP did not
connect. Timeouts remain ISO-DEP 5000 ms and NFC-F 3000 ms. The existing best-effort
MIFARE block-0 read is preserved; no authentication or new card capability is added.

ISO-DEP historical bytes and the higher-layer response are captured from Android's
discovery metadata before `connect()`. A later connection or APDU failure therefore
does not erase the activation evidence already supplied with the successful scan.
Provider-name lookup and reset-information decoding remain in Dart. The native
transport does not consult the bundled provider registry or add a new MethodChannel.

## NFC errors

| Code | Message / details | Meaning |
|---|---|---|
| `BAD_ARGUMENT` | `APDU 数据格式错误`, `FeliCa 帧格式错误` | Existing payload errors, including malformed list elements |
| `BAD_ARGUMENT` | `sessionId 数据格式错误` | Added: ID exists but is not a nonblank string |
| `NFC_UNAVAILABLE` | `当前设备没有 NFC` | Existing unavailable adapter |
| `NFC_DISABLED` | `请先打开系统 NFC` | Existing disabled adapter |
| `TAG_NOT_CONNECTED` | `ISO-DEP 未连接` | Existing missing/wrong/disconnected ISO-DEP transport |
| `FELICA_NOT_CONNECTED` | `NFC-F 未连接` | Existing missing/wrong/disconnected NFC-F transport |
| `TRANSCEIVE_FAILED` | Original exception message; additive `sessionId`, `exception` details | Existing I/O failure code; does not imply that every failure is tag loss |
| `NFC_STOPPED` | `扫描已停止` | Cancelled/replaced/disposed scan or accepted outstanding command |
| `STALE_SESSION` | `NFC 会话已失效`; `sessionId`, optional `activeSessionId` | Added: stale/unknown ID or reused scan ID; no current-session mutation |
| `NFC_BUSY` | `NFC 指令队列已满`; `sessionId` | Added: bounded command queue full; command was not sent |
| `NFC_SCAN_FAILED` | Exception message, fallback `无法启动 NFC 扫描`; session/exception details | Added: reader-mode setup or fatal discovery error |
| `NFC_DISCOVERY_TIMEOUT` | `八达通 NFC-F 发现超时，请重新贴卡。`; `sessionId`, fixed `discoveryPhase` | Dedicated NFC-F discovery/connection deadline; retires the session, not a close-success acknowledgement |
| `NFC_CLOSE_FAILED` | `NFC 连接关闭失败`; `sessionId`, `closing`, plus `errors` or timeout `reason` | Added: truthful incomplete/failed close acknowledgement |

Unknown methods remain `notImplemented`. Platform errors remain errors, never empty
successful frames. Native keeps exception class/message rather than guessing a
protocol diagnosis. Full typed failure translation and partial archive retention
belong to the parent Dart integration.

## QR and file channels

| Channel | Methods | Preserved results |
|---|---|---|
| `transit_card_analyzer/qr_image` | `pickImage` | Cached absolute image path; null on user cancellation |
| `transit_card_analyzer/export` | `saveToDownloads` with `fileName`, `content` | `Download/<actual name>` on API 29+; absolute path on older Android |

Permission request codes remain storage **1001**, image picker **1002**. API 29+
uses MediaStore Downloads; older supported Android requests the existing
`WRITE_EXTERNAL_STORAGE` permission. Photo picker/GET_CONTENT fallback is retained.
Exports whose file name ends in `.json` use the `application/json` MIME type;
other text exports retain `text/plain`. The method name and argument keys are unchanged.
Camera scanning uses the in-app scanner; the Google Code Scanner channel and module
warm-up have been removed.

Both UI shells use a shared acquisition owner. Before opening the camera or
photo picker it awaits the ordinary and Octopus NFC close acknowledgements;
NFC cannot restart while acquisition or camera teardown is pending. The
scanner serializes camera start/stop around permission and foreground changes.
Back or barcode detection waits for camera stop before popping; a failed stop
keeps the camera screen open for retry. On Android the retry uses the installed
`mobile_scanner` 7.5 channel's existing forced stop, because both the Dart
controller and the plugin cache can already report stopped after a failed
call. No TrafArch NFC or file method names or arguments change.
Cancellation/failure codes/messages at these boundaries are:
`PICK_IN_PROGRESS`, `PICKER_UNAVAILABLE`, `IMAGE_READ_FAILED`, `PICK_CANCELLED`,
`BAD_ARGUMENT`, `PERMISSION_DENIED`, `EXPORT_FAILED`, `EXPORT_CANCELLED`.

`EXPORT_IN_PROGRESS` / `导出正在等待存储权限` is additive: a second permission-waiting
export is rejected instead of overwriting the first pending result. Image selection
remains busy through its cache copy. Disposal cancels in-flight copy/write replies
as well as UI/permission waits. Late callbacks target their captured once-only reply;
they cannot take a successor request. File/copy operations already inside system I/O
may finish after cancellation; cancellation is not a rollback of a completed write.

## Verification boundary

This contract describes source implementation and required Dart integration.
The Octopus addition has Dart channel/lifecycle tests, Kotlin type checking and
an isolated JVM lifecycle smoke check; no APK build or emulator run was performed
for this change. The local balance reader's frame flow was additionally captured
from the supplied third-party app on a real Octopus card on 2026-11-17: that
logging establishes the card command/response bytes and the balance formula, not
TrafArch's own end-to-end native transport on a device. These checks do not
establish driver abort latency or final Android package compatibility.
