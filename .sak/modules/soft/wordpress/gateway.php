<?php
/**
 * Swiss Army Knife -- (WordPress Gateway Library)
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package    WordPress
 * @subpackage Gateway
 */

/** Disables PHP error output */
function disable_errors() {
  error_reporting(E_ERROR);
  ini_set('display_errors','Off');
  ini_set('error_log',null);
}

disable_errors();
umask(022);

// Check that we are not root
if (((function_exists('posix_getuid')) ? ((posix_getuid() == 0) ? true : false) : (($_ENV['USER'] == "root") ? true : false) )) {
  fprintf(STDERR,"This script can not be run as root.\n");
  exit(1);
}

/** @ignore */
function do_includes($extra = array()) {
  foreach ($extra as $file) {
    if (!is_file(WP_ROOT.$file)) {
      fprintf(STDERR, "Error: Required include '%s' missing (is this install old/broken?).\n", $file);
      exit(2);
    }
  }

  ob_start();
  foreach ($extra as $file)
    require_once(WP_ROOT.$file);

  $output = ob_get_contents();
  ob_end_clean();

  if (strlen($output) > 0) {
    fprintf(STDERR,"%s: Unexpected output during inclusion of WordPress libraries.\nOutput was:\n\n", $self);
    fwrite(STDERR,$output);
    exit(2);
  }
}

////////////////////////////////////////////////////////////////////////////////

/**
 * Toggles WordPress plugins
 *
 * @param array $args Array containing plugins to toggle
 */
function toggle_plugins($args) {
  global $err_delay, $wpdb;

  do_includes(array("wp-admin/includes/plugin.php"));

  if (!function_exists('activate_plugin') || !function_exists('deactivate_plugins')) {
    fprintf(STDERR,"%s: Could not get plugin functions. Exiting.\n", $self);
  }

  while (($plugin = array_shift($args))) {
    $ret = null;
    $action = substr($plugin,0,1);
    $plugin = substr($plugin,1);

    if (!is_file("wp-content/plugins/".$plugin)) {
      $err_delay = true;
      fprintf(STDERR,"%s: Invalid plugin, or file not found.\n",$plugin);
      continue;
    }

    switch ($action) {
      case '+':
        $ret = activate_plugin($plugin);
        break;
      case '-':
        $ret = deactivate_plugins($plugin);
        break;
      case '*':
        $ret = activate_plugin($plugin,false,false,true);
        break;
      case '/':
        $ret = deactivate_plugins($plugin,true);
        break;
      default:
        fprintf(STDERR,"%s: Could not determine whether to activate or not. Skipped.\n", $plugin);
        continue;
    }

    if ($ret != null) {
      // Non-blocking error
      $err_delay = true;
      fprintf(STDERR,"%s: Error during activation/de-activation.\n",$plugin);
      print_r($ret);
    } else {
      fprintf(STDOUT,"%s: Success.\n",$plugin);
    }
  }
  // Required since WP caches enabled status for some reason
  wp_cache_flush();
}

/**
 * Applies WP Super Cache recommended settings
 *
 * @param string  $output   File to output contents
 * @param string  $docroot  Apache document root needed for mod_rewrite
 * @return bool True on success, false otherwise
 * @todo Remove unused $output
 */
function cache_enable_wpsc($output,$docroot = "") {
  $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
  $handle = fopen($output,"w");

  global $wp_cache_config_file, $wp_cache_config_file_sample, $sem_id,
         $cache_path, $wp_cache_mobile_browsers, $wp_cache_mobile_prefixes,
         $current_user, $wp_version;

  $current_user = false;
  if (substr($wp_version,0,1) < 3) {            # Require WP >= 3.0
    fprintf(STDERR,"Error: This version of WordPress (%s) is too old!\n",$wp_version);
    return 1;
  } elseif (substr($wp_version,0,3) == "3.0") { # WP < 3.1
    $users = get_users_of_blog();
  } else {                                      # All others
    $users = get_users();
  }

  foreach ($users as $user) {
    $user = new WP_User($user->ID);
    if ($user->has_cap('delete_users')) {
      $current_user = $user;
      break;
    }
  }

  if ($current_user === false) {
    fprintf(STDERR,"Error: Could not find proper admin to apply settings!\n");
    return false;
  }

  // Settings to fool the plugin
  $_SERVER['HTTP_HOST'] = preg_replace('|^https?://([^/]+)/?.*|','\1',get_option('siteurl'));
  $_REQUEST['_wpnonce'] = wp_create_nonce('wp-cache');

  // Docroot cannot be determined within this gateway script
  if ($docroot == "") {
    fprintf(STDERR,"Error: Could not determine document root. Please provide it.");
    return false;
  }

  if (isset($_SERVER['PHP_DOCUMENT_ROOT']))
    unset($_SERVER['PHP_DOCUMENT_ROOT']);

  $_SERVER['DOCUMENT_ROOT'] = $docroot;

  $_POST = array(
    'action' => 'scupdates',
    'wp_cache_enabled' => 1,
    'wp_cache_mod_rewrite'=> 1,
    'wp_cache_not_logged_in' => 1,
    'cache_compression' => 1,
    'cache_rebuild_files' => 1,
    'wp_cache_front_page_checks' => 1,
    'wp_supercache_cache_list' => 1,
    'updatehtaccess' => 1,
  );

  // Just in case.
  $_GET = array('page'=>'wpsupercache','tab'=>'settings');
  $_REQUEST = array_merge($_REQUEST,$_GET,$_POST);

  // Bring in the plugin now
  require_once('wp-content/plugins/wp-super-cache/wp-cache.php');

  $preflight = false;
  ob_start(); // We don't need no stinkin' badges.

  if (
    wp_cache_check_link() &&
    wp_cache_verify_config_file() &&
    wp_cache_verify_cache_dir() &&
    wp_cache_check_global_config()
  )
    $preflight = true;

  $output = ob_get_contents();
  ob_end_clean();

  if (!($preflight)) {
    // TODO: Check $output
    fprintf(STDERR,"Error: Preflight failed.");
    fwrite(STDERR,$output);
    return false;
  }

  $success = false;
  ob_start();

  if (
    extract(wpsc_get_htaccess_info(), EXTR_PREFIX_ALL, "wpsc_sak") > 0 &&
    wp_cache_manager_updates() !== false &&
    wpsc_update_htaccess() &&
    insert_with_markers($cache_path.'.htaccess', 'supercache', explode("\n", $wpsc_sak_gziprules))
  ) $success = true;

  $output = ob_get_contents();
  ob_end_clean();

  if (!($success))
    fwrite(STDERR, $output);

  return $success;
}

/**
 * Forces updates to .htaccess mod_rewrite rules
 * @uses fake_mod_rewrite Filter to force got_rewrite to return true.
 */
function flush_rewrite() {
  require_once('wp-includes/rewrite.php');
  require_once('wp-admin/includes/misc.php');

  // We DO have mod_rewrite
  add_filter('got_rewrite','fake_mod_rewrite');

  // Reset, rewrite.
  delete_option('rewrite_rules');
  if (!save_mod_rewrite_rules()) {
    fprintf(STDERR,"Error updating mod_rewrite rules. Check .htaccess for permissions or other problems.\n");
    return false;
  }
  return true;
}

/**
 * WordPress hook to make sure it knows we have mod_rewrite
 */
function fake_mod_rewrite() {
  return true;
}

////////////////////////////////////////////////////////////////////////////////

if ($argc < 4) {
  fprintf(STDERR, "Error: Too few arguments.\n");
  exit(1);
}

$args = $argv;
$self = basename(array_shift($args));
$target = array_shift($args);
$err_delay = false;
/** @ignore */
define('WP_ROOT', rtrim($target,"/") . '/');

if (!is_dir($target) || !is_readable($target)) {
  fprintf(STDERR, "Error: Directory is invalid or inaccessible (does it exist, or is it suspended?): %s\n", $target);
  exit(2);
} else {
  chdir($target);
}

/**#@+ @ignore */
define('WP_REPAIRING', true);
define('WP_CACHE', false);
define('WP_DEBUG', false);
/**#@-*/

// wp-load.php must be included in the global context
/**#@+ @ignore */
ob_start();
if (file_exists(WP_ROOT."wp-load.php")) {
  require_once(WP_ROOT."wp-load.php");
} else {
  require_once(WP_ROOT."wp-config.php");
}
require_once('wp-admin/includes/file.php');
require_once('wp-admin/includes/misc.php');
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

array_merge($_SERVER,array(
  'SERVER_SOFTWARE' => 'Swiss-Army-Knife',
  'HTTP_USER_AGENT' => 'Swiss-Army-Knife',
  'REQUEST_URI' => '/',
  'SERVER_ADDR' => '0.0.0.0',
  'SERVER_PORT' => 80,
  'REQUEST_METHOD' => 'GET',
  'QUERY_STRING' => '',
  'DOCUMENT_ROOT' => dirname(__FILE__),
));

while ($arg = array_shift($args)) {
  if ($arg == null) { break; }
  switch ($arg) {
    case 'plugin':
      /**#@+ @ignore */
      define('WP_ALLOW_MULTISITE', false);
      define('MULTISITE', false);
      /**#@-*/
      $_SERVER['REQUEST_URI'] = '/';
      toggle_plugins((array) $args);
      break 2;
    case 'w3tc':
      get_w3tc_info(array_shift($args));
      break 2;
    case 'wpsc':
      get_wpsc_info(array_shift($args));
      break 2;
    case 'enable_wpsc':
      cache_enable_wpsc(array_shift($args),array_shift($args));
      break 2;
    case 'rewrite':
      flush_rewrite();
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
