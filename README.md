# Session Counter for Hebnix

A Hebnix overlay plugin that shows your **win/loss record for the current session**, for each game mode separately, over Rocket League. It's a port of [rocket-league-obs-session-counter](../rocket-league-obs-session-counter), which does the same thing as an OBS browser source.

![Ranked Snow Day 7–3, 3 win streak](../rocket-league-obs-session-counter/docs/overlay.png)

Hebnix already connects to Rocket League's Stats API, so there's nothing else to set up.

## Install

```powershell
pwsh ./package.ps1 -Install
```

Then enable or reload **Session Counter** in Hebnix's plugins tab. By default the counter sits in the top-left corner and shows from the start of a match until you leave it, including the post-match screen.

## What it shows and what counts

Same as the OBS overlay:

- **The current mode** from the playlist (*Ranked 2v2*, *Casual 3v3*, *Ranked Hoops*...), with that mode's wins and losses. Each mode keeps its own record and streak.
- **A streak** once you win or lose two in a row.
- **Counted:** matches against real players in any online playlist or private match. Your team is the player the camera follows.
- **Not counted:** free play, training and matches against bots.
- **Leaving early** counts as a loss once the match has kicked off. Reconnecting to the same match takes it back.
- **New session** after 4 hours without a counted match. The record survives restarts of Hebnix and the game.

One difference: if Hebnix loses the Stats API mid-match (the game closed or crashed), that match is dropped, not counted as a leave. That's what the OBS overlay did when its socket closed.

## Settings

| Section | Settings |
| --- | --- |
| General | Enable; **Show**: during matches (default), between plays (hidden from each kickoff countdown until the next goal or the end of the match, so nothing covers live play), while Rocket League is running, or always; **Show preview** draws a sample record (Ranked Snow Day 7–3, 3 win streak) so you can position and style it outside a match; **Play pop animation** |
| This session | Each mode's record; **+W / −W / +L / −L** for the mode on screen; **Reset session** |
| Counting | Leaving counts as a loss; hours before a new session; extra playlist names (`73:Heatseeker`) |
| Position & size | Anchor, X/Y as % of the screen, size %, scale with resolution |
| Appearance | Mode name on/off and capitals, streak on/off, pop animation, text shadow, background opacity and corner radius, every color, **Restore default appearance** |
| Troubleshooting | Connection/match details under the counter; the last 30 match outcomes |

Each match's outcome is also written to the Hebnix console, prefixed `[Session Counter]`.

## Tests

The plugin runs against a mocked Hebnix host in Lua 5.4 (the version Hebnix embeds), through Python's `lupa`:

```powershell
python -m pip install lupa
python tests/run_tests.py
```

## License

MIT. See [LICENSE](LICENSE).
