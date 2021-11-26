<?php
/**
 * Swiss Army Knife -- (Joomla PHP Library)
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package Joomla
 */

set_include_path(realpath(dirname(__FILE__)."/../../").":.");

/** For standard functions */
require_once('php/main.php');
/** Reference: {@link SoftwareTemplate} */
require_once('php/library/classSoftwareTemplate.php');
/** Reference: {@link sak_getopt()} */
require_once('php/library/libGetopt.php');

disable_errors();
require_root();

/**
 * Joomla class based on {@link SoftwareTemplate}
 * @package Joomla
 */
final class Joomla extends SoftwareTemplate {
  /**
   * Joomla version
   * @var string
   */
  protected $version = null;

  /**#@+ @var string */
  /** Basic settings array */
  private $basics = array();
  /** Users array */
  private $users = null;
  /**#@-*/

  /**
   * Constructor
   *
   * @param string  $username Database user
   * @param string  $password Database password
   * @param string  $hostname Database host
   * @param string  $prefix   Table prefix
   * @param string  $database Database name
   */
  public function __construct($version, $username = "",$password = "",$hostname = "localhost", $prefix = "jos_", $database = "") {
    parent::__construct($username, $password, $hostname, $prefix, $database);
    $this->version = $version;
  }

  /**
   * init not required in this class
   * @return void
   */
  public function init() { }

################################################################################
################################################################################

  /**
   * Parses Joomla templateDetails.xml files
   *
   * @param string $dir     Path to the Joomla root directory
   * @param int    $client  Key: 0 = Frontend, 1 = Administration
   * @param string $root    The root theme directory (for recursion)
   * @param int    $recurse Max depth of recursion
   * @return array List of theme information
   */
  function pull_theme_files($dir, $client = 0, $root = "", $recurse = 1) {
    if (!is_dir($dir)) die_with_error("Invalid directory: `".$dir."'");

    if ($root == "") {
      $root = $dir;
      $dir = $dir.((!($client))?"":"/administrator")."/templates";
    }
    $subdir = substr($dir,strlen($root.((!($client))?"":"/administrator")."/templates")+1);
    $handle = opendir($dir);

    $res = array();
    while (false !== ($item = readdir($handle))) {
      if ($item != "." && $item != ".." && is_dir($dir."/".$item) && $recurse > 0)
        $res = array_merge($res,$this->pull_theme_files($dir."/".$item,$client,$root,$recurse - 1));

      if ($item != "templateDetails.xml") continue;

      $xml = simplexml_load_file($dir."/".$item);
      $res[]=array(
        'enabled'   => 0,
        'client_id' => $client,
        'template'  => $subdir,
        'version'   => $xml->version,
        'title'     => (string) $xml->name
      );
    }
    return $res;
  }

################################################################################
################################################################################

  /**
   * Outputs theme information
   *
   * @param string $dir     Path to the Joomla root directory for searching
   * @param string $output  Filename for output
   * @return void
   */
  function output_templates($dir, $output) {
    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"w");

    if ($this->check_version("1.6")) {      // 1.6 and up
      if (false === $this->query(
        "SELECT home as enabled,client_id,template,title FROM `%s`;",
        $this->table('template_styles'))
      ) die_with_error('Error: Error during query.',true);
      while ($row = $this->fetch_array(MYSQLI_ASSOC)) {
        $tdir = (($row['client_id'] == 0) ? $dir."/templates/" : $dir."/administrator/templates/" );
        $xml = simplexml_load_file($tdir.$row['template']."/templateDetails.xml");
        fprintf($handle,"%s\x1E%s\x1E%s\x1E%s\x1E%s\n",
          $row['enabled'],
          $row['client_id'],
          $row['template'],
          $xml->version,
          $row['title']
        );
      }
    } elseif ($this->check_version("1.5")) {  // 1.5.x
      $ta = $tc = null;
      if (false === $this->query(
        "SELECT client_id,template FROM `%s`;", $this->table('templates_menu'))
      ) die_with_error('Error: Error during query.',true);
      while ($row = $this->fetch_array(MYSQLI_ASSOC)) {
        $ta = (($row['client_id'] == 1) ? $row['template'] : $ta ); // Store admin template
        $tc = (($row['client_id'] == 0) ? $row['template'] : $tc ); // Store client template
        $tdir = (($row['client_id'] == 0) ? $dir."/templates/" : $dir."/administrator/templates/" );
        $xml = simplexml_load_file($tdir.$row['template']."/templateDetails.xml");
        fprintf($handle,"%s\x1E%s\x1E%s\x1E%s\x1E%s\n",
          1,
          $row['client_id'],
          $row['template'],
          $xml->version,
          $xml->name);
      }

      $templates = array_merge(
        $this->pull_theme_files($dir),
        $this->pull_theme_files($dir,1));

      foreach ($templates as $row)
        if ($row['template'] != $ta && $row['template'] != $tc)
          fprintf($handle,"%s\x1E%s\x1E%s\x1E%s\x1E%s\n",
            $row['enabled'],
            $row['client_id'],
            $row['template'],
            $row['version'],
            $row['title']);
    }
  }

################################################################################
################################################################################

/* 1.5.x groups are hard-coded:
  Users:
    Registered
      Author
        Editor
          Publisher
  Admins:
    Manager
      Administrator
        Super Administrator */

  /**
   * Output user information
   *
   * @param string $output  Filename for output
   * @return void
   */
  function output_users($output) {
    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"w");

    if ($this->check_version("1.6"))
      $this->query(
        "SELECT U.id, U.username, U.name, U.email, G.title as `group`, ".
        "M.group_id as gid,U.registerDate,U.lastvisitDate FROM `%s` as U ".
        "LEFT OUTER JOIN `%s` AS M ON M.user_id = U.id ".
        "LEFT OUTER JOIN `%s` AS G ON G.id = M.group_id;",
        $this->table('users'),
        $this->table('user_usergroup_map'),
        $this->table('usergroups'));
    else
      $this->query(
        "SELECT U.id, U.username, U.name, U.email, U.usertype as `group`,".
        "'' as gid,U.registerDate,U.lastvisitDate FROM `%s` as U;",
        $this->table('users'));

    if (false === $this->fetch_result()) die_with_error('Error: Error during query.',true);
    while ($row = $this->fetch_array(MYSQLI_ASSOC))
      fwrite($handle,implode("\x1E",$row)."\n");
  }

################################################################################
################################################################################

  /**
   * Toggle addons for Joomla 2.5+
   *
   * @todo Remove $output as it is not used.
   * @param string $mode    Toggle mode. One of "enable" or "disable"
   * @param string $input   Path to input file with addon information.
   * @param string $output  Output file. Deprecated.
   */
  function toggle_addons($mode, $input, $output) {
    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"w");

    $data = explode("\n", file_get_contents($input));
    $data = explode("\x1E", $data[0]);

    if (sizeof($data) != 8 || !is_numeric($data[0]))
      die_with_error('Input data invalid!');
    else
      $id = (int) $data[0];

    switch ($mode) {
      case 'enable': $mode=1; break;
      case 'disable': $mode=0; break;
      default: die_with_error('Mode is invalid!');
    }
    if ($this->check_version("2.5")) {
      if (false === $this->query(
        "UPDATE `%s` SET `checked_out` = 0, `enabled` = %d,".
        " `checked_out_time` = '0000-00-00 00:00:00' WHERE `extension_id` = %d",
        $this->table('extensions'), $mode, $id)
      ) die_with_error('Error: Error during query.',true);
    } else {
      fprintf(STDERR, "Version %s not supported.\n", $this->version);
      exit(1);
    }
    exit(0);
  }

  /**
   * Output addon information
   *
   * This function is incomplete.
   *
   * @param string $output  Filename for output
   * @return void
   * @todo Needs better output and more version support
   */
  function output_addons($output) {
    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"w");

    if ($this->check_version("1.6")) {
      if (false === $this->query(
        "SELECT E.extension_id, E.enabled, E.type, E.name, E.folder, E.element,".
        " E.client_id,E.protected FROM `%s` AS E ORDER BY E.type, E.folder, E.ordering, E.name;",
        $this->table('extensions'))
      ) die_with_error('Error: Error during query.',true);
      fwrite($handle,"extensions_160\n");
      while ($row = $this->fetch_array(MYSQLI_ASSOC))
        fwrite($handle,implode("\x1E",$row)."\n");
    } else {
      // Components
      if (false === $this->query(
        "SELECT C.id, C.enabled, C.name, C.option, IF(C.link='',0,1) AS frontend,".
        "IF(C.admin_menu_link='',0,1) AS backend, C.iscore ".
        "FROM `%s` AS C LEFT OUTER JOIN `%s` AS CC ON CC.id = C.parent ".
        "WHERE C.parent = 0 ORDER BY C.ordering;",
        $this->table('components'),
        $this->table('components'))
      ) die_with_error('Error: Error during query.',true);
      fwrite($handle,"components_150\n");
      while ($row = $this->fetch_array(MYSQLI_ASSOC))
        fwrite($handle,implode("\x1E",$row)."\n");
      // Plugins
      if (false === $this->query(
        "SELECT P.id,P.published,P.name,CONCAT(P.folder,'/',P.element,'.php') AS file, ".
        "P.client_id, P.iscore FROM `%s` AS P ORDER BY P.folder,P.id;",
        $this->table('plugins'))
      ) die_with_error('Error: Error during query.',true);
      fwrite($handle,"plugins_150\n");
      while ($row = $this->fetch_array(MYSQLI_ASSOC))
        fwrite($handle,implode("\x1E",$row)."\n");
    }
  }
} /* class Joomla */

$args = $argv;
$self = basename($argv[0]);

$username = "";
$password = "";

$db     = "";
$prefix = "";
$jos    = null;

$input  = "";
$output = "";
$mode   = "";
$path   = "";
$version= "";

$short = "i:m:o:";
$long  = array(
  'db:','get:','in:','ini:','input:','mode:','output:','path:','prefix:',
  'root','set:','version:');
if (!sak_getopt($args, null, $short, $long)) exit(1);

// All arguments are processed AS PROVIDED. Order is important.
while ($arg = array_shift($args))
  switch ($arg) {
    case '--db':
      $db = array_shift($args);
      break;
    case '--prefix':
      $prefix = array_shift($args);
      break;
    case '--ini':
      $ini = get_ini(array_shift($args));
      $username = $ini['client']['user'];
      $password = $ini['client']['pass'];
      break;
    case '--root':
      $ini = get_ini('/root/.my.cnf');
      $username = $ini['client']['user'];
      $password = $ini['client']['pass'];
      break;
    case '-i':
    case '--in':
    case '--input':
      $input = array_shift($args);
      break;
    case '-m':
    case '--mode':
      $mode = array_shift($args);
      break;
    case '-o':
    case '--output':
      $output = array_shift($args);
      break;
    case '--path':
      $path = array_shift($args);
      break;
    case '--version':
      $version = array_shift($args);
      break;
    case '--get':
      if (empty($version) || empty($username) || empty($password)) {
        fprintf(STDERR,"%s: cannot get data without a valid version, username, and password.\n", $self);
        exit(1);
      }
      // Attempt to init a new Joomla object
      if (!is_a($jos, "Joomla"))
        $jos = new Joomla($version, $username, $password, "localhost", $prefix, $db);
      $arg = array_shift($args);
      switch ($arg) {
        case 'addons':
          $jos->output_addons($output);
          break;
        case 'themes':
        case 'templates':
          if (empty($path)) {
            fprintf(STDERR,"%s: unable to access path `%s'\n", $self,$path);
            exit(1);
          }
          $jos->output_templates($path, $output);
          break;
        case 'users':
          $jos->output_users($output);
          break;
        default:
          fprintf(STDERR,"%s: unknown get type `%s'\n", $self, $arg);
          exit(1);
      }
      break;

    case '--set':
      if (empty($version) || empty($username) || empty($password) || empty($db)) {
        fprintf(STDERR,"%s: cannot get data without a valid version, username, password, and database.\n", $self);
        exit(1);
      }
      if (empty($input)) {
        fprintf(STDERR,"%s: an input file is expected, but none provided.\n", $self);
        exit(1);
      }
      // Attempt to init a new Joomla object
      if (!is_a($jos, "Joomla"))
        $jos = new Joomla($version, $username, $password, "localhost", $prefix, $db);
      $arg = array_shift($args);
      switch ($arg) {
        case 'addons':
          switch ($mode) {
            case 'enable':
            case 'disable':
              $jos->toggle_addons($mode, $input, $output);
              break;
            case '':
              fprintf(STDERR,"%s: Setting addons requires --mode.\n", $self);
              exit(1);
            default:
              fprintf(STDERR,"%s: Invalid mode specified.\n", $self);
              exit(1);
          }
          break;
        default:
          fprintf(STDERR,"%s: unknown set type `%s'\n", $self, $arg);
          exit(1);
      }
      break;
    case '--':
      break;
    default:
      fprintf("%s: unrecognized option `%s'\n", $self, $arg);
      break;
  }
