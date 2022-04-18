#!/usr/bin/env bash

# We could've included $BASHJAZZ_PATH/utils/colors.sh, but
# this would've added an unnecessary dependency for such a small
# thing as adding colors.
Red='\e[0;31m'
Green='\e[0;32m'
Dim='\033[2m'
BRed='\033[1;31m'
BGreen='\033[1;32m'
Bold='\e[1m'
ColorOff='\e[0m'

declare -g  UTOUT
declare -g  CURRENT_UTEST_INDENT=0
declare -g  CURRENT_TEST_CMDS=""
declare -g  ASSERTION_COUNTER=0
declare -g  ASSERTION_RESULTS=""
declare -ga UTESTS=()

utest() {

  begin() {

    utest_name="$1"
    UTESTS+=( $utest_name )
    shift

    if [[ ${#UTESTS} -gt 1 ]] && [[ $ASSERTION_COUNTER == "0" ]]; then
      echo ""
    fi

    ASSERTION_RESULTS=""
    ASSERTION_COUNTER=0

    CURRENT_UTEST_INDENT=$((CURRENT_UTEST_INDENT+4))
    CURRENT_UTEST_INDENT_STR="$(printf %${CURRENT_UTEST_INDENT}s)"

    if [[ -n $PRINT_DESCRIPTIONS ]]; then
      echo -e "\n${CURRENT_UTEST_INDENT_STR}${Bold}${utest_name}${ColorOff}"
      echo -en "${CURRENT_UTEST_INDENT_STR}${Dim}$@${ColorOff}"
    else
      echo -en "${CURRENT_UTEST_INDENT_STR}${Bold}${utest_name}${ColorOff}"
    fi
  }

  # Tests may be nested, so we need to keep an array of test names running,
  # so that when end() is called, it removes the last one and resets variables.
  # This indicates the current "begin" section has been completed.
  end() {
    utest_name=$1

    # Multiple assertions inside the unit test
    if [[ "$ASSERTION_RESULTS" == *";;;"* ]]; then
      ASSERTION_RESULTS="\n${CURRENT_UTEST_INDENT_STR}  $ASSERTION_RESULTS"
      echo -e "$ASSERTION_RESULTS" | \
        sed "s/;;;/\n/g"
    # Single assertion inside the unit test, so no need to enumerate each
    # and print out the result of each assertion on a separate line.
    else
      echo -e "$ASSERTION_RESULTS" | sed -E 's/assertion [0-9]+ -> / -> /g'
    fi

    CURRENT_UTEST_INDENT=$((CURRENT_UTEST_INDENT-4))
    CURRENT_UTEST_INDENT_STR="$(printf %${CURRENT_UTEST_INDENT}s)"

    UTOUT=""
    unset CURRENT_TEST_CMDS
    unset ASSERTION_RESULTS

    # Removes the last element of the UTESTS arr
    UTESTS=( "$(echo "${UTESTS[@]}" | sed -E 's/[^ ]+$//')" )

    local first_utest="$( echo "${UTESTS[0]}" | xargs)"
    if [[ "${#UTESTS[@]}" -eq "0" ]]; then 
      echo ""
    fi

    return ${UTEST_STATUS:-"0"}

  }

  # Runs arbitrary command and captures its output.
  # into the global variable $UTOUT. May be used many times
  # in between begin() and end() calls.
  cmd() {
    if [[ -n "$@" ]]; then
      UTOUT="$($@)"
    else
      local all_cmds="$(echo "$CURRENT_TEST_CMDS" | sed -E 's/ && $//')"
      UTOUT="$($all_cmds)"
    fi
  }

  add_cmd() {
    if test -n "$CURRENT_TEST_CMDS"; then
      local separator=' && '
    fi
    CURRENT_TEST_CMDS="${CURRENT_TEST_CMDS}${separator} $@"
  }

  assert() {

    ASSERTION_COUNTER=$((ASSERTION_COUNTER+1))
    if [[ "$1" =~ ^:[0-9a-zA-Z_]+$ ]]; then
      ASSERTION_NAME="$(echo $1 | grep -oE '[0-9a-zA-Z_]+')"
      shift
    else
      ASSERTION_NAME="assertion $ASSERTION_COUNTER"
    fi

    # "Private" functions are defined before everything else because
    # they're used in other assertion functions or in assert() itself.
    _get_value_type() {
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        echo integer
      else
        echo string
      fi
    }

    local assertion_name
    local -a returned
    local -a expected

    for arg in "${@}"; do
      if test -z $assertion_name; then
        if [[ $arg == "==" ]]; then
          assertion_name="eq"
        else
          returned+=( $arg )
        fi
      else
        expected+=( $arg )
      fi
    done

    local value_type=$(_get_value_type "$3")

    eq() {

      local result

      eq_integer() {
        test $1 -eq $2
      }
      eq_string() {
        test "$1" = "$2"
      }

      if test $value_type = 'integer'; then
        eq_integer "$returned" "$expected"
      else
        eq_string "$returned" "$expected"
      fi

      if [[ $? == '0' ]]; then
        echo -en "${Green}passed${ColorOff}"
        return 0
      else
        echo -e "${Red}failed${ColorOff}"
        echo -en "${CURRENT_UTEST_INDENT_STR}  "
        echo -en "  ${Dim}Expected [$value_type] "
        echo -en "${ColorOff}value: ${Bold}${expected}${ColorOff}, "
        echo -en "${Red}got: ${BRed}${returned}${ColorOff}"
        return 1
      fi
    }

    assertion_result="$($assertion_name "$returned" "$expected")"

    if [[ $? == "1" ]]; then UTEST_STATUS=1; fi

    if test -n "$ASSERTION_RESULTS"; then
      ASSERTION_RESULTS+=";;;  $CURRENT_UTEST_INDENT_STR"
    fi
    ASSERTION_RESULTS+="${ASSERTION_NAME} -> $assertion_result"
  }

  local function_name=$1
  shift
  $function_name $@

}
