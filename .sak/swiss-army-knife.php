<?php
/**
 * Swiss Army Knife
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package Main
 */

@error_reporting(E_ALL);
ini_set('error_log', '/dev/null');

require_once 'inc/functions.php';
require_once 'inc/defines.php';

printf("Swiss Army Knife %s (%s) - jsouth@hostgator.com\n", SAK_VER, SAK_TS);
sak_check_requirements($argv);

require_once 'Archive/Tar.php';

# Set default mask, helps prevent data leakage
umask(0077);
sak_autoload_register();
# Initialize main class
$sak = new SwissArmyKnife($argv, $argc);
$sak->run();
echo "\n";
exit(0);

################################################################################
################################################################################

/**
 * Main Swiss Army Knife class
 */
class SwissArmyKnife {
  public $name = null;
  public $invoker = null;
  public $wd = null;
  public $verbosity = 1;

  public $version = '0.1.5';
  public $timestamp = '';
  public $session = '';

  private $argv = array();
  private $argc = 0;

  public $install = array();

  /** @var Path */
  public $path = null;
  /** @var Getopt */
  public $getopt = null;
  /** @var VDetect */
  public $vdetect = null;
  /** @var Download */
  public $download = null;
  /** @var SwissArmyKnifeGateway */
  public $gateway = null;

  function __construct($argv, $argc) {
    $this->wd = getcwd();

    $this->invoker = SAK_SELF;
    $this->name = SAK_BASENAME;
    $this->argv = $argv;
    $this->argc = $argc;

    $this->version = SAK_VER;
    $this->timestamp = SAK_TS;
    $this->session = SAK_SID;

    $this->path = new Path($this);
    $this->getopt = new Getopt();
    $this->vdetect = new VDetect($this);
    $this->download = new Download($this);

    if (!$this->download->testRepo($argv))
      $this->fatal("Unable to connect to remote repository, please try again.\n");
  }

  /**
   * Ensures we attempt to return to our original working directory.
   */
  function __destruct() {
    if (getcwd() != $this->wd)
      @chdir($this->wd);
  }

  /**
   * Main execution loop
   *
   * @return void
   */
  function run() {
    $a = (array)$this->argv;  // Preserve argv by making a copy
    array_shift($a);          // Push the script name off the top
    $args = array();          // This will have our global switches

    while (($a) && isset($a[0][0]) && $a[0][0] == '-') {
      $args[] = array_shift($a);
    }

    $os = "DhqRUvV";
    $ol = array("directory:","help","quiet","reseller:","user:","verbose","version");
    $mask = (SAK_GETOPT_M_BLIND | SAK_GETOPT_ARGS_LOWERCASE);

    if (!$this->getopt->parse($args, $this->name, $os, $ol, $mask))
      $this->stop(1);

    while (true) {
      switch ($arg = $args[0]) {
        case '-D':
        case '--directory': array_shift($args);
          $this->vdetect->paths[] = array_shift($args); break;
        case '-U':
        case '--user': array_shift($args);
          $this->vdetect->user[] = array_shift($args); break;
        case '-R':
        case '--reseller': array_shift($args);
          $this->vdetect->reseller[] = array_shift($args); break;

        case '-v':
        case '--verbose': $this->verbosity++; break;
        case '-q':
        case '--quiet': $this->verbosity--; break;

        case '-h':
        case '--help': $this->stop();

        case '-V':
        case '--version': $this->stop();

        case '--': array_shift($args); break 2;

        default:
          if ($arg[0] == '-') {
            if ($arg[1] == '-')
              $this->error(sprintf("unrecognized option `%s'", $arg));
            else
              $this->error(sprintf("invalid option -- %s\n", $arg));
          }
        break 2;
      }
      array_shift($args);
    }

    $this->subcommand($a);
  }

  /**
   * Process a subcommand.
   *
   * @param array $args Argument array
   */
  function subcommand($args = array()) {
    if (!is_array($args)) $args = array($args);
    switch ($arg = array_shift($args)) {
      // SOFTWARE
      case 'wp':
      case 'word':
      case 'wordpress':
        /** @var Core */
        $i = $this->cwdInstall();
        if ($i->type != "wordpress")
          $this->fatal("No WordPress install was found here.");
        if ($i->software())
          $i->software()->command($args);
        else
          $this->fatal("Could not initialize software interface.");
        break;

      case 'jm':
      case 'ja':
      case 'jos':
      case 'joom':
      case 'joomla':
        /** @var Core */
        $i = $this->cwdInstall();
        if ($i->type != "joomla")
          $this->fatal("No Joomla install was found here.");
        if ($i->software())
          $i->software()->command($args);
        else
          $this->fatal("Could not initialize software interface.");
        break;

      // CORE
      case 'list':
      case 'listall':
      case 'listing':
        $this->find(true);
        $this->message('Information','Found '.count($this->install).' software installation(s):');
        echo "\n";
        $this->listing();
        break;

      case 'bk':
      case 'backup':
        $this->cwdInstall()
          ->backup();
        break;
      case 'database':
        break;

      case 'orphans':
        $this->cwdInstall()
          ->orphans();
        break;

      case 'ddiff':
      case 'finediff':
        $fine = true;
      case 'diff':
        $diff = $this->cwdInstall()
          ->diff($args, !isset($fine));
        if ($diff != "")
          $this->less($diff);
        break;

      case 'miss':
      case 'check':
      case 'missing':
      case 'checksum':
        $miss = $this->cwdInstall()
          ->checkFiles();
        if (!empty($miss))
          if (substr_count($miss, "\n") > 22)
            $this->less($miss);
          else
            echo $miss;
        break;

      case 'mass':
      case 'mreplace':
      case 'massreplace':
        $this->find(true);

        if (!($this->install))
          $this->fatal('No supported software was found.');

        Core::massReplace($this, $args);
        break;

      case 'replace':
        if (($install = $this->cwdInstall(false, false)) === false)
          $install =
            $this->install[] = new Core($this, null, null, $this->wd, null);

        $install->replace($args);
        break;

      // AGNOSTIC
      case '':
      case 'info':
        $i = $this->cwdInstall();
        if ($i === false)
          $this->fatal('No supported software was found.');
        $this->subcommand($i->type);
        break;

      default:
    }
  }

  /**
   * Initialize and passthrough for the Gateway class.
   *
   * @param Core  $core Core installation this Gateway will be bound to
   * @param int   $uid  User id that the process will change to
   *
   * @return Gateway
   */
  function gateway(Core $core = null, $uid = null) {
    if (!is_null($this->gateway)) {
      if ((!is_null($core) || !is_null($uid)) && $this->gateway->check($core, $uid))
        $this->fatal('Gateway library already initialized.');

      return $this->gateway;
    }

    if (is_null($core) || is_null($uid))
      return false;

    $this->gateway = new Gateway($this, $core, 556);
    if (!$this->gateway->init())
      $this->fatal('Unable to initialize gateway library.');

    return $this->gateway;
  }

  /**
   * List installations
   *
   * @param mixed $arg Array of install indexes or True to list all.
   */
  function listing($arg = true) {
    $n = 1;

    if ($arg === true)
      $arg = array_keys($this->install);

    foreach ($arg as $i)
      printf("#%-4d \33[1m%-12s\33[0m Ver: \33[1m%-12s\33[0m (%s)  Dir: %s\n",
        $n++, Core::pName($this->install[$i]->type), $this->install[$i]->version,
        Core::pVuln($this->install[$i]->vuln), $this->install[$i]->path);
  }

  /**
   * Return a single install from the current directory
   *
   * Fails on none or duplicates found.
   */
  function cwdInstall($duplicates = false, $die = true) {
    $this->find();

    $path = realpath($this->wd);
    $ret = false;

    foreach ($this->install as $i => $install)
      if ($install->path == $path) {
        $ret = $install;
        break;
      }

    if ($ret === false && $die === true)
      $this->fatal('No supported software was found.');

    if ($ret !== false && ($dupes = $this->findDupe($i)) !== false) {
      echo "\n";
      $this->message('Error', array(
        "There are ".count($dupes)." different/duplicate software installs located in this directory.",
        "You may use '".SAK_BASENAME." <type> [command]' to try working with one type of install.\n"));
      $this->listing($dupes);
      $this->fatal('Cannot determine which install to work on. Giving up.');
    }

    return $ret;
  }

  /**
   * Begin a search for supported software from the current working directory.
   *
   * @param bool  $recurse  True to search recursively
   */
  function find($recurse = false) {
    static $called = 0;
    if ($called++ >= 5) $this->error('find() loop detected.');
    if ($called > 1) return;

    $this->message('Scanning', 'Scanning for software...');
    $this->vdetect->run($recurse);
  }

  /**
   * Check for duplicate installs matching the index given.
   *
   * @param int $index  Numbered index of the install to check for
   *
   * @return  mixed   Array of install indexes on success. False if none found.
   */
  function findDupe($index) {
    if (!($this->install)) return false;

    $dupes = array($index);
    $path = $this->install[$index]->path;

    foreach ($this->install as $i => $install)
      if ($index == $i)
        continue;
      elseif ($install->path == $path)
        $dupes[] = $i;

    return ((count($dupes) > 1) ? $dupes : false);
  }

  /**
   * Open less for paged viewing of data
   *
   * @param string  $data     Content to be viewed
   * @param string  $options  Options to be passed to less
   */
  function less(&$data, $options = "-iSR") {
    // Write data directly to STDOUT if it's not a console (e.g. piped)
    if (!posix_isatty(STDOUT)) {
      fwrite(STDOUT, $data);
      return;
    }

    // Fall through and exec less, allowing for colors and long lines.
    // STDOUT descriptor is not captured so that less opens tty directly
    $fd = array(0 => array("pipe", "r"), 2 => array("pipe", "w"));

    $args = array("less", $options);
    $cmd = implode(' ', $args);
    $proc = proc_open($cmd, $fd, $pipes);

    if (is_resource($proc)) {
      stream_set_blocking($pipes[2], 0);
      if ($err = stream_get_contents($pipes[2])) {
        fclose($pipes[0]);
        fclose($pipes[2]);
        proc_close($proc);
        $this->error(sprintf('Could not execute less. Error: %s', $err));
      }

      fwrite($pipes[0], $data);
      fclose($pipes[0]);

      $err = stream_get_contents($pipes[2]);
      fclose($pipes[2]);

      $ret = proc_close($proc);
      // TODO: Handle errors
    } else {
      $this->fatal('Could not execute less.');
    }
  }

  /**
   *  Download and cache a file.
   *
   *  @param string $description  'Updating $description...'
   *  @param string $source       Source URL
   *  @param string $local        Local filename for storage
   *  @param bool   $force        Force download regardless of timestamp
   *  @param int    $maxDelta     Download if file is older than $maxDelta seconds
   *  @param int    $tsLine       Line which contains remotely generated timestamp. Use null to specify local file's mtime.
   *  @param string $tsRe         Regular expression to filter timestamp (e.g. if embedded in XML)
   *
   *  @return bool  True on success. False on failure.
   */
  function cacheFile($description, $source, $local, $force = false, $maxDelta = 21600, $tsLine = 0, $tsRe = '/^(?:<!-- )?([0-9]{10,})(?: -->)?$/') {
    if (!file_exists($local) || $force === true)
      $this->message('Cache', "Updating $description...");

    $this->download->set($source, $local);
    if (!$this->download->exec($force))
      return false;
    if (($force))
      return true;

    if (!is_null($tsLine)) {
      if (($fd = fopen($local, 'r')) === false) return false;

      // Read first 8KB
      $buffer = explode("\n", fread($fd, 8192));
      fclose($fd);

      $ts = (int) preg_replace($tsRe, '\1', $buffer[$tsLine]);
    } else
      $ts = ((file_exists($local)) ? filemtime($local) : 0);

    if (!($ts >= 0)) return false;

    if (time() - $ts > $maxDelta)
      return $this->cacheFile($description, $source, $local, true, $maxDelta, $tsLine, $tsRe);
    return true;
  }

  /**
   * Print a message to the console.
   *
   * @param string $title
   * @param string $message
   * @param int $type
   * @param int $level
   * @param bool $newline
   */
  function message($title, $message, $type = SAK_LOG_INFO, $level = 1, $newline = true) {
    static $ltype = null;
    if (is_null($ltype))
      $ltype = array(
        SAK_LOG_INFO  => sprintf("\e[37;1m[\e[32m++\e[37m]\e[0m"),
        SAK_LOG_MESG  => '',
        SAK_LOG_WARN  => sprintf("\e[37;1m[\e[33m==\e[37m]\e[0m"),
        SAK_LOG_ERROR => sprintf("\e[37;1m[\e[31m!!\e[37m]"),
        SAK_LOG_DEBUG => '');
    // if ($this->muted) return;
    if ($level > $this->verbosity) return;
    $code = $ltype[$type];

    if ($level > 1 && $type == SAK_LOG_MESG) $code = sprintf("\e[37;1m[\e[36m??\e[37m]\e[0m");
    if ($title == 'Warning') $title = sprintf("\e[1mWarning\e[0m");
    if ($title == 'Error') $code = $ltype[SAK_LOG_ERROR];
    //if ($type == SAK_LOG_INFO) $title = sprintf("\33[1m%s\33[0m", $title);

    foreach ((array)$message as $m) {
      printf("%s <%s> %s\33[0m%s", $code, $title, $m, (($newline) ? "\n" : ""));
      flush();
    }
  }

  /**
   * Print a message to the console and prompt for input.
   *
   * @param string $title
   * @param string $message
   * @param string $regex
   * @param int $type
   */
  function prompt($title, $message, $regex = '/^[yYnN]?$/', $type = SAK_LOG_INFO) {
    while (true) {
      $this->message($title, $message, $type, -999, false);
      $answer = fread(STDIN, 1);
      if ($answer != "\n") echo "\n";

      if (!preg_match($regex, $answer))
        $this->message('Error', 'Invalid input.');
      else
        break;
    }
    return $answer;
  }

  function verbose($level = 1) {
    return ($this->verbosity >= $level);
  }

  /**
   * Return to original working directory and immediately stop execution.
   *
   * Does not print any message and by default, exit status is 0 (no error).
   *
   * @param int $status Exit status
   */
  function stop($status = 0) {
    if (getcwd() != $this->wd)
      chdir($this->wd);
    exit($status);
  }

  /**
   * Print a basic error to STDERR and exit with an optional status.
   *
   * @param string  $message  Error message
   * @param int     $exit     Exit status
   */
  function error($message, $exit = 1) {
    fprintf(STDERR, "%s: %s\n", SAK_BASENAME, $message);
    if (!is_null($exit)) $this->stop($exit);
  }

  /**
   * Print a formatted/styled error to STDERR, exit with an optional status,
   * and optionally print a backtrace.
   *
   * @param string  $message    Error message
   * @param int     $exit       Exit status
   * @param bool    $backtrace  Set to true to print a backtrace
   */
  function fatal($message, $status = 1, $backtrace = false) {
    echo "\n";
    foreach ((array)$message as $msg)
      printf("\e[37;1m[\e[31m!!\e[37m] %s\e[0m\n", $msg);
    echo "\n";
    if ($backtrace) debug_print_backtrace();
    $this->stop($status);
  }

  static public function readMySQLINI($ini = "/root/.my.cnf") {
    if (($ini = @parse_ini_file($ini, true)) === false)
      return false;

    $username = "";
    $password = "";
    if (array_key_exists('client', $ini)) {
      $client = $ini['client'];
      if (array_key_exists('password', $client))
        $password = $client['password'];

      if ($password == '' && array_key_exists('pass', $client))
        $password = $client['pass'];

      if (array_key_exists('user', $client))
        $username = $client['user'];
    }
    if ($username == "" || $password == "")
      return false;

    return array($username, $password);
  }
}
