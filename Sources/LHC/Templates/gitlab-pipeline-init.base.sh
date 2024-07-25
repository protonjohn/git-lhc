# $DESCRIBE_DIR should be the output directory of the `git-lhc describe` command.
cp -r $DESCRIBE_DIR/{% if release.tagName %}release{% else %}{{ config.name }}{% endif %}/fastlane .
if [ -f "$HOME/.profile" ]; then
    source "$HOME/.profile"
fi
