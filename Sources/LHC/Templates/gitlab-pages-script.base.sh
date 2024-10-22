{#
 # Pages script
 # This script converts a .docc bundle, meant to describe a software release, into an HTML static site, and then
 # stashes the site content in the repository so it can be re-used in future pipeline runs.
 #
 # $BASE_PATH: The path to the site from $CI_PAGES_URL.
 # $DOCC_PATH: The path to the .docc bundle directory.
 #}
echo "$CI_PAGES_URL/$BASE_PATH"

WORKTREE_PATH=./public
REF_NAMESPACE=x-pages
RELEASES_PATH=$REF_NAMESPACE/releases
git config remote.origin.url "https://oauth2:${PIPELINE_ACCESS_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git"

if ! git fetch origin "+refs/$RELEASES_PATH:refs/$RELEASES_PATH"; then
    echo "Setting up pages storage..."
    git worktree add --detach "$WORKTREE_PATH"
    cd "$WORKTREE_PATH"
    git checkout --orphan ci/$RELEASES_PATH
    git commit --allow-empty -m "pages: initial commit"
    cd ..
else
    echo "Checking out pages storage..."

    # If the directory exists, remove it first
    [ ! -d "$WORKTREE_PATH" ] || rm -r "$WORKTREE_PATH"

    git update-ref refs/heads/ci/$RELEASES_PATH refs/$RELEASES_PATH
    git worktree prune
    git worktree add "$WORKTREE_PATH" ci/$RELEASES_PATH
fi

RETRIES=5
BACKOFF=2
RETRY=false

while [ $RETRIES -gt 0 ]; do
    [ "$RETRY" == "false" ] || git reset --hard refs/$RELEASES_PATH

    # Making sure BASE_PATH exists, especially for merge results pipelines
    mkdir -p "$WORKTREE_PATH/$BASE_PATH"

    {#
     # Hack to get the path component of the URL, so we can tell the doc generation what the base path is
     # (use CI_PAGES_DOMAIN as the delimiter of a URL like https://subdomain.pages-host.com/page/base/path;
     # since CI_PAGES_DOMAIN is pages-host.com, then the "second field" of the string is /page/base/path,
     # and then the sed command strips the leading slash)
     #}
    PROJECT_PATH=$(awk -F "$CI_PAGES_DOMAIN" '{print $2}' <<< "$CI_PAGES_URL" | sed 's/^\///')
    xcrun docc convert --hosting-base-path "${PROJECT_PATH}/$BASE_PATH" --output-path "$WORKTREE_PATH/$BASE_PATH" $DOCC_PATH

    # stash the pages output in a separate refs namespace, since it's just being used for storage, and push it.
    cd "$WORKTREE_PATH"
    git add "$BASE_PATH"
    git commit -m "pages: {{ config.name }} release {{ version }} $TIMESTAMP"

    # Add a snapshot, just in case :)
    SNAPSHOT_REF=$REF_NAMESPACE/snapshots/$TIMESTAMP.{{ config.name }}
    git update-ref refs/$SNAPSHOT_REF refs/heads/ci/$RELEASES_PATH

    # Stash the reference in the main branch
    git update-ref refs/$RELEASES_PATH refs/heads/ci/$RELEASES_PATH
    # Force-push back to origin
    if git push -f origin refs/$SNAPSHOT_REF refs/$RELEASES_PATH; then
        break
    else
        sleep $BACKOFF
        RETRY=true
        RETRIES=$((RETRIES-1))

        echo "Push failed. Retrying a maximum of $RETRIES more time(s) before giving up..."
        BACKOFF=$((BACKOFF*2))
        git fetch origin "+refs/$RELEASES_PATH:refs/$RELEASES_PATH"
    fi
done

[ $RETRIES -gt 0 ] || (echo "Gave up." && exit 1)
