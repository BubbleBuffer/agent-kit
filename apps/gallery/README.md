# Gallery

With no live settings, the gallery runs its existing scripted scenes. The
scripted mode also runs in a browser.

To use a local BubblePaw host, supply all three Dart defines to a desktop build:

```sh
flutter run -d linux \
  --dart-define=BP_BIN=/path/to/bubblepaw \
  --dart-define=BP_WORKSPACE=/path/to/workspace \
  --dart-define=BP_DATA=/path/to/host-data
```

If the desktop runner has not been generated, first run
`flutter create --platforms=linux --project-name agent_kit_gallery .` in this
directory. Select the corresponding platform and device for another desktop OS.

Live mode uses the host configuration associated with the selected workspace and
data directory. The gallery owns its child host and requests shutdown when the
window exits. Partial settings show a configuration error; a web build with live
settings explains that a desktop app is required. Startup failures use generic
copy so local paths and host diagnostics do not appear in the UI.

The adapter workflow builds web and Linux variants. Its separate opt-in local
transport test uses the checksum-verified public BubblePaw v0.2.2 release and
the offline demo provider. The gap test drops a real host notification and
injects a synthetic `events.gap` to exercise recovery; it does not reproduce a
host buffer overflow.
