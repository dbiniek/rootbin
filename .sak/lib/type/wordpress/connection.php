<?php
/**
 * Swiss Army Knife -- (WordPress PHP Library)
 *
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package WordPress
 */

/**
 * WordPress class based on {@link Software}
 * @package WordPress
 */
class Type_WordPress_Connection extends Software {
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
      "SELECT option_name, option_value FROM `%s` WHERE option_name IN (%s);",
      $this->table('options'), implode(",", $stuff)))
    ) die_with_error('Error: Error during query. '.$this->fetch_error(),true);

    while ($row = $this->fetch_array_from($res, MYSQLI_ASSOC)) {
      switch($row['option_name']) {
        // We get cron here since it's part of wp_options anyway...
        case 'cron':
          if (false === ($data = @unserialize($row['option_value']))) continue;
          $this->basics[$row['option_name']] = $data;
          $this->have('cron',true);
          break;
        case 'active_plugins':
          if (false === ($data = @unserialize($row['option_value']))) continue;
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
   * Set basic WordPress settings
   *
   * @param mixed $update Array of settings to update, or field to update
   * @param mixed $value  Optional value to update field with
   *
   * @return bool   True on success
   */
  public function set_basics($update = array(), $value = null) {
    $settings = $this->get_basics();

    if (!is_array($update))
      $update = array($update => $value);

    $targets = array();
    $stuff = array(
      'blogname',
      'blogdescription',
      'siteurl',
      'home',
      'stylesheet',
      'template',
      'current_theme',
      'permalink_structure',
    );

    foreach ($update as $field => $value)
      if ($settings[$field] != $update[$field])
        $targets[$field] = $update[$field];

    // Nothing changed so no update required
    if (empty($targets)) return true;

    foreach ($targets as $field => $value) {
      if (false === ($res = $this->query(
        "INSERT INTO `%s` SET option_name = '%s', option_value = '%s' ".
        "ON DUPLICATE KEY UPDATE option_value = '%s';",
        $this->table('options'), $this->escape($field),
        $this->escape($value), $this->escape($value)))
      ) $this->fatal("Error: Error during query.\n".$this->fetch_error());
    }

    $this->have('basics', false);
    $this->pull_basics();
    return true;
  }

################################################################################
################################################################################

  /**
   * Compile and store user information
   *
   * @uses Type_WordPress_Connection::array_sort_id
   */
  private function pull_users() {
    // Check that wp_usermeta exists, if not, we fall back
    if (false === $this->query("SHOW TABLES LIKE '%s';", '%usermeta'))
      die_with_error('Error: Error during query.',true);

    if ($this->fetch_num_rows() == 0) {
      if (false === ($res = $this->query(
        "SELECT u.ID,u.user_nickname AS display_name,u.user_login,u.user_email,".
        "u.user_registered,u.user_status,user_level AS user_capabilities ".
        "FROM `%s` AS u;", $this->table('users')))
      ) die_with_error('Error: Error during query.',true);

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
      ) die_with_error('Error: Error during query.',true);

      while ($row = $this->fetch_array_from($res, MYSQLI_ASSOC)) {
        $row['user_capabilities'] = unserialize($row['user_capabilities']);
        $id = $row['ID'];
        $this->users[$id] = $row;
      }
      uasort($this->users, array('self', 'array_sort_id'));
      $this->have('users',true);
    }
  }

  /**
   * Set user information from input file
   *
   * @param string  $input  Filename with tab delimited settings
   *
   * @return bool   True on success
   */
  //public function set_users($input) {
  //  if (!$this->connected()) return false;
  //  $data = explode("\n",file_get_contents($input));
  //  foreach ($data as $line) {
  //    if ($line == "") continue;
  //
  //    list($id,
  //         $user_login,
  //         $display_name,
  //         $user_email,
  //         $garbage, /*user_registered*/
  //         $garbage, /*user_status*/
  //         $capabilities) = explode("\t",$line);
  //
  //    if (false === ($res = $this->query(
  //      "UPDATE `%s` SET user_login = '%s', user_email = '%s', ".
  //      "display_name = '%s' WHERE ID = %d;",
  //      $this->table('users'),
  //      $this->escape($user_login),
  //      $this->escape($user_email),
  //      $this->escape($display_name),
  //      $this->escape($id)))
  //    ) die_with_error('Error: Error during query.',true);
  //
  //    // WordPress requires this format
  //    $capabilities = serialize(array($capabilities => 1));
  //
  //    if (false === ($res = $this->query(
  //      "UPDATE `%s` SET meta_value = '%s' WHERE meta_key LIKE '%s' AND ".
  //      "user_id = %s;",
  //      $this->table('usermeta'),
  //      $this->escape($capabilities),
  //      $this->table('%capabilities'),  // Cheating here.
  //      $this->escape($id)))
  //    ) die_with_error('Error: Error during query.',true);
  //  }
  //  return true;
  //}

################################################################################
################################################################################

  /**
   * Recursively check a directory for valid plugins
   *
   * @param string  $dir      Directory to begin in
   * @param string  $root     Root directory (remains unchanged)
   * @param int     $recurse  Specifies max depth of recursion
   *
   * @return array  Array of theme data
   */
  private function pull_plugin_files($dir, $root, $recurse = true) {
    if (!is_dir($dir)) $this->fatal("Directory does not exist or is inaccessible: `".$dir."'");

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
   *
   * @return array  Array of theme data
   */
  private function pull_theme_files($dir, $root, $recurse = 2) {
    if (!is_dir($dir)) $this->fatal("Directory does not exist or is inaccessible: `".$dir."'");

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
   *
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
   * @todo Unused
   */
  //private function pull_widgets() {
  //  if (false === ($res = $this->query(
  //    "SELECT option_name,option_value FROM `%s` WHERE option_name ".
  //    "LIKE 'widget\_%' OR option_name = 'sidebars_widgets';",
  //    $this->table('options')))
  //  ) die_with_error('Error: Error during query.',true);
  //  while ($row = $this->fetch_array($res, MYSQLI_ASSOC)) {
  //    if (false !== ($data = @unserialize($row['option_value']))) {
  //      printf(">>> %s\n",$row['option_name']);
  //      print_r($data);
  //    }
  //  }
  //}

################################################################################
################################################################################

  /**
   * Return basic WordPress information
   *
   * @param string  $output Filename to output data
   *
   * @return bool True on success
   */
  public function get_basics() {
    if (!$this->have('basics')) {
      $this->pull_basics();
    }
    return $this->basics;
  }

  /**
   * Return cron information
   *
   * @param string  $output Filename to output data
   *
   * @return bool True on success
   */
  public function get_cron() {
    if (!$this->have('basics'))
      $this->pull_basics();
    if (!$this->have('cron'))
      return false; // This blog must not have cron, possibly too old
    return $this->basics['cron'];
  }

  /**
   * Return list of user information
   *
   * @param string  $output Filename to output data
   *
   * @return bool True on success
   */
  public function get_users(/*$output*/) {
    if (!$this->have('users')) {
      $this->pull_users();
    }

    return $this->users;
  }

  /**
   * Return plugin information and status
   *
   * @return bool   True on success
   *
   * @uses Type_WordPress_Connection::array_sort_id
   */
  public function get_plugins() {
    if (!$this->have('basics')) {
      $this->pull_basics();
    }

    $plugins = $this->pull_plugin_files(
                 $this->core->path.DS.'wp-content'.DS.'plugins', $this->core->path);
    uasort($plugins, array('self', 'array_sort'));
    $active = (array) $this->basics['active_plugins'];

    foreach ($plugins as $index => $plugin) {
      if (in_array($plugin['Filename'], $active)) {
        $plugins[$index]['Active'] = true;
      } else {
        $plugins[$index]['Active'] = false;
      }
    }
    sort($plugins);
    return $plugins;
  }

  /**
   * Return theme information
   *
   * @return bool   True on success
   *
   * @uses Type_WordPress_Connection::array_sort_id
   */
  public function get_themes() {
    if (!$this->have('basics')) {
      $this->pull_basics();
    }

    $themes = $this->pull_theme_files(
                $this->core->path.DS.'wp-content'.DS.'themes', $this->core->path);

    uasort($themes, array('self', 'array_sort'));

    foreach ($themes as $index => $theme) {
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
        $theme['Active'] = (($this->basics['current_theme'] == $theme['Name']) ? true : false );
      } else {
        $theme['Active'] = (($this->basics['template'] == $theme['Directory']) ? true : false );
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
      $themes[$index] = $theme;
    }
    sort($themes);
    return $themes;
  }

  /**
   * Return post, comment, and taxonomy counts
   */
  public function get_counts() {
    if (!$this->have('basics')) $this->pull_basics();
    if (!$this->connected()) return false;

    $counts = array();
    $dbver = ((array_key_exists('db_version',$this->basics)) ? $this->basics['db_version'] : 0 );

    // POSTS
    if ($dbver <= 3441) // WP v2.0.11 and below
      $sql = "post_status <> 'static' GROUP BY post_status;";
    else
      $sql = "post_type = 'post' GROUP BY post_status;";

    if (false === ($res = $this->query(
      "SELECT post_status, COUNT(*) AS num_posts FROM `%s` WHERE %s",
      $this->table('posts'), $sql))
    ) die_with_error('Error: Error during query.',true);
    while ($row = $this->fetch_array(MYSQLI_ASSOC))
      $counts['posts'][$row['post_status']] = $row['num_posts'];

    // PAGES
    if ($dbver <= 3441) // WP v2.0.11 and below
      $sql = "post_status = 'static' GROUP BY post_status;";
    else
      $sql = "post_type = 'page' GROUP BY post_status;";

    if (false === ($res = $this->query(
      "SELECT post_status, COUNT(*) AS num_pages FROM `%s` WHERE %s",
      $this->table('posts'), $sql))
    ) die_with_error('Error: Error during query.',true);
    while ($row = $this->fetch_array(MYSQLI_ASSOC))
      $counts['pages'][$row['post_status']] = $row['num_pages'];

    // CATEGORIES
    if ($dbver < 6124) // WP v2.2.3 and below
      $sql = $this->table('categories')."`;";
    else //                 half quoted -^  v- half quoted
      $sql = $this->table('term_taxonomy')."` WHERE taxonomy = 'category';";

    if (false === ($res = $this->query("SELECT COUNT(*) AS total FROM `%s", $sql)))
      die_with_error('Error: Error during query.',true);//half quoted ^
    while ($row = $this->fetch_array(MYSQLI_ASSOC))
      $counts['categories'] = $row['total'];

    // TAGS
    if ($dbver >= 6124) { // WP v2.3 and up
      if (false === ($res = $this->query(
        "SELECT COUNT(*) AS total FROM `%s` WHERE taxonomy = 'post_tag';",
        $this->table('term_taxonomy')))
      ) die_with_error('Error: Error during query.',true);
      while ($row = $this->fetch_array(MYSQLI_ASSOC))
        $counts['tags'] = $row['total'];
    }

    // COMMENTS
    if (false === ($res = $this->query(
      "SELECT comment_approved, COUNT(*) AS total FROM `%s` GROUP BY comment_approved;",
      $this->table('comments')))
    ) die_with_error('Error: Error during query.',true);

    $ctype=array(
      1=>"approved","approved"=>"approved",0=>"waiting","waiting"=>"waiting",
      "spam"=>"spam","post-trashed"=>"trash","trash"=>"trash");
    $counts['comments'] = array('approved'=>0,'waiting'=>0,'spam'=>0,'trash'=>0);
    while ($row = $this->fetch_array(MYSQLI_ASSOC)) {
      $c = $row['comment_approved'];
      $c = ((array_key_exists($c,$ctype)) ? $ctype[$c] : $c );
      $counts['comments'][$c] = $row['total'];
    }
    return $counts;
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
      die_with_error('Error: Error during query.',true);

    $prefixes = array();
    while ($row = $this->fetch_array(MYSQLI_NUM)) {
      $prefixes[] = substr($row[0], 0, (strlen($row[0]) - 5) );
    }

    // Filter out prefixes that do not have an options table
    foreach ($prefixes as $index => $prefix)
      $this->prefix = $prefix;
      if (false === ($this->query("SHOW TABLES LIKE '%s';", $this->table('options', true))))
        die_with_error('Error: Error during query.', true);
      elseif ($this->fetch_num_rows() == 0)
        unset($prefixes[$index]);

    $prefixes = array_unique($prefixes, SORT_STRING); // Nuke dupes
    return $prefixes;
  }

  /**
   * Return database schema version
   *
   * @param string  $output Filename to output data
   *
   * @return bool True on success
   *
   * @uses Type_WordPress_Connection::get_prefixes()
   */
  public function pull_dbver() {
    $mu = 0;
    if ($this->connected()) {
      if (false === $this->query("SHOW TABLES LIKE '%s';",$this->table('options', true)))
        die_with_error('Error: Error during query.', true);

      if ($this->fetch_num_rows() == 0)
        return false;

      // Guess if MU/Multisite
      if (false === $this->query("SHOW TABLES LIKE '%s';", $this->table('blogs')))
        die_with_error('Error: Error during query.', true);

      if ($this->fetch_num_rows() > 0)
        $mu = 1;
    }
    if (!$this->have('basics')) $this->pull_basics();
    if (!$this->connected()) return false;

    return array($this->fetch_database(),$this->prefix,$this->basics['db_version'],$mu);
  }

  /**
   * Natural language array sort on 'Name' key
   *
   * @param array $a  First array
   * @param array $b  Second array
   *
   * @return int
   */
  static private function array_sort($a, $b) {
    return strnatcasecmp($a['Name'],$b['Name']);
  }

  /**
   * Numeric array sort on 'ID' key
   *
   * @param array $a  First array
   * @param array $b  Second array
   *
   * @return int
   */
  static private function array_sort_id($a, $b) {
    $a = $a['ID'];
    $b = $b['ID'];

    if ($a == $b)
      return 0;
    elseif ($a > $b)
      return 1;
    return -1;
  }
} /* class WordPress */
