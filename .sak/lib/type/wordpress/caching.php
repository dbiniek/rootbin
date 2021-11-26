<?php
/**
 * Swiss Army Knife -- (WordPress Caching Library)
 *
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package WordPress
 */

/**
 * WordPress Caching class based on {@link Type_Template}
 * @package WordPress
 */
class Type_WordPress_Caching extends Type_Template {
  /** @var Type_WordPress */
  private $software = null;
  protected $type = null;

  public function __construct(SwissArmyKnife $owner, Type_WordPress $software, Core $core) {
    parent::__construct($owner, $core);
    $this->software = $software;
  }

  public function command($args = array()) {
    $mass = false;
    if ($this->getopt($args, $this->owner->name, '-h', '--help', (SAK_GETOPT_QUIET |
      SAK_GETOPT_ARGS_KEEP | SAK_GETOPT_ARGS_LOWERCASE | SAK_GETOPT_ARGS_ORDER)
    ) === false) $this->owner->stop(1);

    while ($args) {
      switch ($arg = array_shift($args)) {
        case '-h':
        case '--help':
          echo "[WP CACHE HELP PLACEHOLDER]\n";
          $this->stop();
        //case 'mass':
        //case 'masset':
        //case 'massset':
        //  $mass = true;
        //case 'set':
        //  $this->setCaching($mass, $args);
        //  break;
        case '':
        case 'info':
          echo "\n";
          $this->printCaching($args);
          $this->stop();
        case '--': break 2;
        default:
          echo "\n";
          if (strlen($arg) && $arg[0] == '-') {
            if (strlen($arg) > 1 && $arg[1] == '-')
              $this->fatal(sprintf("%s: unrecognized option `%s'", SAK_BASENAME, $arg));
            $this->fatal(sprintf("%s: invalid option -- %s\n", SAK_BASENAME, $arg));
          }
          $this->error(sprintf("unrecognized command or predicate `%s'", $arg));
          break;
      }
    }
    $this->printCaching($args);
  }

  public function scan() {
    $path = $this->core->path;
    if (!file_exists($path.DS.'wp-content'.DS.'advanced-cache.php')) {
      $this->type = 'none';
      return false;
    } else
      $this->type = '';

    $plugins = $this->software->connect()->get_plugins($path);

    foreach ($plugins as $plugin) {
      if ($plugin['Name'] == "WP Super Cache" && ($plugin['Active'])) {
        if (file_exists($path.DS.($config = 'wp-content'.DS.'wp-cache-config.php'))) {
          $this->type = "wpsc";
          $this->config = $config;
          $this->setting();
          return true;
        }
      }
    }
  }

  public function printCaching() {
    $this->scan();
    $wp_cache = $this->software->setting('WP_CACHE');

    switch ($this->type) {
      case '':
        echo "  \33[1mCache drop-ins found, but Super Cache not detected/activated, check manually.\33[0m\n";
        if ($wp_cache)
          echo "  \33[1mConfiguration file has WP_CACHE enabled.\33[0m\n";
        break;

      case 'none':
        echo "  \33[31mNo caching enabled, drop-in does not exist.\33[0m\n";
        if ($wp_cache)
          echo "\n  \33[1m*** Warning: \33[31mConfiguration file has WP_CACHE enabled.\n".
               "  \33[0;1m*** Warning: \33[31mCaching is likely not set up properly or was removed improperly.\33[0m\n";
        break;

      case 'wpsc':
        $enabled   = (bool)$this->setting('cache_enabled');
        $rewrite   = (bool)$this->setting('wp_cache_mod_rewrite');
        $legacy    = (false & (bool)$this->setting('super_cache_enabled'));
        $compress  = (bool)$this->setting('cache_compression');
        $lifetime  = $this->setting('cache_max_time');
        $usercache = (false & (bool)$this->setting('wp_cache_not_logged_in'));
        $phpmode   = ((!($rewrite) && !($legacy)) ? true : false);
        $browser   = (($rewrite) || (bool)$this->setting('wp_supercache_304'));

        printf(
          "\33[1mCaching Plugin\33[0m:  \33[1;4;34mWP Super Cache\33[0m (\33[32mActive\33[0m)\n".
          "\33[1mCaching Enabled\33[0m: \33[3%sm%s\33[0m   \33[1;4mRecommended\33[0m\n".
          "\33[1mBrowser Cache\33[0m:   \33[3%sm%s\33[0m       \33[3%smYes\33[0m\n\n".

          "\33[1mRewrite Mode\33[0m:    \33[3%sm%s\33[0m       \33[3%smYes\33[0m\n".
          "\33[1mPHP Mode\33[0m:        \33[3%sm%s\33[0m       \33[3%smNo\33[0m\n".
          "\33[1mLegacy Mode\33[0m:     \33[3%sm%s\33[0m       \33[3%smNo\33[0m\n\n".

          "\33[1mCache Users\33[0m:     \33[3%sm%s\33[0m       \33[3%smNo\33[0m\n".
          "\33[1mCompression\33[0m:     \33[3%sm%s\33[0m       \33[3%smYes\33[0m\n".
          "\33[1mCache Expiry\33[0m:    \33[35m%-9s\33[0m \33[3%sm3600 s\33[0m\n",
          (($enabled)  ? 4:3),(($enabled)  ? "Yes":"No "),
          (($browser)  ? 4:3),(($browser)  ? "Yes":"No "),(($browser)  ? 2:1),
          (($rewrite)  ? 4:3),(($rewrite)  ? "Yes":"No "),(($rewrite)  ? 2:1),
          (($phpmode)  ? 4:3),(($phpmode)  ? "Yes":"No "),(($phpmode)  ? 1:2),
          (($legacy)   ? 4:3),(($legacy)   ? "Yes":"No "),(($legacy)   ? 1:2),
          (($usercache)? 4:3),(($usercache)? "Yes":"No "),(($usercache)? 1:2),
          (($compress) ? 4:3),(($compress) ? "Yes":"No "),(($compress) ? 2:1),
                                $lifetime,        ((3600 <= $lifetime) ? 2:1));
        if (!($wp_cache))
          echo "\n  \33[1m*** Warning: \33[31mConfiguration file does not have WP_CACHE enabled.\n".
               "  \33[0;1m*** Warning: \33[31mCaching is likely not functioning properly.\33[0m\n";
        break;
    }
  }

//  private function setCaching($mass = false, $args = array()) {
//    $options = array("d:e:hinp:y", array("docroot:","errors:","help",
//      "ignore-version","no","permalinks:","yes"));
//
//    if ($this->getopt($args, $this->owner->name, $options[0],
//      $options[1], (SAK_GETOPT_QUIET | SAK_GETOPT_ARGS_KEEP | SAK_GETOPT_ARGS_LOWERCASE)
//    ) === false) $this->owner->stop(1);
//
//    $yes = false;
//    $errors = true;
//    $ignore = false;
//    $permalinks = true;
//    $docroot = null;
//    while (true) {
//      switch ($arg = $args[0]) {
//        case '-d':
//        case '--docroot': array_shift($args);
//          $docroot = $args[0];
//          if (!file_exists($docroot) || !is_dir($docroot))
//            $this->fatal(sprintf('Docroot does not exist or is not directory: %s', $docroot));
//          $docroot = realpath($docroot);
//          break;
//        case '-e':
//        case '--errors': array_shift($args);
//          $errors = $args[0];
//          break;
//        case '-i':
//        case '--ignore-version':
//          $ignore = true;
//          break;
//        case '-p':
//        case '--permalinks': array_shift($args);
//          $permalinks = $args[0];
//          if (empty($permalinks))
//            $this->fatal('Permalink setting cannot be empty.');
//          elseif ($permalinks == 'common')
//            $permalinks = '/%year%/%monthnum%/%postname%/';
//          elseif ($permalinks == 'fail')
//            $permalinks = true;
//          elseif ($permalinks == 'skip')
//            $permalinks = false;
//          elseif (!preg_match('/(?:%post_id%|%postname%)/', $permalinks))
//            $this->fatal(sprintf("Invalid permalinks setting -- `%s'", $permalinks));
//          break;
//        case '-y':
//        case '--yes': $yes = true;  break;
//        case '-n':
//        case '--no':  $yes = false; break;
//        case '-h':
//        case '--help':
//          break;
//        case '--': array_shift($args); break 2;
//        default:
//          if ($arg[0] == '-') {
//            if ($arg[1] == '-')
//              $this->fatal(sprintf("%s: unrecognized option `%s'", SAK_BASENAME, $arg));
//            else
//              $this->fatal(sprintf("%s: invalid option -- %s\n", SAK_BASENAME, $arg));
//          }
//          break 2;
//      }
//      array_shift($args);
//    }
//    echo "\n";
//
//    if (!$args)
//      $this->fatal('No caching option provided.');
//    elseif (count($args) > 1)
//      $this->fatal(sprintf("Too many arguments provided: `%s'", implode("', `", $args)));
//    elseif (strtolower($args[0]) != 'supercache')
//      $this->fatal(sprintf("Invalid caching option: `%s'", $args[0]));
//
//    //switch (strtolower($args[0])) {
//    //  case 'supercache': break;
//    //  case 'w3tc': break;
//    //}
//
//    $basics = $this->software->connect()->get_basics();
//    $plugins = $this->software->connect()->get_plugins();
//
//    if (!$this->checkVersion('3.0'))
//      $this->fatal('Cache command requires WordPress 3.0 or higher.');
//
//    // Check for Multisite
//    if ($this->software->setting('MULTISITE') === true)
//      $this->fatal('MultiSite installations are not supported at this time.');
//
//    // Check that our permalinks are set properly and adjust, skip, or fail
//    if (empty($basics['permalink_structure'])) {
//      if ($permalinks === true)
//        $this->fatal('Permalinks not set, exiting with failure.');
//      elseif ($permalinks === false)
//        $this->message('Permalinks', 'Permalinks not set, ignoring.');
//      else {
//        $this->message('Permalinks', sprintf('Permalinks not set, attempting to set them to: %s', $permalinks));
//        if ($this->software->connect()->set_basics('permalink_structure', $permalinks))
//          $this->fatal('Could not update permalinks');
//      }
//    } else
//      $this->message('Permalinks', 'Permalinks are set, no adjustments required.');
//
//    // If DocumentRoot is not provided, try to guess
//    if (is_null($docroot)) {
//      $this->message('DocRoot', 'No --docroot specified. Scanning for valid DocumentRoot.');
//      if (!file_exists($conf = '/usr/local/apache/conf/httpd.conf'))
//        $this->fatal('No --docroot specified and /usr/local/apache/conf/httpd.conf does not exist or is not readable.');
//
//      $conf = file($conf);
//      $dir = $this->core->path;
//      while (true) {
//        foreach ($conf as $line)
//          if (preg_match(sprintf('/DocumentRoot\s+(%s)\s*$/i', preg_quote($dir, '/')), $line, $match)) {
//            $docroot = $match[1];
//            $this->message('DocRoot', sprintf("Detected `%s' as document root.", $docroot));
//            break 2;
//          }
//
//        $dir = dirname($dir);
//        if (empty($dir) || $dir == '/')
//          $this->fatal('Could not determine document web-root. Please use --docroot=PATH to specify it manually.');
//      }
//    }
//
//    // Check for caching plugins and disable them
//    $installed = false;
//    $disable = array();
//    foreach ($plugins as $i => $plugin)
//      switch ($plugin['Name']) {
//        case 'WP Super Cache':
//          $this->message('Plugin', sprintf("Found WP Super Cache version %s.", $plugin['Version']));
//          // If plugin is already installed, check version, make sure it's up to date
//          if (!version_compare($plugin['Version'], '', '>'))
//            $this->fatal('WP Super Cache is outdated. Cowardly refusing to change settings. Please update the plugin manually.');
//          $installed = true;
//        case 'W3 Total Cache':
//        case 'Lite Cache':
//        case 'Quick Cache':
//        case 'Hyper Cache':
//        case 'Hyper Cache Extended':
//          if ($plugin['Active'] === true) {
//            $disable[$i] = true;
//            $this->message('Plugin', sprintf("Cache plugin `%s' is active and will be disabled.", $plugin['Name']));
//          } else
//            $this->message('Plugin', sprintf("Cache plugin `%s' is installed, but is already disabled.", $plugin['Name']));
//          break;
//      }
//
//    // Check to see if we missed any
//    if (file_exists($path.DS.'wp-content'.DS.'advanced-cache.php'))
//      $this->fatal('Page cache drop-in still exists! Please disable any caching plugins manually before trying again.');
//
//die();
//
//    # If we have no version, we need to install
//    # Fire it up!
//    # Apply settings
//    # Make sure the settings actually took
//
//    foreach ($plugins as $plugin) {
//      var_export($plugin);
//      echo "\n";
//    }
//      $this->stop();
//
//    $gate = $this->owner->gateway($this->core, fileowner($this->core->path));
//    if (!$gate->init())
//      $this->fatal('Failed to initialize software gateway library.');
//
//    $ret = $gate->wp_cache_enable_wpsc($this->core->path);
//  }
}
