# mmrtb.ca

Bilingual (fr-CA / en-CA) website for MMRTB, hosted on GitHub Pages.

## Editing

| To change… | Edit |
|---|---|
| Text of a page | `pages/fr/…` or `pages/en/…` (the part below the `---` header) |
| Google title / description of a page | the `title:` and `description:` lines in that page's `---` header |
| Email, phone, booking link, LinkedIn, service list, cities served | `site.json` (an empty value is hidden on the site) |
| Header, footer, menu | `layout.html` and the `locales` section of `site.json` |
| Colours, spacing | the `:root` block at the top of `static/assets/site.css` |

Every French page has an English twin: the `alt:` line names the other one, and
the build stops if a page and its twin don't point at each other.

## Preview and publish

```powershell
pwsh -File tools/serve.ps1     # builds, then serves http://localhost:8642
```

Pushing to `main` runs `build.ps1` on GitHub and publishes `_site/`.
`build.ps1` also writes `sitemap.xml`, `robots.txt`, structured business data
and the fr/en language links, and warns when a title or description is too long
for Google.

`tools/make-images.ps1` re-renders the share images and icons (needs Edge) after
changing `static/favicon.svg` or `tools/og.html`.
