#!/usr/bin/env bash

declare -g MAIN_GREETING="default greeting"

Example() {


  # This will pass
  print_hello() {
    MAIN_GREETING="hello world"
    echo "$MAIN_GREETING"
  }

  # This will also pass, building upon the call to print_hello()
  print_custom_hello() {
    echo "$MAIN_GREETING $@"
  }

  print_back() {
    echo "$1"
  }

  # Given existing tests, this function will no fail any of them
  add() {
    echo $(($1+$2))
  }

  # Given existing tests, this function will fail when decimals are passed,
  # but pass with integers.
  multiply() {
    echo $(($1*$2))
  }

  local CALL_NESTED="$1"
  shift
  $CALL_NESTED "$@"
  return $?

}
