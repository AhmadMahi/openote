<div align="center">

# Slate

**An open source OneNote alternative with a glassmorphism design and a lot of extra features.**

*Your notes. Your format. Every platform.*

`Freeform canvas` · `Handwriting & math` · `Open file format` · `Local-first` · `Glassmorphism UI` · `macOS · Windows`

</div>

---

> **Usable today, and still actively developed.** Slate is a real, working app:
> a freeform canvas, ink, math, live Markdown, an open file format, sync through
> any folder you already have, a OneNote importer that handles real notebooks,
> flashcards from your own notes, and a planner, wrapped in a new glassmorphism
> interface. It still gets frequent updates, and an update can occasionally
> break a feature until the next one fixes it. Whatever happens, your notes are
> safe: they live on your own machine in an open, documented format that stays
> readable without Slate, so nothing is locked in. Released builds are macOS and
> Windows; the codebase is cross-platform and Linux can be built from source.

## Install

Grab the latest build from the [Releases page](https://github.com/AhmadMahi/openote/releases).

| | Download | Then |
|---|---|---|
| **macOS** | `slate-*-macos-universal.dmg` | Open it, drag **Slate** to Applications. |
| **Windows** | `slate-*-windows-x64-setup.exe` | Run it. Installs for your user only, so it never asks for an administrator password. (Prefer no installer? The `.zip` is the same build.) |

Your notes are written to your own machine in an open, documented format. There
is no account, and nothing is uploaded anywhere.

### Your operating system will warn you. Here is why, honestly.

Slate is not code-signed. Certificates cost a few hundred dollars a year per
platform, and while the project is this young that money buys nothing a user
would notice. The warnings do not mean the software is unsafe, only that we have
not paid to tell your OS who we are. Every release is built by the
[public workflow](.github/workflows/release.yml) in this repository, from the
tagged commit.

- **Windows**: *"Windows protected your PC"*, click **More info** then **Run anyway**.
- **macOS**: *"Slate is damaged and can't be opened"*, after copying to
  Applications run `xattr -cr /Applications/Slate.app` once.

## What is Slate?

Microsoft OneNote is, for many people, the best freeform note-taking tool ever
made: an infinite canvas where you click anywhere, drop a text box, draw with a
pen, and write complex equations, all inside a familiar notebook, section and
page structure. Nothing open has quite matched it.

But OneNote traps your notes in a proprietary format, defaults to a mandatory
cloud, has no native Linux client, gates core features behind subscriptions, and
has ignored years of requests for Markdown, an open format, and backlinks.

Slate matches OneNote's experience with open technology, and fixes its
structural failings by construction:

- 🎨 **A genuine freeform infinite canvas**: click anywhere, place anything, pan and zoom in every direction, free-form or snap-to-grid.
- 🗂️ **The notebook hierarchy you know**: notebooks, section groups, sections, pages, subpages.
- ✍️ **Rich text with inline-rendered Markdown**: formatting appears where you type it.
- 🪟 **Live page embeds**: render a block, range or region of another page inside the current one, always up to date and click-through to the source.
- ➗ **Beautiful math entry**: type linearly and watch it build into 2-D notation, OneNote-style.
- 🖊️ **First-class pen and handwriting**: low-latency, pressure-sensitive ink you can write and draw with anywhere.
- 📦 **An open, documented file format**: local-first, no lock-in, no size limits, readable without us.
- ☁️ **Cloud-optional sync**: work across your devices, bring your own backend, no account required.
- 🐧 **Cross-platform**: desktop-first, tablets close behind.

## What Slate adds

Slate is a redesign and an expansion built on top of Openote. The engine is the
same proven canvas, ink and open format; the interface and much of the
day-to-day experience are new:

- **A glassmorphism interface**: ambient page backgrounds, frosted-glass panels, a soft accent colour that washes the whole app, and full light and dark themes.
- **A Home dashboard**: every notebook as a card with its real page and section counts, and a Recent pages row to jump back to where you were.
- **A notebook overview**: a notebook's sections and pages laid out as tiles.
- **One calm toolbar**: Format, Insert and View as tidy popovers, with the drawing tools always to hand, instead of four tabs.
- **Floating canvas controls**: zoom, fit-to-width and focus mode in the page's own top-right corner.
- **A focus mode**: the page edge to edge with a floating glass tool palette and nothing else around it.
- **Sectioned Settings**: a sidebar of sections instead of one long scroll, plus **default page settings** (pattern, spacing, paper, page size, stretch to screen) for new pages.
- **Colour palettes done right**: delete a saved palette in place, and a **Random colours** swatch that rolls a fresh, distinct, theme-visible set each time you tap it.
- **More page backgrounds**: the signature ambient paper, plus Blue grey, Sage, Sky, Blush, Charcoal and Midnight.
- **Live page thumbnails**: in a paged document, the page strip shows each page as a small live preview of its real content, with drag-to-reorder and per-page delete.
- **Native desktop chrome**: opens on Home, a rounded page card everywhere including full screen, and an in-app update check against this repository's releases.

## Credits

Slate is a fork of **Openote** by [icmric](https://github.com/icmric/openote).
The freeform canvas, the open `.onote` file format, the OneNote importer and the
native Rust core are the original project's work, and Slate would not exist
without it. Huge thanks to the original author. Slate builds a new interface and
a wider feature set on that foundation.

## Guiding principles

1. **Your data is yours**: an open format, documented and versioned from day one.
2. **Local-first, cloud-optional**: fully usable offline, no account required.
3. **The canvas is sacred**: freeform placement, fast startup and responsive ink come first.
4. **Interpret, don't interrupt**: formatting happens where you type it.
5. **Native feel on every platform**: cross-platform, not lowest-common-denominator.
6. **Open by construction**: an open license, a published format spec, an extensible core.

## Documentation

Start here → **[docs/README.md](docs/README.md)**. Design and specification
documents live under [`docs/`](docs/README.md); build instructions are in
[`app/README.md`](app/README.md); and what is and isn't verified is tracked
honestly in [TESTING.md](TESTING.md).

## License

Three tiers, mapped in full in [LICENSING.md](LICENSING.md):

- **[AGPL-3.0-or-later](LICENSE)**: the application. Fork it, self-host it, modify it; improvements stay open, including for hosted forks.
- **[Apache-2.0](rust/onote_core/LICENSE)**: `onote_core`, the `.onote` reader/writer, hashing and importers. Build anything you like on it, including closed commercial software.
- **[CC0-1.0](docs/specs/LICENSE)**: the file-format specification. Implement it freely, no attribution required.

The asymmetry is the point: the app resists closed forks, while reading and
writing your notes is legally frictionless for everyone. Contributions are
inbound = outbound with a [DCO](https://developercertificate.org/) sign-off
(`git commit -s`) and no CLA.

## Contributing

Ideas, critiques and expertise, especially on cross-platform ink, rich-text
editing, CRDTs and math input, are very welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md).

---

<div align="center">
<sub>Slate is not affiliated with or endorsed by Microsoft. "OneNote" and "Microsoft" are trademarks of Microsoft Corporation, referenced here for comparison and interoperability only.</sub>
</div>
