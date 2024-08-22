{#
 # Pages script
 # This script converts a .docc bundle, meant to describe a software release, into an HTML static site, and then
 # stashes the site content in the repository so it can be re-used in future pipeline runs.
 #
 # $BASE_PATH: The path to the site from $CI_PAGES_URL.
 # $DOCC_PATH: The path to the .docc bundle directory.
 #}
echo "$CI_PAGES_URL/$BASE_PATH"

REF_NAMESPACE=x-pages
CI_JOB_TOKEN=$PIPELINE_ACCESS_TOKEN
RELEASES_PATH=$REF_NAMESPACE/releases
if ! git fetch origin "+refs/$RELEASES_PATH:refs/$RELEASES_PATH"; then
    echo "Setting up pages storage..."
    git worktree add --detach public
    cd public
    git checkout --orphan ci/$RELEASES_PATH
    git commit --allow-empty -m "pages: initial commit"
    cd ..
else
    echo "Checking out pages storage..."
    git update-ref refs/heads/ci/$RELEASES_PATH refs/$RELEASES_PATH
    git worktree prune
    git worktree add public ci/$RELEASES_PATH
fi

{#
 # Hack to get the path component of the URL, so we can tell the doc generation what the base path is
 # (use CI_PAGES_DOMAIN as the delimiter of a URL like https://subdomain.pages-host.com/page/base/path;
 # since CI_PAGES_DOMAIN is pages-host.com, then the "second field" of the string is /page/base/path,
 # and then the sed command strips the leading slash)
 #}
PROJECT_PATH=$(awk -F "$CI_PAGES_DOMAIN" '{print $2}' <<< "$CI_PAGES_URL" | sed 's/^\///')
xcrun docc convert --hosting-base-path "${PROJECT_PATH}/$BASE_PATH" --output-path "public/$BASE_PATH" $DOCC_PATH

# stash the pages output in a separate refs namespace, since it's just being used for storage, and push it.
cd public
git add "$BASE_PATH"
git commit -m "pages: {{ config.name }} release {{ version }} $TIMESTAMP"

# Add a snapshot, just in case :)
git update-ref refs/$REF_NAMESPACE/snapshots/{% include "timestamp.base" %} refs/heads/ci/$RELEASES_PATH
# Stash the reference in the main branch
git update-ref refs/$RELEASES_PATH refs/heads/ci/$RELEASES_PATH
# Force-push back to origin
git push -f origin refs/$REF_NAMESPACE/*
