# Solving a Terminal Palette for One Pair of Eyes

This is the reasoning behind the light theme in this repo.
The short version: none of the colors were chosen.
They were solved, against four constraints that fight each other, and the interesting part is *how* they fight.

## The Constraints

| Condition | What It Demands |
| --- | --- |
| Myopia −1.25 + astigmatism | Residual blur even when corrected. Blur scales with pupil size. |
| Presbyopia (reading add) | Less accommodation available; depth of focus matters more. |
| Red/green color vision deficiency | The hue circle collapses to one axis. Half of normal color coding is unavailable. |
| Long working hours | Glare and absolute luminance are real costs, not aesthetics. |

## 1. Why Light, in Diopters

The usual dark-vs-light argument is taste.
This one isn't.
Pupil diameter is driven by field luminance, and geometric blur from residual defocus scales **linearly** with pupil diameter.

Using the Stanley & Davies (1995) pupil model as unified by Watson & Yellott (2012), at a 150-nit display white over a ~30°×18° field:

| Field | cd/m² | Pupil | Blur @ 0.50 D |
| --- | --- | --- | --- |
| TokyoNight Storm `#24283b` | 3.3 | 5.42 mm | 9.3 arcmin |
| Warm paper `#f2e9d8` | 123.2 | 3.44 mm | **5.9 arcmin** |

A 37% reduction in retinal blur from the same uncorrected error, and the astigmatic blur ellipse shrinks by the same factor.
This is the one change that helps defocus, astigmatism and presbyopia *simultaneously*.
It also retires the halation workaround the dark theme needed: dark-on-light spreads dark into light, which does not bloom.

## 2. Why Not White

Pure white constricts the pupil to 3.35 mm (only **0.09 mm** past the warm paper) while raising field luminance **22%**.
Essentially all of the optical benefit is already captured at L\* 92.6.
The rest is glare you'd be paying for nothing.

## 3. Why Warm

The eye is not corrected for chromatic aberration.
Thibos' chromatic-eye model (1992) gives the defocus of each wavelength relative to 555 nm:

| Wavelength | Defocus vs 555 nm |
| --- | --- |
| 450 nm (deep blue) | −0.83 D |
| 490 nm (cyan) | −0.44 D |
| 610 nm (red) | +0.26 D |

Blue is roughly **three times further out of focus than red**, and the total spread across the visible band is over a diopter; you cannot focus both ends at once.
Weighting the background long makes it the best-focused thing on screen.
It also has two knock-on rules: never put body text in saturated blue, and where blue must be used, give it extra *luminance* contrast, since the chromatic edge arrives blurred and only the luminance edge survives.

## 4. The Colorblind Constraint, and One Correction Most Tools Miss

Candidate colors are run through the Viénot, Brettel & Mollon (1999) dichromat simulation and scored on their *worst-case* separation across normal, protanope and deuteranope vision.
Taking the minimum rather than the mean is the whole point: a pair only counts as distinguishable if it survives every way of seeing it.

> **WCAG overstates reds.**
> The contrast formula's luminance coefficients encode a *normal* observer's luminous efficiency.
> A saturated red that measures 4.5:1 reads substantially darker to a protanope.
> Every color here is checked against all three observers, not just the default one, which is why some reds ended up darker than the naive calculation would require.

The structural consequence is severe and worth stating plainly: under dichromacy the hue circle collapses onto a single blue–yellow line.
Six syntax categories are therefore competing for room along *one axis plus lightness*.
Some faces must differ by lightness alone.
That is forced by the mathematics, not a failure of the palette.

## 5. The Finding That Changed the Design

On a light background you cannot maximize contrast and colorfulness at once: sRGB's most chromatic colors sit at middle lightness, and demanding contrast drags you away from there.
Measuring the average maximum CIELAB chroma achievable over 24 hues:

| Background | At AA 4.5:1 | At 7:1 |
| --- | --- | --- |
| Dark `#24283b` | **82.3** | 46.3 |
| Warm paper `#f2e9d8` | 72.8 | **60.4** |
| White | 77.5 | 66.0 |

The intuition that dark backgrounds carry bolder color is **correct at AA**, and it **inverts at high contrast**.
At 7:1 the paper carries 30% more chroma than the dark field, because bright saturated colors simply are not bright enough to hold contrast against black.
At the contrast these eyes need, light is the better substrate for vivid color.

Two practical consequences.
Lightening the paper is *not* a useful lever: going all the way to white buys ~6% chroma for 22% more glare.
The contrast floor is the lever: dropping 7:1 to 4.5:1 buys 20% more chroma.

## 6. Two Solving Modes

The original mistake was maximizing contrast everywhere.
Syntax keywords sat at **11.06:1 against a 4.5 requirement**: six wasted stops, paid for in color, which is exactly why the first light version read as uniformly dark and lifeless.

- **Read for minutes** (body text, syntax) → solve for contrast, 4.5–11:1.
  Correctness first.
- **Glanced at** (prompt, diffs, status) → solve for *chroma subject to a floor*.
  Everything above the floor is contrast you are not using; spend it as color.

Re-solving this way roughly tripled the chroma on the prompt directory and quadrupled it on added diff lines, changing no ratio that mattered.

### Hue Assignment by Token Frequency

Because dichromacy flattens hue to one axis, the richest and most separable bands should go to the tokens you see most.
Keywords therefore take **violet** rather than the customary amber, and types take the olive slot.
Swapping those two was worth **+302% chroma on keywords** and moved the solution from 97% to 100% of its separation targets.

Comments are a *neutral* gray, not a warm one: a warm comment and a green string both land on olive under deuteranope simulation, which had capped strings at +12% chroma.
Neutralizing the comment freed the entire green band and strings gained +177%.

## 7. Mistakes, and What Each One Teaches

| Mistake | Symptom | Rule It Produced |
| --- | --- | --- |
| Chose `doom-oksolar-light` for being "OKLab-derived and warm" | Every accent 2–4:1; its own fg 4.08:1 | Warm and light ≠ high contrast. Measure a base theme's palette before adopting it. |
| Inverted ANSI slot 0 to a near-background tone (the usual light-theme convention) | 1.13:1; TUIs using color 0 for dim text rendered invisible | Every ANSI slot must be readable as a *foreground*. Cost: nothing may paint a colored background. |
| Left git on xterm indices 39 and 208 | Stayed at ~2:1 through every theme change | Ghostty remaps only 0–15. Indices 16–255 are a fixed cube; use literal hex. |
| Assumed the terminal palette governed Claude Code and starship | Light-gray truecolor on paper | An app's own truecolor config bypasses the terminal entirely and needs its own light setting. |
| Put TOML top-level keys after a `[table]` header | Prompt silently reverted to starship's defaults, with no error | Bare keys bind to the most recent table. Validate, don't eyeball. |
| Optimized *mean* chroma across syntax faces | One face starved to near-black to feed the rest | Set per-slot chroma floors ranked by token frequency. |

## 8. The Deployed Palette

Background `#f2e9d8` (L\* 92.6), ink `#2f2b25` (11.63:1).
All values verified for normal, protanope and deuteranope observers.

| Role | Hex | Contrast | C\* |
| --- | --- | --- | --- |
| Syntax keyword (violet) | `#8620d9` | 5.03:1 | 102.0 |
| Syntax function (indigo) | `#1b25e3` | 7.09:1 | 111.9 |
| Syntax string (orange, hand-tuned) | `#b33204` | 4.54:1 | 72.3 |
| Syntax type (magenta, hand-tuned) | `#a7037b` | 5.17:1 | 68.6 |
| Syntax constant (red) | `#780404` | 8.62:1 | 56.7 |
| Syntax builtin (teal) | `#045b80` | 5.69:1 | 28.4 |
| Comment (neutral) | `#6b6862` | 4.59:1 | 3.8 |
| Git added | `#0e4ad8` | 5.52:1 | 85.9 |
| Git removed | `#b11902` | 5.00:1 | 76.5 |
| Prompt directory | `#0e4ad8` | 5.52:1 | 85.9 |
| Prompt branch | `#925401` | 4.71:1 | 54.6 |
| Prompt alert | `#880a01` | 7.39:1 | 63.2 |
| Prompt ok (teal) | `#0165a7` | 4.66:1 | 42.2 |

String and type were re-tuned by eye on 2026-11-01, away from the solver's green (`#036831`) and olive (`#696406`); see [examples/README.md](examples/README.md).
Weakest syntax pair as deployed: `keyword`/`function` at 16.2 ΔE for the worst observer, which is the target `examples/light/syntax.json` now uses for that pair.
`git added` vs `removed`: 120.9 ΔE; blue against warm rides the intact axis, so that pair survives completely.

## 9. Regenerating

```sh
bin/beholder assess examples/light/deployed.json   # re-measure everything deployed
bin/beholder solve  examples/light/syntax.json     # editor font-lock faces
bin/beholder solve  examples/light/prompt.json     # shell prompt
bin/beholder solve  examples/light/diff.json       # git diff colors

./pupil.lisp                                      # pupil size and retinal blur per field
./lca.lisp                                        # chromatic aberration per wavelength
./tradeoff.lisp                                   # chroma available per background
```

Re-measure after any palette edit; `assess` exits non-zero if anything falls below AA for any of the three observers.
The constraints interact, so nudging one hex by hand tends to break a pair somewhere else; change the constraints and re-solve instead.

## Sources

- Watson & Yellott (2012), *A unified formula for light-adapted pupil size*, J. Vision 12(10):12.
- Stanley & Davies (1995), *The effect of field of view size on steady-state pupil diameter*.
- Thibos, Ye, Zhang & Bradley (1992), *The chromatic eye*, Applied Optics 31:3594.
- Viénot, Brettel & Mollon (1999), *Digital video colourmaps for checking the legibility of displays by dichromats*, Color Res. Appl. 24:243.
- WCAG 2.1 contrast-ratio definition (with the normal-observer caveat noted in §4).
