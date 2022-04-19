#!/usr/bin/env bash

Example() {

  # For unit-test compliance and allowing to unit-test nested functions,
  # (but can also be used in other cases we allow to call each individual
  # function from the nested functions. For this to work,
  # the first argument should be -c function_name (-c stands for 'call').
  # The actual calls will be done after function declarations.
  # Here, we need to to shift the first two argument (-c flag itself and its
  # value.
  if test $1 = '-c'; then
    local CALL_NESTED="$2"
    shift 2
  fi

  # This will pass
  print_hello() {
    declare -g MAIN_GREETING="hello  world"
    echo "$MAIN_GREETING"
  }

  print_custom_hello() {
    echo "$MAIN_GREETING $1"
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
  test -n $CALL_NESTED && $CALL_NESTED $@ && exit $?

}
