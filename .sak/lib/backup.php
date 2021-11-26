<?php

class Backup {
  /** @var SwissArmyKnife */
  private $owner = null;
  /** @var Core */
  public $core = null;

  private $type = null;
  private $source = null;
  private $miss = 0;
  private $basedir = null;

  private $name = null;
  private $ext = null;
  private $timestamp = null;

  public function __construct(SwissArmyKnife $owner, Core $core = null) {
    $this->owner = $owner;
    $this->core = $core;

    $this->timestamp = date('-Y-m-d_H-i-s');
  }

  public function set($type = SAK_BAK_CORE, Array $source = null, $basedir = null) {
    $this->miss = 0;
    $this->source = array();
    $path = $this->core->path;
    switch ($type) {
      case SAK_BAK_CORE:
        $this->name = sprintf('sak-core-%s-%s', $this->core->type, $this->core->version);
        $this->ext = '.tar.gz';
        $this->basedir = $this->owner->path->user($this, SAK_PATH_BACKUP);

        foreach ($this->core->filelist() as $file) {
          if (!file_exists($path.DS.$file) || !is_file($path.DS.$file)) {
            $this->miss++;
            continue;
          }

          $this->source[] = $file;
        }
        break;

      case SAK_BAK_FILE:
        // Check files relative to the install's path
        $path = $this->core->path;
        $this->name = 'sak-file';
        $this->ext = '.tar.gz';
        $this->basedir = $this->owner->path->user($this, SAK_PATH_BACKUP_FILE);

        foreach ($source as $file) {
          $result = $this->core->filename($file, true);
          if ($result === 0) {
            $this->owner->message('Backup', "Not relative to this install: $file", SAK_LOG_WARN);
            continue;
          }

          if (!$this->core->corefile($result)) {
            $this->owner->message('Backup', "Not a core file: $file", SAK_LOG_WARN);
            continue;
          }

          if (!is_string($result)) {
            $this->owner->message('Backup', "Does not exist or not a file: $file", SAK_LOG_WARN);
            continue;
          }

          $this->source[] = $result;
        }
        break;

      case SAK_BAK_DB:
        $this->basedir = $this->owner->path->user($this, SAK_PATH_BACKUP_DB);
        $this->name = 'sak-db';
        $this->ext = '.tar.gz';

        if ($source) {
          foreach ($source as $database)
            $this->source[$database] = array();
        } else {
          $database = $this->core->software()->setting('DB_NAME');
          if ($database === false)
            $this->owner->fatal('Could not determine software database.');

          // TODO: Verify DB exists
          $this->name .= "-$database";
          $this->source = array($database => array());
        }
        break;

      case SAK_BAK_DB_TABLE:
        $this->basedir = $this->owner->path->user($this, SAK_PATH_BACKUP_DB);
        $this->ext = '.tar.gz';

        // TODO: Verify DB & tables exist
        if (count($source) == 0) {
          list($database) = array_keys($source);
          $this->name = "sak-db-$database-tables";
        } else
          $this->name .= "sak-db-tables";

        $this->source = $source;
        break;

      default:
        $this->owner->fatal('Unknown or unsupported backup type was specified.');
    }

    $this->type = $type;
    if (!is_null($basedir))
      $this->basedir = $basedir;

    return true;
  }

  public function exec() {
    if (count($this->source) < 1) {
      $this->owner->message('Backup', "No content to backup.", SAK_LOG_WARN);
      return false;
    }

    if ($this->type & (SAK_BAK_DB | SAK_BAK_DB_TABLE)) {
      $dumps = array();
      foreach ($this->source as $database => $tables) {
        $this->owner->message('Backup', "Exporting database '$database'...", SAK_LOG_INFO);
        if (count($tables) == 0)
          $tables[] = '';

        foreach ($tables as $table) {
          $cmd = escapeshellarg($database);
          if (!empty($table)) {
            $this->owner->message('Backup', "Dumping table '$table'...", SAK_LOG_INFO);
            $cmd .= ' '.escapeshellarg($table);
          } else
            $this->owner->message('Backup', "Dumping all tables...", SAK_LOG_INFO);

          $output = array();
          $return = 0;
          exec('mysqldump --skip-extended-insert '. $cmd, $output, $return);

          if ($return > 0)
            $this->owner->fatal("Database backup failed ($return).");

          $dumps[] = array($database => array($table => implode("\n", $output)));
        }

        umask(022);
        $tar = new Archive_Tar($this->basedir.DS.$this->filename(), 'gz');
        foreach ($dumps as $data)
          foreach ($data as $db => $tables)
            foreach ($tables as $table => $content)
              $tar->addString($db.((!empty($table)) ? "-$table" : "").".sql", $content);
        umask(077);
      }
    } else {
      $cwd = getcwd();
      chdir($this->core->path);

      if ($this->type & SAK_BAK_CORE) {
        $miss = (($this->miss > 0) ? ", ".$this->miss." missing" : "");
        $this->owner->message('Backup', "Backing up ".count($this->source).
                                        " core files$miss...", SAK_LOG_INFO);
      } else
        $this->owner->message('Backup', "Backing up ".count($this->source).
                                        " file".((count($this->source)>1)?'':'s')."...", SAK_LOG_INFO);

      umask(022);
      $tar = new Archive_Tar($this->basedir.DS.$this->filename(), 'gz');
      $tar->add($this->source);
      umask(077);
      chdir($cwd);
    }

    $output = array();
    exec("/bin/ls -l ".escapeshellarg($this->basedir.DS.$this->filename())." 2>/dev/null", $output);
    $this->owner->message('Backup', implode($output), SAK_LOG_INFO);
    $this->owner->message('Backup', "Completed.", SAK_LOG_INFO);
    echo "\n";
    return true;
  }

  private function filename() {
    return $this->name.$this->timestamp.$this->ext;
  }
}
