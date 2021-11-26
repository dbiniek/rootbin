<?php
/**
 * Swiss Army Knife -- (Gateway library script)
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package    SwissArmyKnife
 * @subpackage Gateway
 */

require_once 'inc/functions.php';
require_once 'inc/defines.php';

/**
 * Gateway class
 *
 * @package     SwissArmyKnife
 * @subpackage  Gateway
 */
class Gateway extends Lib {
  /** @var SwissArmyKnife */
  protected $owner = null;
  /** @var Core */
  protected $core = null;

  /** @var int */
  protected $uid = null;
  /** @var bool */
  protected $init = false;
  /** @var bool */
  protected $wp_init = false;

  /** @var mixed */
  protected $data = null;

  /**
   * Construct a Gateway class.
   *
   * @param SwissArmyKnife  $owner  Object owner
   * @param Core            $core   Core object to bind to
   * @param int             $user   Numeric system user ID
   */
  function __construct(SwissArmyKnife $owner, Core $core, $user) {
    $this->owner = $owner;
    $this->core = $core;

    if (!is_numeric($user)) {
      if (($info = posix_getpwnam($user)) === false)
        $this->fatal(sprintf("Could not resolve uid for username `%s'", $user));

      $uid = $info['uid'];
    }

    if ($uid == 0 || $uid < 500)
      $this->fatal(sprintf('Could not find valid user for software access. Got uid = %d', $uid));

    $this->uid = $uid;
  }

  /**
   * Prepare Gateway for command execution.
   *
   * Disables automatic class loading and changes process owner to the set UID.
   *
   * @return bool True on success
   */
  public function init() {
    if ($this->init === true) return true;

    if (is_null($this->core) || is_null($this->uid))
      return false;

    sak_autoload_unregister();
    $info = posix_getpwuid($this->uid);
    if ($info === false) return false;

    $this->message('Gateway', 'Adjusting process ownership...');
    if (posix_setgid($info['gid']) == 0 || posix_setuid($info['uid']) == 0)
      $this->fatal('Could not set process ownership.');

    $new_uid = posix_getuid();
    $info = posix_getpwuid($new_uid);
    $this->message('Gateway', sprintf('New process owner: %s (%d)', $info['name'], $new_uid));

    return ($this->init = true);
  }

  /**
   * Verify if a Gateway object is initialized for the given Core and UID.
   *
   * @param Core  $core Core object for comparison
   * @param int   $uid  User ID
   */
  public function check(Core $core, $uid) {
    if (is_null($this->init) || $this->core != $core || $this->uid != $uid)
      return false;
    return true;
  }

  /**
   * Disable PHP errors
   */
  private function disable_errors() {
    error_reporting(E_ERROR);
    ini_set('display_errors', 'Off');
    ini_set('error_log', '/dev/null');
  }

  /**#@+ @section WordPress */
  /**
   * Prepare a plugin interaction.
   *
   * Called with an array of plugin updates. Each item is an array of 3 options,
   * the plugin name, the active status (true = enable, false = disable),
   * ignore hooks (true = do not trigger hooks, false = default).
   *
   * Example:
   * <code>
   * $ret = $gateway->wp_set_plugins(
   *   array(
   *     array('Plugin One', true),
   *     array('PLugin Two', false, true)
   *   )
   * )
   * </code>
   *
   * @param array $plugins  Plugin settings
   *
   * @return bool True on success
   */
  public function wp_set_plugins($plugins = array()) {
    if (!$this->wp_init()) return false;

    $this->data = array();
    foreach ($plugins as $plugin) {
      if (!isset($plugin[1])) $plugin[] = true;
      if (!isset($plugin[2])) $plugin[] = false;
      $this->data[] = $plugin;
    }

    return true;
  }

  /**
   * Execute plugin interaction.
   *
   * @return array  Array of results
   */
  public function wp_toggle_plugins_exec() {
    if (!is_array($this->data)) return array(false);

    return $this->wp_toggle_plugins();
  }

  /**
   * Initialize WordPress by loading base libraries.
   *
   * @return bool True on success
   */
  private function wp_init() {
    if (!$this->init()) return false;
    if ($this->wp_init) return true;

    /**#@+ @ignore */
    define('WP_ROOT', $this->core->path.DS);
    define('WP_REPAIRING', true);
    define('WP_CACHE', false);
    define('WP_DEBUG', false);

    ob_start();
    $this->message('WPINIT', 'If you see this message, a fatal error has occured. Review output below:', SAK_LOG_ERROR);
    require_once(WP_ROOT.(file_exists(WP_ROOT."wp-load.php")
      ? 'wp-load.php' : 'wp-config.php'));

    require_once('wp-admin'.DS.'includes'.DS.'file.php');
    require_once('wp-admin'.DS.'includes'.DS.'misc.php');
    $output = ob_get_contents();
    ob_end_clean();
    /**#@-*/

    array_merge($_SERVER, array(
      'SERVER_SOFTWARE' => 'Swiss-Army-Knife',
      'HTTP_USER_AGENT' => 'Swiss-Army-Knife',
      'REQUEST_URI'     => '/',
      'SERVER_ADDR'     => '0.0.0.0',
      'SERVER_PORT'     => 80,
      'REQUEST_METHOD'  => 'GET',
      'QUERY_STRING'    => '',
      'DOCUMENT_ROOT'   => $this->core->path,
    ));

    return ($this->wp_init = true);
  }

  /**
   * Pull in WordPress files for inclusion.
   *
   * @param array $extra  Array of extra files to include
   */
  function wp_do_includes($extra = array()) {
    foreach ($extra as $file)
      if (!is_file(WP_ROOT.$file))
        $this->fatal(sprintf("Error: Required include '%s' missing (is this install old/broken?).", $file));

    ob_start();
    $this->message('Includes', 'If you see this message, a fatal error has occured. Review output below:', SAK_LOG_ERROR);
    foreach ($extra as $file)
      require_once(WP_ROOT.$file);

    $output = ob_get_contents();
    ob_end_clean();
    $output = array_splice(explode("\n", trim($output, "\n")), 1);

    if ($output) {
      $this->fatal("Unexpected output during inclusion of WordPress libraries. Output was:");
      printf("  %s\n", implode("\n  ", $output));
    }
  }

  /**
   * Toggles WordPress plugins
   *
   * @param array $plugins Array containing plugins to toggle
   */
  private function wp_toggle_plugins() {
    if (!is_array($this->data)) return false;

    global $wpdb;
    $this->wp_do_includes(array('wp-admin'.DS.'includes'.DS.'plugin.php'));
    $this->disable_errors();

    if (!function_exists('activate_plugin') || !function_exists('deactivate_plugins')) {
      $this->fatal('Could not get plugin functions. Exiting.');
    }

    $enable = $atte = 0;
    $disable = $attd = 0;
    $err_delay = false;

    echo "\n";
    foreach ($this->data as $plugin) {
      $ret = null;
      $filename = $plugin[0];
      if (!is_file($this->core->path.DS.'wp-content'.DS.'plugins'.DS.$filename)) {
        $err_delay = true;
        $this->message('Plugin', 'Invalid plugin, or file not found.', SAK_LOG_ERROR);
        continue;
      }

      ob_start();
      $this->message('Plugin', 'If you see this message, a fatal error has occured. Review output below:', SAK_LOG_ERROR);
      if ($plugin[1] === true) {
        $action = "\e[32mEnabled";
        $ret = (($plugin[2] === false)
          ? activate_plugin($filename)
          : activate_plugin($filename, false, false, true));
        $atte++;
      } else {
        $action = "\e[31mDisabled";
        $ret = (($plugin[2] === false)
          ? deactivate_plugins($filename)
          : deactivate_plugins($filename, true));
        $attd++;
      }
      $output = @ob_get_contents();
      @ob_end_clean();
      $output = array_splice(explode("\n", trim($output, "\n")), 1);

      if (!is_null($ret)) {
        $this->message('Plugin', sprintf("%s\e[0m: \e[1m%s\e[0m: \e[33;1mPossible failure.\e[0m See output below:", $action, $filename), SAK_LOG_WARN);
        printf("\n  %s\n\n", implode("\n  ", explode("\n", trim(var_export($ret, true), "\n"))));
        $err_delay = true;
      } elseif ($output) {
        $this->message('Plugin', sprintf("%s\e[0m: \e[1m%s\e[0m: \e[33;1mPossible failure.\e[0m See output below:", $action, $filename), SAK_LOG_WARN);
        printf("\n  %s\n\n", implode("\n  ", $output));
        $err_delay = true;
      } else {
        ($plugin[1] === true) ? $atte--   : $attd--;
        ($plugin[1] === true) ? $enable++ : $disable++;
        $this->message('Plugin', sprintf("%s\e[0m plugin: \e[1m%s\e[0m", $action, $filename));
      }
    }
    // Required since WP caches enabled status for some reason
    wp_cache_flush();

    return array(!($err_delay), $enable, $disable, $atte, $attd);
  }

  /**
   * Applies WP Super Cache recommended settings
   *
   * @param string  $output   File to output contents
   * @param string  $docroot  Apache document root needed for mod_rewrite
   * @return bool True on success, false otherwise
   * @todo Remove unused $output
   */
  //private function wp_cache_enable_wpsc($docroot = "") {
  //  global $wp_cache_config_file, $wp_cache_config_file_sample, $sem_id,
  //         $cache_path, $wp_cache_mobile_browsers, $wp_cache_mobile_prefixes,
  //         $current_user, $wp_version;
  //
  //  $this->disable_errors();
  //  $current_user = false;
  //  if (version_compare($wp_version, '3', '<')) {           # Require WP >= 3.0
  //    $this->fatal(sprintf("This version of WordPress (%s) is too old!", $wp_version));
  //  } elseif (version_compare($wp_version, '3.1', '<')) {   # WP < 3.1
  //    $users = get_users_of_blog();
  //  } else {                                                # All others
  //    $users = get_users();
  //  }
  //
  //  foreach ($users as $user) {
  //    $user = new WP_User($user->ID);
  //    if ($user->has_cap('delete_users')) {
  //      $current_user = $user;
  //      break;
  //    }
  //  }
  //
  //  if ($current_user === false)
  //    $this->fatal("Could not find proper admin to apply settings!");
  //
  //  // Settings to fool the plugin
  //  $_SERVER['HTTP_HOST'] = preg_replace('|^https?://([^/]+)/?.*|', '\1', get_option('siteurl'));
  //  $_REQUEST['_wpnonce'] = wp_create_nonce('wp-cache');
  //
  //  // Docroot cannot be determined within this gateway script
  //  if ($docroot == "")
  //    $this->fatal("Error: Could not determine document root. Please provide it.");
  //
  //  if (isset($_SERVER['PHP_DOCUMENT_ROOT']))
  //    unset($_SERVER['PHP_DOCUMENT_ROOT']);
  //
  //  $_SERVER['DOCUMENT_ROOT'] = $docroot;
  //
  //  $_POST = array(
  //    'action' => 'scupdates',
  //    'wp_cache_status' => 'all',
  //    'super_cache_enabled' => 1,
  //    'cache_compression' => 1,
  //    'wp_supercache_304' => 1,
  //    'wp_cache_not_logged_in' => 1,
  //    'cache_rebuild_files' => 1,
  //    'wp_cache_front_page_checks' => 1,
  //    'wp_supercache_cache_list' => 0,
  //    'updatehtaccess' => 1,
  //  );
  //
  //  // Just in case.
  //  $_GET = array('page'=>'wpsupercache','tab'=>'settings');
  //  $_REQUEST = array_merge($_REQUEST, $_GET, $_POST);
  //
  //  // Bring in the plugin now
  //  require_once('wp-content'.DS.'plugins'.DS.'wp-super-cache'.DS.'wp-cache.php');
  //
  //  $output = '';
  //  $preflight = false;
  //  ob_start(); // We don't need no stinkin' badges.
  //  $this->message('WPCACHE-1', 'If you see this message, a fatal error has occured. Review output below:', SAK_LOG_ERROR);
  //
  //  if (
  //    wp_cache_check_link() &&
  //    wp_cache_verify_config_file() &&
  //    wp_cache_verify_cache_dir() &&
  //    wp_cache_check_global_config()
  //  ) $preflight = true;
  //
  //  $output = ob_get_contents();
  //  ob_end_clean();
  //
  //  if (!($preflight)) {
  //    // TODO: Check $output
  //    $output = array_splice(explode("\n", trim($output, "\n")), 1);
  //    $this->message('Cache', "Preflight failed:");
  //    printf("  %s\n", implode("\n  ", $output));
  //    $this->stop(1);
  //  }
  //
  //  $output = '';
  //  $success = false;
  //  ob_start();
  //  $this->message('WPCACHE-2', 'If you see this message, a fatal error has occured. Review output below:', SAK_LOG_ERROR);
  //
  //  if (
  //    extract(wpsc_get_htaccess_info(), EXTR_PREFIX_ALL, "wpsc_sak") > 0 &&
  //    wp_cache_manager_updates() !== false &&
  //    wpsc_update_htaccess() &&
  //    insert_with_markers($cache_path.'.htaccess', 'supercache', explode("\n", $wpsc_sak_gziprules))
  //  ) $success = true;
  //
  //  $output = ob_get_contents();
  //  ob_end_clean();
  //
  //  if ($success !== true) {
  //    $output = array_splice(explode("\n", trim($output, "\n")), 1);
  //    $this->message('Cache', "\e[31;1mFailed\e[0m. Check below for errors:");
  //    printf("  %s\n", implode("\n  ", $output));
  //    $this->stop(1);
  //  }
  //
  //  return $success;
  //}

  /**
   * Forces updates to .htaccess mod_rewrite rules
   * @uses wp_fake_mod_rewrite Filter to force got_rewrite to return true.
   */
  public function wp_flush_rewrite() {
    require_once('wp-includes'.DS.'rewrite.php');
    require_once('wp-admin'.DS.'includes'.DS.'misc.php');

    $this->disable_errors();
    // We DO have mod_rewrite
    add_filter('got_rewrite', array($this, 'wp_fake_mod_rewrite'));

    // Reset, rewrite.
    delete_option('rewrite_rules');
    if (!save_mod_rewrite_rules())
      $this->fatal("Error updating mod_rewrite rules. Check .htaccess for permissions or other problems.");

    return true;
  }

  /**
   * WordPress hook to make sure it knows we have mod_rewrite
   */
  public function wp_fake_mod_rewrite() {
    return true;
  }
  /**#@-*/
}
