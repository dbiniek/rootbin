<?php
/**
 * Swiss Army Knife -- (Software PHP Classes)
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package    SwissArmyKnife
 * @subpackage SoftwareTemplate
 */

/** Reference: {@link DBConnection} */
require_once('classDBConnection.php');

/**
 * Software template abstract class
 *
 * This class is abstract as there is no point in using it directly. Note that
 * {@link DBConnection} is not abstract as it is useful on its own.
 *
 * {@link SoftwareTemplate::init()} is abstract as it is called within {@link SoftwareTemplate::__construct()}
 *
 * @package    SwissArmyKnife
 * @subpackage SoftwareTemplate
 */
abstract class SoftwareTemplate extends DBConnection {
  /**
   * Table prefix
   * @var string
   */
  public $prefix = "";
  /**
   * Storage array for basic data
   * @var array
   */
  private $have = array();

  /**
   * Constructor
   *
   * @param string  $username Database user
   * @param string  $password Database password
   * @param string  $hostname Database host
   * @param string  $prefix   Table prefix
   * @param string  $database Database name
   *
   * @uses init()
   */
  public function __construct($username = "", $password = "", $hostname = "localhost", $prefix = "", $database = "") {
    parent::__construct($username, $password, $database, $hostname);
    $this->prefix = $prefix;
    $this->init();
  }

  /**
   * Init function so that the constructor does not need to be overridden
   *
   * This function is abstracted as it is called within {@link __construct()}
   *
   * @return void
   */
  abstract public function init();

  /**
   * Returns the table name with the current prefix prepended
   *
   * Note: Does not check if the table exists
   *
   * Calling with {@link $escape} true will escape sequences which are wildcards
   * for LIKE statements.
   *
   * Escape example:
   * <code>
   * $this->prefix = 'wp_';
   * $this->table('users', true); // Returns: 'wp\_users'
   * </code>
   *
   * @param string $table   Table name
   * @param bool   $escape  Set to true to return escaped table name
   * @return string
   */
  protected function table($table, $escape = false) {
    if ($escape === true)
      return preg_replace('/([%_])/','\\\\\1',
        sprintf('%s%s',$this->prefix, $table));
    return sprintf('%s%s',$this->prefix, $table);
  }

  /**
   * Returns if the current version is greater or equal to the specified version
   *
   * @param string $required The required version
   * @return bool  True if equal or greater to {@link $required}
   */
  public function check_version($required) {
    if (version_compare($this->version,$required,'>='))
      return true;
    else
      return false;
  }

  /**
   * Stores or retrieves a value from {@link $have}
   *
   * Can also specify an array as first argument to set several items at once
   * If second argument is not set, will return the value of the first argument
   * If second argument is set, will store it as the value of the first argument
   *
   * @param mixed $what   Tag or descriptor. Alternatively accepts array of keyed arguments.
   * @param mixed $value  Value for this tag. Not required if {@link $what} is an array.
   * @return mixed  Returns the value for the tag if {@link $value} is null
   */
  public function have($what = null, $value = null) {
    if (!is_array($what) && $value == null) {
      if ($what == null || !array_key_exists($what,$this->have)) { return false; }
      return $this->have[$what];
    } else {
      if (is_array($what)) {
        foreach ($what as $item => $value) {
          $this->have[$item] = $value;
        }
      } else {
        $this->have[$what] = $value;
      }
    }
  }
}
