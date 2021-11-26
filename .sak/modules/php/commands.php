<?php
/**
 * Swiss Army Knife -- (Generic PHP Commands Library)
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package    SwissArmyKnife
 * @subpackage Commands
 */

set_include_path(realpath(dirname(__FILE__)."/"));

/** Standard functions */
require_once('main.php');
/** Reference: {@link DBConnection} */
require_once('library/classDBConnection.php');
/** Reference: {@link sak_getopt()} */
require_once('library/libGetopt.php');

disable_errors();
require_root();

/**
 * Natural language sort commandlet
 *
 * Reads tabbed data from stdin and writes directly to stdout
 *
 * @return void
 * @uses natversort()
 */
function cmdlet_natsort() {
  $handle = @fopen("php://stdin","r");    // Read from STDIN
  if (!is_resource($handle)) exit(1);

  $data = array();
  while (!feof($handle))
    $data[]=explode("\t",fgets($handle)); // Read by line, then explode tabs

  uasort($data,'natversort');             // Custom array sort
  foreach($data as $item)                 // Output new data, tab delimited
    echo implode("\t",$item);
}

/**
 * Tests a database connection
 *
 * Checks access with SHOW TABLES
 *
 * @param string  $username MySQL connection username
 * @param string  $password MySQL connection password
 * @param string  $database MySQL connection database
 * @param string  $hostname MySQL connection hostname
 * @return bool True if success
 */
function cmdlet_check_select($username, $password, $database, $hostname = "localhost") {
  $db = new DBConnection($username, $password, $database, $hostname);
  if ($db->connected() && $db->selected())
    if (false !== $db->query("SHOW TABLES;"))
      return true;
  fprintf(STDERR, "Error: %s\n", $db->fetch_error());
  return false;
}

/**
 * Checks user table for existing users
 *
 * Checks access with SHOW TABLES
 *
 * @param string  $username MySQL connection username
 * @param string  $password MySQL connection password
 * @param string  $virtuser MySQL virtual user to check
 * @param string  $hostname MySQL connection hostname
 * @return bool True if success
 */
function cmdlet_check_user($username, $password, $virtuser, $hostname = "localhost") {
  $db = new DBConnection($username, $password, "mysql", $hostname);
  if ($db->connected() && $db->selected())
    if (false !== $db->query("SELECT User from user WHERE User = '%s';",$db->escape($virtuser)))
      if ($db->fetch_num_rows() == 0) {
        fprintf(STDERR, "Error: User not found.\n");
        return false;
      } else
        return true;
  fprintf(STDERR, "Error: %s\n", $db->fetch_error());
  return false;
}

/**
 * Checks user table for suspended user
 *
 * Checks for suspensions via max_questions
 *
 * @param string  $username MySQL connection username
 * @param string  $password MySQL connection password
 * @param string  $virtuser MySQL virtual user to check
 * @param string  $hostname MySQL connection hostname
 * @return bool True if success
 */
function cmdlet_check_suspension($username, $password, $virtuser, $hostname = "localhost") {
  $db = new DBConnection($username, $password, "mysql", $hostname);
  if ($db->connected() && $db->selected())
    if (false !== $db->query("SELECT max_questions from user WHERE User = '%s';",$db->escape($virtuser)))
      if ($db->fetch_num_rows() == 0) {
        fprintf(STDERR, "Error: User not found.\n");
        return false;
      } else {
      	while($row = $db->fetch_array())
      	  if($row['max_questions'] != "0")
            return false;
        return true;
      }
  fprintf(STDERR, "Error: %s\n", $db->fetch_error());
  return false;
}



/**
 * Creates a new user
 *
 * @param string  $username MySQL connection username
 * @param string  $password MySQL connection password
 * @param string  $input    Input filename to parse for username and password
 * @param string  $hostname MySQL connection hostname
 * @return bool
 */
function cmdlet_create_auth($username, $password, $input, $hostname = "localhost") {
  if (!file_exists($input)) {
    fprintf(STDERR, "Error: Could not read input file.\n");
    exit(2);
  }
  list($virtuser, $virtpass) = explode("\t", file_get_contents($input));
  $db = new DBConnection($username, $password, "mysql", $hostname);
  if ($db->connected()) {
    if (false !== $db->query(
      "CREATE USER '%s'@'localhost' IDENTIFIED BY '%s';",
      $virtuser, $db->escape($virtpass))) {
      if (false !== $db->query(
        "GRANT USAGE ON *.* TO '%s'@'localhost';",
        $virtuser)) {
        if (false !== $db->query("FLUSH PRIVILEGES;"))
          return true;
      }
    }
  }
  fprintf(STDERR, "Error: %s\n", $db->fetch_error());
  return false;
}

/**
 * Creates new grant privileges
 *
 * @param string  $username MySQL connection username
 * @param string  $password MySQL connection password
 * @param string  $virtuser MySQL virtual user to give grants to
 * @param string  $database MySQL database to give grants on
 * @param string  $hostname MySQL connection hostname
 * @return bool
 */
function cmdlet_create_grant($username, $password, $virtuser, $database, $hostname = "localhost") {
  # GRANT ALL PRIVILEGES ON `software\_wrdp1`.* TO 'software_wrdp1'@'localhost'
  $db = new DBConnection($username, $password, "mysql", $hostname);
  if ($db->connected()) {
    if (false !== $db->query(
      "GRANT ALL PRIVILEGES ON `%s`.* TO '%s'@'localhost';",
      $db->escape($database), $virtuser)) {
      if (false !== $db->query("FLUSH PRIVILEGES;"))
        return true;
    }
  }
  fprintf(STDERR, "Error: %s\n", $db->fetch_error());
  return false;
}

/**
 * Sets a new password for a virtual user
 *
 * @param string  $username MySQL connection username
 * @param string  $password MySQL connection password
 * @param string  $input    Input filename to parse for username and password
 * @param string  $hostname MySQL connection hostname
 * @return bool
 */
function cmdlet_create_pass($username, $password, $input, $hostname = "localhost") {
  if (!file_exists($input)) {
    fprintf(STDERR, "Error: Could not read input file.\n");
    exit(2);
  }
  list($virtuser, $virtpass) = explode("\t", file_get_contents($input));

  $db = new DBConnection($username, $password, "mysql", $hostname);
  if ($db->connected()) {
    if (false !== $db->query(
      "SET PASSWORD FOR '%s'@'localhost' = PASSWORD('%s');",
      $virtuser, $db->escape($virtpass))) {
      if (false !== $db->query("FLUSH PRIVILEGES;"))
        return true;
    }
  }
  fprintf(STDERR, "Error: %s\n", $db->fetch_error());
  return false;
}

/**
 * Quick exit function when parsing options
 *
 * @return void
 */
function _exit() {
  fprintf(STDERR,"Error: insufficient information.\n");
  exit(1);
}

$args = $argv;
$self = basename($argv[0]);

$username = "";
$password = "";
$database = "";
$hostname = "localhost";

if ($argc == 1) {
  fprintf(STDERR, "%s: too few arguments\n", $self);
  exit(1);
}

$short = "";
$long = array('check-auth-db','check-user:','create-auth:','check-suspension:','create-grant:',
'create-pass:','database:','db:','host:','hostname:','ini:','natsort','root',
'user:','username:');

if (!sak_getopt($args, null, $short, $long)) exit(1);

while ($arg = array_shift($args))
  switch ($arg) {
    /* <authentication> */
    case '--user':
    case '--username':
      $username = array_shift($args);
      break;
    case '--db':
    case '--database':
      $database = array_shift($args);
      break;
    case '--host':
    case '--hostname':
      $hostname = array_shift($args);
      break;
    /* </authentication> */

    /* <ini> */
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
    /* </ini> */

    case '--natsort':
      cmdlet_natsort();
      break;

    case '--check-auth-db':
      if (empty($username) || empty($password) || empty($database)) _exit();
      if (!cmdlet_check_select($username, $password, $database, $hostname)) exit(2);
      break;
    case '--check-user':
      if (empty($username) || empty($password)) _exit();
      if (!cmdlet_check_user($username, $password, array_shift($args))) exit(2);
      break;
    case '--check-suspension':
      if (empty($username) || empty($password)) _exit();
      if (!cmdlet_check_suspension($username, $password, array_shift($args))) exit(2);
      break;
    case '--create-auth':
      if (empty($username) || empty($password)) _exit();
      if (!cmdlet_create_auth($username, $password, array_shift($args), $hostname)) exit(2);
      break;
    case '--create-grant':
      if (empty($username) || empty($password) || empty($database)) _exit();
      if (!cmdlet_create_grant($username, $password, array_shift($args), $database, $hostname)) exit(2);
      break;
    case '--create-pass':
      if (empty($username) || empty($password)) _exit();
      if (!cmdlet_create_pass($username, $password, array_shift($args), $hostname)) exit(2);
      break;

    case '--':
      break;
    default:
      fprintf(STDERR, "%s: unrecognized option `%s'\n", $self, $arg);
      exit(1);
  }
