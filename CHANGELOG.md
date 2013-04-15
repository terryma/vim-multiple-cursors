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
