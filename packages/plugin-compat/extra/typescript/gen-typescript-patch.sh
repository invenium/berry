set -ex

THIS_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMP_DIR="/tmp/ts-repo"

PATCHFILE="$TEMP_DIR"/patch.tmp
JSPATCH="$THIS_DIR"/../../sources/patches/typescript.patch.ts

FIRST_PR_COMMIT="5d50de3"

HASHES=(
  # Patch   # Base    # Ranges
  "426f5a7" "e39bdc3" ">=3.0 <3.5"
  "426f5a7" "cf7b2d4" ">=3.5 <3.6"
  "2f85932" "e39bdc3" ">=3.6 <3.9"
  "2f85932" "d68295e" ">=3.9"
)

mkdir -p "$TEMP_DIR"
if ! [[ -d "$TEMP_DIR"/clone ]]; then (
    git clone git@github.com:arcanis/typescript "$TEMP_DIR"/clone
    cd "$TEMP_DIR"/clone
    git remote add upstream git@github.com:microsoft/typescript
); fi

cd "$TEMP_DIR"/clone

git cherry-pick --abort || true

git fetch origin
git fetch upstream

reset-git() {
  git reset --hard "$1"
  git clean -df

  npm install --before "$(git show -s --format=%ci)"
}

rm -f "$PATCHFILE" && touch "$PATCHFILE"
rm -f "$JSPATCH" && touch "$JSPATCH"

while [[ ${#HASHES[@]} -gt 0 ]]; do
  HASH="${HASHES[0]}"
  BASE="${HASHES[1]}"
  RANGE="${HASHES[2]}"
  HASHES=("${HASHES[@]:3}")

  rm -rf "$TEMP_DIR"/orig
  rm -rf "$TEMP_DIR"/patched

  mkdir -p "$TEMP_DIR"/orig
  mkdir -p "$TEMP_DIR"/patched

  reset-git "$BASE"

  yarn gulp local LKG
  cp -r lib/ "$TEMP_DIR"/orig/

  reset-git "$BASE"
  git cherry-pick "$FIRST_PR_COMMIT"^.."$HASH"

  yarn gulp local LKG
  cp -r lib/ "$TEMP_DIR"/patched/

  DIFF="$THIS_DIR"/patch."${HASH}"-on-"${BASE}".diff

  git diff --no-index "$TEMP_DIR"/orig "$TEMP_DIR"/patched \
    | perl -p -e"s#^--- #semver exclusivity $RANGE\n--- #" \
    | perl -p -e"s#$TEMP_DIR/orig##" \
    | perl -p -e"s#$TEMP_DIR/patched##" \
    | perl -p -e"s#__spreadArrays#[].concat#" \
    > "$DIFF"

  cat "$DIFF" \
    >> "$PATCHFILE"
done

echo '/* eslint-disable */' \
  >> "$JSPATCH"
echo 'export const patch =' \
  >> "$JSPATCH"
node "$THIS_DIR"/../jsonEscape.js < "$PATCHFILE" \
  >> "$JSPATCH"
echo ';' \
  >> "$JSPATCH"
