#!/bin/bash
#
# Creates a script containing samples of all the dynamically generated
# functions bash-cache.sh makes. The resulting script can be used to lint and
# validate this dynamic content (namely via ShellCheck).
#
# Note that inline comments are not preserved making it difficult to suppress
# warnings. It may be necessary to manipulate the generated script before
# invoking shellcheck.

DIR=$(mktemp -d "${TMPDIR:-/tmp}/bc-benchmark-XXXXXX")
trap 'rm -rf "$DIR"' EXIT

# https://stackoverflow.com/a/246128/113632
# shellcheck source=/dev/null
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/../bash-cache.sh" || exit

declare -F | cut -d' ' -f3 | sort > "$DIR/orig_func.txt"

# Since bc::locked_cache delegates to bc::cache this should give us coverage of
# All dynamically generated functions
expensive() { :; } && bc::locked_cache expensive

printf "Capturing generated functions:"
printf '%s\n' '#!/bin/bash' '#' '# GENERATED SCRIPT FOR USE WITH SHELLCHECK' '' > "generated.sh"

# declare config variables
printf '# shellcheck disable=SC2034\ndeclare' >> "generated.sh"
printf ' %s' '_bc_cache_dir' '_bc_locks_dir' '_bc_enabled' >> "generated.sh"

for func in $(comm -13 "$DIR/orig_func.txt" <(declare -F | cut -d' ' -f3 | sort)); do
  printf " %s" "$func"
  printf '\n\n' >> "generated.sh"
  declare -f "$func" >> "generated.sh"
done
printf '\nWrote generated functions to generated.sh\n'