<?php
/**
 * Swiss Army Knife -- (getopt PHP library)
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package    SwissArmyKnife
 * @subpackage Getopt
 */

/**
 * Getopt class
 *
 * @package    SwissArmyKnife
 * @subpackage Getopt
 */
class Getopt {
  /**
   * Emulates getopt(1) because PHP's default getopt() sucks. If $name is not set,
   * $args[0] will be used instead, this is handy for passing the $argv array.
   *
   * Short options are provided in one string, each letter representing one option
   * optionally followed by a colon (:) to signify that an argument is required.
   *
   * Long options are provided in an array, one option name per item. If the name
   * is ended by a colon (:), the option will require an argument.
   *
   * Example:
   * <code>
   * $ret = sak_getopt(
   *   $argv,                 // Pass $argv directly by reference
   *   null,                  // Name here is optional as $argv[0] will be used
   *   "f:hqv",               // -f requires an argument; -h, -q, and -v do not
   *   array("file:","help"), // --file requires an argument; --help does not
   *   SAK_GETOPT_ARGS_NEST   // Bitmask to nest options with arguments
   * );
   * </code>
   *
   * @param  array   &$args Array reference to be modified upon return
   * @param  string  $name  Program name
   * @param  string  $short Short option string
   * @param  array   $long  Long option array
   * @param  bitmask $mode  Settings bitmask. Default = SAK_GETOPT_NONE
   *
   * @return bool    True on success, false otherwise
   *
   * @uses sak_in_array     Checks against option arrays
   * @uses sak_getopt_error Error output
   */
  public function parse(Array &$args, $name = null, $short = null, $long = null,
                  $mode = null) {

    if ($short == null && $long == null && $mode == null)
      $mode = SAK_GETOPT_M_BLIND;
    elseif ($mode == null)
      $mode = SAK_GETOPT_NONE;

    // Allow a cosmetic dash (e.g. $short = '-abcdef')
    if (strlen($short) && strpos($short, '-') === 0)
      $short = substr($short, 1);

    $success = true;

    // Convert to: array( "o" => bool );
    $s = $short;
    $short = array();
    $c = strlen($s);
    for ($i=0; $i < $c; $i++) {
      $cc = substr($s, $i, 2);
      if (strlen($cc) == 2 && $cc[1] == ":") {
        $short[$cc[0]] = true;
        $i++;
      } else
        $short[$cc[0]] = false;
    }

    // Convert to: array( "option" => bool );
    $l = (array) $long;
    $long = array();
    foreach ($l as $n => $v) {
      $v = ltrim($v,"-");
      if (substr($v, -1, 1) == ":")
        $long[rtrim($v, ":")] = true;
      else
        $long[$v] = false;
    }

    unset($s);  // Destroy temporary arrays
    unset($l);

    if (!($mode & SAK_GETOPT_NO_NAME) && empty($name))
      $name = basename(
        array_shift($args));      // Store name and pop $args[0] off array

    $options = array();           // Successfully parsed options
    $addon = array();             // Any argument which is not a switch
    $endargs = false;

    $l = sizeof($args);

    for ($i = 0; $i < $l; $i++) {
      $arg = $args[$i];
      $next = $extra = $match = null;

      if (isset($args[($i+1)])) $next = $args[($i+1)];

      $delim = substr($arg, 0, 2);

      // Check for '--' marking the end of args
      if (!($endargs) && $arg == '--') {
        $arg = null;                            // Destroy
        $endargs = true;
      }

      if (!($endargs) && $delim == "--") {      // == Long options ==
        $arg = substr($arg, 2);                 // Strip delimiter
        $eq = strpos($arg, "=");                // Check for --option=argument
        if ($eq !== false) {                    // Extract value
          $extra = substr($arg, ($eq + 1));
          $arg   = substr($arg, 0, $eq);
        }

        // Search for matching long option
        $match = $this->in_array($arg, $long, !($mode & SAK_GETOPT_ARGS_NO_CASE));

        if ($match !== false) {
          if (!($mode & SAK_GETOPT_ARGS_NO_EXPAND))
            $arg = $match;                      // Expand option
          if (($long[$match])) {                // Argument is required
            if (!is_null($extra)) {             // Syntax: --option=argument
              $next = $extra;                   // Pull from $extra
            } elseif (!is_null($next)) {        // Syntax: --option argument
              $i++;                             // Skip next arg
            } else {                            // Argument not supplied
              if (!($mode & SAK_GETOPT_QUIET)) {
                $this->error($name, "option `--%s' requires an argument", $arg);
                $success = false;
              }
              if (!($mode & SAK_GETOPT_ARGS_KEEP))
                $arg = null;                    // Destroy if no argument
            }
            $arg = array("--".$arg => $next);   // Prepend match and add argument
          } else
            $arg = "--".$arg;                   // Prepend match
        } else {                                // Could not find match
          if (!($mode & SAK_GETOPT_QUIET)) {
            $this->error($name, "unrecognized option `--%s'", $arg);
            $success = false;
          }
          if (!($mode & SAK_GETOPT_ARGS_KEEP))
            $arg = null;                        // Destroy non-match
          else {
            $arg = "--".$arg;                   // Prepend non-match
            if (!is_null($extra))               // NOTE: $next cannot be used here
              $arg = array($arg => $extra);     // Add $extra if exists
          }
        }

        if (is_null($arg))
          continue;                             // Skip destroyed argument

        if (is_array($arg) && !($mode & SAK_GETOPT_ARGS_NEST)) {
          foreach ($arg as $n => $v) {          // Un-nest
            $options[] =                        // Store option
              (($mode & SAK_GETOPT_ARGS_LOWERCASE) ? strtolower($n) : $n);
            $options[] = $v;                    // Store argument
          }
        } else
          $options[] =                          // Store option and any argument
            (($mode & SAK_GETOPT_ARGS_LOWERCASE) ? strtolower($arg) : $arg);

      } elseif (!($endargs) && $delim[0] == "-") { // == Short options ==
        $arg = substr($arg, 1);                 // Strip delimiter
        $c = strlen($arg);

        for ($x = 0; $x < $c; $x++) {
          $a = substr($arg, $x, 1);             // Extract short option

          // This skips the rest of the string as an argument of previous option
          if (!($mode & SAK_GETOPT_ARGS_KEEP) && $a == "=")
            break;

          $eq = false;
          if (substr($arg, ($x + 1), 1) == "=") {
            $next = substr($arg, ($x + 2));
            $eq = true;
          }

          // Search for matching short option
          $match = $this->in_array($a, $short, !($mode & SAK_GETOPT_ARGS_NO_CASE));

          if ($match !== false) {
            if (!($mode & SAK_GETOPT_ARGS_NO_EXPAND))
              $a = $match;                      // Expand option (i.e. case)

            if (($short[$match])) {             // Argument is required
              if ($x >= ($c - 1) && !is_null($next)) {
                $i++;                           // Syntax: -o argument
              } elseif ($x < ($c - 1)) {
                $next = substr($arg, ($x + 1)); // Syntax: -oargument
                $c = $x;
              } else {                          // Argument not supplied
                if (!($mode & SAK_GETOPT_QUIET)){
                  $this->error($name, "option requires an argument -- %s", $a);
                  $success = false;
                }
                if (!($mode & SAK_GETOPT_ARGS_KEEP))
                  $a = null;                    // Destroy if no argument
              }
              if (!is_null($a))
                $a = array("-".$a => $next);    // Prepend match and add argument
            } else
              $a = "-".$a;                      // Prepend match
          } else {                              // Could not find match
            if (!($mode & SAK_GETOPT_QUIET)) {
              $this->error($name, "invalid option -- %s", $a);
              $success = false;
            }

            if (!($mode & SAK_GETOPT_ARGS_KEEP))
              $a = null;                        // Destroy non-match
            elseif (($eq) && count($short) == 0 && !is_null($next)) {
              // Option has an argument
              $a = array("-".$a => $next);
              $c = $x;
            } else
              $a = "-".$a;                      // Prepend non-match
          }

          if (is_null($a))
            continue;                           // Skip destroyed argument

          if (is_array($a) && !($mode & SAK_GETOPT_ARGS_NEST)) {
            foreach ($a as $n => $v) {          // Un-nest
              $options[] = $n;                  // Store option
              $options[] = $v;                  // Store argument
            }
          } else
            $options[] = $a;                    // Store option and any argument
        }
      } else {                                  // == Non-option ==
        if (is_null($arg))
          continue;                             // Skip destroyed argument

        if (($mode & SAK_GETOPT_ARGS_ORDER))
          $options[] = $arg;                    // Preserve order
        else
          $addon[] = $arg;                      // Appended after --

        continue;
      }
    }

    // Bring everything together
    $args = array_merge($options, array("--"), $addon);
    return $success;
  }

  /**
   * Internal error output for Getopt
   *
   * @param  string $name     Program name
   * @param  string $format   Format string
   * @param  mixed  $args     Optional arguments
   * @return void
   */
  private function error($name, $format, $args = "") {
    $args = func_get_args();
    $name = array_shift($args);
    $error = call_user_func_array('sprintf',$args);

    $result = sprintf("%s: %s\n", $name, $error);
    fwrite(STDERR, $result);
  }

  /**
   * Internal adaptation of in_array and allows partial beginning matches
   *
   * @param  string $needle   Term to search for
   * @param  array  $haystack Array to search
   * @param  bool   $case     Case sensitive toggle
   * @return string|false     If one and only one match, returns that match. False otherwise.
   */
  private function in_array($needle, Array $haystack, $case = true) {
    $count = 0;
    $match = null;
    foreach ($haystack as $stack => $garbage) {
      if ((($case) && $needle == $stack) ||
        (!($case) && strtolower($needle) == strtolower($stack))
      ) return $stack;                  // Exact match
      if ((($case) && strpos ($stack, $needle) === 0) ||
        (!($case) && stripos($stack, $needle) === 0)
      ) { $count++; $match = $stack; }  // Partial match
    }

    if ($count == 1) return $match;
    return false;
  }
}

/**#@+ @var bitmask */
/** Default, no options. */
define('SAK_GETOPT_NONE',           0x000);
/** Do not shift $args[0] off the array as the program name. */
define('SAK_GETOPT_NO_NAME',        0x001);
/** Suppress error output. */
define('SAK_GETOPT_QUIET',          0x002);
/** Options with arguments will be nested together in arrays. */
define('SAK_GETOPT_ARGS_NEST',      0x004);
/** Keep all options and arguments passed in the result. */
define('SAK_GETOPT_ARGS_KEEP',      0x008);
/** Do not move unmatched arguments to the end after "--" */
define('SAK_GETOPT_ARGS_ORDER',     0x010);
/** Match options without case sensitivity. */
define('SAK_GETOPT_ARGS_NO_CASE',   0x020);
/** Convert all long options to lowercase. */
define('SAK_GETOPT_ARGS_LOWERCASE', 0x040);
/** Do not rename partial argument matches (e.g. --h to --help) */
define('SAK_GETOPT_ARGS_NO_EXPAND', 0x080);
/**#@-*/

/**#@+
 * Option collapsing defines.
 *
 * NOTE: Not recommended with {@link SAK_GETOPT_ARGS_NO_EXPAND}!
 *
 * @var   bitmask
 * @todo  Not yet implemented.
 */
/** <code>Passing --arg="one" --arg="two" --arg="three" returns: "arg" => array("one")</code> */
define('SAK_GETOPT_ARGS_COLLAPSE_FIRST', 0x100);
/** Passing --arg="one" --arg="two" --arg="three" returns: "arg" => array("one","two","three") */
define('SAK_GETOPT_ARGS_COLLAPSE_MERGE', 0x200);
/** Passing --arg="one" --arg="two" --arg="three" returns: "arg" => array("three") */
define('SAK_GETOPT_ARGS_COLLAPSE_LAST',  0x400);
/**#@-*/

/**
 * Macro for quiet, keep arguments, and keep order. Handy for passing $argv
 *
 * Combination of {@link SAK_GETOPT_QUIET}, {@link SAK_GETOPT_ARGS_KEEP}, and {@link SAK_GETOPT_ARGS_ORDER}.
 *
 * @var bitmask
 */
define('SAK_GETOPT_M_BLIND', (SAK_GETOPT_QUIET | SAK_GETOPT_ARGS_KEEP | SAK_GETOPT_ARGS_ORDER));
