#!/usr/bin/env bash
source utest.sh
source example.sh

echo '––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––'
echo "BASHJAZZ UTETS EXAMPLE"
echo "----------------------------------------------------------------------"
echo -e "If everything is correct, running this file should result in only one
test failing, due to usage of decimal numbers instead of integers."
echo "----------------------------------------------------------------------"

utest begin Example 'An example test-suite for the rather useless example.sh'

  # Indentation is not necessary, but it helps to visually distinguish
  # between the nested "begin" blocks".
  utest begin print_hello 'Simply prints hello world'
    utest cmd Example print_hello
    utest assert "$UTOUT" == 'hello world'
  utest end print_hello

  utest begin print_custom_hello \
    'Demonstrates use of add_cmd for the execution of multiple commands'
    utest add_cmd Example print_hello
    utest add_cmd Example print_custom_hello 'and welcome'
    utest cmd
    utest assert "$UTOUT_TAIL"    == "hello world and welcome"
  utest end print_hello

  utest begin add 'Adds two integers and prints out the result'
    utest cmd Example add 1 2
    utest assert $UTOUT_TAIL == 3
    utest cmd Example add 2 2
    utest assert $UTOUT_TAIL == 4
  utest end add

  utest begin print_back_nothing 'Demonstrating usage of "is" & "blank"'
    utest cmd Example print_back ''
    utest assert $UTOUT is blank
    utest assert $UTOUT is ''
    utest assert $UTOUT eq ''
    utest assert $UTOUT == ''
  utest end print_back_nothing

  utest begin print_back_something 'Demonstrating usage of "not_to", "is_not" & "blank"'
    utest cmd Example print_back something
    utest assert $UTOUT is_not blank
    utest assert $UTOUT is_not ''
    utest assert $UTOUT not_to eq ''
    utest assert $UTOUT not_to == ''
  utest end print_something

  utest begin print_text_with_spaces \
  'Checks that utest assert can handle spaces in its leftmost argument'
    utest set_var UTOUT "$(Example print_back 'some text with     many spaces')"
    utest assert "$UTOUT_TAIL" == 'some text with     many spaces'
  utest end print_text_with_spaces

  utest begin multiply 'multiplies two integers and prints out the result'
    utest cmd Example multiply 1 2
    utest assert $UTOUT == 2
    utest cmd Example multiply 2 2
    utest assert $UTOUT == 4
    utest assert $UTOUT not_to eq 8
    utest assert $UTOUT not_to == 2
  utest end multiply

  utest begin multiply_with_intentional_error
    # The assertion below will fail because the function only
    # supports integers
    utest cmd Example multiply 2.0 2
    utest assert $UTOUT == 4
  utest end add

utest end Example
