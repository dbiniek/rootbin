<?php
/**
 * Swiss Army Knife -- (Joomla Template Library)
 *
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package Joomla
 */

/**
 * Joomla class based on {@link Type_Template}
 * @package Joomla
 */
class Type_Joomla extends Type_Template {

  public function __construct(SwissArmyKnife $owner, Core $core) {
    parent::__construct($owner, $core);
    $this->config = "configuration.php";
  }

  public function command($args = array()) {
    if ($this->getopt($args, $this->owner->name, 'h', '--help', (SAK_GETOPT_QUIET |
      SAK_GETOPT_ARGS_KEEP | SAK_GETOPT_ARGS_LOWERCASE | SAK_GETOPT_ARGS_ORDER)
    ) === false) $this->owner->stop(1);

    while ($args) {
      switch ($arg = array_shift($args)) {
        case '-h':
        case '--help':
          echo "[JOS HELP PLACEHOLDER]\n";
          $this->stop();
        case '':
        case 'i':
        case 'info':
          $this->printInfo();
          $this->stop();
        case 'theme':
        case 'themes':
        case 'templates':
          $this->printThemes(true);
          $this->stop();
        case 'user':
        case 'users':
          $this->printUsers(true);
          $this->stop();
        case 'addon':
        case 'addons':
          $this->addons($args);
          $this->stop();
        case 'set':
          $this->set($args);
          $this->stop();
        case '--': break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
    }
  }

  /**
   * Initialization and passthrough for connection class
   */
  public function connect() {
    if (is_null($this->connection)) {
      $reqs = array("configuration.php","administrator","templates","includes");
      foreach ($reqs as $req)
        if (!file_exists($req))
          $this->owner->fatal(array("Missing: $req","This install appears to be broken or otherwise unsupported."));

      if (is_null($dbname = $this->setting('db')))
        $this->owner->fatal('Could not find database name.');

      if (is_null($dbprefix = $this->setting('dbprefix')))
        $this->owner->fatal('Could not find database table prefix.');

      list($username, $password) = SwissArmyKnife::readMySQLINI();

      if (is_null($username) || is_null($password) || $username == "" || $password == "")
        $this->owner->fatal('Could not parse MySQL connection information. Is /root/.my.cnf correct?');

      $this->connection = new Type_Joomla_Connection($this->owner, $this->core,
        $this, $dbname, $dbprefix, $username, $password);
    }

    return $this->connection;
  }

  /**
   * Save install settings.
   *
   * @see Type_Joomla_Connection::save
   */
  public function save() {
    return $this->connect()->save();
  }

  public function printInfo() {
    echo "\n==[ Overview ]======================-==--- -- -\n";
    $this->printBasic();
    echo "\n==[ Themes ]========================-==--- -- -\n";
    $this->printThemes();
    echo "\n==[ Users ]=========================-==--- -- -\n";
    $this->printUsers();
  }

  function printBasic() {
    $basics = $this->connect()->get_basics();
    printf(
      "Path    : %s\n".
      "Software: \e[1mJoomla\e[0m\n".
      "Version : \e[1m%s\e[0m (%s\e[0m)\n\n".

      "Database: \e[1m%s\e[0m\n".
      "Prefix  : \e[1m%s\e[0m\n\n".

      "Site Name:  \e[1m%s\e[0m\n".
      "Site Desc:  \e[1m%s\e[0m\n\n".

      "Sessions:    \e[36m%s\e[0m\n".
      "Maint mode:  %s\n\n".

      "Compression: %s\n".
      "Caching:     %s (\e[36m%s\e[0m)\n".
      "Cache Time:  \e[35m%d min\e[0m\n\n".

      "SEF URLs:    %s     SEF Suffix:  %s\n".
      "Use Rewrite: %s     Use CAPTCHA: %s\n",

      $this->core->path, $this->core->version, Core::pVuln($this->core->vuln),
      $basics['db'], $basics['prefix'], $basics['name'], $basics['description'],
      (($basics['sessions'] == 'none') ? 'PHP' : ucfirst($basics['sessions'])), self::getYesNo($basics['offline']),
      self::getYesNo($basics['gzip']), self::getYesNo($basics['caching']), $basics['cache_handler'], $basics['cache_time'],
      self::getYesNo($basics['sef']), self::getYesNo($basics['sef_suffix']),
      self::getYesNo($basics['sef_rewrite']), self::getYesNo($basics['captcha']));
  }

  function printThemes($long = false) {
    if ($long) printf("\nLegend: [\e[33mA\e[0m] = Administrator,  [\e[34mF\e[0m] = Front-end\n\n");

    $i = 0;
    $output = '';
    $themes = $this->connect()->get_themes();
    foreach ($themes as $theme) {
      if ($i++ % 25 == 0)
        $output .= sprintf("\e[1m###    Enabled   Display Name                                          Type  Filename\e[0m\n");
      $output .= sprintf("#%-3d [\e[%-12s\e[0m] \e[34m%-32s\e[0m Version \e[33m%-12s\e[0m [\e[%s\e[0m]   \e[1m%s\e[0m\n",
        $i,
        ($theme['enabled'])
          ? (($theme['admin']) ? '33m  Admin' : '34mFront-end') : '0;m',
        $theme['title'],
        $theme['version'],
        ($theme['admin']) ? '33mA' : '34mF',
        $theme['template']);

      if (!($long) && $i == 25) {
        $output .= sprintf("\e[33mShowing the first 25 (of %s) themes, use \e[1m\"%s jos users\"\e[0;33m to list all.\e[0m\n", count($users), SAK_BASENAME);
        break;
      }
    }

    if ($long && substr_count($output, "\n") > 22)
      $this->less($output);
    else
      echo $output;
  }

  function printUsers($long = false) {
    $i = 0;
    $output = (($long) ? "\n" : '');
    $uid = array();
    $users = $this->connect()->get_users();
    foreach ($users as $user) {
      $uid[$user['id']] = true;
      $output .= sprintf(
        "#%-3d \e[34m%-12s\e[0m \e[1m%-22s\e[0m  Disp: \e[34m%-16s\e[0m  \e[1m%s\e[0m  Reg: \e[1m%s\e[0m  Visit: \e[1m%s\e[0m\n",
        $user['id'],
        $user['username'],
        $user['group'],
        $user['display'],
        $user['email'],
        $user['registered'],
        $user['visited']);

      if (++$i == 25 && !($long)) {
        $output .= sprintf("\e[33mShowing the first 25 (of %s) user listings, use \e[1m\"%s jos users\"\e[0;33m to list all.\e[0m\n", count($users), SAK_BASENAME);
        break;
      }
    }

    $output .= sprintf("\n  Unique users: %s\n", count($uid));
    if ($long && substr_count($output, "\n") > 50)
      $this->less($output);
    else
      echo $output;
  }

  function addons($args = array()) {
    // TODO: Review this...
    $subcommand = (($args) && $args[0][0] != '-')
      ? strtolower(array_shift($args))
      : '';
    switch ($subcommand) {
      case 'enable':
      case 'disable':
        $options = array("afh", array("admin","frontend","help"));
        break;
      case 'info':
      default:
        $subcommand = 'info';
        $options = array("def:hpt:", array("filter:","filter-disabled",
          "filter-enabled","filter-protected","help","type:"));
        break;
    }

    if ($this->owner->getopt->parse($args, $this->owner->name, $options[0],
      $options[1], (SAK_GETOPT_QUIET | SAK_GETOPT_ARGS_KEEP | SAK_GETOPT_ARGS_LOWERCASE)
    ) === false) $this->owner->stop(1);

    switch ($subcommand) {
      case 'enable':
      case 'disable':
        if ($this->checkVersion('2.5'))
          $this->toggleAddons($subcommand, $args);
        else
          $this->owner->fatal(sprintf("Toggle of Joomla %s addons is not supported.", $this->core->version));
        break;
      case 'info':
      default:
        $this->printAddons($args);
        break;
    }
  }

  function printAddons($args) {
    if ($this->getopt($args, $this->owner->name, '-defhpt', array('--help',
      '--filter','--filter-disabled','--filter-enabled','--filter-protected',
      '--type'), (SAK_GETOPT_ARGS_LOWERCASE)
    ) === false) $this->owner->stop(1);

    $fe = $fd = $fp = false;
    $type = null;
    while (true) {
      switch ($arg = $args[0]) {
        case '-f':
        case '--filter': array_shift($args);
          $name = $args[0];
          switch ($name) {
            case 'enabled':   $fe = true; break;
            case 'disabled':  $fd = true; break;
            case 'protected': $fp = true; break;
            default:
              $this->owner->fatal(sprintf("%s: Unknown filter option `%s'", SAK_BASENAME, $name));
              break;
          }
          break;
        case '-d':
        case '--filter-disabled':
          $fd = true; break;
        case '-e':
        case '--filter-enabled':
          $fe = true; break;
        case '-p':
        case '--filter-protected':
          $fp = true; break;
        case '-t':
        case '--type': array_shift($args);
          $type = $args[0];
          switch ($type) {
            case 'component':
            case 'language':
            case 'library':
            case 'module':
            case 'plugin':
              break;
            default:
              $this->owner->fatal(sprintf("%s: Unknown type option `%s'", SAK_BASENAME, $name));
              break;
          }
          break;
        case '-h':
        case '--help':
          echo "[JOS ADDONS HELP PLACEHOLDER]\n";
          $this->stop();
        case '--': array_shift($args); break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
      array_shift($args);
    }

    $i = 0;
    $output = '';
    $previous = '';
    $addons = $this->connect()->get_addons();

    // Joomla 1.6+
    if (($ver = (($this->checkVersion('1.6')) ? '1.6' : '1.5')) == '1.6') {
      foreach ($addons[$ver] as $addon) {
        if (($fe) && !($addon['enabled'])) continue;
        if (($fd) &&  ($addon['enabled'])) continue;
        if (($fp) && !($addon['protected'])) continue;
        if (!is_null($type) && $type != $addon['type']) continue;

        if ($addon['type'] != $previous)
          $output .= sprintf("\n\e[1;4m#####        Sect      Type P Name                           Element                       \e[0m\n");

        $output .= sprintf("%-7d [%s] [%s] \e[1m%10s\e[0m %s %-29s  %s\n",
          $addon['id'], (($addon['enabled']) ? "\e[32mON\e[0m" : "  "),
          (($addon['client']) ? "\e[33mA\e[0m" : "\e[34mF\e[0m"),
          $addon['type'], (($addon['protected']) ? "*" : " "),
          preg_replace('/^(?:com|mod|plg)_/', '', $addon['name']),
          (($addon['type']=='plugin')?'plg_':'').$addon['element']);
        $previous = $addon['type'];
      }

      $output .= sprintf("\n  Legend:  \e[1m*\e[0m = Protected (Cannot remove),  [\e[33mA\e[0m] = Administrator,  [\e[34mF\e[0m] = Front-end\n");
    } else {
      // Joomla 1.5 and below
      $this->owner->message("Warning", "Older version of Joomla detected.", SAK_LOG_WARN);
      $this->owner->message("Warning", "Filters disabled and output will be limited.", SAK_LOG_WARN);
      $output .= sprintf("\n\e[1;4m%-13s %-20s %-20s\e[0m\n", 'COMPONENTS', 'Option', 'Name');

      foreach ($addons[$ver]['components'] as $addon) {
        $t = (($addon['frontend'])
          ? (($addon['backend']) ? "\e[35mB\e[0m" : "\e[34mF\e[0m")
          : (($addon['backend']) ? "\e[33mA\e[0m" : " "));
        $output .= sprintf("%-4s %s [%s] %s \e[1m%-20s\e[0m %s\n",
          $addon['id'], (($addon['enabled']) ? "\e[32mON\e[0m" : "  "), $t,
          (($addon['core']) ? "*" : " "), $addon['option'], $addon['name']);
      }

      $output .= sprintf("\n\e[1;4m%-14s %-20s\e[0m\n", 'PLUGINS', 'Name');
      foreach ($addons[$ver]['plugins'] as $addon) {
        $output .= sprintf("%-4s %s [%s] %s  %s\n",
          $addon['id'], (($addon['published']) ? "\e[32mON\e[0m" : "  "),
          (($addon['client']) ? "\e[33mA\e[0m" : "\e[34mF\e[0m"),
          (($addon['core']) ? "*" : " "), $addon['name']);
      }

      $output .= sprintf("\n  Legend:  [\e[33mA\e[0m] = Administrator,  [\e[34mF\e[0m] = Front-end,  [\e[35mB\e[0m] = Both\n%12s\e[1m*\e[0m  = Protected (Cannot remove)\n", '');
    }

    if (substr_count($output, "\n") > 50)
      $this->less($output);
    else
      echo $output;
  }

  function toggleAddons($command = 'enable', $args) {
    $client = null;
    while (true) {
      switch ($arg = $args[0]) {
        case '-a':
        case '--admin':
          $client = 1;
          break;
        case '-f':
        case '--frontend':
          $client = 0;
          break;
        case '-h':
        case '--help':
          echo "[WP JOS ADDON TOGGLE HELP PLACEHOLDER]\n";
          $this->stop();
        case '--': array_shift($args); break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
      array_shift($args);
    }

    // Validate addon targets
    $addons = $this->connect()->get_addons();
    $targets = array();
    while ($arg = array_shift($args)) {
      if (is_numeric($arg)) {
        $targets[(int)$arg] = true;
      } else {
        if ($arg[3] == '_')
          $name = substr($arg, 4);
        else {
          $name = $args[1];
          array_shift($args);
        }

        switch (strtolower(substr($arg, 0, 3))) {
          case 'com': $type = 'component';  break;
          case 'mod': $type = 'module';     break;
          case 'plg': $type = 'plugin';     break;
          default:
            $this->owner->fatal(ucfirst($command), sprintf("Unknown addon type `%s'", $arg));
            break;
        }

        foreach ($addons['1.6'] as $addon)
          if (strtolower($addon['element']) == strtolower($name)) {
            $targets[$addon['id']] = true;
            break;
          }
      }
    }

    $on = $off = array();
    $targets = array_keys($targets);
    if ($command == 'enable')
      $on = &$targets;
    else
      $off = &$targets;

    echo "\n";
    if ($this->connect()->set_addons($on, $off, $client)) {
      $this->connect()->pull_addons();
      $addons = $this->connect()->get_addons();

      printf("\e[1;4m#####        Sect      Type P Name                           Element                       \e[0m\n");
      foreach ($addons['1.6'] as $addon)
        foreach ($targets as $target)
          if ($addon['id'] == $target)
            printf("%-7d [%s] [%s] \e[1m%10s\e[0m %s %-29s  %s\n",
              $addon['id'], (($addon['enabled']) ? "\e[32mON\e[0m" : "  "),
              (($addon['client']) ? "\e[33mA\e[0m" : "\e[34mF\e[0m"),
              $addon['type'], (($addon['protected']) ? "*" : " "),
              preg_replace('/^(?:com|mod|plg)_/', '', $addon['name']),
              (($addon['type']=='plugin')?'plg_':'').$addon['element']);

      echo "\n";
      $this->owner->message(ucfirst($command), 'Complete.');
    }
  }

  function set($args = array()) {
    if (!$args || !isset($args[0]) || empty($args[0]) || !isset($args[1])) {
      $this->owner->fatal('Not enough arguments.');
    }

    $invert = false;
    while (true) {
      switch ($arg = $args[0]) {
        case 'captcha': array_shift($args);
          $this->connect()->set_basics('captcha',
            ((self::setYesNo($args[0])) ? '1' : '0'));
          break 2;
        case 'name': array_shift($args);
          $this->connect()->set_basics('name', $args[0]);
          break 2;
        case 'desc': array_shift($args);
          $this->connect()->set_basics('description', $args[0]);
          break 2;
        case 'offline':
          $invert = true;
        case 'online': array_shift($args);
          $this->connect()->set_basics('offline',
            ((self::setYesNo($args[0], $invert)) ? '1' : '0'));
          break 2;
        case 'maintmsg':
        case 'maintmessage':
        case 'maint_message':
        case 'maint-message':
        case 'offmsg':
        case 'offmessage':
        case 'offlinemessage':
        case 'offline-message':
        case 'offline_message': array_shift($args);
          $this->connect()->set_basics('offline_message', $args[0]);
          break 2;
        case 'rewrite': array_shift($args);
          $this->connect()->set_basics('rewrite',
            ((self::setYesNo($args[0])) ? '1' : '0'));
          break 2;
        case 'sef':
        case 'seo': array_shift($args);
          $this->connect()->set_basics('sef',
            ((self::setYesNo($args[0])) ? '1' : '0'));
          break 2;
        case 'suffix': array_shift($args);
          $this->connect()->set_basics('sef_suffix',
            ((self::setYesNo($args[0])) ? '1' : '0'));
          break 2;
        case '--': array_shift($args); break 2;
        default:
          $this->defaultOption($arg);
          break;
      }
      array_shift($args);
    }

    if ($this->save()) {
      echo "\n";
      $this->printBasic();
    } else
      $this->owner->fatal('Error writing configuration file.');
  }

  private static function getYesNo($value) {
    if ((is_numeric($value) && (int)$value == 1))
      return "\e[34mYes\e[0m";
    return "\e[33mNo \e[0m";
  }

  private static function setYesNo($value, $invert = false, $die = true) {
    global $sak;
    $value =  ((is_string($value))  ? strtolower($value) :
              ((is_bool($value))    ? (($value) ? '1' : '0') :
              ((is_int($value))     ? (string)$value
                                    : $value)));

    switch ($value) {
      case '1':
      case 'on':
      case 'true':
      case 'enable':
      case 'enabled':
        return ((!$invert) ? true : false);

      case '0':
      case 'off':
      case 'false':
      case 'disable':
      case 'disabled':
        return ((!$invert) ? false : true);

      default:
        if ($die)
          $sak->fatal("Unknown boolean value `$value'");
        else
          return null;
    }
  }
}
