# Changelog

All notable changes to Session Counter. Versions match the Hebnix plugin portal.

## Unreleased

- Console lines no longer repeat the plugin name ("[Session Counter] [Session Counter] ...").

## 1.0.2 (2026-11-18)

- New "Show" option, "Between plays": the counter is visible before kickoff, after goals and after the match, and hidden while the ball is live, so it never overlays live play.
- The plugin no longer runs any per-frame work of its own.

## 1.0.1 (2026-11-18)

- Uses less CPU: text measurements are reused instead of being redone every frame.
- The game overlay is only active while the counter is on screen or fading out. While it's hidden, Rocket League can present frames directly again, which can make gameplay smoother.

## 1.0.0 (2026-11-17)

- First release on Hebnix: a per-mode win/loss record and streaks for the current session, drawn over the game. It started as an OBS overlay for streams.
