# Examples

Two worked themes, a light one and a dark one, as the requests that produced them.
They were tuned for one person's eyes and screens, so read them as examples of setting up a problem, not as themes to adopt.

```sh
bin/beholder solve  examples/light/syntax.json     # find the light theme's syntax colors
bin/beholder assess examples/dark/deployed.json    # check the dark theme's colors in use
```

| File | What It Asks For |
|---|---|
| `light/syntax.json`, `dark/syntax.json` | Editor syntax colors: keyword, string, function, type, constant, builtin |
| `light/prompt.json`, `dark/prompt.json` | Shell prompt colors: directory (blue), error (warm), branch (gold), ok (teal) |
| `light/diff.json`, `dark/diff.json` | Git diff colors: added (blue) and removed (warm) |
| `dark/ansi.json` | Terminal colors 1 to 6: red, green, yellow, blue, magenta, cyan |
| `light/deployed.json`, `dark/deployed.json` | Every color the theme uses today, checked against a 4.5 floor |

Solves aren't seeded, so a run can land on a different palette of similar quality than the one in use.

## The Two Themes

Every solve keeps the theme's body text (`fg`) and comment colors fixed and steers the new colors clear of them.

**Light** is a warm off-white background, `#f2e9d8`, like paper, with near-black text.
The comment color is a plain gray on purpose: a warm gray ended up looking too much like the green strings, and making it neutral left the strings room to be much more colorful.
The search stays between lightness 0.13 and 0.58, and 8 restarts is what found the colors in use; more restarts find a different prompt palette that's just as good.

**Dark** is a muted green-gray, `#33362f`, with slightly tinted off-white text.
It is easier on the eyes than a navy, which is the hardest background to focus on, and it was picked by eye over graphite, warm gray, pine, slate and aubergine.
Its requests carry a ceiling of 9.04, the body text's own contrast: no accent may be brighter than the text.
On a dark background bright text glows a little, and an accent brighter than everything else would be the blurriest word on the line.
The dark search tries more colors per slot (lightness 0.40 to 0.92), so it needs 40 restarts to find a good answer.

## Syntax

Syntax colors are read for hours, so they get solid contrast: floors of 5.0, and 5.5 for function and builtin.
Teal and blue are the hardest colors for the eye to focus sharply, so they get a bit more to make up for it.

The most common tokens get the most distinct colors, so keywords are violet rather than the more usual amber.
Keyword and function want 16 apart on light; 20 pushed function to a near-navy.

The dark theme keeps each token in the same color family as the light theme's colors in use (orange strings, magenta types), so switching themes doesn't reshuffle what's what.
Function is green there rather than blue: blue functions and violet keywords looked too alike, and those two sit next to each other in every language, so their target is raised to 35.

## Prompt and Diff

Prompt and diff colors are glanced at rather than read, so they only need to clear a contrast minimum (4.6 for the prompt, 5.0 for diffs, a bit more for blue) and can spend the rest on being colorful.
On a light background those pull against each other: the most colorful colors are mid-lightness, and every bit of extra contrast costs some color.

Blue against orange is the pair that matters most: added against removed in a diff, directory against error in the prompt.
The prompt's directory uses the same blue band as diffs, so there's one blue everywhere.

Gold and warm are the pair most likely to collide.
Both collapse toward olive for a protan or deutan, so they are told apart by lightness rather than hue; keep one clearly darker than the other.

## Terminal Colors

Every terminal program draws with colors 1 to 6, so they need the same care as the editor colors.
Each stays close enough to its name that a program asking for "red" gets something reddish, but green leans teal and cyan leans sky blue, which keeps them apart from red and yellow.
Red against green matters most: in a terminal that's error against success.

Green and magenta have higher chroma minimums so "ok" and "passed" don't look washed out.
That costs some distance between colors (cyan and magenta end up closest), which was checked by eye and is fine.
This solve doesn't reach its targets (feasibility about 0.75), and the colors in use are its best answer.

There is no light version.
The light theme's terminal colors were picked before this problem existed, and on the light background nothing in the green band clears 4.6 with a chroma of 50.

## The Colors in Use

`deployed.json` holds what each theme uses today, by where it's used: `syn:` for editor faces, `git:` for diffs, `prompt:` for the shell prompt, and `tig:` for the git browser tig.
tig can only use terminal colors 0 to 15, so its rows are really the terminal palette; checking them stops a palette change from quietly making a tig color hard to read.

These files are the authority, not the solver.
The solver is the thing to re-run when a constraint changes: a new background, a different floor, an added syntax category.
Don't hand-edit a single hex to taste.
Every color is scored against every other for how far apart they look, so nudging one value tends to break a pair somewhere else; change the constraint and re-solve.

### Hand-Tuned Exceptions

Two light syntax colors are tuned by hand, not solved, and that is deliberate.
Solving `light/syntax.json` will not reproduce them: its string band is still green and its type band still olive.
Don't "fix" them back to the solver's output.

| Role | Solved | In Use | Why |
|---|---|---|---|
| `syn:string` | `#036831` green | `#b33204` orange, 4.54:1 | The green was disliked, and in practice ran together with nearby colors |
| `syn:type` | `#696406` olive | `#a7037b` magenta, 5.17:1 | Too drab to pick out at a glance |

Chosen on 2026-11-01 by eye in Emacs, with each candidate measured against the other syntax colors held fixed.
Orange string against magenta type is 74.4 dE for the worst observer, and every pair still clears 16 (the closest touching either new color is magenta against builtin teal, at 17.7).
The orange is the lightest that clears 4.5:1 and sits under the solver's 5.0 floor on purpose; the darker `#a53302` (5.05:1) was tried and read too dark.
Which hue went on which role was a judgment of how much of each color lands on the page, not a separation result: the swap is separation-neutral.
