<?php
/**
 * Swiss Army Knife -- (Joomla Gateway Library)
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package    Joomla
 * @subpackage Gateway
 */

// For debugging purposes only
error_reporting(E_ALL);
ini_set('display_errors','On');
ini_set('error_log',null);

// Check that we are not root
if (((function_exists('posix_getuid')) ? ((posix_getuid() == 0) ? true : false) : (($_ENV['USER'] == "root") ? true : false) )) {
  fprintf(STDERR,"This script can not be run as root.\n");
  exit(1);
}

/** @ignore */
function do_includes($extra = array()) {
  foreach ($extra as $file) {
    if (!is_file(JOS_ROOT.$file)) {
      fprintf(STDERR, "Error: Required include '%s' missing (is this install old/broken?).\n", $file);
      exit(2);
    }
  }

  ob_start();
  foreach ($extra as $file)
    require_once(JOS_ROOT.$file);

  $output = ob_get_contents();
  ob_end_clean();

  if (strlen($output) > 0) {
    fprintf(STDERR,"%s: Unexpected output during inclusion of Joomla libraries.\nOutput was:\n\n", $self);
    fwrite(STDERR,$output);
    exit(2);
  }
}

////////////////////////////////////////////////////////////////////////////////

/**
 * Reads configuration.php and converts it to delimited output
 *
 * @deprecated Handled by bash now.
 * @param string $output  Filename to write output to
 */
function dump_configuration($output) {
  if (!class_exists("JConfig")) {
    fprintf(STDERR,"Error: Did not get proper configuration class information. Possibly too old?");
    exit(2);
  }
  $config = new JConfig;
  $handle = fopen($output,"w");

  foreach ((array) $config as $key => $value) {
    if (is_array($value)) continue;
    $value = strtr($value,array("\n"=>' ',"\r"=>""));
    fprintf($handle,"%s\x1E%s\n",$key,$value);
  }
}

/**
 * Generates a new config based on new values.
 *
 * @param string $input  Delimited input for new values.
 * @param string $output Filename where output is written.
 */
function write_configuration($input, $output) {
  if (!class_exists("JConfig")) {
    fprintf(STDERR, "Error: Did not get proper configuration class information. Possibly too old?");
    exit(2);
  }
  $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
  $handle = fopen($output,"w");
  if ($handle === false) {
    fprintf(STDERR, "Could not open new configuration file for writing.\n");
    exit(2);
  }

  $config = new JConfig;
  $aconf = (array) $config;
  $lines = explode("\n", file_get_contents($input));
  foreach ($lines as $line) {
    if (empty($line)) continue;
    list($name, $value) = explode("\x1E", $line);
    if (!empty($name)) $config->$name = $value;
  }

  $new = new JRegistry('config');
  $new->loadArray($config);
  fwrite($handle, $new->toString('PHP', array('class' => 'JConfig', 'closingtag' => false)));
}

////////////////////////////////////////////////////////////////////////////////

if ($argc < 3) {
  fprintf(STDERR, "Error: Too few arguments (%d).\n",$argc);
  exit(1);
}

$self = basename(array_shift($argv));
$target = array_shift($argv);
$err_delay = false;
/** @ignore */
define('JOS_ROOT', rtrim($target,"/") . '/');

if (!is_dir($target)) {
  fprintf(STDERR, "Error: Directory is invalid or inaccessible (does it exist, or is it suspended?): %s\n", $target);
  exit(2);
} else {
  chdir($target);
}

ob_start();
/**#@+ @ignore */
define('_JEXEC', 1);
define('DS', DIRECTORY_SEPARATOR);

if (file_exists(JOS_ROOT . '/defines.php'))
  include_once JOS_ROOT . '/defines.php';

if (!defined('_JDEFINES')) {
  define('JPATH_BASE', JOS_ROOT);
  require_once JPATH_BASE.'/includes/defines.php';
}

require_once JPATH_LIBRARIES . '/import.php';
require_once JPATH_LIBRARIES . '/cms.php';
require_once JPATH_CONFIGURATION . '/configuration.php';

$output = ob_get_contents();
/**#@-*/
ob_end_clean();

if (strlen($output) > 0) {
  fprintf(STDERR,"%s: Unexpected output during inclusion of Joomla libraries.\nOutput was:\n\n", $self);
  fwrite(STDERR, $output);
  exit(2);
}

while ($arg = array_shift($argv)) {
  if ($arg == null) { break; }
  switch ($arg) {
    case 'getconfig':
      dump_configuration(array_shift($argv));
      break 2;
    case 'writeconfig':
      write_configuration(array_shift($argv), array_shift($argv));
      break 2;
    default:
      fprintf(STDERR,"Unknown argument `%s'\n",$arg);
      exit(1);
  }
}

if (($err_delay))
  exit(1);
else
  exit(0);
