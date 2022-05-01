#!/usr/bin/env bash

declare -g MAIN_GREETING

Example() {

  local CALL_NESTED="$1"
  shift

  # This will pass
  print_hello() {
    declare -g MAIN_GREETING="hello world"
    echo "$MAIN_GREETING"
  }

  # This will also pass, building upon the call to print_hello()
  print_custom_hello() {
    echo "$MAIN_GREETING ${@}"
  }

  print_back() {
    echo -n "${@}"
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

  # ATTENTION: here the program will exit if the wrong an individual nested 
  # is being called (which would be the case with unit testing).
  test -n "$CALL_NESTED" && $CALL_NESTED "${@}" || return $?

}
