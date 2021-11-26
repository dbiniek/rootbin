<?php

/**
 * Class for resolving various required paths, such as backups, logs, etc.
 */
class Path {
  /** @var SwissArmyKnife */
  private $owner = null;

  function __construct(SwissArmyKnife $owner) {
    $this->owner = $owner;
  }

  public function system($type) {
    $base = SAK_DIR;
    switch($type) {
      case SAK_PATH_BIN:
        $dir = 'bin';
        break;
      case SAK_PATH_TMP:
        $dir = 'tmp';
        break;
      case SAK_PATH_LOGS:
      default:
        $dir = 'logs';
        break;
      case SAK_PATH_CACHE:
        $dir = 'cache';
        break;
      case SAK_PATH_CORETMP:
        $dir = 'coretmp';
        break;
      case SAK_PATH_FAILSAFE_STOR:
        $dir = 'failsafe';
        break;
    }

    // System directories must always exist
    $this->mkdir($base.DS.$dir, true, 0700);
    return $base.DS.$dir;
  }

  public function user($object, $type, $create = true) {
    $ret = false;
    $base = $dir = $path = '';

    if (property_exists($object, 'core') && property_exists($object->core, 'path'))
      $path = $object->core->path;
    elseif (property_exists($object, 'path'))
      $path = $object->path;
    else
      $path = getcwd();

    $path = realpath($path);
    $pathowner = posix_getpwuid(fileowner($path));

    $match = array();
    if (preg_match('|^(/home\d*)/([^/]+)/(\S+)/?|', $path, $match) === 1) {
      $home = $match[1];
      $user = $match[2];
      $subdir = $match[3];
      $base = $home.DS.$user;
    }

    $match = array();
    if (preg_match('|^(/var/www/vhosts)/([^/]+)/(\S+)/?|', $path, $match) === 1) {
      $home = $match[1];
      $user = $match[2];
      $subdir = $match[3];
      $base = $home.DS.$user;
    }

    switch($type) {
      case SAK_PATH_LOG:
        if (strpos($path, '/var/www/vhosts') === false)
          $dir = 'logs/sak';
        else
          $dir = 'statistics/sak/logs';
        break;
      case SAK_PATH_BACKUP_DB:
        $dir = 'backups/sak/mysql';
        break;
      case SAK_PATH_BACKUP:
      case SAK_PATH_BACKUP_FILE:
      default:
        $dir = 'backups/sak';
    }

    if (empty($base))
      $base = $this->system(SAK_PATH_FAILSAFE_STOR);

    if (($create) && $ret !== false)
      if (!$this->mkdir($ret)) {
        $base = $this->system(SAK_PATH_FAILSAFE_STOR);
        $dir = $user.DS.$dir;
      }

    return $base.DS.$dir;
  }

  private function mkdir($path, $die = false, $mode = 0755) {
    $ret = false;
    if (file_exists($path) && is_dir($path))
      $ret = true;
    else
      $ret = @mkdir($path, $mode, true);

    if ($die === true && $ret === false) {
      debug_print_backtrace();
      $this->owner->fatal('Could not create directory: '. $path);
    }

    return $ret;
  }
}
