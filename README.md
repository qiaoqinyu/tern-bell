# Bell for Tern

Ring a sound when an agent turn finishes in [Tern](https://tern.stencil.so): your chosen bell for success, Basso for failure. macOS only.

Open the command palette and choose **Bell: Settings**. The settings pane opens in a new tab; changes stay in a draft until saved.

- Up/down (or click a sound): select and preview; a new selection stops the previous preview.
- Left/right: adjust preview volume by 10%, bounded to 0–100%.
- Space: toggle automatic notification, not saved until you save.
- Enter or **Save**: persist sound, volume and switch, close the pane.
- Esc or **Cancel**: stop preview, discard changes.

Closing the pane also stops playback. Fourteen macOS system sounds are built in.

## Requirements

- Tern on macOS (playback uses `/usr/bin/afplay` and `/usr/bin/python3`, both ship with macOS).
- An agent that reports `done`/`failed` turn results to Tern (for example OMP or Pi running in a Tern pane). Print-mode exits alone do not ring.

## Install

```sh
tern plugin install github.com/qiaoqinyu/tern-bell
```

Update with `tern plugin install github.com/qiaoqinyu/tern-bell --force`.

## Optional CS 1.6 clips

The repository ships no CS 1.6 audio (redistribution rights are unclear). If you own the clips, drop `.wav` files into:

```
<plugin-data>/bell/sounds/cs16/*.wav
```

Find the folder via the plugin's data directory (`~/Library/Application Support/Tern/plugin-data/bell/sounds/cs16` by default). Each file appears as `CS16_<name>` in the settings list on the next reload. A typical set: terwin, sticktog, roger, negative, locknload, letsgo, enemydown, ctwin, ct_fireinhole, ct_affirm, bombpl, bombdef.

## Notes

- Settings persist through `tern.kv` in `plugin-data/bell/kv.json`; preview/request tokens live in the same data folder, never in the package.
- Playback runs as an owned child (`play.py`) that is cancelled when the request changes or the pane closes; a sound already playing finishes.
- Multiple windows can receive the same event and ring independently; overlapping playback in one window is skipped.
- Turn Bell off in settings or Preferences → Plugins; turning it off affects future events only.

## License

MIT. Sound files are not included and remain the property of their owners.
