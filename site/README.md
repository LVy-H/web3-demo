# Tessera — marketing / showcase site

A lightweight, **static** marketing + blog site for Tessera, the open-source,
self-hostable verifiable bulletin board for trustworthy group decisions.

Hand-authored **HTML + CSS** (plus one inline SVG mark). No framework, no build
step, no JavaScript required. It opens directly in a browser and deploys to any
static host.

> This is the *marketing* site only. It is self-contained in `site/` and is
> **not** the Tessera app (the Flutter client) — the live demo embeds into the
> `#demo` placeholder on the landing page later.

## Why these claims are safe to ship

The copy is deliberately **honest** — no "trustless", no "unhackable", no
overclaimed privacy against the host. Every claim is sourced from the system
design doc:

- `docs/superpowers/specs/2026-06-19-tessera-system-design.md`
  — §1 core job · §2 actors · §6 honest threat model · §8 bulletin board ·
  §11 verification protocol · §13 the "why not Google Forms + a hash?" table ·
  §16 1.0 vs post-1.0.
- `docs/project/ROADMAP.md` and `docs/project/STATUS.md` — current status and
  "what changed and why".

The honest threat model (`honesty.html`) mirrors §6 exactly: what holds even
against a malicious host, what rests on host honesty, and what is out of scope.

## Structure

```
site/
├── index.html        Landing: hero · problem · how-it-works (+ diagram) ·
│                      "why not a Google Form?" table · self-host · demo slot
├── honesty.html      "What Tessera does and doesn't guarantee" (the §6 anchor)
├── styles.css        Shared Dark Bauhaus stylesheet (tokens from the design system)
├── assets/
│   └── tessera-mark.svg   Brand mark / favicon (mirrors branding/tessera-mark.svg)
├── blog/
│   ├── index.html
│   ├── why-we-rebuilt-tessera-from-first-principles.html
│   └── how-you-can-check-the-result-yourself.html
└── README.md         (this file)
```

## Design language

"Dark Bauhaus" — high-contrast, bold geometric, restrained palette, sharp
corners, hairline rules, Inter + JetBrains Mono. The colour tokens in
`styles.css` (`:root` custom properties) are a 1:1 port of `Db.*` from
`codes/app/packages/design_system/lib/theme.dart`, so the site matches the app.

The brand mark is the same 3×3 mosaic with one offset, rotated `segnale` tile
("the one anonymous voice") used across `branding/`.

## Preview

It's static — just open the file:

```bash
# macOS
open site/index.html
# Linux
xdg-open site/index.html
```

Or serve it with any static server (recommended, so relative links and the
favicon resolve exactly as in production):

```bash
# Python
python3 -m http.server 8080 --directory site
# Node
npx serve site
```

Then visit <http://localhost:8080>.

## Deploy

Any static host works — no build step.

- **Cloudflare Pages / GitHub Pages / Netlify:** point the host at the `site/`
  directory (or set it as the publish/output directory). No build command.
- **GitHub Pages from a subfolder:** publish `site/` (e.g. via an action that
  uploads `site/` as the Pages artifact), or move the contents to the repo root
  of a `gh-pages` branch.

All asset paths are **relative**, so the site works from any base path.

## Adding the live demo

The landing page reserves a single, obvious spot:

```html
<div id="demo"> … placeholder … </div>
```

in `index.html` (the "See it in action" section). Replace the inner placeholder
markup with the Flutter web app `<iframe>` or a launch link when the demo is
ready. Nothing else needs to change.
