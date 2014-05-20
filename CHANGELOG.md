# Change log

## 0.1.3 ([#6](https://git.mobcastdev.com/Deployment/proteus/pull/6) 2014-05-20 11:36:52)

Allow the improvement keyword

### Improvement

- Patch to add the "improvement" keyword, it will be recognised as a PATCH version bump.



## 0.1.2 ([#5](https://git.mobcastdev.com/Deployment/proteus/pull/5) 2014-04-25 13:31:39)

Falsely detecting changes to CHANGELOG & VERSION

### Bug fixes

* Fixed a bug where Proteus was not diff-ing from the right branch to check the last upstream commit changes ([CP-1416](https://tools.mobcastdev.com/jira/browse/CP-1416))
* Changed the exit code from `1` to `3` when an exception is captured

## 0.1.1 ([#4](https://git.mobcastdev.com/Deployment/proteus/pull/4) 2014-04-24 16:03:50)

Allow underscores in repo names

### Bug fixes

- Accepts repo and owner names which have underscores in.

## 0.1.0 ([#3](https://git.mobcastdev.com/Deployment/proteus/pull/3) 2014-04-23 13:56:08)

Correct checking for banned files

### New features

- Fail gifs. Because awesome.

### Bug fix

- Correctly ascertains if you've tried to push a pull request with changes to `VERSION` or `CHANGELOG.md` files.

