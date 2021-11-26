<?php
/**
 * Swiss Army Knife -- (WordPress PHP Library)
 *
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package WordPress
 */

set_include_path(realpath(dirname(__FILE__)."/../../").":.");

/** For standard functions */
require_once('php/main.php');
/** Reference: {@link SoftwareTemplate} */
require_once('php/library/classSoftwareTemplate.php');
/** Reference: {@link PasswordHash} */
require_once('php/library/classPasswordHash.php');
/** Reference: {@link sak_getopt()} */
require_once('php/library/libGetopt.php');

disable_errors();
require_root();

/**
 * WordPress class based on {@link SoftwareTemplate}
 * @package WordPress
 */
final class WordPress extends SoftwareTemplate {
  /**#@+ @var array */
  /** Basic setting storage */
  private $basics = array();
  /** Cron setting storage */
  private $cron = null;
  /** Plugin storage */
  private $plugins = null;
  /** User storage */
  private $users = array();
  /**#@-*/

  /**
   * Initialize settings
   *
   * @return void
   */
  public function init() {
    $this->have(array(
      'basics' => false,
      'cron' => false,
      'users' => false,
      'plugins' => false));
  }

################################################################################
################################################################################

  /**
   * Compile and store basic WordPress settings
   *
   * @return void
   */
  private function pull_basics() {
    // The STUFF we want.
    $stuff = array(
      "'blogname'",
      "'blogdescription'",
      "'siteurl'",
      "'home'",
      "'stylesheet'",
      "'template'",
      "'current_theme'",
      "'permalink_structure'",
      "'cron'",
      "'active_plugins'",
      "'db_version'",
    );

    if (false === ($res = $this->query(
      "SELECT option_name,option_value FROM `%s` WHERE option_name IN (%s);",
      $this->table('options'), implode(",",$stuff)))
    ) die_with_error('Error: Errror checking options table. Verify table exists and the prefix is correct in the wp-config.php file. '.$this->fetch_error(),false);

    while ($row = $this->fetch_array_from($res, MYSQLI_ASSOC)) {
      switch($row['option_name']) {
        // We get cron here since it's part of wp_options anyway...
        case 'cron':
          if (false === ($data = @unserialize($row['option_value']))) break;
          $this->basics[$row['option_name']] = $data;
          $this->have('cron',true);
          break;
        case 'active_plugins':
          if (false === ($data = @unserialize($row['option_value']))) break;
          $this->basics[$row['option_name']] = $data;
          $this->have('plugins',true);
          break;
        default:
          $this->basics[$row['option_name']] = $row['option_value'];
          break;
      }
    }
    $this->have('basics',true);
  }

  /**
   * Set basic WordPress settings from input file
   *
   * @param string  $input  Filename with tab delimited settings
   * @return bool   True on success
   */
  public function set_basics($input) {
    if (!$this->connected()) return false;
    $data = explode("\n",file_get_contents($input));
    foreach ($data as $line) {
      if ($line == "") break;
      list ($field, $value) = explode("\t", $line);
      if (false === ($res = $this->query(
        "INSERT INTO `%s` SET option_name = '%s', option_value = '%s' ON DUPLICATE KEY UPDATE option_value = '%s';",
        $this->table('options'),
        $this->escape($field),
        $this->escape($value),
        $this->escape($value)))
      ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);
    }
    return true;
  }

  public function import_basics($ini, $path = null) {
    if (!$this->connected()) return false;
    if (!file_exists($ini) || !is_readable($ini)) {
      fprintf(STDERR, "Error: Import INI file not found or unreadable.\n");
      exit(2);
    }
    $settings = parse_ini_file($ini, true);
    $settings['additional'] = array(); // Pseudo section for TZ/theme handling
    foreach (array('general','reading','discussion','permalinks','additional') as $sect)
      foreach ($settings[$sect] as $field => $value) {
        // Special handling for themes
        if ($sect == "general" && $field == "theme") {
          if (is_dir($path)) {
            $themes = $this->pull_theme_files($path."/wp-content/themes", $path);
            foreach ($themes as $theme)
              if ($theme['Name'] == $value) {
                $settings['additional']['current_theme'] = $theme['Name'];
                $settings['additional']['template'] = $theme['Directory'];
                $settings['additional']['stylesheet'] = $theme['Directory'];
                break; // foreach $theme
              }
          }
          break;
        }
        // Special handling for UTC offsets
        if ($sect == "general" && $field == "timezone_string") {
          $matches = array();
          if (preg_match('/^UTC\+?(-?\d+)(?:|:(\d+))$/', $value, $matches)) {
            $hrs = (int)$matches[1];
            $min = ((!empty($matches[2])) ? ((int)$matches[2]/60) : 0 );
            $settings['additional']['gmt_offset'] = (($hrs >= 0) ? $hrs+$min : $hrs-$min );
            $value = '';
          } else
            $settings['additional']['gmt_offset'] = "";
        }
        // Update the database or insert new value
        if (false === ($res = $this->query(
          "INSERT INTO `%s` SET option_name = '%s', option_value = '%s' ON DUPLICATE KEY UPDATE option_value = '%s';",
          $this->table('options'),
          $this->escape($field),
          $this->escape($value),
          $this->escape($value)))
        ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);
      }
    return true;
  }

################################################################################
################################################################################

  /**
   * Compile and store user information
   *
   * @return void
   * @uses array_sort_id()
   */
  private function pull_users() {
    // Check that wp_usermeta exists, if not, we fall back
    if (false === $this->query("SHOW TABLES LIKE '%s';", '%usermeta'))
      die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);

    if ($this->fetch_num_rows() == 0) {
      if (false === ($res = $this->query(
        "SELECT u.ID,u.user_nickname AS display_name,u.user_login,u.user_email,".
        "u.user_registered,u.user_status,user_level AS user_capabilities ".
        "FROM `%s` AS u;", $this->table('users')))
      ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);

      while ($row = $this->fetch_array_from($res, MYSQLI_ASSOC)) {
        $id = $row['ID'];
        $this->users[$id] = $row;
      }
      $this->have('users',true);
    } else {
      if (false === ($res = $this->query(
        "SELECT u.ID,u.display_name,u.user_login,u.user_email,u.user_registered,".
        "u.user_status,m.meta_value AS user_capabilities FROM `%s` AS u,`".
        "%s` AS m WHERE m.meta_key LIKE '%s' AND u.ID = m.user_id;",
        $this->table('users'), $this->table('usermeta'), $this->table('%capabilities')))
      ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);

      while ($row = $this->fetch_array_from($res, MYSQLI_ASSOC)) {
        $row['user_capabilities'] = unserialize($row['user_capabilities']);
        $id = $row['ID'];
        $this->users[$id] = $row;
      }
      uasort($this->users,'array_sort_id');
      $this->have('users',true);
    }
  }

  /**
   * Set user information from input file
   *
   * @param string  $input  Filename with tab delimited settings
   * @return bool   True on success
   */
  public function set_users($input) {
    if (!$this->connected()) return false;
    $data = explode("\n",file_get_contents($input));
    foreach ($data as $line) {
      if ($line == "") continue;

      list($id,
           $user_login,
           $display_name,
           $user_email,
           $garbage, /*user_registered*/
           $garbage, /*user_status*/
           $capabilities) = explode("\t",$line);

      if (false === ($res = $this->query(
        "UPDATE `%s` SET user_login = '%s', user_email = '%s', ".
        "display_name = '%s' WHERE ID = %d;",
        $this->table('users'),
        $this->escape($user_login),
        $this->escape($user_email),
        $this->escape($display_name),
        $this->escape($id)))
      ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);

      // WordPress requires this format
      $capabilities = serialize(array($capabilities => 1));

      if (false === ($res = $this->query(
        "UPDATE `%s` SET meta_value = '%s' WHERE meta_key LIKE '%s' AND ".
        "user_id = %s;",
        $this->table('usermeta'),
        $this->escape($capabilities),
        $this->table('%capabilities'),  // Cheating here.
        $this->escape($id)))
      ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);
    }
    return true;
  }

################################################################################
################################################################################

  /**
   * Recursively check a directory for valid plugins
   *
   * @param string  $dir      Directory to begin in
   * @param string  $root     Root directory (remains unchanged)
   * @param int     $recurse  Specifies max depth of recursion
   * @return array  Array of theme data
   */
  private function pull_plugin_files($dir, $root, $recurse = true) {
    if (!is_dir($dir)) die_with_error("Directory does not exist or is inaccessible: `".$dir."'");

    $pluginroot = $root."/wp-content/plugins";
    $subdir = substr($dir,strlen($pluginroot)+1);
    $handle = opendir($dir);

    $res = array();
    while (false !== ($item = readdir($handle))) {
      if ($item == "." || $item == "..")
        continue;
      if (is_dir($dir."/".$item) && ($recurse))
        $res = array_merge($res,$this->pull_plugin_files($dir."/".$item,$root,false));

      $data = null;
      if (substr($item,-4) == ".php") {
        $data = $this->pull_file_headers($pluginroot."/".ltrim($subdir."/".$item,"/"));
        $data['Filename'] = ltrim($subdir."/".$item,"/");
        if (is_array($data) && $data['Name'] != "")
          $res[]=$data;
      }
    }
    return $res;
  }

  /**
   * Recursively check a directory for valid themes
   *
   * @param string  $dir      Directory to begin in
   * @param string  $root     Root directory (remains unchanged)
   * @param int     $recurse  Specifies max depth of recursion
   * @return array  Array of theme data
   */
  private function pull_theme_files($dir, $root, $recurse = 2) {
    if (!is_dir($dir)) die_with_error("Directory does not exist or is inaccessible: `".$dir."'");

    $pluginroot = $root."/wp-content/themes";
    $subdir = substr($dir,strlen($pluginroot)+1);
    $handle = opendir($dir);

    $res = array();
    while (false !== ($item = readdir($handle))) {
      if ($item == "." || $item == "..")
        continue;
      if (is_dir($dir."/".$item) && $recurse > 0)
        $res = array_merge($res,$this->pull_theme_files($dir."/".$item,$root,$recurse - 1));

      $data = null;
      if ($item == "style.css") {
        $data = $this->pull_file_headers($pluginroot."/".ltrim($subdir."/".$item,"/"),true);
        $data['Directory'] = $subdir;
        if (is_array($data) && $data['Name'] != "")
          $res[]=$data;
      }
    }
    return $res;
  }

################################################################################
################################################################################

  /**
   * Compile plugin and theme header data
   *
   * @param string  $target Filename to parse for headers
   * @param bool    $theme  True if parsing a theme file
   * @return array Array of header data
   */
  private function pull_file_headers($target,$theme = false) {
    if (!($handle = fopen($target,'r'))) {
      die_with_error("Error opening `".$target."'");
    }
    $data = fread($handle,8192);
    fclose($handle);

    if (!($theme)) {
      $headers = array(
        'Name' => 'Plugin Name',
        'PluginURI' => 'Plugin URI',
        'Version' => 'Version',
        'Description' => 'Description',
        'Author' => 'Author',
        'AuthorURI' => 'Author URI',
        'TextDomain' => 'Text Domain',
        'DomainPath' => 'Domain Path',
        'Network' => 'Network',
        '_sitewide' => 'Site Wide Only'
      );
    } else {
      $headers = array(
        'Name' => 'Theme Name',
        'URI' => 'Theme URI',
        'Description' => 'Description',
        'Author' => 'Author',
        'AuthorURI' => 'Author URI',
        'Version' => 'Version',
        'Template' => 'Template',
        'Status' => 'Status',
        'Tags' => 'Tags'
      );
    }

    foreach ($headers as $field => $regex) {
      preg_match( '/^[ \t\/*#@]*'.preg_quote($regex,'/').':(.*)$/mi',$data,${$field});
      if (!empty(${$field}))
        ${$field} = trim(preg_replace("/\s*(?:\*\/|\?>).*/",'',${$field}[1]));
      else
        ${$field} = '';
    }

    $data = compact(array_keys($headers));
    return $data;
  }

################################################################################
################################################################################

  /**
   * Compile widget data
   *
   * @return void
   * @todo Needs to be completed
   */
  private function pull_widgets() {
    if (false === ($res = $this->query(
      "SELECT option_name,option_value FROM `%s` WHERE option_name ".
      "LIKE 'widget\_%' OR option_name = 'sidebars_widgets';",
      $this->table('options')))
    ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);
    while ($row = $this->fetch_array($res, MYSQLI_ASSOC)) {
      if (false !== ($data = @unserialize($row['option_value']))) {
        printf(">>> %s\n",$row['option_name']);
        print_r($data);
      }
    }
  }

################################################################################
################################################################################

  /**
   * Output basic WordPress information
   *
   * @param string  $output Filename to output data
   * @return bool True on success
   */
  public function get_basics($output) {
    if (!$this->have('basics')) {
      $this->pull_basics();
    }

    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"w");

    foreach ($this->basics as $type => $value) {
      switch ($type) {
        case 'active_plugins':
        case 'cron':
          break;
        default:
          fprintf($handle,"%s\x1E%s\n",$type,$value);
          break;
      }
    }
  }

  /**
   * Output cron information
   *
   * @param string  $output Filename to output data
   * @return bool True on success
   */
  public function get_cron($output) {
    if (!$this->have('basics'))
      $this->pull_basics();
    if (!$this->have('cron'))
      return false; // This blog must not have cron, possibly too old

    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"w");

    foreach ($this->basics['cron'] as $ts => $entry) {
      if ($ts == 'version') continue;
      foreach ($entry as $name => $job) {
        list($md5) = array_keys($job);
        $job = $job[$md5];
        $schedule = $job['schedule'];
        $interval = $job['interval'];
        $args = $job['args'];
        if ($md5 != md5(serialize($job['args']))) {
          $md5 = "INVALID";
        }
        // TIMESTAMP  FUNCTION  HASH  SCHEDULE  INTERVAL
        fprintf($handle,"%d\x1E%s\x1E%s\x1E%s\x1E%d\x1E%s\n",$ts,$name,$md5,$schedule,$interval,timedelta($interval));
      }
    }
  }

  /**
   * Output list of user information
   *
   * @param string  $output Filename to output data
   * @return bool True on success
   */
  public function get_users($output) {
    if (!$this->have('users')) {
      $this->pull_users();
    }

    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"w");

    foreach ($this->users as $id => $user) {
      if (is_array($user['user_capabilities'])) {
        if (sizeof($user['user_capabilities']) > 0)
          list($capabilities) = array_keys($user['user_capabilities']);
       	else
          $capabilities	= ""; // Shouldn't happen, but have seen it
      } else
        $capabilities = "Level ".$user['user_capabilities'];
      fprintf($handle,"%d\x1E%s\x1E%s\x1E%s\x1E%s\x1E%s\x1E%s\n",
        $id,
        $user['user_login'],
        $user['display_name'],
        $user['user_email'],
        $user['user_registered'],
        $user['user_status'],
        $capabilities
      );
    }
  }

  /**
   * Output plugin information and status
   *
   * @param string  $dir    Directory to begin in
   * @param string  $output Filename to output data
   * @return bool   True on success
   * @uses array_sort
   */
  public function get_plugins($dir, $output) {
    if (!$this->have('basics')) {
      $this->pull_basics();
    }

    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"w");

    $plugins = $this->pull_plugin_files($dir."/wp-content/plugins",$dir);
    uasort($plugins,'array_sort');
    $active = (array) $this->basics['active_plugins'];

    foreach ($plugins as $plugin) {
      if (in_array($plugin['Filename'],$active)) {
        $plugin['Active'] = 1;
      } else {
        $plugin['Active'] = 0;
      }
      fprintf($handle,"%d\x1E%s\x1E%s\x1E%s\n",$plugin['Active'],$plugin['Filename'],$plugin['Version'],$plugin['Name']);
    }
  }

  /**
   * Output theme information
   *
   * @param string  $dir    Directory to begin in
   * @param string  $output Filename to output data
   * @return bool   True on success
   * @uses array_sort
   */
  public function get_themes($dir, $output) {
    if (!$this->have('basics')) {
      $this->pull_basics();
    }

    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"w");

    $themes = $this->pull_theme_files($dir."/wp-content/themes",$dir);
    uasort($themes,'array_sort');

    foreach ($themes as $theme) {
      if ($theme['Template'] != "") {
        $temp = "!".$theme['Template'];
        foreach ($themes as $t) {
          if ($t['Directory'] == $theme['Template']) {
            $temp = $theme['Template'];
            break;
          }
        }
        $theme['Template'] = $temp;
      }

      if (array_key_exists('current_theme',$this->basics)) {
        $theme['Active'] = (($this->basics['current_theme'] == $theme['Name']) ? 1 : 0 );
      } else {
        $theme['Active'] = (($this->basics['template'] == $theme['Directory']) ? 1 : 0 );
      }

      foreach ($theme as $name => $value) {
        switch ($name) {
          case 'Template':
            break;
          case 'Version':
            if ($value == "")
              $theme[$name] = 0;
            break;
        }
      }
      fprintf($handle,"%d\x1E%s\x1E%s\x1E%s\x1E%s\n",$theme['Active'],$theme['Directory'],$theme['Version'],$theme['Name'],$theme['Template']);
    }
  }

  /**
   * Output post, comment, and taxonomy counts
   *
   * @param string  $output Filename to output data
   * @return bool True on success
   */
  public function get_counts($output) {
    if (!$this->have('basics')) $this->pull_basics();
    if (!$this->connected()) return false;

    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"w");

    $dbver = ((array_key_exists('db_version',$this->basics)) ? $this->basics['db_version'] : 0 );

    // POSTS
    if ($dbver <= 3441) // WP v2.0.11 and below
      $sql = "post_status <> 'static' GROUP BY post_status;";
    else
      $sql = "post_type = 'post' GROUP BY post_status;";

    if (false === ($res = $this->query(
      "SELECT post_status, COUNT(*) AS num_posts FROM `%s` WHERE %s",
      $this->table('posts'), $sql))
    ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);
    while ($row = $this->fetch_array(MYSQLI_ASSOC))
      fprintf($handle,"posts\x1E%s\x1E%s\n",$row['post_status'],$row['num_posts']);

    // PAGES
    if ($dbver <= 3441) // WP v2.0.11 and below
      $sql = "post_status = 'static' GROUP BY post_status;";
    else
      $sql = "post_type = 'page' GROUP BY post_status;";

    if (false === ($res = $this->query(
      "SELECT post_status, COUNT(*) AS num_pages FROM `%s` WHERE %s",
      $this->table('posts'), $sql))
    ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);
    while ($row = $this->fetch_array(MYSQLI_ASSOC))
      fprintf($handle,"pages\x1E%s\x1E%s\n",$row['post_status'],$row['num_pages']);

    // CATEGORIES
    if ($dbver < 6124) // WP v2.2.3 and below
      $sql = $this->table('categories')."`;";
    else //                 half quoted -^  v- half quoted
      $sql = $this->table('term_taxonomy')."` WHERE taxonomy = 'category';";

    if (false === ($res = $this->query("SELECT COUNT(*) AS total FROM `%s", $sql)))
      //                                                  half quoted ^
      die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);
    while ($row = $this->fetch_array(MYSQLI_ASSOC))
      fprintf($handle,"categories\x1E%s\n",$row['total']);

    // TAGS
    if ($dbver >= 6124) { // WP v2.3 and up
      if (false === ($res = $this->query(
        "SELECT COUNT(*) AS total FROM `%s` WHERE taxonomy = 'post_tag';",
        $this->table('term_taxonomy')))
      ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);
      while ($row = $this->fetch_array(MYSQLI_ASSOC))
        fprintf($handle,"tags\x1E%s\n",$row['total']);
    }

    // COMMENTS
    if (false === ($res = $this->query(
      "SELECT comment_approved, COUNT(*) AS total FROM `%s` GROUP BY comment_approved;",
      $this->table('comments')))
    ) die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);

    $ctype=array(
      1=>"approved","approved"=>"approved",0=>"waiting","waiting"=>"waiting",
      "spam"=>"spam","post-trashed"=>"trash","trash"=>"trash");
    while ($row = $this->fetch_array(MYSQLI_ASSOC)) {
      $c = $row['comment_approved'];
      $c = ((array_key_exists($c,$ctype)) ? $ctype[$c] : $c );
      fprintf($handle,"comments\x1E%s\x1E%s\n",$c,$row['total']);
    }
    return true;
  }

  /**
   * Use SHOW TABLES to parse for table prefixes that match WordPress tables
   *
   * @return array Array containing prefixes
   */
  public function pull_prefixes() {
    if (!$this->connected()) return false;
    // Searches for users table as one and only one is required for all installs
    if (false === ($this->query("SHOW TABLES LIKE '%s';", '%users')))
      die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);

    $prefixes = array();
    while ($row = $this->fetch_array(MYSQLI_NUM)) {
      $prefixes[] = substr($row[0], 0, (strlen($row[0]) - 5) );
    }

    // Filter out prefixes that do not have an options table
    foreach ($prefixes as $index => $prefix)
      $this->prefix = $prefix;
      if (false === ($this->query("SHOW TABLES LIKE '%s';", $this->table('options', true))))
        die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);
      elseif ($this->fetch_num_rows() == 0)
        unset($prefixes[$index]);

    $prefixes = array_unique($prefixes, SORT_STRING); // Nuke dupes
    return $prefixes;
  }

  /**
   * Outputs database schema version
   *
   * @param string  $output Filename to output data
   * @return bool True on success
   * @uses get_prefixes()
   */
  public function pull_dbver($output) {
    $mu = 0;
    if ($this->connected()) {
      if (false === $this->query("SHOW TABLES LIKE '%s';",$this->table('options', true)))
        die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);

      if ($this->fetch_num_rows() == 0)
        return false;

      // Guess if MU/Multisite
      if (false === $this->query("SHOW TABLES LIKE '%s';", $this->table('blogs')))
        die_with_error('Error: Error during query. ' . $this->fetch_error() ,true);

      if ($this->fetch_num_rows() > 0)
        $mu = 1;
    }
    if (!$this->have('basics')) $this->pull_basics();
    if (!$this->connected()) return false;

    $output = (($output == "STDOUT" || $output == "") ? "php://stdout" : $output);
    $handle = fopen($output,"a");

    fprintf($handle,"%s\x1E%s\x1E%d\x1E%d\n",
      $this->fetch_database(),$this->prefix,$this->basics['db_version'],$mu);
    return true;
  }
} /* class WordPress */

/**
 * Natural language array sort on 'Name' key
 *
 * @param array $a  First array
 * @param array $b  Second array
 * @return int
 */
function array_sort($a, $b) {
  return strnatcasecmp($a['Name'],$b['Name']);
}

/**
 * Numeric array sort on 'ID' key
 *
 * @param array $a  First array
 * @param array $b  Second array
 * @return int
 */
function array_sort_id($a, $b) {
  $a = $a['ID'];
  $b = $b['ID'];

  if ($a == $b)
    return 0;
  elseif ($a > $b)
    return 1;
  return -1;
}

$args = $argv;
$self = basename($argv[0]);

$username = "";
$password = "";

$db     = "";
$prefix = "";
$wp     = null;

$input  = "";
$output = "";
$path   = "";

$short = "i:o:";
$long  = array(
  'db:','get:','in:','ini:','import-basics','input:','out:','output:','path:',
  'prefix:','root','set:');
if (!sak_getopt($args,null,$short,$long)) exit(1);

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
    case '-o':
    case '--out':
    case '--output':
      $output = array_shift($args);
      break;
    case '--path':
      $path = array_shift($args);
      break;
    case '--import-basics':
      if (empty($username) || empty($password)) {
        fprintf(STDERR,"%s: cannot get data without a valid username and password.\n", $self);
        exit(1);
      }
      if (empty($input)) {
        fprintf(STDERR,"%s: cannot import data without input file.\n", $self);
        exit(1);
      }
      if (!is_a($wp,"WordPress"))
        $wp = new WordPress($username,$password,"localhost",$prefix,$db);
      $wp->import_basics($input, $path);
      break;
    case '--get':
      if (empty($username) || empty($password)) {
        fprintf(STDERR,"%s: cannot get data without a valid username and password.\n", $self);
        exit(1);
      }
      // Attempt to init a new WordPress object
      if (!is_a($wp,"WordPress"))
        $wp = new WordPress($username,$password,"localhost",$prefix,$db);
      $arg = array_shift($args);
      switch ($arg) {
        case 'basics':
          $wp->get_basics($output);
          break;
        case 'users':
          $wp->get_users($output);
          break;
        case 'cron':
          $wp->get_cron($output);
          break;
        case 'plugins':
          $wp->get_plugins(rtrim($path,"/"),$output);
          break;
        case 'themes':
          $wp->get_themes(rtrim($path,"/"),$output);
          break;
        case 'counts':
          $wp->get_counts($output);
          break;
        case 'widgets':
          $wp->pull_widgets($output);
          break;
        case 'prefixes':
          print_r($wp->pull_prefixes());
          break;
        case 'dbver':
          if ($prefix == "") {
            // Use current connection to query prefixes
            $prefixes = $wp->pull_prefixes();
            unset($wp); // Destroy current object so we can iterate prefixes
            foreach ($prefixes as $p) {
              $wp = new WordPress($username,$password,"localhost",$p,$db);
              //$wp->pull_prefixes();
              $wp->pull_dbver($output);
            }
          } else {
            $wp->pull_dbver($output);
          }
          break;
        default:
          fprintf(STDERR,"%s: unknown get type `%s'\n",$self, $arg);
          exit(1);
      }
      break;
    case '--set':
      if (empty($username) || empty($password) || empty($db)) {
        fprintf(STDERR,"%s: cannot get data without a valid username, password, and database.\n",$self);
        exit(1);
      }
      if (empty($input)) {
        fprintf(STDERR,"%s: an input file is expected, but none provided.\n",$self);
        exit(1);
      }
      // Attempt to init a new WordPress object
      if (!is_a($wp,"WordPress"))
        $wp = new WordPress($username,$password,"localhost",$prefix,$db);
      $arg = array_shift($args);
      switch ($arg) {
        case 'basics':
          $wp->set_basics($input);
          break;
        case 'users':
          $wp->set_users($input);
          break;
        case 'cron':
          $wp->set_cron($input);
          break;
        default:
          fprintf(STDERR,"%s: unknown set type `%s'\n",$self, $arg);
          exit(1);
      }
      break;
    case '--':
      break;
    default:
      fprintf("%s: unrecognized option `%s'\n", $self, $arg);
      break;
  }
