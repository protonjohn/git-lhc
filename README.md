# LHC

LHC is a tool for creating and finding releases based on Git commit history, using Conventional Commits and Semantic
Versioning. It's meant to be used both from an engineer's machine and from within CI pipelines.

You can use LHC to create new release tags, generate changelogs from Git history, find which versions of your project
first introduced a change mentioning a task ID (i.e., from Jira or GitLab), embed the latest version tag in your project
files, and more.

LHC is currently under active development. Try running the `help` command for some usage examples. Every minor
release before version 1.0.0 should be considered to contain breaking changes.

## Naming LHC

Depending on how annoyed you are, LHC either stands for Less-Hectic Committing or Large Hack Collider. :)

## Running LHC

LHC has been run successfully on macOS desktop machines. Its use has not yet been proven on Linux or WSL, but if you
have success installing `homebrew`, it's recommended to first install `mint`:

```bash
brew install mint
```

Then you can invoke LHC by running `mint run <this repository url>`.

## Using LHC

### Requirements

LHC works best if your repository's commits follow the [Conventional Commit](http://conventionalcommits.org) syntax,
and if your project follows the [Semantic Versioning](https://semver.org) convention. It is more performant, but not
required, to use [git trailers](https://git-scm.com/docs/git-interpret-trailers) in your commits to declare task IDs
instead of including them in your commit subjects. (It saves precious characters in your changelog, too!)

### Releasing

When you're ready to create a release of your project, use `lhc create-release`. If you have tag pipelines set up,
you can automate your release deployments in CI by checking the prerelease identifiers in the semantic version to know
which release channel to deploy to (`alpha`, `beta`, `rc`, or `prod`, for example). Use the command's `--push` option
to automatically push the resulting tag to the default remote, and your CI can take care of the rest for you.

If your project is a Swift package or Xcode project, you can use LHC's package plugins to embed your project's
version information or release changelog in your code or app resources. Just make sure that you set up a release train
which has the same name as your build target. For more information, consult the Release Trains section below.

For easier usage of LHC in your CI pipelines, check out the `Jobs/` directory of this project for job templates you
can include from your own workflows.

### Finding Releases

Once you've made a few releases with LHC, you'll find it's very easy to figure out in which version of the project a
task was completed using `lhc find-versions --task-id EXAMPLE-1234`. If you maintain multiple branches of your code,
for example to support backports and hotfixes to older versions of your app, LHC will find and print every release
that a change landed in.

### Release Trains

Sometimes it's necessary to ship multiple products out of one repository, for instance, both an iOS and a macOS
application, or a framework and executable. LHC can track multiple projects in one repository by adding a prefix
to its version tags, e.g., `mac/1.2.3-rc.1` and `ios/2.3.4-alpha.3`. You can configure this and other train-specific
options in your project's `.lhc.yml` file - see below.

## Configuring LHC

For a basic configuration file, invoke `lhc create-default-config` to get up and running. LHC does not require
a configuration file for basic usage, but you can take advantage of more of its functionality by defining `.lhc.yml`
in your repository root. For more advanced configurations, take a look at `lhc.example.yml` in `Sources/lhc`.
