<?php
/**
 * Swiss Army Knife -- (Generic Database PHP Classes)
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package    SwissArmyKnife
 * @subpackage Database
 */

/**
 * Generic MySQL Database connection class
 *
 * Manages database connections and keeps track of everything so you don't have
 * to.
 *
 * @package    SwissArmyKnife
 * @subpackage Database
 */
class Database extends Lib {
  /**#@+ @var string */
  /** Database name */
  private $database = "";
  /** Connection username */
  private $username = "";
  /** Connection password */
  private $password = "";
  /** Connection hostname */
  private $hostname = "";
  /**#@-*/

  /**
   * Internal status of database selection
   * @var string|bool
   */
  private $selection = false;
  /**
   * Stores the most recent SQL query
   * @var string
   */
  public $query = "";

  /**#@+ @var resource */
  /** Internal connection resource identifier */
  protected $connection = false;
  /** Stores the most recent query resource identifier */
  protected $query_result = false;
  /**#@-*/

  /**
   * Database Constructor
   *
   * If sufficient connection information is provided, will automatically
   * connect. If $database provided, will also select a database.
   *
   * @param string  $username Database user
   * @param string  $password Database password
   * @param string  $database Database name
   * @param string  $hostname Database host
   */
  public function __construct(SwissArmyKnife $owner, $database, $username = "", $password = "", $hostname = "localhost") {
    parent::__construct($owner);
    if ($username == "" && $password == "")
      list($username, $password) = SwissArmyKnife::readMySQLINI();

    $this->username = $username;
    $this->password = $password;
    $this->database = $database;
    $this->hostname = $hostname;
    $this->connect();
  }

  /**
   * Database Destructor
   *
   * Forces MySQL disconnect on destruction.
   *
   * @return void
   */
  public function __destruct() {
    $this->disconnect();
  }

  /**
   * Checks for required settings to make a connection
   *
   * Does not check if the connection information is valid, only that the
   * information exists.
   *
   * @return bool
   */
  private function can_connect() {
    if ($this->username != "" && $this->password != "" && $this->hostname != "")
      return true;
    return false;
  }

  /**
   * Checks to see if currently connected and can select a database
   *
   * Does not check if the database name is valid or if current permissions
   * allow access.
   *
   * @return bool
   */
  private function can_select_db() {
    if ($this->connected() && $this->database != "")
      return true;
    return false;
  }

  /**
   * Current connected status
   *
   * @return bool
   */
  public function connected() {
    if ($this->connection === false)
      return false;
    return true;
  }

  /**
   * Selected database status
   *
   * @return bool
   */
  public function selected() {
    if ($this->selection === false)
      return false;
    return true;
  }

  /**
   * Connects to MySQL using internal information, or new information provided
   *
   * @param string  $username Database user
   * @param string  $password Database password
   * @param string  $database Database name
   * @param string  $hostname Database host
   *
   * @return bool
   */
  public function connect($username = "", $password = "", $database = "", $hostname = "localhost") {
    if ($username != "")
      $this->username = $username;
    if ($password != "")
      $this->password = $password;
    if ($hostname != "")
      $this->hostname = $hostname;

    if (!$this->can_connect())
      return false;

    $connection = mysqli_connect($this->hostname,$this->username,$this->password);
    if (!$connection)
      return false;
    $this->connection = $connection;

    if ($database != "")
      $this->database = $database;

    if (!$this->select_db())
      return false;

    return true;
  }

  /**
   * Closes any MySQL connections and clears connection resources
   *
   * @return void
   */
  public function disconnect() {
    if ($this->connected())
      @mysqli_close($this->connection);
    $this->connection = false;
    $this->selection = false;
  }

  /**
   * Selects a database
   *
   * @param string  $database Option new database name
   * @return bool True on success
   */
  public function select_db($database = "") {
    if ($database == "")
      $database = $this->database;

    if ($this->connected() && $this->can_select_db())
      if (mysqli_select_db($this->database, $this->connection)) {
        $this->selection = $this->database;
        return true;
      }

    return false;
  }

  /**
   * Performs a query if currently connected and returns result resource
   *
   * If additional arguments are passed, the query and arguments are passed
   * through sprintf() using {@link $query} as the format string.
   *
   * The result is also stored in {@link $query_result} for use later.
   *
   * @param string $query SQL query optionally as a format string
   * @param mixed  $args  Optional arguments
   * @return resource|bool  Returns result or false on error
   */
  public function query($query, $args = null) {
    $args = func_get_args();
    if (sizeof($args) > 1)
      $query = call_user_func_array('sprintf',$args);

    if ($this->connected() && $this->selected()) {
      $this->query_result = false;
      $result = mysqli_query($this->connection, $query);
      if ($result !== false)
        $this->query_result = $result;
      return $this->query_result;
    }

    return false;
  }

  /**
   * Wrapper for mysqli_real_escape_string()
   *
   * @param string $string String to escape
   * @return string MySQL escaped string
   */
  public function escape($string) {
    if ($this->connected())
      return mysqli_real_escape_string($this->connection, $string);
    return null;
  }

  /**
   * Wrapper for mysqli_error and $this->connected()
   *
   * Returns string from mysqli_error if non-empty, otherwise if not connected,
   * then "Not connected." is returned. An empty string is returned if no error.
   *
   * @return string MySQL error string
   */
  public function fetch_error() {
    if ($this->can_connect()) {
      if ($this->connection === false || !$this->connected())
        return "Not connected or connection failed.\n";
    } else {
      return "Not enough connection information.\n";
    }

    $error = mysqli_error($this->connection);
    if (!empty($error))
      return $error;
    return "";
  }

  /**
   * Wrapper for mysqli_num_rows which uses the internal query result
   *
   * @return int|bool Returns number of rows, or false on error
   */
  public function fetch_num_rows() {
    if ($this->query_result === false)
      return false;
    return mysqli_num_rows($this->query_result);
  }

  /**
   * Fetches a row from a recent query
   *
   * @param int $mode MYSQLI_ASSOC (default), MYSQL_NUM, or MYSQLI_BOTH
   * @return array|bool Returns array with row data or false on error
   */
  public function fetch_array($mode = MYSQLI_ASSOC) {
    if ($this->query_result === false || !($mode & (MYSQLI_ASSOC | MYSQLI_NUM | MYSQLI_BOTH)))
      return false;
    return mysqli_fetch_array($this->query_result, $mode);
  }

  /**
   * Fetches a row from a query result
   *
   * @param resource $resource  Query result
   * @param int      $mode      MYSQLI_ASSOC (default), MYSQL_NUM, or MYSQLI_BOTH
   * @return array|bool Returns array with row data or false on error
   */
  public function fetch_array_from($resource, $mode = MYSQLI_ASSOC) {
    if (!is_resource($resource) ||
      !($mode & (MYSQLI_ASSOC | MYSQLI_NUM | MYSQLI_BOTH))) return false;
    return mysqli_fetch_array($this->query_result, $mode);
  }

  /**
   * Returns the last query result
   *
   * @return mixed  Resource or false if previous query failed.
   */
  public function fetch_result() {
    return $this->query_result;
  }

  /**
   * Returns the current selected database or false if none
   *
   * @return string|bool
   */
  public function fetch_database() {
    return $this->selection;
  }
}
