# LHC

Drive your CI purely through Git.

`git-lhc` is a versioning tool written in Swift that allows developers to drive powerful CI/CD integrations from their versioning history. It combines [templates](https://github.com/stencilproject/Stencil), [semantic versions](https://semver.org), [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/), and [several](https://git-scm.com/docs/git-interpret-trailers) [features](https://www.git-scm.com/docs/git-notes) native to [git](https://www.git-scm.com) to implement the following features of its own:
### Automatic Versioning
If your project already uses conventional commits, great! LHC will look for the last reachable release tag in your current branch, calculate the new version number for you, and create a new tag. A release tag is a tag with an optional prefix that parses as a semantic version string. LHC gives first-class support for the `alpha`, `beta`, and `rc` prerelease identifiers, allowing you to use it for every stage of your delivery pipeline.

### Commit Attributes
LHC interprets the [trailers](https://git-scm.com/docs/git-interpret-trailers) of a commit (or tag) as attributes of that object. Trailers are useful for assigning attributes to an object at creation time, but LHC takes it one step further by also parsing a git object's [notes](https://www.git-scm.com/docs/git-notes). It provides a command-line interface for adding, removing, and querying these values, and signs the resulting note commit, ensuring attributes can't be forged or manipulated. Attributes are also available for lookup from within both release and checklist templates, which are described below.

### Release Checklists
Perhaps your team uses a bug tracker which you'd like to keep in sync with your project's development state, or you have a bunch of manual steps to perform before each release. LHC lets you write templates to create dynamic checklists evaluated from your versioning history. Checklists are written in [Markdown](https://en.wikipedia.org/wiki/Markdown), and every list element in the document is interpreted as a step. Steps can contain inline code and code blocks, which are evaluated as shell commands. Their output is captured during execution of the checklist, and the result of the checklist session is recorded and attached to the target commit (or tag) as a signed git note, which can't be replayed onto other objects.

### Changelog Generation
Using [[Releases]], you can generate change logs for your releases in whatever format you like. The templating engine also gives you access to all checklists evaluated for that release, which gives you a powerful tool for generating CI configurations, updating metadata files, generating wikis for project status pages, and more. Several base templates are also packaged with this project and are available using the `{% include %}` tag.

### Project Trains
Does your repository ship multiple projects, perhaps several apps on different platforms? No problem. LHC is designed from the ground up for this use case, and has first-class support for tag prefixes, along with an expressive configuration format suitable for customizing most of its settings on a per-project basis.