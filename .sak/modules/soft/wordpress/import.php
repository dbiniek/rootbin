<?php
/**
 * Swiss Army Knife -- (WordPress Import Library)
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package    WordPress
 * @subpackage Import
 */

/** Disables PHP errors and timeout */
set_time_limit(0);
error_reporting(E_ERROR);
ini_set('display_errors','Off');
ini_set('error_log',null);

if ($argc < 1) {
  fprintf(STDERR, "Error: Too few arguments.\n");
  exit(1);
}

define('DS',DIRECTORY_SEPARATOR);
$args = $argv;
$self = basename(array_shift($args));
$ini = array_shift($args);
$target = array_shift($args);

if (!file_exists($ini) || !is_readable($ini)) {
  fprintf(STDERR, "Error: Import INI file not found or unreadable.\n");
  exit(2);
}

$settings = parse_ini_file($ini, true);

if ($settings === false || count($settings) == 0) {
  fprintf(STDERR, "Error: Could not parse INI file.");
  exit(2);
}

$ini_dir = dirname($ini);
$input = $ini_dir .DS. $settings['import']['filename'];

if (!file_exists($input) || !is_readable($input)) {
  fprintf(STDERR, "Error: Import file not found or unreadable.\n");
  exit(2);
}

if (!is_dir($target) || !is_readable($target)) {
  fprintf(STDERR, "Error: Directory is invalid or inaccessible (does it exist, or is it suspended?): %s\n", $target);
  exit(2);
} else {
  chdir($target);
}

/*#@+ @ignore */
define('WP_ROOT', $target.'/');

define('WP_CACHE',          false);
define('WP_DEBUG',          false);
define('WP_REPAIRING',      true );
define('WP_LOAD_IMPORTERS', true );
define('IMPORT_DEBUG',      true );

ob_start();
  if (file_exists(WP_ROOT."wp-load.php")) {
    require_once(WP_ROOT."wp-load.php");
  } else {
    require_once(WP_ROOT."wp-config.php");
  }

  require_once('wp-admin/includes/file.php');
  require_once('wp-admin/includes/misc.php');
  require_once('wp-admin/includes/taxonomy.php');
  require_once('wp-admin/includes/post.php');
  require_once('wp-admin/includes/image.php');
  require_once('wp-admin/includes/comment.php');
$output = ob_get_contents();
ob_end_clean();
/**#@-*/

if (strlen($output) > 0) {
  fprintf(STDERR,"%s: Unexpected output during inclusion of WordPress libraries.\nOutput was:\n\n", $self);
  fwrite(STDERR,$output);
  exit(2);
}

if (defined(WP_DEBUG) && WP_DEBUG) {
  fprintf(STDERR, "Error: WP_DEBUG is enabled. Cannot continue.\n");
  exit(2);
}

array_merge($_SERVER, array(
  'SERVER_SOFTWARE' => 'Swiss-Army-Knife',
  'HTTP_USER_AGENT' => 'Swiss-Army-Knife',
  'REQUEST_URI' => '/wp-admin/admin.php',
  'SERVER_ADDR' => '0.0.0.0',
  'SERVER_PORT' => 80,
  'REQUEST_METHOD' => 'POST',
  'QUERY_STRING' => '',
  'DOCUMENT_ROOT' => dirname(__FILE__),
));

$_POST = array();

// Prepare for importing
wordpress_importer_init();
$wp_import->fetch_attachments = 1;

// Load and parse input
$data = $wp_import->parse($input);
// Pull all authors from data
$wp_import->get_authors_from_import($data);

$i=0;
// Map all authors according to INI file.
// If not found, map to timestamped names to avoid any conflicts
foreach ($data['authors'] as $name => $auth) {
  $login_old = $auth['author_login'];
  $login_new = ( (!empty($settings['authors'][$login_old]) )
    ? $settings['authors'][$login_old] : $login_new = substr('import_'.date("Ymd_His").'_'.$login_old, 0, 60));
  $_POST['imported_authors'][$i] = $login_old;
  $_POST['user_new'][$i] = $login_new;
  $_POST['user_map'][$i] = $i++;
}

ob_start();
  // Perform the actual import
  $wp_import->import($input);
  $output = ob_get_contents();
ob_end_clean();
