# README media

`run.sh` builds a separate, ad-hoc-signed **Glance Demo.app** using the real dashboard and Settings controllers. It creates a temporary profile with isolated `HOME` and `CFFIXED_USER_HOME`, supplies fictional pull requests through an offline fetch closure, and places a solid neutral window behind the UI. It never starts the normal app lifecycle, live GitHub refresh, login-item registration, notifications, embedded browser, or Sparkle updater. Merge actions return an offline-demo error.

Run it from the repository:

```sh
scripts/readme-media/run.sh
```

Stop it with Control–C in that terminal. The printed temporary directory contains only demo build products and fixture data; remove that directory after capture if no longer needed. The installed app and normal Glance profile are not used.

Capture only the demo window, never the desktop or a real account. The committed media was captured and checked with Computer Use. Use these filenames:

- `panel.png`: initial dashboard.
- `search-02.png`: search for `desktop`.
- `search-03.png`: search for `api`.
- `search-04.png`: clear the search.
- `triage-01.png`: select the first PR with J. If search has focus, Tab returns to dashboard navigation.
- `triage-02.png`: P to pin the selected PR.
- `triage-03.png`: D to dismiss it.
- `triage-04.png`: click Undo before its timeout.
- `colors.png`: Settings → Repo Colors.

`encode.py` requires Pillow. It expects the reviewed Retina window captures from this session (880 × 1220 dashboard; 1440 × 1184 Settings). It rejects other sizes, crops the macOS titlebar sharing indicator, adds neutral padding and action captions, and writes two PNGs and two looping GIFs to `docs/images`. For a different capture scale or OS titlebar, review and adjust the dimensions and crop first.

```sh
python3 scripts/readme-media/encode.py /path/to/captures
```

The encoder also writes `review-sheet.png` beside the input captures. Review **every final frame**, both PNGs, and the rendered README before committing. Check that only invented names, repositories, titles, and account data are visible, with no desktop, personal wallpaper, notifications, browser content, file paths, or system menu bar. The generated media has no source screenshot metadata.
