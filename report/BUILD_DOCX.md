# Building the submission document

The brief requires the report as **MS Word**, **1.5 line spacing**, **11 pt Calibri
(Body)**, and **2.54 cm margins on all four sides**, with appropriate section
headings, IEEE in-text citations and an IEEE reference list.

Pandoc cannot set those properties from the command line. It copies them from a
**reference document**, so the one-time job is to create a `reference.docx` whose
styles already match the brief; after that every rebuild is a single command.

---

## 1. Install pandoc

```bash
# macOS
brew install pandoc

# Debian / Ubuntu
sudo apt-get install -y pandoc
```

Check: `pandoc --version` (3.x recommended).

## 2. Create the reference document — once

```bash
cd report
pandoc -o reference.docx --print-default-data-file reference.docx
```

Open `reference.docx` in Word and set the styles below. Edit the **styles**, not the
text — Word applies a style to every paragraph that uses it, so editing the style is
what makes the whole document compliant.

### Page setup

**Layout → Margins → Custom Margins**: Top, Bottom, Left, Right = **2.54 cm**.

### Styles to modify

Open the Styles pane, right-click each style → **Modify**:

| Style | Font | Size | Spacing | Notes |
|-------|------|-----:|---------|-------|
| **Normal** | Calibri (Body) | 11 pt | Line spacing **1.5** | Sets the body text. Do this one first — most others inherit from it |
| **Body Text** | Calibri (Body) | 11 pt | 1.5 | Pandoc uses this for paragraphs |
| **First Paragraph** | Calibri (Body) | 11 pt | 1.5 | Pandoc's style for the first paragraph after a heading |
| **Compact** | Calibri (Body) | 11 pt | 1.5 | Used inside list items |
| **Heading 1** – **Heading 4** | Calibri (Body) | 16 / 14 / 12 / 11 pt bold | 1.5 | Keep the hierarchy visible |
| **Table Caption**, **Image Caption** | Calibri (Body) | 10 pt italic | single | Captions may stay single-spaced |
| **Source Code** | Consolas or Courier New | 9 pt | single | Configuration listings; a monospaced font is essential for alignment |
| **Table** / **Table Grid** | Calibri (Body) | 9–10 pt | single | Wide addressing tables need the smaller size to fit the page |

For each style, in **Modify → Format → Paragraph**, set **Line spacing: 1.5 lines**.

Save and close. Keep `reference.docx` in the repository so every rebuild is identical.

## 3. Build

```bash
cd report
pandoc PartA_Report.md \
  --reference-doc=reference.docx \
  --toc --toc-depth=2 \
  --number-sections \
  --resource-path=.:figures \
  -f gfm+tex_math_dollars \
  -o PartA_Report.docx
```

| Flag | Why |
|------|-----|
| `--reference-doc` | Applies the Calibri / 11 pt / 1.5 spacing / 2.54 cm styles |
| `--toc --toc-depth=2` | Table of contents down to `##` headings |
| `--number-sections` | Numbers headings, so cross-references like "see §4.4" resolve |
| `--resource-path=.:figures` | Lets figures be referenced as `figures/…` or bare filenames |
| `-f gfm+tex_math_dollars` | GitHub-flavoured Markdown, which is what the pipe tables are written in |

## 4. Optional PDF

```bash
# Via LaTeX
pandoc PartA_Report.md -o PartA_Report.pdf \
  -V geometry:margin=2.54cm -V fontsize=11pt \
  -V mainfont="Calibri" --pdf-engine=xelatex \
  --toc --number-sections

# Or via WeasyPrint (no LaTeX needed)
pandoc PartA_Report.md -t html5 -s --toc --number-sections \
  -c print.css -o PartA_Report.html
weasyprint PartA_Report.html PartA_Report.pdf
```

`print.css` for the WeasyPrint route:

```css
@page { size: A4; margin: 2.54cm; }
body  { font-family: Calibri, Carlito, sans-serif; font-size: 11pt; line-height: 1.5; }
pre, code { font-family: Consolas, "Courier New", monospace; font-size: 9pt; }
table { border-collapse: collapse; width: 100%; font-size: 9.5pt; }
th, td { border: 1px solid #999; padding: 4px 6px; text-align: left; }
thead { background: #f0f0f0; }
h1 { page-break-before: always; }
h1:first-of-type { page-break-before: avoid; }
```

**Submit the `.docx`.** The brief specifies MS Word format; treat the PDF as a
convenience copy unless your tutor says otherwise.

---

## 5. Mermaid diagrams

The three topology diagrams live as Mermaid source in
[`../docs/TOPOLOGY.md`](../docs/TOPOLOGY.md). Pandoc does not render Mermaid, so
export them to PNG first.

**Easiest — no install.** Open `docs/TOPOLOGY.md` on GitHub, which renders Mermaid
natively, and screenshot each diagram at a high zoom.

**Reproducible — CLI.**

```bash
npm install -g @mermaid-js/mermaid-cli

# Save each mermaid block from docs/TOPOLOGY.md as a .mmd file, then:
mmdc -i fig1-zones.mmd     -o report/figures/fig1-zones.png     -w 2400 -b white
mmdc -i fig2-physical.mmd  -o report/figures/fig2-physical.png  -w 3200 -b white
mmdc -i fig3-ospf.mmd      -o report/figures/fig3-ospf.png      -w 2000 -b white
```

Figure 2 is wide — render it at `-w 3200` and consider placing it landscape or across
a full page.

---

## 6. Before submitting — checklist

**Format, from the brief**

- [ ] `.docx`, opens correctly in MS Word
- [ ] 11 pt Calibri (Body) body text
- [ ] 1.5 line spacing throughout the body
- [ ] 2.54 cm margins on all four sides
- [ ] Section headings present and numbered
- [ ] Completed Assignment Cover Page attached
- [ ] Word count within limit — 2000 across Parts A, B and C. Count body prose only; exclude tables, figures, captions, code listings, references and appendices. Confirm what your tutor counts if unsure

**Content**

- [ ] All figure placeholders replaced with real images
- [ ] All `SS-nn` screenshot slots filled — see [`../verification/CHECKS.md`](../verification/CHECKS.md) §12
- [ ] §6 verification results filled in and the "pending execution" banner removed
- [ ] Sign-off matrix in `CHECKS.md` §11 completed
- [ ] At least five IEEE references, each verified against the source, with access dates
- [ ] Reference [9] updated to the exact Cisco design guide consulted
- [ ] GenAI declaration present and accurate, and entry [13] added to the reference list
- [ ] No Cisco IOS binary image committed to the repository — the images are proprietary and must not be redistributed

**Lab state matches the report**

- [ ] `python3 scripts/validate_configs.py` exits 0
- [ ] All five router configurations re-applied (see [`../docs/APPLY_STEPS.md`](../docs/APPLY_STEPS.md))
- [ ] The three loop-closing cross-links deleted in GNS3
- [ ] `PC5`/`PC8` placement decided, and the lab and documents agree — see `REVIEW_FINDINGS.md` R-17

The last group matters more than it looks. A report that disagrees with the
screenshots undermines every other piece of evidence in it, regardless of how good
either one is alone.

---

## 7. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Body text is Cambria, not Calibri | `reference.docx` not passed, or **Normal** style not modified | Confirm `--reference-doc=reference.docx` and re-edit the **Normal** style |
| Spacing still single | Only the font was changed | In each style: **Modify → Format → Paragraph → Line spacing: 1.5 lines** |
| Wide tables run off the page | Default table font too large | Set the **Table** style to 9 pt; set that section landscape if still too wide |
| Config listings wrap and lose alignment | Proportional font applied to code | Set **Source Code** to Consolas 9 pt |
| Images missing | Relative path not resolved | Add `--resource-path=.:figures`, and confirm the filenames match `CHECKS.md` §12 |
| Mermaid blocks appear as raw text | Pandoc does not render Mermaid | Export to PNG per §5 and reference the image |
