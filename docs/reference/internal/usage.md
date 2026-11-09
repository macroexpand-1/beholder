# Beholder Usage Reference

The full description of beholder's two commands, their requests and responses, how the solver decides, the Lisp API, the tests and the scripts.
The top-level `README.md` covers what beholder is and how to build it; this page covers everything after that.

## The Commands

```sh
bin/beholder assess request.json     # check colors you have
bin/beholder solve  request.json     # have colors found for you
bin/beholder assess < request.json   # or read the request from standard input
```

Each command reads a JSON request and writes a JSON response to standard output.
The exit code says how it went:

| Code | Meaning |
|---|---|
| 0 | The colors passed (`assess`), or every target was met (`solve`) |
| 1 | They didn't, or a slot couldn't be filled at all |
| 2 | The request itself is bad: not JSON, a missing field, a bad hex, a file that can't be read |

A bad request still gets a JSON response, so a caller always has one stream to read:

```json
{
  "passed": false,
  "error": { "kind": "bad_request", "message": "colors.fg should be a color like \"#f2e9d8\"" }
}
```

`kind` lets a caller branch without reading the message: `bad_request` here, and `infeasible_slot` from `solve` (below).

Keys are snake_case, and colors are objects keyed by role in both directions.
Unknown fields are refused rather than ignored, so a misspelled field can't quietly fall back to its default.
Numbers come back at full precision.

## Assess

```json
{
  "background": "#f2e9d8",
  "colors": { "keyword": "#8620d9", "string": "#036831", "comment": "#6b6862" },
  "policy": {
    "floor": 4.5,
    "targets": {
      "default": 16,
      "pairs": [{ "roles": ["keyword", "string"], "de": 22 }]
    }
  }
}
```

Only `background` and `colors` are required.
A hex may leave out the `#`.

| Field | Default | Meaning |
|---|---|---|
| `policy.floor` | `4.5` | Minimum contrast, checked for the worst observer |
| `policy.ceiling` | None | Maximum contrast for normal vision, for dark themes where a too-bright accent glows |
| `policy.targets` | None | How far apart pairs must look, in dE; without it no pair is checked |
| `policy.observers` | `["normal", "protan", "deutan"]` | Whose eyes each check is taken for |

`targets.default` applies to every pair not listed in `targets.pairs`, and a pair's two roles can come in either order.

The response:

```json
{
  "passed": true,
  "background": "#f2e9d8",
  "colors": {
    "keyword": {
      "hex": "#8620d9",
      "contrast": { "normal": 5.407, "protan": 6.305, "deutan": 5.032 },
      "worst_contrast": 5.032,
      "chroma": 102.012,
      "lstar": 39.767,
      "passed": true
    }
  },
  "weakest_pair": { "roles": ["comment", "string"], "de": 19.548 },
  "short_pairs": []
}
```

(Shortened to one color, with numbers rounded for reading.)

| Field | Meaning |
|---|---|
| `passed` | Every color cleared the floor and stayed under any ceiling, and no pair came up short |
| `colors.ROLE.contrast` | Contrast against the background for each observer |
| `colors.ROLE.worst_contrast` | The lowest of those; the floor is checked against this |
| `colors.ROLE.chroma` | How colorful it is: 0 for a gray, higher for more vivid |
| `colors.ROLE.lstar` | Lightness, from 0 (black) to 100 (white) |
| `weakest_pair` | The two colors that look most alike, and how far apart; `null` with fewer than two colors |
| `short_pairs` | Every pair closer than its target, each with its `de` and `target` |

`weakest_pair` is always reported, even when everything passes, because it's the first thing to look at when tuning.

## Solve

```json
{
  "background": "#f2e9d8",
  "slots": {
    "keyword": { "hues": [272, 322], "floor": 5.0, "max_saturation": 0.78, "min_chroma": 46 },
    "string":  { "hues": [100, 165], "floor": 5.0, "min_chroma": 44 }
  },
  "fixed": { "fg": "#2f2b25", "comment": "#6b6862" },
  "targets": { "default": 16, "pairs": [{ "roles": ["keyword", "string"], "de": 22 }] },
  "search": { "lightness": [0.13, 0.58] }
}
```

A slot is a color to find: a band of hues in degrees, and a contrast floor it must clear for every observer.
A band across red, such as `[350, 10]`, wraps around.
`fixed` colors are ones you already have (body text, comments); the solver leaves them alone but keeps the new colors clear of them, so targets can name them.
A role can't be both a slot and a fixed color.

Only `background` and `slots` are required, and in a slot only `hues` and `floor`.

| Field | Default | Meaning |
|---|---|---|
| `max_saturation` | `1.0` | Highest HSL saturation tried for the slot |
| `min_chroma` | `0` | Least colorful the slot's color may be |
| `fixed` | None | Colors to keep clear of |
| `targets` | Default 16, no pairs | How far apart pairs must look, fixed colors included |
| `ceiling` | None | Maximum contrast for normal vision |
| `observers` | `["normal", "protan", "deutan"]` | Whose eyes the floor and targets are checked for |
| `search.lightness` | `[0, 1]` | HSL lightness band to search |
| `search.restarts` | `8` | How many random starting points to try |
| `search.hue_step` | `3` | Degrees between hues tried |
| `search.saturation_min` | `0.34` | Lowest HSL saturation tried |
| `search.saturation_step` | `0.05` | Step between saturations tried |
| `search.lightness_step` | `0.008` | Step between lightnesses tried |

The response:

| Field | Meaning |
|---|---|
| `passed` | `feasibility` is 1: every target was met |
| `palette` | Role to hex, for a caller that only wants the colors |
| `colors` | The same measurements per color as `assess`, without `passed` (every color clears its floor by construction) |
| `feasibility` | How close the tightest pair came to its target, capped at 1: 0.8 means it got 80% of the way |
| `mean_chroma` | How colorful the palette is on average |
| `weakest_pair` | The two colors that look most alike, fixed colors included |

Below a feasibility of 1 the palette is still returned, as the best the solver found, with exit code 1.
Every candidate is rounded to its hex code before the search starts, so the numbers describe exactly the colors returned.

When a slot can't be filled at all, the error names the slot and the field that emptied it (`floor`, `ceiling` or `min_chroma`), so you know what to loosen:

```json
{
  "passed": false,
  "error": {
    "kind": "infeasible_slot",
    "slot": "green",
    "constraint": "min_chroma",
    "message": "slot green: no candidates; nothing that clears the contrast floor reaches the chroma minimum"
  }
}
```

That exits 1, like a palette that falls short: the request was fine and the answer is no.

There is no seed: two runs of the same request can return different palettes of similar quality.

## How the Solver Decides

There is one objective: meet the targets first, then be as colorful as possible.
A guess scores `min(feasibility, 1) * 1000 + mean chroma`, so no amount of color makes up for a missed target.
If you want more contrast rather than more color, raise the slot's `floor`; contrast above the floor is not rewarded.

On a light background contrast and color pull against each other: the most colorful colors are mid-lightness, so every bit of contrast above what a surface needs costs some color.
Text read for hours wants a higher floor; a prompt or a diff that is only glanced at can sit near 4.5 and spend the rest on color.

The search takes every color on the grid for each slot, rounded to its hex code, drops those that miss the floor, the ceiling or the chroma minimum, then starts from a random pick per slot.
One slot at a time, it tries every remaining candidate with the others held still and keeps the best, and it repeats until nothing improves.
That can settle on a so-so answer, so it starts over `restarts` times and keeps the best.

## From Lisp

Load the system with ASDF and call the functions directly; they take values and return values, and never print or exit.

```lisp
(asdf:load-system "beholder")
(beholder:assess (beholder:hex "#f2e9d8")
                 (list (cons "fg" (beholder:hex "#2f2b25"))))
```

| File | What It Holds |
|---|---|
| `src/color.lisp` | The `color` value (`hex`, `hsl`, `color-hex`), contrast, CIELAB, chroma, and the observers (`+normal+`, `+protan+`, `+deutan+`, from Viénot, Brettel and Mollon 1999) that `worst-contrast`, `profile` and `separation` take as `:observers` |
| `src/assess.lisp` | `assess`: a background, named colors and a `policy` in, a `report` out |
| `src/solve.lisp` | `solve`: a `problem` (background, slots, fixed colors, targets, ceiling, grid, restarts) in, a `result` out; a slot with no candidate signals `infeasible-slot` |
| `src/json.lisp` | Requests into those values and results back out as JSON, with a small JSON reader and writer of its own |
| `src/main.lisp` | `respond`, which answers one request, and `main`, the executable's entry point |

`respond` takes a command name and the request text and returns the response text and the exit code, so a Lisp caller can use the JSON form without the executable.

## Tests

The tests use [fiveam](https://github.com/lispci/fiveam), from Quicklisp; nothing else does.

```lisp
(ql:quickload "fiveam")
(asdf:test-system "beholder")
```

The request tests go through `respond`, the same function the executable calls.
Every file in `examples/` is read as a request, and the colors in use are checked to pass; the example solves themselves are not run.

## The Scripts

The scripts in the root support the write-up and run in place under `sbcl --script`.

| Script | What It Does |
|---|---|
| `tradeoff.lisp` | The most chroma a background can carry at a given contrast floor, for several backgrounds |
| `pupil.lisp` | Pupil diameter and retinal blur per background luminance |
| `lca.lisp` | Longitudinal chromatic aberration per wavelength |
