# Hebnix portal listing: Session Counter

Paste these into the upload form. Upload files:
- banner: `listing/banner.png` (1600×900, rebuild with `python tools/make_banner.py`)
- plugin: `dist/session_counter-<version>.zip` (build it with `pwsh ./package.ps1`)

Version history lives in `CHANGELOG.md`, not here.

## Name

Session Counter

## Category

Overlay

## Version

1.0.2

## Short description

Your win/loss record for this session, kept separately for each game mode, on screen while you play. Streaks included.

## Long description

Session Counter keeps your wins and losses for the current session and shows them over the game. Each game mode has its own record: queue Ranked 2v2, then Hoops, then back to 2v2, and each one picks up where it left off. It started as an OBS overlay for streams and now runs right in the game through Hebnix.

What it shows
• The current mode (Ranked 2v2, Casual 3v3, Ranked Hoops, Tournament...) with that mode's wins and losses.
• A win or loss streak once you get two in a row.
• A quick pop animation when a result is counted.
• By default it appears when a match starts and stays through the post-match screen.

What counts
• Matches against real players in any online playlist or private match. Your team is detected automatically, on any account.
• A win still counts when the other team quits. A forfeit counts as a loss.
• Leaving a match early counts as a loss, like it does in ranked. If you reconnect to the same match, the loss is taken back and the real result counts instead. You can turn this off.
• Free play, training and matches against bots aren't counted.
• A new session starts after 4 hours without a counted match (you can change this). Your record survives restarts of Hebnix and the game.

Settings
• Show it during matches only, only between plays (hidden while the ball is live), whenever Rocket League is running, or all the time.
• Preview mode draws a sample record, so you can set it up from the main menu.
• Position it anywhere on screen and set its size. It scales with your resolution.
• Change every color, add a background or text shadow, and hide the mode name or streak.
• Fix the record by hand (+W, −W, +L, −L) or reset the session.
• Name playlists it doesn't know yet.

Notes
• The Rocket League Stats API must be enabled. Hebnix can do this for you.
• Each match's result is written to the Hebnix console, and the last 30 are listed in the plugin's settings, so you can see why a match wasn't counted.
