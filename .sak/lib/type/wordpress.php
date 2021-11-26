<?php
/**
 * Swiss Army Knife -- (WordPress Template Library)
 *
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package WordPress
 */

/**
 * WordPress class based on {@link Type_Template}
 * @package WordPress
 */
class Type_WordPress extends Type_Template {
  /** @var Type_WordPress_Caching */
  private $caching = null;

  public function __construct(SwissArmyKnife $owner, Core $core) {
    parent::__construct($owner, $core);
    $this->config = "wp-config.php";
    $this->caching = new Type_WordPress_Caching($owner, $this, $core);
  }

  public function command($args = array()) {
    if ($this->getopt($args, $this->owner->name, 'h', '--help', (SAK_GETOPT_QUIET |
      SAK_GETOPT_ARGS_KEEP | SAK_GETOPT_ARGS_LOWERCASE | SAK_GETOPT_ARGS_ORDER)
    ) === false) $this->owner->stop(1);

    while ($args) {
      switch ($arg = array_shift($args)) {
        case '-h':
        case '--help':
          echo "[WP HELP PLACEHOLDER]\n";
          $this->stop();
        case '':
        case 'i':
        case 'info':
          $this->printInfo(true);
          $this->stop();
        case 'b':
        case 'basic':
        case 'basics':
          $this->printBasic(true);
          $this->stop();
        case 'count':
        case 'counts':
          $this->printCounts(true);
          $this->stop();
        case 'c':
        case 'cache':
        case 'caching':
          $this->caching->command($args);
          $this->stop();
        case 'u':
        case 'user':
        case 'users':
          $this->printUsers(true);
          $this->stop();
        case 't':
        case 'theme':
        case 'themes':
          $this->themes($args);
          $this->stop();
        case 'p':
        case 'plugin':
        case 'plugins':
          $this->plugins($args);
          $this->stop();
        case 'cr':
        case 'cron':
          $this->printCron();
          $this->stop();
        case 's':
        case 'set':
          $this->setBasics($args);
          $this->stop();
        case '--': break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
    }
    $this->printInfo(true);
  }

  /**
   * Initialization and passthrough for connection class
   */
  public function connect() {
    if (is_null($this->connection)) {
      $reqs = array("wp-config.php","wp-content","wp-content/plugins","wp-content/themes");
      foreach ($reqs as $req)
        if (!file_exists($req))
          $this->fatal(array("Missing: $req","This install appears to be broken or otherwise unsupported."));

      if (is_null($dbname = $this->setting('DB_NAME')))
        $this->fatal('Could not find database name.');

      if (is_null($dbprefix = $this->setting('table_prefix')))
        $this->fatal('Could not find database table prefix.');

      list($username, $password) = SwissArmyKnife::readMySQLINI();

      if (is_null($username) || is_null($password) || $username == "" || $password == "")
        $this->fatal('Could not parse MySQL connection information. Is /root/.my.cnf correct?');

      $this->connection = new Type_WordPress_Connection($this->owner,
        $this->core, $this, $dbname, $dbprefix, $username, $password);
    }

    return $this->connection;
  }

  public function printInfo() {
    echo "\n==[ Overview ]======================-==--- -- -\n";
    $this->printBasic();
    echo "\n==[ Counts ]========================-==--- -- -\n";
    $this->printCounts();
    echo "\n==[ Caching ]=======================-==--- -- -\n";
    $this->printCaching();
    echo "\n==[ Users ]=========================-==--- -- -\n";
    $this->printUsers();
    echo "\n==[ Themes ]========================-==--- -- -\n";
    $this->printThemes();
    echo "\n==[ Plugins ]=======================-==--- -- -\n";
    $this->printPlugins();
  }

  function printBasic($long = false) {
    $basics = $this->connect()->get_basics();
    if ($long === true) echo "\n";

    $caching = array();
    if (file_exists($this->core->path.DS.'wp-content'.DS.'advanced-cache.php'))
      $caching[] = "File";
    if (file_exists($this->core->path.DS.'wp-content'.DS.'object-cache.php'))
      $caching[] = "Object";
    if (file_exists($this->core->path.DS.'wp-content'.DS.'db.php'))
      $caching[] = "DB";
    $caching = (($caching) ? implode(" ", $caching) : "NONE");

    printf("Path    : %s\n".
           "Software: \33[1mWordPress\33[0m\nVersion : \33[1m%s\33[0m (%s)\n\n",
      $this->core->path, $this->core->version, Core::pVuln($this->core->vuln));

    printf("Database: \33[1m%s\33[0m\nDB Ver  : \33[1m%s\33[0m\n".
           "Prefix  : \33[1m%s\33[0m\n\n",
      $this->setting('DB_NAME'), $basics['db_version'], $this->setting('table_prefix'));

    if ($this->setting('MULTISITE'))
      echo " \33[1m*** \33[33mWARNING: \33[31mMultisite enabled!\n \33[0;1m*** \33[33mSome functions may not work or may produce unexpected results!\33[0m\n\n";

    printf("Site Name: \33[1m%s\33[0m\nTagline:   \33[1m%s\33[0m\n\n",
      $basics['blogname'], $basics['blogdescription']);

    printf("Home URL: \33[34;4m%s\33[0m\nSite URL: \33[34;4m%s\33[0m\n\n",
      $basics['home'], $basics['siteurl']);

    printf("Permalink: \33[1m%s\33[0m\n\nCaching Drop-ins: \33[1m%s\33[0m\n",
      $basics['permalink_structure'], $caching);
  }

  function setBasics($args = array()) {
    if ($this->getopt($args, $this->owner->name, '-h', '--help',
      (SAK_GETOPT_ARGS_LOWERCASE)
    ) === false) $this->owner->stop(1);

    while ($args) {
      switch ($arg = $args[0]) {
        case '-h':
        case '--help':
          echo "[WP SET HELP PLACEHOLDER]\n";
          $this->stop();
        case '--': array_shift($args); break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
      array_shift($args);
    }

    if (!$args)
      $this->fatal('No set option provided.');
    elseif (count($args) > 2)
      $this->fatal(sprintf("Too many arguments provided: `%s'", implode("', `", $args)));

    $ret = false;
    switch ($args[0]) {
      case 'name':
        $ret = $this->connect()->set_basics('blogname', $args[1]);
        break;
      case 'tag':
      case 'desc':
      case 'description':
        $ret = $this->connect()->set_basics('blogdescription', $args[1]);
        break;
      case 'home':
        $ret = $this->connect()->set_basics('home', $args[1]);
        break;
      case 'site':
        $ret = $this->connect()->set_basics('siteurl', $args[1]);
        break;
      case 'url':
        $ret = $this->connect()->set_basics(
          array('home' => $args[1], 'siteurl' => $args[1]));
        break;
      case 'permalink':
        if ($this->connect()->set_basics('permalink_structure', $args[1]) === true) {
          $gate = $this->owner->gateway($this->core, fileowner($this->core->path));
          if (!$gate->init())
            $this->fatal('Failed to initialize software gateway library.');

          $ret = $gate->wp_flush_rewrite();
        }
        break;
    }

    if ($ret === false)
      $this->fatal('Unable to apply changes.');

    $this->printBasic(true);
  }

  function printCounts($long = false) {
    $counts = $this->connect()->get_counts();
    if ($long === true) echo "\n";

    printf("Posts: \33[1m%-8d\33[0m    Comments  : \33[1m%d\33[0m (\33[1;32m%d\33[0m/\33[1;33m%d\33[0m/\33[1;31m%d\33[0m/\33[1;30m%d\33[0m)\n",
      array_sum($counts['posts']), array_sum($counts['comments']),
      $counts['comments']['approved'], $counts['comments']['waiting'], $counts['comments']['spam'], $counts['comments']['trash']);

    printf("Pages: \33[1m%-8d\33[0m    (\33[1;32mApproved\33[0m/\33[1;33mWaiting\33[0m/\33[1;31mSpam\33[0m/\33[1;30mTrash\33[0m)\n",
      array_sum($counts['pages']));

    printf("Tags : \33[1m%-8d\33[0m    Categories: \33[1m%-8d\33[0m\n",
      $counts['tags'], $counts['categories']);
  }

  function printCaching() {
    return $this->caching->printCaching();
  }

  function printUsers($long = false) {
    $users = $this->connect()->get_users();
    $total = count($users);
    $output = (($long) ? "\n" : '');

    $i = 0;
    foreach ($users as $user) {
      $capabilities = "";
      if (is_array($user['user_capabilities'])) {
        if (sizeof($user['user_capabilities']) > 0)
          list($capabilities) = array_keys($user['user_capabilities']);
      } else
        $capabilities = "Level ".$user['user_capabilities'];

      $output .= sprintf("#%-3d \33[34m%-12s\33[0m \33[1m%-16s\33[0m  Disp: \33[34m%-16s\33[0m  Registered: \33[1m%s\33[0m  Email: \33[1m%s\33[0m\n",
        $user['ID'], $user['user_login'], "($capabilities)", $user['display_name'], $user['user_registered'], $user['user_email']);

      if (++$i == 25 && !($long)) {
        $output .= sprintf("\e[33mShowing the first 25 (of %s) user listings, use \e[1m\"%s wp users\"\e[0;33m to list all.\e[0m\n", count($users), SAK_BASENAME);
        break;
      }
    }

    if ($long && substr_count($output, "\n") > 22)
      $this->less($output);
    else
      echo $output;
  }

  function themes($args = array()) {
    if ($this->getopt($args, $this->owner->name, 'h', '--help', (SAK_GETOPT_QUIET |
      SAK_GETOPT_ARGS_KEEP | SAK_GETOPT_ARGS_LOWERCASE | SAK_GETOPT_ARGS_ORDER)
    ) === false) $this->owner->stop(1);

    while ($args) {
      switch ($arg = array_shift($args)) {
        case 'set':
        case 'change':
          $this->setTheme($args);
          $this->stop();
        case '':
        case 'info':
        case 'list':
          $this->printThemes($args, true);
          $this->stop();
        case '-h':
        case '--help':
          echo "[WP THEME HELP PLACEHOLDER]\n";
          $this->stop();
        case '--': break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
    }

    $this->printThemes($args, true);
  }

  function printThemes($args = array(), $long = false) {
    if ($this->getopt($args, $this->owner->name, '-h', '--help',
      (SAK_GETOPT_ARGS_LOWERCASE)
    ) === false) $this->owner->stop(1);

    while (true) {
      switch ($arg = array_shift($args)) {
        case '-h':
        case '--help':
          echo "[WP THEME HELP PLACEHOLDER]\n";
          $this->stop();
        case '--': break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
    }

    $themes = $this->connect()->get_themes();
    $output = (($long) ? "\n" : '');

    $i = 0;
    foreach ($themes as $index => $theme) {
      $output .= sprintf("#%-3d [%s] \33[34m%-32s\33[0m Version \33[33m%-12s\33[0m (Template: \33[1m%s\33[0m)\n",
        ($index + 1), (($theme['Active'])?"\33[32mActive\33[0m":'      '), $theme['Name'], $theme['Version'], $theme['Directory']);

      if (++$i == 25 && !($long)) {
        $output .= sprintf("\e[33mShowing the first 25 (of %s) themes, use \e[1m\"%s wp users\"\e[0;33m to list all.\e[0m\n", count($users), SAK_BASENAME);
        break;
      }
    }

    if ($long && substr_count($output, "\n") > 22)
      $this->less($output);
    else
      echo $output;
  }

  function setTheme($args = array()) {
    if ($this->getopt($args, $this->owner->name, '-h',
      array('--default','--help','--reset'), (SAK_GETOPT_ARGS_LOWERCASE)
    ) === false) $this->owner->stop(1);

    $default = false;
    while (true) {
      switch ($arg = array_shift($args)) {
        case '--reset':
        case '--default':
          $default = true;
          break;
        case '-h':
        case '--help':
          echo "[WP THEME SET HELP PLACEHOLDER]\n";
          $this->stop();
        case '--': break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
    }

    if (!$default && !$args)
      $this->fatal('No theme name provided.');
    elseif (count($args) > 1)
      $this->fatal(sprintf("Too many arguments provided: `%s'", implode("', `", $args)));

    $theme = null;
    $themes = $this->connect()->get_themes();

    if (!$default) {
      foreach ($themes as $temp)
        if ($temp['Name'] == $args[0] || $temp['Directory'] == $args[0]) {
          $theme = $temp;
          break;
        }
    } else {
      $t = 'Twenty ';
      $defs = array($t.'Fifteen'  => 0, $t.'Fourteen' => 1, $t.'Thirteen' => 2,
                    $t.'Twelve'   => 3, $t.'Eleven'   => 4, $t.'Ten'      => 5,
                    'WordPress Default' => 6);

      $found = array();
      foreach ($themes as $temp)
        if (isset($defs[$temp['Name']]))
          $found[$defs[$temp['Name']]] = $temp;

      sort($found, SORT_NUMERIC);
      $theme = array_shift($found);
    }

    if (is_null($theme))
      $this->fatal('No valid default theme found');

    if ($theme['Active']) {
      echo "\n";
      $this->message('Themes', sprintf("`\e[1m%s\e[0m' already active.", $theme['Name']), SAK_LOG_WARN);
    }

    if (false === $this->connect()->set_basics(array(
      'stylesheet'    => $theme['Directory'],
      'template'      => $theme['Directory'],
      'current_theme' => $theme['Name'])))
        $this->fatal('Unable to apply changes.');

    $this->printThemes(array(), true);
  }

  function plugins($args = array()) {
    if ($this->getopt($args, $this->owner->name, 'h', '--help', (SAK_GETOPT_QUIET |
      SAK_GETOPT_ARGS_KEEP | SAK_GETOPT_ARGS_LOWERCASE | SAK_GETOPT_ARGS_ORDER)
    ) === false) $this->owner->stop(1);

    while ($args) {
      switch ($arg = array_shift($args)) {
        case 'enable':
        case 'disable':
        case 'toggle':
          $this->togglePlugins($arg, $args);
          $this->stop();
        case 'install':
        case 'search':
        case 'test':
          $this->stop();
        case '':
        case 'info':
          $this->printPlugins($args, true);
          $this->stop();
        case '-h':
        case '--help':
          echo "[WP PLUGINS HELP PLACEHOLDER]\n";
          $this->stop();
        case '--': break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
    }

    $this->printPlugins($args, true);
  }

  function printPlugins($args = array(), $long = false) {
    if ($this->getopt($args, $this->owner->name, '-deh',
      array("disabled","enabled","help"), (SAK_GETOPT_ARGS_LOWERCASE)
    ) === false) $this->owner->stop(1);

    $fa = $fd = false;
    while ($long) {
      switch ($arg = $args[0]) {
        case '-a':
        case '--active':
          $fa = true; break;
        case '-d':
        case '-e':
        case '--disabled':
        case '--enabled':
          $fd = true; break;
        case '-h':
        case '--help':
          echo "[WP PLUGIN INFO HELP PLACEHOLDER]\n";
          $this->stop();
        case '--': array_shift($args); break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
      array_shift($args);
    }

    $plugins = $this->connect()->get_plugins();
    $total = count($plugins);

    $i = 0;
    $active = 0;
    $output = (($long) ? "\n" : '');
    foreach ($plugins as $index => $plugin) {
      $active += ($plugin['Active']) ? 1 : 0;
      if (++$i > 25 && !($long)) continue;
      if (($fa) && !($plugin['Active'])) continue;
      if (($fd) &&  ($plugin['Active'])) continue;

      $output .= sprintf("#%-3d [\33[3%s\33[0m] \33[34m%-32s\33[0m Version \33[33m%-12s\33[0m (File: \33[1m%s\33[0m)\n",
        $i, (($plugin['Active'])?"2m Active ":"1mDisabled"), $plugin['Name'],
        $plugin['Version'], $plugin['Filename']);

      if ($i == 25 && !($long)) {
        $output .= sprintf("\e[33mShowing the first 25 plugins, use \e[1m\"%s wp plugins\"\e[0;33m to list all.\e[0m\n", SAK_BASENAME);
        break;
      }
    }
    $output .= sprintf("                \33[32mActive: %-3d\33[0m    \33[31mDisabled: %-3d\33[0m\n", $active, ($total - $active));

    if (substr_count($output, "\n") > 50)
      $this->less($output);
    else
      echo $output;
  }

  function togglePlugins($command = 'enable', $args) {
    $targets = $enable = $disable = array();
    $plugins = $this->connect()->get_plugins();

    while (true) {
      switch ($arg = $args[0]) {
        case '-e':
        case '--enable': array_shift($args);
          if ($command == 'disable')
            $this->fatal(sprintf("Conflicting `enable' argument: %s %s", $command, $args[1]));
          $enable[] = $args[1];
          break;
        case '-d':
        case '--disable': array_shift($args);
          $disable[] = $args[1];
          break;
        case '-h':
        case '--help':
          echo "[WP PLUGIN TOGGLE HELP PLACEHOLDER]\n";
          $this->stop();
        case '--': array_shift($args); break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
      array_shift($args);
    }

    $refs = array('toggle'=>$args, 'enable'=>$enable, 'disable'=>$disable);
    foreach ($refs as $status => $array) {
      foreach ($array as $item) {
        $name = null;
        foreach ($plugins as $plugin) {
          if ($item == $plugin['Filename'] || $item == $plugin['Name']) {
            $name = $plugin['Filename'];
            break;
          }
        }

        if (is_null($name))
          $this->fatal(sprintf("Unknown plugin reference `%s'", $item));

        switch ($status) {
          case 'enable':
            if (!$plugin['Active'])
              $bool = true;
            else
              $this->message('Plugin', sprintf('Plugin already enabled: %s', $name), SAK_LOG_WARN);
            continue;
          case 'disable':
            if ($plugin['Active'])
              $bool = false;
            else
              $this->message('Plugin', sprintf('Plugin already enabled: %s', $name), SAK_LOG_WARN);
            continue;
          case 'toggle':
            $bool = (($command == 'toggle') ? !($plugin['Active'])
              : (($command == 'enable') ? true : false));
            break;
        }
        $targets[] = array($name, $bool, false);
      }
    }

    $gate = $this->owner->gateway($this->core, fileowner($this->core->path));
    if (!$gate->init())
      $this->fatal('Failed to initialize software gateway library.');

    if (!$gate->wp_set_plugins($targets))
      $this->fatal('Failed to set plugin status with gateway library.');

    list($status, $on, $off, $atte, $attd) = $gate->wp_toggle_plugins_exec();

    if (!$status)
      $this->message('Plugin', 'Possible errors while toggling plugins. Check above for output.', SAK_LOG_ERROR);

    echo "\n";
    $this->message('Plugin',
      sprintf("\e[32;1mEnabled\e[0m:  \e[1m%d\e[0m%s   \e[31;1mDisabled\e[0m: \e[1m%d\e[0m%s",
        $on,  (($atte) ? " ($atte unknown)" : ""),
        $off, (($attd) ? " ($attd unknown)" : "")),
      (($atte || $attd) ? SAK_LOG_WARN : SAK_LOG_INFO));
  }

  function printCron() {
    $cron = $this->connect()->get_cron();
    echo "\n";

    $i = 0;
    $output = '';
    foreach ($cron as $ts => $group) {
      if (!is_array($group)) continue;
      foreach ($group as $name => $entry) {
        if (count($entry) > 1 || trim($ts, '0123456789') != '') continue;
        $entry = array_shift($entry);
        if ($i++ % 25 == 0)
          echo "\33[1mNext Run             Function Call                     Schedule  (Name)\33[0m\n";
        $interval = ((array_key_exists('interval', $entry))?timedelta($entry['interval']):'None');
        $schedule = (($entry['schedule'])?"  (".$entry['schedule'].")":'');
        $run = date("Y-m-d H:i:s", $ts);
        $run = ((time() >= $ts)?"\33[33m$run\33[0m":$run);
        $output .= sprintf("%s  %-32s  %s%s\n", $run, $name, $interval, $schedule);
      }
    }
  }
}
