# Bell for Tern

Local sound notifications for [Tern](https://tern.stencil.so): choose a completion sound and a separate failure sound. When the main agent explicitly needs input, Bell plays the completion sound once. macOS only.

Open the command palette and choose **Bell: Settings**. The settings pane opens in a new tab; changes stay in a draft until saved.

- Up/down (or click a sound): select and preview; a new selection stops the previous preview.
- Each event has a separate row: **Task complete / needs input** and **Task failed**, with its current sound and an **Edit** button. **Editing** marks the row controlled by the sound list. Use Tab or the row buttons to switch; each row keeps its own draft selection.
- Left/right: adjust preview volume by 10%, bounded to 0-100%.
- Space: toggle automatic notification, not saved until you save.
- Enter or **Save**: persist both sounds, shared volume and switch, then close the pane.
- Esc or **Cancel**: stop preview, discard changes.

Closing the settings pane stops its preview without saving. Fourteen macOS system sounds are referenced from your Mac, not bundled in this repository.

## Requirements

- Tern on macOS with working `/usr/bin/afplay` and `/usr/bin/python3` executables. Install Python / Apple developer tools if that Python path is unavailable.
- An agent that reports `done`/`failed` turn results to Tern. Waiting reminders require Tern to expose that agent pane as `waiting_input`; Bell does not infer a request from reply text or an editable input box.

## Install

```sh
tern plugin install github.com/qiaoqinyu/tern-bell
```

Update with `tern plugin install github.com/qiaoqinyu/tern-bell --force`.

## Optional custom sounds

The repository ships no audio assets. Add your own files with `.wav`, `.aiff`, `.mp3`, `.m4a` or `.caf` extensions, encoded in a format your Mac's `afplay` can play:

```
<plugin-data>/bell/sounds/custom/
```

Find the folder via the plugin's data directory (`~/Library/Application Support/Tern/plugin-data/bell/sounds/custom` by default). Each file appears in the settings list by its name without extension, after the built-ins, on the next reload. For example, `roger.wav` shows as `roger`.

## Notes

- Settings persist through `tern.kv` in `plugin-data/bell/kv.json`; settings-preview tokens live in the same data folder, never in the package.
- Automatic notifications run in `notify.py`: settings reads, sound lookup and audio playback happen outside the UI thread. Each notification is independent; a later completion does not cancel a preceding input reminder. Settings previews use an owned child (`play.py`); selecting another preview or closing settings cancels that pane's previous preview. There is no cross-window notification deduplication or global playback queue.
- Missing files and playback failures show a visible error toast for automatic notifications, or an inline error during preview. Identical notification errors are suppressed until a notification plays successfully; errors are also written to the Tern log. Bell does not retry or silently substitute a different sound.
- Turn Bell off in settings or Preferences → Plugins; turning it off affects future events only. Zero volume is silent for completion, failure and input reminders.

## Notification boundaries

- Success and failure use Tern's `agent_finished` event for the main agent pane. Exiting or closing a pane alone does not ring.
- Input reminders observe top-level agent panes every 750 ms and ring only on a transition into `waiting_input`. Remaining in that state does not repeat the reminder. Returning to work and later waiting again can ring again.
- The first observation of each pane establishes a baseline without ringing, including after plugin reload. Normal idle, tool execution and internal subagent results do not independently trigger a reminder. A separately launched agent in its own pane is treated as its own main agent.
- Every plugin load starts a new observer, including hot reloads. A transient settings or agent-list error does not stop polling. The same polling error is reported once until a successful poll; a pending wait can be handled after recovery without replaying panes already handled. This does not retry failed audio playback.
- Completion and waiting share the existing `settings.sound`; failure uses `settings.failureSound`, defaulting to Basso. Existing sound, volume and enabled settings are preserved. Both categories use the same volume and master switch.

## Reliability fix (1.2.1)

Automatic notifications no longer read settings or touch playback-token files in a window callback. Tern disables a window hook until reload when it exceeds 50 ms; synchronous disk access previously exposed both completion and input-reminder callbacks to this failure. The window now submits an external notification process and handles its result without filesystem access. Settings previews remain on the host worker, with their existing cancellation behavior.

A pending input reminder waits for its asynchronous result before submitting another request. Invalid settings remain pending until repaired; stale results cannot revive an earlier wait or a removed pane. Playback failures remain visible and are not retried. Existing settings and custom sounds require no migration.

Verification commands (with a running Tern window):

```sh
python3 tests/notification.py
python3 tests/run.py
python3 tests/budget.py
```

The first two cover notification selection/errors and ten waiting/completion lifecycle cases. The native budget regression runs the real callback, filesystem and player in an isolated plugin: a settings read blocked for 150 ms prevents playback on 1.2.0, but 1.2.1 plays that notification and the next without reload. It plays Glass quietly, temporarily links/unlinks a uniquely named plugin, and leaves production settings and sound files unchanged. Pass an unfixed source directory to `tests/budget.py` to repeat the failing-before check.

An end-to-end macOS window → lab-wsl2 pane check emitted the same OSC 7501 reports as OMP: `working → done`, `working → error`, `working → done`. All three arrived as `agent_finished` events (`done`, `failed`, `done`), and the installed Bell launched the selected completion/failure/completion sounds through local `afplay`, without intermediate reload or Bell errors. Process execution was observed; acoustic output was not independently measured. The temporary observer and remote pane were removed.

## Verification (1.2.0)

Verified locally in Tern with an interactive OMP agent: independent failure selection, draft cancellation and save, a sustained input request ringing once followed by a separate completion, no internal subagent/tool-wait notification, and silence when disabled or at zero volume. A deliberately rejected model request used the selected failure sound. Temporarily removing the selected audio file showed one error; the same failure stayed quiet until a successful playback reset the error record. Native settings trees were checked at normal and narrower window sizes; screenshot capture was unavailable.

Before publishing a future change, repeat these scenarios with a disposable agent pane. Preserve user settings and audio files; do not use private credentials or sound files as test fixtures in the repository.

An invalid-audio fixture also exercised a real `afplay` decoding error and the asynchronous error toast. All temporary fixtures were removed and the original audio was restored.

Lifecycle regressions: run `python3 tests/run.py` from the checkout with `tern` on PATH and a Tern window open. The runner executes the real window entry in Tern's Luau VM against a deterministic lifecycle model. It temporarily links and unlinks a uniquely named test plugin, which reloads plugins in the running app; it neither plays audio nor changes Bell settings. Seven cases cover reload, settings and snapshot recovery, repeated errors, partial scans, notification boundaries and completion/failure selection.

The original implementation failed four of the initial six cases; the repaired implementation passes all seven. A separate native smoke test used an interactive OMP pane and an isolated Bell copy: the installed Bell issued a notification after hot reload; invalid settings prevented the isolated copy from issuing one; restoring its JSON resumed the pending notification without reload. Request tokens stayed unchanged during sustained waiting and during a reload while waiting. These checks observed notification requests, not audibility. The isolated plugin, state and test panes were removed; production settings were unchanged.

## License

MIT. Sound files are not included and remain the property of their owners.