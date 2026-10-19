<p align="center">
  <img src="docs/images/icon.svg" width="128" height="128" alt="Notchboard icon: a small pixel creature under a notch">
</p>

<h1 align="center">Notchboard</h1>

<p align="center">
  <b>Your Claude Desktop chats, routines and profiles, at a glance in the MacBook notch.</b>
</p>

<p align="center">
  <a href="https://github.com/yusufyesil/notchboard/releases/latest"><img src="https://img.shields.io/github/v/release/yusufyesil/notchboard?style=flat-square&label=release&color=5dcaa5" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111?style=flat-square&logo=apple&logoColor=white" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift and SwiftUI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-3b7dd8?style=flat-square" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/network-none-6e6a62?style=flat-square" alt="No network access">
</p>

<p align="center">
  <a href="https://github.com/yusufyesil/notchboard/releases/latest/download/Notchboard.dmg"><img src="https://img.shields.io/badge/Download_for_Mac-.dmg-000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for Mac" height="40"></a>
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#features">Features</a> ·
  <a href="#how-it-compares">Compare</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#faq">FAQ</a> ·
  <a href="docs/README.tr.md">Türkçe</a>
</p>

<p align="center">
  <img src="docs/images/closed.svg" width="760" alt="Notchboard closed in the menu bar: a sad pixel creature, two project logos stacked, a red 1 for a failed routine and orange dots for a chat at work">
</p>

<p align="center"><sub><b>Closed:</b> the most urgent project's critter, the projects that want a look, and what's failing or working.</sub></p>

<p align="center">
  <img src="docs/images/preview.svg" width="760" alt="Notchboard open under the notch: an Attention card with a failed routine, then chats grouped by project with logos, pixel creatures and a profile badge">
</p>

<p align="center"><sub><b>Open on hover:</b> problems on top, everything else grouped by project. Illustrations with sample data.</sub></p>

<!-- Add a short screen recording here once there is one: docs/images/demo.gif (hover the notch, switch tabs, click a chat). -->

Notchboard is a small, native macOS app that lives in the notch. It reads the files Claude Desktop already keeps on your Mac and shows what your chats and scheduled routines are doing: which one is typing, which one replied, which one is waiting for you, which routine failed or never ran. Hover to see the list; click a row to jump into that chat.

## Install

1. **[Download Notchboard.dmg](https://github.com/yusufyesil/notchboard/releases/latest/download/Notchboard.dmg)**, open it and drag **Notchboard** to **Applications**.
2. Open Notchboard. macOS says it can't verify the app, because builds aren't notarized by Apple yet. Click **Done**.
3. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to Notchboard. You only do this once.
4. In the window that appears, turn on **Open at login**.

Requires macOS 14 Sonoma or later, on Apple silicon or Intel. Homebrew is coming; see [docs/RELEASING.md](docs/RELEASING.md).

<details>
<summary><b>Build from source</b></summary>

<br>

Needs the Swift toolchain (Xcode or the Command Line Tools). No approval step: the app is built on your Mac.

```bash
git clone https://github.com/yusufyesil/notchboard.git
cd notchboard
./build.sh
```

`build.sh` builds a release binary, installs it as `~/Applications/Notchboard.app` and starts it with a LaunchAgent (`~/Library/LaunchAgents/app.notchboard.plist`) so it opens at login. Run it again to update; it stops the app and updates the bundle in place.

</details>

<details>
<summary><b>First launch: permissions</b></summary>

<br>

A **Permissions and settings** window explains what Notchboard needs. Reopen it any time from the right-click menu on the notch.

| | |
|---|---|
| **Read Claude data** | Usually works out of the box. If nothing shows up, grant Full Disk Access. |
| **Notifications** | Optional. New replies, questions and routine results. |
| **Open chats** | macOS asks whether Notchboard may control Claude. This is what opens a chat in the right profile. |
| **Open at login** | Starts Notchboard when you log in. |

</details>

<details>
<summary><b>Uninstall</b></summary>

<br>

Quit Notchboard from its right-click menu, then delete `Notchboard.app`, `~/Library/LaunchAgents/app.notchboard.plist` and `~/Library/Application Support/Notchboard`.

To only stop it from opening at login:

```bash
launchctl bootout gui/$(id -u)/app.notchboard
```

</details>

## Features

### 👥 Every Claude profile in one list

Run several copies of Claude Desktop with Claude Profiles, say a work and a personal account? Notchboard finds each one and merges them into one list.

- The same project in two profiles shows up as **one group**.
- Rows from an extra profile carry a small **badge in that profile's Dock colour**.
- A menu at the top right narrows the list to one profile.
- **A click opens the chat in the right profile's window.** Notchboard sends the link to that exact Claude process, so it doesn't land in whichever copy macOS picks.

### ⏰ Routine tracking

Scheduled tasks are first class, not an afterthought.

- The last run of each routine: **succeeded**, **failed**, **missed** (the time passed with no run, say the Mac was asleep) or **never ran**.
- The **next run** on every row; the closed notch counts down to the soonest one.
- Failures and missed runs land in an **Attention** card. **OK** acknowledges one, **Acknowledge all** clears the card, and a routine that fails again comes back.
- Hover a routine to read its summary or error.

### 🗂️ Grouped by project, with real logos

Chats and routines are grouped by the project folder they run in; worktrees are filed under their repository.

- Notchboard **finds each project's logo**: an app icon, a root `logo` or `icon` file, a favicon, a `logo` or `brand` folder. Build output, dependencies and archives are skipped.
- No logo? The project's initial on a colour of its own.
- **Right-click a group** to choose a logo, use the initial, go back to automatic, or show the folder in Finder.
- Logos also show in the Attention card, in the closed notch and in notifications.

### And also

| | |
|---|---|
| 📬 **Inbox logic** | A chat is unread when Claude replied after you last opened it. Questions and errors go to Attention; a click marks it read. |
| 👾 **Pixel critters** | Each row has a tiny creature in the project's logo colour. It types while Claude works, waves when it needs you, hops on a new reply, slumps on a failure, sleeps otherwise. |
| 🔌 **Zero setup** | No hooks, no plugins, no changes to Claude's settings. Notchboard reads the files Desktop already writes. |
| 🔒 **Fully local** | No network requests at all. Nothing leaves your Mac. |
| 🔔 **Notifications** | Optional; a click opens the right profile. |
| 🖥️ **No notch? Fine.** | On an external display it sits in the middle of the menu bar. |
| 🌍 **English and Turkish** | Follows your macOS language order. |

## How it compares

Most notch apps for AI agents watch **terminal** agents (Claude Code CLI, Codex and others) through hooks. Notchboard is built for **Claude Desktop**.

| | Notchboard | Claude Island | Open Island | Vibe Island |
|---|:---:|:---:|:---:|:---:|
| Built for | Claude Desktop | Claude Code CLI | Terminal agents | Terminal agents |
| How it gets data | Desktop's own files | Hooks | Hooks | Hooks |
| Setup | None | Installs hooks | Installs hooks | Installs hooks |
| Scheduled routines: status, next run, missed | ✅ | — | — | — |
| Several Claude profiles in one list | ✅ | — | — | — |
| Opens a chat in the right profile's window | ✅ | — | — | — |
| Live terminal events: tool calls, permission prompts | — | ✅ | ✅ | ✅ |
| License | MIT | Open source | GPL-3.0 | Paid |

If you live in the terminal, one of the others is probably the better fit. If you live in Claude Desktop, especially with routines or more than one profile, that's what Notchboard is for. <sub>Based on each project's public description as of October 2026; corrections welcome.</sub>

## How it works

Notchboard re-reads these files every 15 seconds. It only reads them; it never writes to Claude's folders.

| What | Where |
|---|---|
| Routines and their schedules | `~/Library/Application Support/Claude/claude-code-sessions/*/*/scheduled-tasks.json` |
| Each session's title, activity, error and summary | `local_*.json` in the same folders (and in `local-agent-mode-sessions`) |
| Whether a turn is in progress | The last entries of `~/.claude/projects/*/<session>.jsonl` |
| Extra profiles | `~/.claude-instances/<slug>/`, same layout as the main folder |
| Profile names and colours | Launchers in `~/Applications` with bundle id `local.claude-profiles.<slug>`, and `~/.claude-instances/.runtime/badges` |
| Project logos | Image files inside each project folder |

A session counts as running when the transcript's last message is a tool call, a tool result or your prompt; one quiet for 10 minutes counts as stopped. A chat is unread when its last activity is later than when you last focused it in Desktop (`lastFocusedAt`).

Notchboard keeps its own state in `UserDefaults` (`app.notchboard`): acknowledgements, read marks, when you last looked, logo choices. Logos you pick are copied to `~/Library/Application Support/Notchboard/logos`.

> [!NOTE]
> These are Claude Desktop's internal files, not a public API. A Desktop update can change them, and Notchboard may need an update in turn.

<details>
<summary><b>Command-line flags</b></summary>

<br>

Handy for checking what Notchboard reads, and for bug reports:

```bash
# Print the state of the latest chats and every routine, then exit
/Applications/Notchboard.app/Contents/MacOS/Notchboard --states

# Print the logo Notchboard would pick for each project folder, then exit
/Applications/Notchboard.app/Contents/MacOS/Notchboard --find-icon ~/code/my-app ~/code/other-app
```

Open on the Routines tab instead of Chats:

```bash
defaults write app.notchboard startTab routines
```

(Built from source? The app is in `~/Applications` instead.)

</details>

## Privacy

- **No network access.** No analytics, telemetry or update checks.
- Reads only the files listed above, all on your Mac.
- Chat titles and summaries appear only in the notch and, if you allow them, in macOS notifications.

## Compatibility

| | |
|---|---|
| macOS | 14 Sonoma or later. Tested on macOS 27.0. |
| Claude Desktop | Tested with 2.37337.1. |
| Profiles | Claude Profiles copies in `~/.claude-instances`. |
| Hardware | Apple silicon and Intel; with or without a notch. |

## FAQ

<details>
<summary><b>Does it work with the Claude Code CLI on its own?</b></summary>
<br>
Partly. Notchboard lists the sessions Claude Desktop knows about. Terminal-only sessions don't appear; for those, a hook-based app like Claude Island is a better fit.
</details>

<details>
<summary><b>Can I reply to Claude or approve a tool call from the notch?</b></summary>
<br>
No. Notchboard shows status and takes you to the right chat; you reply in Claude Desktop.
</details>

<details>
<summary><b>Nothing shows up.</b></summary>
<br>
Open <b>Permissions and settings</b> from the right-click menu. If "Read Claude data" isn't green, grant Full Disk Access to Notchboard in System Settings. Then run <code>Notchboard --states</code> to see what it reads.
</details>

<details>
<summary><b>A click opens Claude but not the chat.</b></summary>
<br>
Allow "Open chats" in Permissions and settings (macOS asks whether Notchboard may control Claude). Without it, Notchboard can only bring Claude to the front.
</details>

<details>
<summary><b>The wrong logo shows up.</b></summary>
<br>
Right-click the project's header and choose a logo, or use the initial.
</details>

<details>
<summary><b>How do I get the Turkish interface?</b></summary>
<br>
It follows your macOS language order. To force it for Notchboard only: <code>defaults write app.notchboard AppleLanguages -array tr</code>
</details>

<details>
<summary><b>macOS says the app was "prevented from modifying apps".</b></summary>
<br>
That happens when the bundle is deleted while the app runs. <code>build.sh</code> stops the app first and updates it in place; use it rather than copying the app by hand.
</details>

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)

<br>

<p align="center"><sub>Notchboard is an independent project. It is not affiliated with, endorsed by or sponsored by Anthropic. "Claude" is a trademark of Anthropic, used here only to say what Notchboard works with.</sub></p>
