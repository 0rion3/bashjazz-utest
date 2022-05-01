#!/usr/bin/env bash

# We could've included $BASHJAZZ_PATH/utils/colors.sh, but
# this would've added an unnecessary dependency for such a small
# thing as adding colors.
Red='\e[0;31m'
Green='\e[0;32m'
Dim='\033[2m'
Yellow='\e[33m'
Blue='\e[34m'
BRed='\033[1;31m'
BGreen='\033[1;32m'
BYellow='\033[1;33m'
Bold=$(tput bold)
Normal=$(tput sgr0)
ColorOff='\e[0m'

NULL_SYM='␀'

declare -g  UTOUT
declare -g  UTERR
declare -g  CURRENT_UTEST_INDENT=0
declare -g  STANDARD_INDENT_NUMBER=4
declare -g  ASSERTION_COUNTER=0
declare -g  ASSERTION_RESULTS=""
declare -g  CURRENT_TEST_CMDS=""
declare -ga UTESTS=()

utest() {

  STANDARD_INDENT_NUMBER=4

  begin() {

    utest_name=$1
    UTESTS+=( $utest_name )
    shift

    if [[ ${#UTESTS} -gt 1 ]] && [[ $ASSERTION_COUNTER == "0" ]]; then
      echo ""
    fi

    ASSERTION_RESULTS=""
    ASSERTION_COUNTER=0

    CURRENT_UTEST_INDENT=$((CURRENT_UTEST_INDENT+STANDARD_INDENT_NUMBER))
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
    pending=$2

    # Multiple assertions inside the unit test
    if [[ "$ASSERTION_RESULTS" == *";;;"* ]]; then
      ASSERTION_RESULTS="\n${CURRENT_UTEST_INDENT_STR}  $ASSERTION_RESULTS"
      echo -e "$ASSERTION_RESULTS" | \
        sed "s/;;;/\n/g"
    # Single assertion inside the unit test, so no need to enumerate each
    # and print out the result of each assertion on a separate line.
    elif [[ -n "$pending" ]]; then
      echo -en " -> ${Yellow}pending${ColorOff}"
    else
      echo -e "$ASSERTION_RESULTS" | sed -E 's/assertion [0-9]+ -> / -> /g'
    fi

    CURRENT_UTEST_INDENT=$((CURRENT_UTEST_INDENT-4))
    CURRENT_UTEST_INDENT_STR="$(printf %${CURRENT_UTEST_INDENT}s)"

    UTOUT=""
    unset CURRENT_TEST_CMDS
    unset ASSERTION_RESULTS

    # Removes the last element of the UTESTS arr
    unset UTESTS[-1]

    if [[ "${#UTESTS[@]}" -eq 0 ]]; then
      finished_callback
    fi

    return ${UTEST_STATUS:-"0"}

  }

  finished_callback() {
    test -z $DISABLE_BASHJAZZ_DONATION_MSG && _print_donation_msg
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

    local cmd_result=$?
    UTOUT="${UTOUT:-"$NULL_SYM"}"

    if [ $cmd_result -gt 0 ]; then
      if [[ "$UTERR" != "$UTOUT" ]]; then
        UTERR="$UTOUT"
        echo -e "\n  ${CURRENT_UTEST_INDENT_STR}${Red}ERROR:"
        echo -e "    ${CURRENT_UTEST_INDENT_STR}$UTERR${ColorOff}"
      fi
      UTOUT="$NULL_SYM"
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
    shift

    if [[ "$1" == "not_to" ]]; then
      local invert=' --invert '
      shift
    fi

    local assertion_name="$1"
    shift
    local expected="$@"

    local expected_value_type=$(_get_value_type "$expected")
    local returned_value_type=$(_get_value_type "$returned")

    print_error() {

      # $verb could be "to be" or "not to be". Shakespeare here people!
      #
      # (but it could technically it can be anything,
      # for instance "to include" or "not to include").
      verb="${@}"

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
      echo -en "  ${Dim}Expected [$returned_value_type]"
      echo -en " value: ${ColorOff}${returned}${ColorOff} "
      echo -en "${Red}${verb}:${ColorOff} ${expected}${ColorOff}"
      echo -en "${Dim} [$expected_value_type]${ColorOff}"
    }

    print_passed() {
      echo -en "${Green}passed${ColorOff}"
    }

    eq() {

      local result

      if [[ "$1" = "--invert" ]]; then
        local negation="NOT "
        shift
      fi

      eq_integer() {
        test $1 -eq $2
      }
      eq_string() {
        test "$1" = "$2"
      }

      if test "$expected_value_type" != "$returned_value_type"; then
        if [[ -z "$negation" ]];  then
          print_error "TYPE to be"
          return 1
        fi
      fi

      if test $expected_value_type = 'integer'; then
        eq_integer "$returned" "$expected"
      else
        if [[ $expected == "blank" ]] || [[ $expected == "empty" ]]; then
          expected=""
        fi
        test "$returned" == '␀' && returned=''
        eq_string "$returned" "$expected"
      fi

      cmd_result="$?"

      if [[ $cmd_result == "0" ]] && [[ -z "$negation" ]]; then
        print_passed
      elif [[ $cmd_result != "0" ]] && [[ -n "$negation" ]]; then
        print_passed
      else
        print_error "${negation}to be equal to"
        return 1
      fi
    }

    is() {
      eq "$@"
    }

    is_not() {
      eq --invert "$@"
    }

    if [[ -n "$UTERR" ]]; then exit 1; fi

    if [[ "$assertion_name" == "==" ]]; then
      assertion_name="eq"
    fi

    local assertion_result="$($assertion_name $invert "$returned" "$expected")"

    if [ $? -gt 0 ]; then UTEST_STATUS=1; fi

    if test -n "$ASSERTION_RESULTS"; then
      ASSERTION_RESULTS+=";;;  $CURRENT_UTEST_INDENT_STR"
    fi
    ASSERTION_RESULTS+="${ASSERTION_NAME} -> $assertion_result"
  }

  _print_donation_msg() {
    INDENT_STR="$(printf %${STANDARD_INDENT_NUMBER}s)"
    echo -en "${INDENT_STR}${Yellow}"
    echo "------------ Donate if you like this project ------------------"
    echo -en "${ColorOff}"
    echo "${INDENT_STR}If you find this or any of the other BASHJAZZ projects useful,"
    echo "${INDENT_STR}please donate to this Bitcoin address:"
    echo -en "\n${INDENT_STR}${INDENT_STR}${BYellow}"
    echo "36GN5qTZUaRmQA2fwAycuzyVwgF2AvJqbB"
    echo -en "\n${ColorOff}"
    echo "${INDENT_STR}To donate with other cryptocurrencies or via an international"
    echo "${INDENT_STR}wire transfer, see this page for details and contact info:"
    echo -en "${Blue}${INDENT_STR}"
    echo -e "https://bashjazz.orion3.space/donate.html"
    echo -en "${Yellow}${INDENT_STR}"
    echo -e "---------------------------------------------------------------"
    echo -en "${ColorOff}${Dim}"
    echo -e "${INDENT_STR}To get rid of this message, add DISABLE_UTEST_DONATION_MSG=1"
    echo -e "${INDENT_STR}to your shell's environment file (.bashrc, .zshrc etc.)"
    echo -e "${ColorOff}"
  }

  local function_name=$1
  shift
  $function_name "${@}"

}
