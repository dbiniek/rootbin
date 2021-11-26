<?php

function sak_autoload_register() {
  if (function_exists('spl_autoload_register')) {
    spl_autoload_register('sak_class_autoload');
  } else {
    function __autoload($class) { sak_class_autoload($class); }
  }
}

function sak_autoload_unregister() {
  if (function_exists('spl_autoload_unregister'))
    spl_autoload_unregister('sak_class_autoload');
}

function sak_class_autoload($name) {
  $name = 'lib'.DS.strtolower($name).'.php';

  for ($i=2; $i < 5; $i++)
    if (file_exists($file = preg_replace('/_/', DS, $name, $i)))
      return @include($file);

  return @include(preg_replace('/_/', DS, $name));
}

function sak_env_define($name, $default = null, $key = null, $return = false) {
  if (is_null($key)) $key = $name;

  if (!array_key_exists($key, $_ENV) || $_ENV[$key] == "") {
    if (is_null($default)) {
      if ((!$return)) {
        fprintf(STDERR, "\nRequired data (%s) missing from environment.\n", $key);
        exit(1);
      } else
        return false;
    }
    define($name, $default);
  }

  define($name, $_ENV[$key]);
  return true;
}

function sak_check_requirements($argv) {
  $help = "You may specify a custom PHP binary with the SAK_PHP environment variable.\n";

  if (php_sapi_name() != "cli" || version_compare(SAK_REQ_PHPVER, phpversion(), '>=')) {
    fprintf(STDERR, "\nThis script requires PHP version %s or higher with the CLI SAPI.\n%s", SAK_REQ_PHPVER, $help);
    exit(1);
  }

  $extensions = explode(" ", SAK_REQ_PHPEXT);
  foreach ($extensions as $ext) {
    if (!extension_loaded($ext)) {
      fprintf(STDERR, "\nThis script requires the '%s' PHP extension.\n%s", $ext, $help);
      exit(1);
    }
  }
}

function sak_get_all_php_option($filename) {
  $res = array('v' => array(), 'd' => array());
  if (file_exists($filename)) {
    $content = php_strip_whitespace($filename);

    $cap =
      '(?:'.
        '(?<int>\d+)'.
      '|'.
        '(?<bool>(?i:true|false))'.
      '|'.
        '(?|\'(?<value>.*?)(?<!\x5C)\''.
      '|'.
        '"(?<value>.*?)(?<!\x5C)"'.
      '))';

    $regex = array(
      'v' => '/\s\$(?<name>\S+)\s*=\s*'.$cap.'\s*;/',
      'd' => '/\s(?i:define)\s*\(\s*(?|\'(?<name>\S+)\'|"(?<name>\S+)")\s*,\s*'.$cap.'\s*\)\s*;/');

    foreach ($regex as $type => $re) {
      preg_match_all($re, $content, $sub);

      foreach ($sub['name'] as $index => $name) {
        $res[$type][$name] = '';

        if ($sub['value'][$index] != '')
          $res[$type][$name] = $sub['value'][$index];

        if ($sub['int'][$index] != '')
          $res[$type][$name] = (int)$sub['int'][$index];

        if ($sub['bool'][$index] != '')
          $res[$type][$name] = (bool)$sub['bool'][$index];
      }
    }
  } else
    return false;

  return $res;
}

/**
 * Prints errors and exits with status 2 automatically
 *
 * @param string  $msg    Message to display
 * @param bool    $mysql  Set to true to automatically pull mysqli_error()
 */
function die_with_error($msg, $mysql = false, $status = 2) {
  if (($mysql)) {
    fprintf(STDOUT,"%s\n%s\n",$msg, mysqli_error($this->connection));
  } else {
    fprintf(STDOUT,"%s\n",$msg);
  }
  echo "\n";
  debug_print_backtrace();
  exit((int)$status);
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

  $time .= (($weeks>0)?" $weeks week(s)" :"");
  $time .= (($days>0)? " $days day(s)"   :"");
  $time .= (($hours>0)?" $hours hour(s)" :"");
  $time .= (($mins>0)? " $mins minute(s)":"");
  $time .= (($s>0)?    " $s second(s)"   :"");

  return trim($time);
}

/**
 * Verify if a given string is a valid octal number.
 *
 * Slightly modified from {@link http://php.net/manual/en/function.octdec.php#85170}.
 *
 * @param string $num String representation of a potential octal number.
 * @return bool
 */
function is_octal($num) {
  return (decoct(octdec($num)) == $num);
}
