<?php

abstract class Type_Template extends Lib {
  /** @var SwissArmyKnife */
  //protected $owner = null;
  /** @var Core */
  protected $core = null;
  /** @var Software */
  protected $connection = null;

  protected $config = 'config.php';
  protected $settings = null;

  public function __construct(SwissArmyKnife $owner, Core $core) {
    parent::__construct($owner);
    $this->core = $core;
  }

  public function setting($key = null, $other = false) {
    if (is_null($this->settings)) {
      if ($this->config[0] == '/') {
        trigger_error('Config path was not relative.', E_USER_WARNING);
        $this->settings = sak_get_all_php_option($this->config);
      } else
        $this->settings = sak_get_all_php_option($this->core->path.DS.$this->config);
    }

    if ($this->settings === false) return null;

    if ($other)  {
      switch ($key) {
        case 'config':
          return $this->config;
        case 'settings':
          return $this->settings;
        case 'variables':
          if (array_key_exists('v', $this->settings))
            return $this->settings['v'];
          else return null;
        case 'defines':
          if (array_key_exists('d', $this->settings))
            return $this->settings['d'];
          else return null;
      }
    }

    if (is_null($key)) return null;

    if (array_key_exists('v', $this->settings) && array_key_exists($key, $this->settings['v']))
      return $this->settings['v'][$key];

    if (array_key_exists('d', $this->settings) && array_key_exists($key, $this->settings['d']))
      return $this->settings['d'][$key];

    return null;
  }

  /**
   * Returns if the current version is greater or equal to the specified version
   *
   * @param string $required The required version
   * @return bool  True if equal or greater to {@link $required}
   */
  public function checkVersion($required) {
    return version_compare($this->core->version, $required, '>=');
  }

  /**
   * Return full path to configuration file
   */
  public function configPath() {
    if (!is_null($this->config))
      return $this->core->path.DS.$this->config;
    else
      return null;
  }

  abstract public function command($args = array());
}
