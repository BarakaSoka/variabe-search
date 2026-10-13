# Contributing to Variabe Search

Thanks for your interest in Variabe Search. A few notes up front save everyone time.

## Open an issue first

Please open an issue before you write any code, for a fix as much as for a feature. The same change may already be in
progress, and an issue gets you a clear "yes", "not now" or "here's how it should fit" before you spend an evening on
it.

## Pull requests

Once an issue says go:

- Keep it to one fix or one feature, with the reason in the description.
- Make sure `swift test` passes.
- If it changes what search returns, run the evals in `evals/` before and after (`variabe eval evals/synthetic.json`)
  and include both results.
- For speed or memory changes, measure before and after on the same Mac.
- For UI changes, include a screenshot (`scripts/dev-run.sh -debugQuery "…" -debugSnapshot /tmp/panel.png` draws the
  search bar without touching your real index).

Variabe Search keeps everything on the Mac, so changes that send data elsewhere, like telemetry or cloud services,
aren't a fit.

## Reporting a bug

Helpful reports include your Mac (chip and memory), the macOS and Variabe Search versions, what you did or searched
for, and what you expected instead. Logs are in `~/Library/Application Support/Variabe Search/index.noindex`
(`app.log` and `indexer.log`). They can contain file names and your searches, so look through them before you paste.

For a security problem, please use "Report a vulnerability" on the Security tab instead of a public issue.
