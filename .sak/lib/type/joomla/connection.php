<?php
/**
 * Swiss Army Knife -- (Joomla PHP Library)
 *
 *
 * @author Jon South <jsouth@hostgator.com>
 * @package WordPress
 */

/**
 * Joomla class based on {@link Software}
 * @package Joomla
 */
class Type_Joomla_Connection extends Software {
  /**#@+ @var array */
  /** Basic setting storage */
  private $basics = array();
  /** User storage */
  private $users = array();
  /** Theme storage */
  private $themes = array();
  /** Addons storage */
  private $addons = array();
  /**#@-*/

  /**
   * Initialize settings
   *
   * @return void
   */
  public function init() {
    libxml_use_internal_errors(true);
    $this->have(array(
      'basics' => false,
      'users' => false,
      'themes' => false,
      'addons' => false));
  }

################################################################################
################################################################################

  /**
   * Compile and store basic Joomla settings
   */
  public function get_basics() {
    if ($this->have('basics')) return $this->basics;

    $this->basics['db']             = $this->template->setting('db');
    $this->basics['prefix']         = $this->template->setting('dbprefix');

    $this->basics['name']           = $this->template->setting('sitename');
    $this->basics['description']    = $this->template->setting('MetaDesc');
    $this->basics['sessions']       = $this->template->setting('session_handler');
    $this->basics['offline']        = $this->template->setting('offline');
    $this->basics['gzip']           = $this->template->setting('gzip');
    $this->basics['caching']        = $this->template->setting('caching');
    $this->basics['cache_handler']  = $this->template->setting('cache_handler');
    $this->basics['cache_time']     = $this->template->setting('cachetime');
    $this->basics['sef']            = $this->template->setting('sef');
    $this->basics['sef_suffix']     = $this->template->setting('sef_suffix');
    $this->basics['sef_rewrite']    = $this->template->setting('sef_rewrite');
    $this->basics['captcha']        = $this->template->setting('captcha');

    $this->have('basics', true);
    return $this->basics;
  }

  /**
   * Set Joomla configuration options
   *
   * @param string  $key    Option name
   * @param string  $value  Option value
   *
   * @return bool   True on success
   */
  public function set_basics($key, $value) {
    if (!$this->have('basics')) $this->get_basics();
    $this->basics[$key] = $value;
  }

################################################################################
################################################################################

  public function get_themes() {
    if (!$this->have('themes')) $this->pull_themes();
    return $this->themes;
  }

  public function get_users() {
    if (!$this->have('users')) $this->pull_users();
    return $this->users;
  }

################################################################################
################################################################################

  public function get_addons() {
    if (!$this->have('addons')) $this->pull_addons();
    return $this->addons;
  }

  /**
   * Set addons on/off for Joomla 2.5+
   *
   * @param array $on   Array of addons to turn on
   * @param array $off  Array of addons to turn off
   *
   * @return bool True on success
   */
  function set_addons($on = array(), $off = array(), $client = null) {
    if ($this->template->checkVersion('2.5')) {
      $add = '';
      if (!is_null($client))
        $add = sprintf(" AND client_id = %d", (int)$client);

      if ($on)
        if (false === $this->query(
          "UPDATE `%s` SET `checked_out` = 0, `enabled` = 1, ".
          "`checked_out_time` = '0000-00-00 00:00:00' ".
          "WHERE `extension_id` IN (%s)%s;",
          $this->table('extensions'), implode(', ', (array) $on), $add)
        ) $this->owner->fatal('Error during query.');

      if ($off)
        if (false === $this->query(
          "UPDATE `%s` SET `checked_out` = 0, `enabled` = 0, ".
          "`checked_out_time` = '0000-00-00 00:00:00' ".
          "WHERE `extension_id` IN (%s)%s;",
          $this->table('extensions'), implode(', ', (array) $off), $add)
        ) $this->owner->fatal('Error during query.');
    } else
      $this->owner->fatal(sprintf("Version %s is not supported.", $this->core->version));

    return true;
  }

################################################################################
################################################################################

  /**
   * Return theme information
   *
   * @param string $dir     Path to the Joomla root directory for searching
   * @param string $output  Filename for output
   */
  function pull_themes() {
    $this->themes = array();
    if ($this->template->checkVersion('1.6')) {      // 1.6 and up
      if (false === $this->query(
        'SELECT home AS enabled, client_id AS admin, template, title FROM `%s`;',
        $this->table('template_styles'))
      ) $this->owner->fatal('Error during query: '. $this->fetch_error());

      while ($row = $this->fetch_array(MYSQLI_ASSOC)) {
        $file = $this->core->path.DS.((!($row['admin'])) ? '' : 'administrator'.DS).
          'templates'.DS.$row['template'].DS.'templateDetails.xml';

        $xml = (is_file($file)) ? simplexml_load_file($file) : false;
        $this->themes[] = array(
          'enabled'  => (($row['enabled'] == '1') ? true : false),
          'admin'    => (($row['admin'] == '1') ? true : false),
          'template' => $row['template'],
          'version'  => (($xml !== false) ? (string)$xml->version : ''),
          'title'    => $row['title']);
      }
    } elseif ($this->template->checkVersion('1.5')) {  // 1.5.x
      $temp = array();
      $admin = false;
      $targets = array('templates'.DS, 'administrator'.DS.'templates'.DS);
      foreach ($targets as $target) {
        $dir = $this->core->path.DS.$target;
        $h = opendir($dir);
        while (false !== ($item = readdir($h))) {
          if ($item != '.' && $item != '..' && is_dir($dir.DS.$item)) {
            $dh = opendir($dir.DS.$item);
            while (false !== ($subitem = readdir($dh))) {
              if ($subitem != 'templateDetails.xml') continue;

              $xml = simplexml_load_file($dir.DS.$item.DS.$subitem);
              $id = (($admin) ? '1' : '0').'|'.$item;
              $temp[$id] = array(
                'enabled'  => false,
                'admin'    => $admin,
                'template' => $item,
                'version'  => (($xml !== false) ? (string)$xml->version : ''),
                'title'    => (($xml !== false) ? (string)$xml->name : ''));
            }
          }
        }

        $admin = true;
        closedir($h);
      }

      if (false === $this->query(
        "SELECT client_id AS admin, template FROM `%s`;", $this->table('templates_menu'))
      ) $this->owner->fatal('Error during query: '. $this->fetch_error());

      while ($row = $this->fetch_array(MYSQLI_ASSOC)) {
        $file = $this->core->path.DS.((!($row['admin'])) ? '' : 'administrator'.DS).
          'templates'.DS.$row['template'].DS.'templateDetails.xml';

        $xml = (is_file($file)) ? simplexml_load_file($file) : false;
        $id = (int)$row['admin'].'|'.$row['template'];
        $temp[$id] = array(
          'enabled'  => true,
          'admin'    => (($row['admin'] == '1') ? true : false),
          'template' => $row['template'],
          'version'  => (($xml !== false) ? (string)$xml->version : ''),
          'title'    => (($xml !== false) ? (string)$xml->name : ''));
      }

      // Remove key names
      $this->themes = array_values($temp);
    }

    libxml_clear_errors();
    $this->have('themes', true);
  }

  function pull_users() {
    $this->users = array();
    if ($this->template->checkVersion('1.6')) {
      if (false === $this->query(
        "SELECT U.id AS id, U.username AS username, U.name AS display,".
        "U.email AS email, G.title as `group`, M.group_id AS gid,".
        "U.registerDate AS registered, U.lastvisitDate AS visited FROM `%s` as U ".
        "LEFT OUTER JOIN `%s` AS M ON M.user_id = U.id ".
        "LEFT OUTER JOIN `%s` AS G ON G.id = M.group_id;",
        $this->table('users'),
        $this->table('user_usergroup_map'),
        $this->table('usergroups')))
          $this->fatal("Error: Error during query.\n".$this->fetch_error());
    } else
      if (false === $this->query(
        "SELECT U.id AS id, U.username AS username, U.name AS display,".
        "U.email AS email, U.usertype as `group`, '' AS gid,".
        "U.registerDate AS registered, U.lastvisitDate AS visited FROM `%s` as U;",
        $this->table('users')))
          $this->fatal("Error: Error during query.\n".$this->fetch_error());

    if (false === $this->fetch_result())
      $this->fatal("Error: Error during query.\n".$this->fetch_error());

    while ($row = $this->fetch_array(MYSQLI_ASSOC))
      $this->users[] = $row;

    $this->have('users', true);
  }

  /**
   * Return addon information
   */
  function pull_addons() {
    $this->addons =
      array('1.6'=>array(), '1.5'=>array('components'=>array(), 'plugins'=>array()));
    if ($this->template->checkVersion('1.6')) {
      // Joomla 1.6 lists all addons as "extensions"
      $this->addons['1.5'] = null;
      if (false === $this->query(
        "SELECT E.extension_id AS id, E.enabled AS enabled, E.type AS type, ".
        "E.name AS name, E.folder AS folder, E.element AS element, ".
        "E.client_id AS client, E.protected AS protected FROM `%s` AS E ".
        "ORDER BY E.type, E.folder, E.ordering, E.name;",
        $this->table('extensions'))
      ) $this->owner->fatal('Error during query: '. $this->fetch_error());

      while ($row = $this->fetch_array(MYSQLI_ASSOC)) {
        $row['id'] = (int)$row['id'];
        $row['enabled'] = (bool)$row['enabled'];
        $row['client'] = (bool)$row['client'];
        $row['protected'] = (bool)$row['protected'];
        $this->addons['1.6'][] = $row;
      }
    } else {
      $this->addons['1.6'] = null;
      // Components
      if (false === $this->query(
        "SELECT C.id AS id, C.enabled AS enabled, C.name AS name, ".
        "C.option AS `option`, IF(C.link='', 0, 1) AS frontend, ".
        "IF(C.admin_menu_link='', 0, 1) AS backend, C.iscore AS core ".
        "FROM `%s` AS C LEFT OUTER JOIN `%s` AS CC ON CC.id = C.parent ".
        "WHERE C.parent = 0 ORDER BY C.ordering;",
        $this->table('components'),
        $this->table('components'))
      ) $this->owner->fatal('Error during query: '. $this->fetch_error());

      while ($row = $this->fetch_array(MYSQLI_ASSOC)) {
        $row['id'] = (int)$row['id'];
        $row['enabled'] = (bool)$row['enabled'];
        $row['core'] = (bool)$row['core'];
        $row['frontend'] = (bool)$row['frontend'];
        $row['backend'] = (bool)$row['backend'];
        $this->addons['1.5']['components'][] = $row;
      }
      // Plugins
      if (false === $this->query(
        "SELECT P.id AS id, P.published AS published, P.name AS name, ".
        "CONCAT(P.folder,'/',P.element,'.php') AS file, P.client_id AS client, ".
        "P.iscore AS core FROM `%s` AS P ORDER BY P.folder, P.id;",
        $this->table('plugins'))
      ) $this->owner->fatal('Error during query: '. $this->fetch_error());

      while ($row = $this->fetch_array(MYSQLI_ASSOC)) {
        $row['id'] = (int)$row['id'];
        $row['published'] = (bool)$row['published'];
        $row['client'] = (bool)$row['client'];
        $row['core'] = (bool)$row['core'];
        $this->addons['1.5']['plugins'][] = $row;
      }
    }
    $this->have('addons', true);
  }

################################################################################
################################################################################

  /**
   * Save install settings to configuration file.
   *
   * @param array $settings Array of settings by: $key => $value
   */
  public function save($settings = array()) {
    $this->get_basics();

    $basics = $this->basics;
    $config = $this->template->configPath();
    $settings = $this->template->setting('settings', true)['v'];

    if (is_null($basics) || is_null($config) || is_null($settings))
      return false;

    // Import items from set_basics(...)
    $settings['sitename']         = $basics['name'];
    $settings['MetaDesc']         = $basics['description'];
    $settings['session_handler']  = $basics['sessions'];
    $settings['offline']          = $basics['offline'];
    $settings['gzip']             = $basics['gzip'];
    $settings['caching']          = $basics['caching'];
    $settings['cache_handler']    = $basics['cache_handler'];
    $settings['cachetime']        = $basics['cache_time'];
    $settings['sef']              = $basics['sef'];
    $settings['sef_suffix']       = $basics['sef_suffix'];
    $settings['sef_rewrite']      = $basics['sef_rewrite'];
    $settings['captcha']          = $basics['captcha'];

    // Remove imported items
    foreach (array(
      'name','description','sessions','offline','gzip','caching','cache_handler',
      'cache_time','sef','sef_suffix','sef_rewrite','captcha') as $key)
      unset($basics[$key]);

    // Import any extras (e.g. custom settings)
    foreach ($basics as $key => $value)
      $settings[$key] = $value;

    // Write the config
    $output = "<\x3Fphp\nclass JConfig {\n";
    foreach ($settings as $name => $value)
      $output .= sprintf("\tpublic $%s = '%s';\n", $name, $value);
    $output .= "}\n";

    if (@file_put_contents($config, $output) > 0)
      return true;
    else
      return false;
  }
} /* class Joomla */
