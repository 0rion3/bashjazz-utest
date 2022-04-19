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
SP_SYMBOL="␠"
NBSP="$(echo -e "\u00A0")"

declare -g  UTOUT
declare -g  CURRENT_UTEST_INDENT=0
declare -g  ASSERTION_COUNTER=0
declare -g  ASSERTION_RESULTS=""
declare -g  CURRENT_TEST_CMDS=""
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
      local description="$(echo "${@}" | xargs | \
        fmt -w 80 | sed "s/^/$CURRENT_UTEST_INDENT_STR/")"
      echo -e "\n${CURRENT_UTEST_INDENT_STR}${Bold}${utest_name}${ColorOff}"
      echo -en "${Dim}$description${ColorOff}"
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
    if [[ -n "${@}" ]]; then
      UTOUT="$("${@}" 2>&1)"
    else
      UTOUT="$(run_in_the_same_context "$CURRENT_TEST_CMDS")"
    fi

    if [[ $? != 0 ]]; then
      if [[ "$UTERR" != "$UTOUT" ]]; then
        UTERR="$UTOUT"
        echo -en "\n  ${CURRENT_UTEST_INDENT_STR}${Red}ERROR: $UTERR${ColorOff}"
      fi
      UTOUT='[null]'
    fi
  }

  run_in_the_same_context() {
    local out
    local last_cmd="$(echo "${@}" | grep -oE ' && .*$' | sed 's/ && //')"
    local other_cmds="$(echo "${@}" | sed 's/ \&\& .*$//')"
    $other_cmds 1> /dev/null
    $last_cmd
  }

  add_cmd() {
    # Even though we use quotations marks when adding an item to an Array,
    # apparently that's not enough and SPACE characters must be replaced with
    # a non-breaking space character defined at the top in the $SP_SYMBOL
    # variable. Its value is set to "␠" (stored in $SP_SYMBOL variable
    # defined at the top of this script - which is a Unicode for
    # character for representing SPACE. It's later replaced with 
    # the actual SPACE character in cmd() before running each command.
    if [[ -n "$CURRENT_TEST_CMDS" ]]; then
      CURRENT_TEST_CMDS+=" && "
    fi
    CURRENT_TEST_CMDS+="${@}"
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
      elif [[ "$1" != "[null]" ]]; then
        echo string
      else
        echo "null"
      fi
    }

    local returned="$1"
    local assertion_name="$2"
    shift 2
    local expected="${@}"
    expected="${expected:-␀}"

    local expected_value_type=$(_get_value_type "$expected")
    local returned_value_type=$(_get_value_type "$returned")

    eq() {

      local result

      eq_integer() {
        test $1 -eq $2
      }
      eq_string() {
        test "$1" = "$2"
      }

      print_error() {

        if [[ "$expected_value_type" == "string" ]]; then
          expected="'${Bold}$expected${ColorOff}'"
        fi

        if [[ "$returned_value_type" == "string" ]]; then
          returned="$(echo -en "'${BRed}$returned${ColorOff}'")"
        fi

        if [[ "$returned_value_type" == "null" ]]; then
          returned="$(echo -en "${BRed}$returned${ColorOff}")"
        fi

        echo -e "${Red}failed${ColorOff}"
        echo -en "${CURRENT_UTEST_INDENT_STR}  "
        echo -en "  ${Dim}Expected [$expected_value_type]"
        echo -en " value: ${ColorOff}${Bold}${expected}${ColorOff}, "
        echo -en "${Red}got:${ColorOff} ${returned}"
      }

      if [[ "$expected_value_type" != "$returned_value_type" ]]; then
        print_error
        return 1
      fi

      if test $expected_value_type = 'integer'; then
        eq_integer "$returned" "$expected"
      else
        eq_string "$returned" "$expected"
      fi

      if [[ $? == '0' ]]; then
        echo -en "${Green}passed${ColorOff}"
        return 0
      else
        print_error
        return 1
      fi
    }

    if [[ "$assertion_name" == "==" ]]; then
      assertion_name="eq"
    fi
    assertion_result="$($assertion_name "$returned" "$expected")"

    if [[ $? == "1" ]]; then UTEST_STATUS=1; fi

    if test -n "$ASSERTION_RESULTS"; then
      ASSERTION_RESULTS+=";;;  $CURRENT_UTEST_INDENT_STR"
    fi
    ASSERTION_RESULTS+="${ASSERTION_NAME} -> $assertion_result"
  }

  local function_name=$1
  shift
  $function_name "${@}"

}
