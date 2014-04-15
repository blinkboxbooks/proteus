# Proteus

A build tool for automatically bumping version numbers

## How it works

### Calculating the new Version number

Proteus reads the pull request body text and looks for any of the following words, bumping the [semantic version](http://semver.org) accordingly:

| Word            | Bump Type | Increment |
|-----------------|-----------|-----------|
| breaking change | Major     | 1.0.0     |
| new feature     | Minor     | 0.1.0     |
| bugfix          | Patch     | 0.0.1     |
| bug fix         | Patch     | 0.0.1     |
| patch           | Patch     | 0.0.1     |

### Writing pull request text

Your pull request text can be phrased any way you like, the Changelog will have a new section added like this:

``` markdown
## 0.0.1 ([28](link-to-pull-request) 2014-04-11 11:39)

Title of Pull Request

Body of Pull request
```

We find it beneficial to write the body of your pull request like this:

``` markdown
### New features

- Now all singing *and* all dancing.

### Bug fixes

- I fixed this bug
- [CP-123](link-to-JIRA-ticket) I fixed this one too
```

