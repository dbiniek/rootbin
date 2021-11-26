<?php
/**
 * Swiss Army Knife - Main PHP Function Library
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package    SwissArmyKnife
 * @subpackage Functions
 */

set_include_path(realpath(dirname(__FILE__)."/../"));

/**
 * Disables PHP error output
 * @return void
 */
function disable_errors() {
  error_reporting(E_ERROR);
  ini_set('display_errors','Off');
  ini_set('error_log',null);
}

/**
 * Checks for root privileges and exits with a status of 1 if necessary
 *
 * @param bool  $require  True if root is required, false otherwise
 * @return void
 */
function require_root($require = true) {
  if (function_exists('posix_getuid'))
    $root = ((posix_getuid() == 0) ? true : false);
  else
    $root = ((@exec('/usr/bin/whoami') == "root") ? true : false);
  // $root = ((function_exists('_posix_getuid')) ? ((posix_getuid() == 0) ? true : false) : (($_ENV['USER'] == "root") ? true : false) );
  if (($require) && !($root)) {
    fprintf(STDERR,"This script must be run as root.\n");
    exit(1);
  } elseif (!($require) && ($root)) {
    fprintf(STDERR,"This script can not be run as root.\n");
    exit(1);
  }
}

/**
 * Prints errors and exits with status 2 automatically
 *
 * @param string  $msg    Message to display
 * @param bool    $mysql  Set to true to automatically pull mysqli_error()
 */
function die_with_error($msg, $mysql = false, $status = 2) {
  if (($mysql)) {
    fprintf(STDOUT,"%s\n%s\n",$msg,mysqli_error($this->connection));
  } else {
    fprintf(STDOUT,"%s\n",$msg);
  }
  echo "\n";
  debug_print_backtrace();
  exit((int)$status);
}

/**
 * Provides array information from .my.cnf for database connection info
 *
 * @param string $filename  Filename to use. Default = /root/.my.cnf
 * @return array Array of INI contents
 */
function get_ini($filename = "/root/.my.cnf") {
  if (!file_exists($filename) || !is_readable($filename)) {
    fprintf(STDERR,"Unable to get MySQL connection information from %s -- Make sure it exists, and is correct.",$filename);
    exit(1);
  }

  $ini = parse_ini_file($filename,true);

  // Compatibility for .my.cnf files that use pass= or password=
  // Will populate both in the array based on what is set and not empty.
  if (!isset($ini['client']['pass']) && isset($ini['client']['password']))
    $ini['client']['pass'] = $ini['client']['password'];

  if (!isset($ini['client']['password']) && isset($ini['client']['pass']))
    $ini['client']['password'] = $ini['client']['pass'];

  if ($ini['client']['pass'] == "" && $ini['client']['password'] != "")
    $ini['client']['pass'] = $ini['client']['password'];

  if ($ini['client']['password'] == "" && $ini['client']['pass'] != "")
    $ini['client']['password'] = $ini['client']['pass'];

  return $ini;
}

/**
 * Used to sort vdetect output by software name, then version
 *
 * @param array $a First array
 * @param array $b Second array
 * @return int
 */
function natversort($a,$b) {
  $nat = strnatcasecmp($a[1],$b[1]);
  if ($nat == 0)
    return version_compare($a[3],$b[3]);
  return $nat;
}

/**
 * Print a human readable time delta.
 *
 * Returns time in the form of "X weeks, X days, X hours, X minutes, X seconds"
 *
 * @param int $seconds Time in seconds.
 * @return string Human readable time based on seconds given.
 */
function timedelta($seconds = 0) {
  if ($seconds <= 0)
    return "0 seconds";

  $time = "";
  $s = (int)$seconds;

  $weeks = floor($s / 604800);
  $s -= ($weeks * 604800);

  $days = floor($s / 86400);
  $s -= ($days * 86400);

  $hours = floor($s / 3600);
  $s -= ($hours * 3600);

  $mins = floor($s / 60);
  $s -= ($mins * 60);

  if ($weeks == 0 && $days == 0 && $hours == 0 && $mins == 0 && $s == 0)
    return "Derp seconds";

  $time .= (($weeks>0)?" $weeks week(s)" :"");
  $time .= (($days>0)? " $days day(s)"   :"");
  $time .= (($hours>0)?" $hours hour(s)" :"");
  $time .= (($mins>0)? " $mins minute(s)":"");
  $time .= (($s>0)?    " $s second(s)"   :"");

  return trim($time);
}
