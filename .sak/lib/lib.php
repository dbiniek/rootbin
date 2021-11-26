<?php
/**
 * Swiss Army Knife -- (Generic Lib class)
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package Lib
 */
abstract class Lib {
  /** @var SwissArmyKnife */
  protected $owner = null;

  public function __construct(SwissArmyKnife $owner) {
    $this->owner = $owner;
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
  protected function message() {
    if (is_null($this->owner)) return;

    return call_user_func_array(array($this->owner, 'message'), func_get_args());
  }

  /**
   * Print a message to the console and prompt for input.
   *
   * @param string $title
   * @param string $message
   * @param string $regex
   * @param int $type
   */
  protected function prompt() {
    if (is_null($this->owner)) return null;

    return call_user_func_array(array($this->owner, 'prompt'), func_get_args());
  }

  /**
   * Open less for paged viewing of data
   *
   * @param string  $data     Content to be viewed
   * @param string  $options  Options to be passed to less
   */
  protected function less() {
    return call_user_func_array(array($this->owner, 'less'), func_get_args());
  }

  /**
   * Print a basic error to STDERR and exit with an optional status.
   *
   * @param string  $message  Error message
   * @param int     $exit     Exit status
   */
  protected function error() {
    return call_user_func_array(array($this->owner, 'error'), func_get_args());
  }

  /**
   * Print a formatted/styled error to STDERR, exit with an optional status,
   * and optionally print a backtrace.
   *
   * @param string  $message    Error message
   * @param int     $exit       Exit status
   * @param bool    $backtrace  Set to true to print a backtrace
   */
  protected function fatal() {
    return call_user_func_array(array($this->owner, 'fatal'), func_get_args());
  }

  /**
   * Return to original working directory and immediately stop execution.
   *
   * Does not print any message and by default, exit status is 0 (no error).
   *
   * @param int $status Exit status
   */
  protected function stop() {
    return call_user_func_array(array($this->owner, 'stop'), func_get_args());
  }

  /**
   * Parse option/argument array.
   *
   * @see GetOpt::parse
   *
   * @param  array   &$args Array reference to be modified upon return
   * @param  string  $name  Program name
   * @param  string  $short Short option string
   * @param  array   $long  Long option array
   * @param  bitmask $mode  Settings bitmask. Default = SAK_GETOPT_NONE
   *
   * @return bool    True on success, false otherwise
   */
  protected function getopt(Array &$args, $name = null, $short = null,
                            $long = null, $mode = null) {
    return $this->owner->getopt->parse($args, $name, $short, $long, $mode);
  }

  /**
   * Default getopt option handling.
   *
   * Checks an unknown argument and prints an error message matching the type
   * provided, whether it's a switch or predicate.
   *
   * @param string $arg   The unknown argument provided
   */
  protected function defaultOption($arg) {
    echo "\n";
    if ($arg[0] == '-') {
      if ($arg[1] == '-')
        $this->fatal(sprintf("%s: unrecognized option `%s'", SAK_BASENAME, $arg));
      else
        $this->fatal(sprintf("%s: invalid option -- %s\n", SAK_BASENAME, $arg));
    }
    $this->error(sprintf("unrecognized command or predicate `%s'", $arg));
  }
}
