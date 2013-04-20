## 1.12 (04/19/2013)

Bugfixes:
  - Fix tab character causing highlight errors. This fixes #18 and fixes #32

## 1.11 (04/18/2013)

Bugfixes:
  - Fix regression where `C-n` doesn't exhibit correct behavior when all matches have been found
  - Clear echo messages when a new input is received

## 1.10 (04/17/2013)

Bugfixes:
  - `O` works now in normal mode. This fixes #24
  - Turn on `lazyredraw` during multicursor mode to prevent the sluggish screen redraws

Features:
  - Add command **MultipleCursorsFind** to add multiple virtual cursors using regexp. This closes #20

## 1.9 (04/17/2013)

Bugfixes:
  - Fix starting multicursor mode in visual line mode. This fixes #25
  - Major refactoring get avoid getting in and out of visual mode as much as possible

## 1.8 (04/16/2013)

Bugfixes:
  - Fix regression that causes call stack to explode with too many cursors

## 1.7 (04/15/2013)

Bugfixes:
  - Finally fix the annoying highlighting problem when the last virtual cursor is on the last character of the line. The solution is a hack, but it should be harmless

## 1.6 (04/15/2013)

Bugfixes:
  - Stop chaining dictionary function calls. This fixes #10 and #11

## 1.5 (04/15/2013)

Bugfixes:
  - Exit Vim's visual mode before waiting for user's next input. This fixes #14

## 1.4 (04/14/2013)

Bugfixes:
  - Don't use clearmatches(). It clears highlighting from other plugins. This fixes #13

## 1.3 (04/14/2013)

Bugfixes:
  - Change mapping from using expression-quote syntax to using raw strings

## 1.2 (04/14/2013)

Bugfixes:
  - Restore view when exiting from multicursor mode. This fixes #5
  - Remove the unnecessary user level mapping for 'prev' and 'skip' in visual mode, since we can purely detect those keys from multicursor mode

## 1.1 (04/14/2013)

Bugfixes:
  - Stop hijacking escape key in normal mode. This fixes #1, #2, and #3

## 1.0 (04/13/2013)

Initial release
