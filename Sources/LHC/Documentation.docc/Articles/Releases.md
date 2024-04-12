Depending on the project and the audience of a new software release, there are many different items in many different formats that need updating, but most of them contain very similar information. LHC's releases feature lets you keep all of that information local to your git repository.

### Release templates

When invoking `git-lhc describe`, the `--template` option lets you specify one or more templates to evaluate as part of the release description. While it's possible to define your own values in the configuration context, LHC also predefines several values for you:

- `release`: the release object itself.
- `commits`: the commit objects contained in the release.
- `version`: the release's version number.
- `short_version`: the short version number, without any prerelease or build identifiers.
- `channel`: the channel of the version. This can be one of `alpha`, `beta`, `rc`, or `production`.
- `object`: the git object, which is a commit if the release is untagged or the tag is lightweight, and a tag otherwise.
- `target`: the target commit that the release tag, if any, is pointing to. This is equal to `commits.first` and may be equal to `target`.
- `now`: the current timestamp.