# beholder

Check a color palette, or have one found for you.

beholder measures contrast, how colorful each color is, and how far apart colors look.
Hand it the colors you have and it tells you which ones hold up and which two look most alike.
Or describe the colors you want ("a blue, at least 5.5:1, this far from the orange") and it searches for the most colorful set that meets every target.

Every check is taken for three observers by default: normal color vision, protan and deutan, with the worst of the three deciding.
It speaks JSON, so anything that can start a process can use it.

## You'll Need

[SBCL](https://www.sbcl.org/), and nothing else.
The executable it builds doesn't even need that.

## Building

```sh
./build.lisp
```

That writes `bin/beholder`, one file you can copy anywhere.

## Using It

```sh
echo '{"background": "#f2e9d8", "colors": {"text": "#2f2b25", "link": "#e0443a"}}' \
  | bin/beholder assess
```

The response gives each color's contrast for every observer, its chroma and lightness, whether it passed, and the pair that looks most alike.
Here the link fails: 3.4:1 for normal vision, and 3.0:1 for a deutan.
The exit code is 0 when everything passes, 1 when something doesn't, and 2 when the request itself is bad, so a pre-commit hook needs nothing but the exit code.

`bin/beholder solve` takes slots (a hue band and a contrast floor for each color you want) and targets, and returns the palette it found.

Everything else (every request field and its default, the responses, exit codes, how the solver decides, the Lisp API, the tests) is in [the usage reference](docs/reference/internal/usage.md).
[`examples/`](examples/) has a light and a dark theme as the requests that produced them, with the reasoning behind each choice.

## The Write-Up

[writeup.html](writeup.html) is why the light example looks the way it does: why light mode is an optics result rather than a preference, why the background is warm and not white, the red/green constraint, and the contrast-versus-colorfulness tradeoff.
It renders when opened straight from the file system.
`tradeoff.lisp`, `pupil.lisp` and `lca.lisp` are the calculations behind it.

## Tests

```lisp
(ql:quickload "fiveam")
(asdf:test-system "beholder")
```

fiveam comes from Quicklisp and is only needed for the tests.

## Gotcha!

A red can clear 4.5:1 and still be hard to read.
WCAG's contrast formula weighs red, green and blue the way normal color vision does, and a protan sees red as much darker than that.
So beholder checks contrast for each observer and keeps the lowest.
Check only normal vision and you can ship an unreadable red with a passing number next to it.

## License

BSD-2-Clause. See [LICENSE](LICENSE).
