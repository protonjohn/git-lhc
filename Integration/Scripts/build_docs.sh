#!/bin/bash -e

DOC_BUNDLE="Sources/LHC/Documentation.docc"
MANPAGE_FILE="$DOC_BUNDLE/Articles/Usage.md"
FASTLANE_FILE="$DOC_BUNDLE/Articles/Fastlane.md"
FASTLANE_README="fastlane/README.md"

FRAMEWORK_TARGET="LHC"
MANPAGE_NAME="git-lhc.1"

CLIP_TEXT='<!-- >8 -->'

function die() {
    echo $1
    exit 1
}

function add_docs() {
    local filename
    local content
    local header
    local lineno
    filename="$1"
    content="$2"

    # The line number where CLIP_TEXT appears in the file, so we know where to append.
    lineno=$(grep -n -- "$CLIP_TEXT" "$filename" | head -n 1 | cut -d ':' -f 1)
    header=$(head -n "$lineno" "$filename")
    cat > "$filename" <<EOF
$header

$content
EOF
}

function manpage() {
    local tmpfile
    local rawman
    local man
    local markdown

    tmpdir=$(mktemp -d)
    rawman=$(swift package --allow-writing-to-directory "$tmpdir" generate-manual -o "$tmpdir")

    [ -f "${tmpdir}/${MANPAGE_NAME}" ] || die "No file exists at ${tmpdir}/${MANPAGE_NAME}."

    man=$(man "${tmpdir}/${MANPAGE_NAME}" | col -bx)
    rm -rf "$tmpdir"

    markdown=$(cat <<EOF
\`\`\`
$man
\`\`\`
EOF
)

    add_docs "$MANPAGE_FILE" "$markdown"
}

function fastlane_readme() {
    local markdown
    fastlane docs

    # Remove the doc header at the top, and knock all headers one level down, since DocC only allows one top-level
    # header per document.
    markdown=$(sed -e '1,/^----$/d; s/^#/##/' "$FASTLANE_README")
    add_docs "$FASTLANE_FILE" "$markdown"
}

function main() {
    local output_dir
    local base_path

    base_path="$1"
    output_dir="$2"
    echo "Base path: $1"
    echo "Output directory: $2"

    echo "Generating manual..."
    manpage

    echo "Generating fastlane usage..."
    # fastlane_readme

    echo "Generating documentation..."
    swift package --allow-writing-to-directory "$output_dir" \
        generate-documentation --target "$FRAMEWORK_TARGET" --output-path "$output_dir" \
        --transform-for-static-hosting --hosting-base-path "$base_path"
}

main $@
echo "Done."
