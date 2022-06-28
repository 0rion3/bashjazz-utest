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
NoClr='\e[0m'

NULL_SYM='␀'
SP_SYM='␠'
NL_SYM='␤'

declare -g  UTOUT
declare -g  UTERR
declare -g  UTOUT_TAIL
declare -g  CURRENT_UTEST_INDENT=0
declare -g  UTEST_FULL_NAME
declare -g  STANDARD_INDENT_NUMBER=4
declare -g  ASSERTION_COUNTER=0
declare -g  ASSERTION_RESULTS=""
declare -ga CURRENT_TEST_CMDS=()
declare -ga UTESTS=()

UTEST_TMPDIR="${TMPDIR:-/tmp}/bashjazz-utest"
mkdir -p $UTEST_TMPDIR

if [[ -n "$UTEST_ONLY" ]]; then
  echo -e "${INDENT_STR}${Yellow}Only running ${Bold}${UTEST_ONLY}${ColorOff}"
fi

utest() {

  STANDARD_INDENT_NUMBER=4

  begin() {

    if [[ ${#UTESTS} -gt 1 ]] && [[ $ASSERTION_COUNTER == "0" ]]; then
      echo ""
    fi

    ASSERTION_RESULTS=""
    ASSERTION_COUNTER=0

    CURRENT_UTEST_INDENT=$((CURRENT_UTEST_INDENT+STANDARD_INDENT_NUMBER))
    CURRENT_UTEST_INDENT_STR="$(printf %${CURRENT_UTEST_INDENT}s)"


    echo -en "${CURRENT_UTEST_INDENT_STR}${Bold}${utest_name}${ColorOff}"

    if [[ -n $PRINT_DESCRIPTIONS ]]; then
      local description="$(echo "${@}" | xargs | \
        fmt -w 80 | sed "s/^/$CURRENT_UTEST_INDENT_STR/")"
      if [[ -n "$description" ]]; then
        echo -en "\n${Dim}$description${ColorOff}"
      fi
    fi

  }

  # Tests may be nested, so we need to keep an array of test names running,
  # so that when end() is called, it removes the last one and resets variables.
  # This indicates the current "begin" section has been completed.
  end() {
    utest_name=$1
    pending=$2


    if [[ -n "$pending" ]]; then
      echo -e " -> ${Yellow}pending${ColorOff}"
    elif [[ -n "$ASSERTION_RESULTS" ]]; then
      # Multiple assertions inside the unit test
      if [[ "$ASSERTION_RESULTS" == *";;;"* ]]; then
        ASSERTION_RESULTS="\n${CURRENT_UTEST_INDENT_STR}  $ASSERTION_RESULTS"
        echo -e "$ASSERTION_RESULTS" |\
          sed "s/;;;/\n/g"
      # Single assertion inside the unit test, so no need to enumerate each
      # and print out the result of each assertion on a separate line.
      else
        echo -e "$ASSERTION_RESULTS" | sed -E 's/.*assertion [0-9]+//g'
      fi
    elif [[ -n "$UTERR" ]]; then
      UTERR="$(echo "$UTERR" | sed "s/$NL_SYM/\n/g" | xargs |\
        sed "s/$NL_SYM/    ${CURRENT_UTEST_INDENT_STR}/g")"
      echo -e " -> ${Red}failed"
      echo -e "  ${CURRENT_UTEST_INDENT_STR}ERROR:"
      echo -e "$UTERR${ColorOff}"
    fi

    CURRENT_UTEST_INDENT=$((CURRENT_UTEST_INDENT-4))
    CURRENT_UTEST_INDENT_STR="$(printf %${CURRENT_UTEST_INDENT}s)"

    UTOUT=""
    UTERR=""
    UTOUT_TAIL=""
    CURRENT_TEST_CMDS=()
    ASSERTION_RESULTS=()

    if [[ "${#UTESTS[@]}" -eq 0 ]]; then
      printf "\n"
      finished_callback
    fi

    return ${UTEST_STATUS:-"0"}

  }

  finished_callback() {
    test -z $DISABLE_BASHJAZZ_DONATION_MSG && _print_donation_msg
  }

  # Technically the same as calling set_var() without $2 containing the value,
  # but it instead uses `unset VARNAME` and `declare -g$2` (the second argument
  # to this function providing the additional one-dash args o the declare
  # built in - such as -a or -A. This is because we cannot know the type of the
  # variable when re-declaring it (or perhaps were too lazy to had been writing
  # more unnecessary code to determine that - it is Bash, after all).
  unset_var() {
    unset $1
    declare -g $2 $1
    if [[ "$1" == "UTOUT" ]]; then
      unset UTOUT_TAIL
      declare -g UTOUT_TAIL
    fi
  }

  set_var() {
    declare -g "$1"="$2"
    if [[ "$1" == "UTOUT" ]]; then
      UTOUT_TAIL="$(echo "$UTOUT" | tail -n1)"
    fi
  }

  # Runs arbitrary command and captures its output.
  # into the global variable $UTOUT. May be used many times
  # in between begin() and end() calls.
  cmd() {

    UTOUT=""
    UTERR=""
    UTOUT_TAIL=""

    if [[ -n "$@" ]]; then add_cmd "$@"; fi

    local tmp_file="$(mktemp \
      --tmpdir=$UTEST_TMPDIR \
      --suffix=".$UTEST_FULL_NAME")"

    for c in "${CURRENT_TEST_CMDS[@]}"; do
      local _cmd="$(echo "$c" | sed "s/$SP_SYM/ /g")"
      if [[ "$_cmd" == *"#ignore-stdout "* ]]; then
        _cmd="$(echo "$_cmd" | sed 's/#ignore-stdout //')"
        $_cmd 2>> $tmp_file
      else
        $_cmd >> $tmp_file 2>&1
      fi
      local cmd_status=$?
      echo "$cmd_status;;;" >> $tmp_file
    done

    local lines
    while IFS= read -r line; do
      if [[ "$line" != *";;;" ]]; then
        lines+="$NL_SYM$line"
      else
        if [[ "$line" == "0;;;" ]]; then
          UTOUT+="$lines"
        else
          UTERR+="$lines"
        fi
        lines=""
      fi
    done < $tmp_file

    rm $tmp_file

    if [[ -z "$UTOUT" ]]; then
      UTOUT="$NULL_SYM"
      UTOUT_TAIL="$NULL_SYM"
    else
      UTOUT="$(echo "$UTOUT" | sed -E "s/^$NL_SYM//")"
      UTOUT="$(echo "$UTOUT" | sed -E "s/$NL_SYM/\n/g")"
      UTOUT_TAIL="$(echo "$UTOUT" | tail -n1)"
    fi

    CURRENT_TEST_CMDS=()

  }

  add_cmd() {
    if [[ "$1" == "--"* ]]; then
      if [[ "$1" == "--ignore-stdout" ]]; then
        local ignore_stdout="#ignore-stdout "
      fi
      shift
    fi
    CURRENT_TEST_CMDS+=( "$(echo -n "${ignore_stdout}${@}" | sed "s/ /$SP_SYM/g")" )
  }

  assert() {


    if [[ $1 == "--error" ]]; then
      local continue_on_error=true
      shift
    fi

    if [[ -n "$UTERR" ]] && [[ -z $continue_on_error ]]; then
      UTEST_STATUS=1
      return 1;
    fi

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

    if [[ "$1" =~ ^(==|eq|is|is_not|not_to)$ ]]; then
      local returned="$NULL_SYM"
    else
      local returned="$1"
      shift
    fi

    if [[ "$1" == "not_to" ]]; then
      local invert=' --invert '
      shift
    fi

    # Assertion name function names
    _get_assertion_name_from_verb() {
      case "$1" in
        'to contain')               echo "contains";;
        '=='|'eq'|'equal'|'equals') echo "eq";;
        'is')                       echo "is";;
        'is_not')                   echo "is_not";;
        *)
          >&2 echo "${Red}No such assertion: ${Bold}$1${NoClr}";;
      esac
    }
    assertion_name="$(_get_assertion_name_from_verb "$1")"
    shift

    # Expected and returned values
    local expected="$1"
    local expected_value_type=$(_get_value_type "$expected")
    local returned_value_type=$(_get_value_type "$returned")

    print_error() {

      # $verb could be "to be" or "not to be". Shakespeare here people!
      #
      # (but it could technically it can be anything,
      # for instance "to include" or "not to include").
      local verb="${Dim}$1${ColorOff}"

      local error_subject="$2" # 'value' or 'type'
      local returned="$3"
      local expected="$4"

      if [[ $error_subject == 'type' ]]; then
        local error_expectation_msg="${Dim}Expected returned value type $verb"
        local error_main_msg="${NoClr}[$returned_value_type]${Dim} but it wasn't."
        local suffix="Returned value was: ${NoClr}${Red}${Bold}'$returned_value'"
      else # assume error subject to be 'value'
        local error_expectation_msg="${Dim}Expected [$returned_value_type] value${NoClr}"
        local error_main_msg="${Red}${Bold}'$returned'${ColorOff} ${Dim}${verb}${NoClr} '$expected'"
        local suffix="${Dim}[$expected_value_type]${ColorOff}"
      fi

      if [[ "$expected_value_type" == "string" ]]; then
        local expected="'${Bold}$expected${ColorOff}'"
      fi

      if [[ "$returned_value_type" == "string" ]]; then
        local returned="$(echo -en "'${BRed}$returned${ColorOff}'")"
      fi

      if [[ "$returned_value_type" == "null" ]]; then
        local returned="$(echo -en "${BRed}$returned${ColorOff}")"
      fi

      echo -e "${Red}failed${ColorOff}"
      echo -en "${CURRENT_UTEST_INDENT_STR}    "
      echo -en "$error_expectation_msg $error_main_msg $suffix"
    }

    print_passed() {
      echo -n "${Green}passed${ColorOff}"
    }

    eq() {

      local result

      if [[ "$1" == "--invert" ]]; then
        local negation="NOT "
        shift
      fi

      eq_integer() {
        test "$1" -eq "$2"
      }
      eq_string() {
        test "$1" = "$2"
      }

      if test "$expected_value_type" != "$returned_value_type"; then
        if [[ -z "$negation" ]];  then
          print_error 'to be' 'type' "$returned" "$expected"
          return 1
        fi
      fi

      returned="${returned:-$NULL_SYM}"
      if test $expected_value_type = 'integer'; then
        eq_integer "$returned" "$expected"
      else
        if [[ $expected =~ ^(empty|blank)?$ ]]; then
          expected=$NULL_SYM
        fi
        eq_string "$returned" "$expected"
      fi

      local cmd_result="$?"

      if [[ $cmd_result == "0" ]] && [[ -z "$negation" ]]; then
        print_passed
      elif [[ $cmd_result != "0" ]] && [[ -n "$negation" ]]; then
        print_passed
      else
        print_error "${negation}to be equal to" 'value' "$returned" "$expected"
        return 1
      fi
    }

    is() {
      eq "$@"
    }

    is_not() {
      eq --invert "$@"
    }

    contains() {
      if [[ "$1" == *"$2"* ]]; then
        print_passed
      else
        print_error "${negation}to contain" 'value' "$returned" "$expected"
      fi
    }

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

  case $function_name in
    begin)
      utest_name=$1
      shift
      UTESTS+=( $utest_name )
      UTEST_FULL_NAME="$(echo "${UTESTS[@]}" | sed 's/ /./g' )"
      ;;
    end)
      # Removes the last element of the UTESTS arr
      unset UTESTS[-1];;
  esac

  if [[ -z "$UTEST_ONLY" ]] || [[ "$UTEST_FULL_NAME" == "$UTEST_ONLY" ]]; then
    $function_name "${@}"
  fi

}
