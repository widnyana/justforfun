#!/bin/bash
# taken from https://bechtsoudis.com/hacking/detect-protect-from-php-backdoor-shells/
 #------------------------------------------------#
 # Search web files for potential malicious code. #
 #------------------------------------------------#
  
  SEARCH_DIR="/var/www/html"
  PATTERNS="passthru|shell_exec|system|phpinfo|base64_decode|popen|exec|proc_open|pcntl_exec|python_eval|fopen|fclose|readfile"
   
   grep -RPl --include=*.{php,txt} "($PATTERNS)" $SEARCH_DIR
    
    exit 0
