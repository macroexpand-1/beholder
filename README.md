# color/

Both themes in this repo, light and dark, are **solved, not chosen**.
This directory holds the solver, the supporting optics calculations, and the write-up explaining why the palette looks the way it does.
The write-up covers the light theme; `theme/README.md` covers what dark does differently.

Nothing here is symlinked or sourced at runtime: it is tooling and documentation.
The palettes themselves are pinned as literal hex in `theme/light/` and `theme/dark/` (Ghostty and git), `doom/config.el` and `starship/starship.toml`.

`tig/tigrc` and `zsh/.zshrc` pin **no** hex.
tig rejects `#rrggbb` and ignores palette indices 16-255, and `LSCOLORS` takes only letters, so both name ANSI slots 0-15, i.e. the Ghostty slot hexes reused as foregrounds.
Those slots are the theme, so neither needs separate light/dark tuning; `verify` still measures each tig role (the `tig:*` rows) so a palette edit that darkens a slot can't push a tig color below AA unnoticed.

The web house sheets (`web/house-light.css`) are not solved here: their accents were re-solved against `#f4efe3` separately, and nothing in this directory measures them.

## Start Here

**[writeup.html](writeup.html)** is the full reasoning.
It is self-contained (the house stylesheet is embedded, so it renders correctly when opened from Finder).
It covers why light mode is an optics result rather than a preference, why the background is warm and not white, the red/green constraint, and the contrast-versus-colorfulness tradeoff that drove the final design.

## Scripts

| Script | What It Does |
|---|---|
| `solve-palette.lisp verify` | Re-measure every deployed color in both themes, read from the config files themselves (each theme's `:sources` in `*themes*` says where each lives). Exits non-zero if anything falls below AA for any of the three observers, or if a source line has gone missing. `githooks/pre-commit` runs it whenever a palette file is staged. `verify dark` measures one theme. |
| `solve-palette.lisp syntax [dark]` | Re-solve the `doom/config.el` font-lock faces for that theme's face block. |
| `solve-palette.lisp prompt [dark]` | Re-solve `starship/starship.toml`'s `[palettes.paper]` (or `[palettes.sage]`). |
| `solve-palette.lisp diff [dark]` | Re-solve `theme/light/gitconfig`'s (or `theme/dark/gitconfig`'s) diff colors. |
| `solve-palette.lisp ansi dark` | Re-solve Ghostty's ANSI slots 1-6 in `theme/dark/ghostty`. The light slots predate this mode and were solved separately. |
| `pupil.lisp` | Pupil diameter and retinal blur per background luminance. |
| `lca.lisp` | Longitudinal chromatic aberration per wavelength. |
| `tradeoff.lisp` | Maximum chroma a background can carry at a given contrast floor. |
| `colorlib.lisp` | Shared color math. `load`ed by `solve-palette.lisp` and `tradeoff.lisp`; not runnable alone. |

Common Lisp, no dependencies beyond SBCL (already in the `Brewfile`); each script carries a `#!/usr/bin/env -S sbcl --script` shebang and runs in place.
`colorlib.lisp` carries the sRGB transfer function, WCAG contrast, CIELAB, and the Viénot/Brettel/Mollon dichromat simulation.

## Two Things That Are Easy to Get Wrong

**Contrast must be checked per observer.**
WCAG's luminance coefficients encode a *normal* observer's luminous efficiency, so a saturated red that measures 4.5:1 reads noticeably darker to a protanope.
`worst-contrast` takes the minimum across normal, protan and deutan simulation.
Checking only the default observer is the single most common way to ship an inaccessible red.

**The two solving modes are not interchangeable.**
Body text and syntax are solved for *contrast*; the prompt, diffs and status text are solved for *chroma subject to a contrast floor*.
On a light background these genuinely conflict (sRGB's most chromatic colors sit at middle lightness), so contrast above what a surface needs is paid for in colorfulness.
The first version of this theme maximized contrast everywhere (syntax keywords at 11.06:1 against a 4.5 requirement) and looked dead as a result.

## Regenerating

The solver is a search, not a closed form, so its output can land away from what is pinned in the configs.
Treat the configs as authoritative and the solver as the thing you re-run when a *constraint* changes: a new background, a different floor, an added syntax category.

Do not hand-edit a single hex to taste.
The constraints interact: every color is scored against every other one for worst-observer separation, so nudging one value tends to break a pair somewhere else.
Change the constraint and re-solve.

## Hand-Tuned Exceptions

Two syntax colors in `doom/config.el` are tuned by hand, not solved, and that is deliberate.
Running `solve-palette.lisp syntax` will not reproduce them: its string band is still green and its type band still olive.
Do not "fix" the configs back to the solver's output.

| Face | Solved | Deployed | Why |
|---|---|---|---|
| `font-lock-string-face` | `#036831` green | `#b33204` orange, 4.54:1 | The green was disliked, and in practice ran together with nearby colors |
| `font-lock-type-face`, `font-lock-preprocessor-face` | `#696406` olive | `#a7037b` magenta, 5.17:1 | Too drab to pick out at a glance |

Chosen on 2026-11-01 by eye in Emacs, with each candidate measured against the other syntax colors held fixed.
Orange string vs magenta type is 74.4 dE for the worst observer, and every pair still clears 16 (closest touching either new color: magenta vs builtin teal, 17.7).
The orange is the lightest that clears AA and sits under the solver's 5.0 floor on purpose; the darker `#a53302` (5.05:1) was tried and read too dark.
Which hue went on which face was also a judgment of how much of each color lands on the page, not a separation result: the swap is separation-neutral.
`verify` measures the two deployed hexes, not the solver's green and olive.
