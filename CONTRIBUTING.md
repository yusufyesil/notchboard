# Contributing

Thanks for helping. Notchboard is small on purpose; changes that keep it that way are the easiest to merge.

## Build and run

```bash
swift build -c release   # compile only
./build.sh               # compile, install to ~/Applications and restart
```

`Notchboard --states` prints what the app reads from Claude Desktop, and `Notchboard --find-icon <folder>…` prints the logo it would pick. Both are handy for checking a change and for bug reports.

## Ground rules

- **Local only.** No network requests, analytics or update checks.
- **Read only.** Never write to Claude Desktop's folders.
- **No setup.** No hooks or changes to Claude's settings.
- **No Anthropic branding** in the app's name, icon or artwork.

## Bug reports

Please include your macOS version, your Claude Desktop version (Claude › About Claude), whether you use Claude Profiles, and the output of `--states` if it's relevant. Remove chat titles you'd rather not share.

When Claude Desktop changes its file format, a report with a redacted sample of the changed `local_*.json` or `scheduled-tasks.json` helps most.

## Pull requests

- Keep each pull request to one change, and say how you tested it.
- Match the surrounding code style. Comments explain why, not what.
- Interface text lives in `Sources/Notchboard/Resources/Localizable.xcstrings`. English is the source text; please add the Turkish translation too, or say in the pull request that it's missing.
