# LHC Release: {{ release.versionString }}
@Metadata {
    @TechnologyRoot
}
{% if release.body %}
## Release Notes

{{ release.body }}
{% endif %}
## Changes
@TabNavigator {
{% for category, changes in release.changes %}
    @Tab("{{ category }}") {
        | Commit | Summary |
        |--------|---------|
        {% for change in changes %}| `{{ change.commitHash|prefix:oid_string_length }}` | {% if change.scope %}change.scope: {% endif %}{{ change.summary }} |
        {% endfor %}
    }
{% endfor %}
## Topics
{% if checklist_filenames %}
### Checklists
{% for filename in checklist_filenames %}
- <article:{{ filename }}>
{% endfor %}
{% endif %}
}
