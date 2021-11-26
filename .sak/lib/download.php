<?php

class Download {
  /** @var SwissArmyKnife */
  private $owner = null;
  private $snoopy = null;
  private $user_agent = '';

  public $base = null;

  public $url = null;
  public $target = null;

  public $available = array();
  public $cache = null;
  public $coretmp = null;
  public $expired = true;

  function __construct(SwissArmyKnife $owner) {
    $this->owner = $owner;
    $this->base = SAK_REPO_BASE_SOFT;
    $this->user_agent =
      sprintf('Swiss-Army-Knife/%s T:%s E:sak-php S:%s M:Snoopy',
        $this->owner->version, $this->owner->timestamp, $this->owner->session);

    $this->snoopy = new Snoopy;
    $this->snoopy->agent = &$this->user_agent;
    $this->snoopy->read_timeout = 5;

    //$this->coretmp = SAK_DIR .'/coretmp';
    $this->coretmp = $owner->path->system(SAK_PATH_CORETMP);
    $this->cache = $this->coretmp.DS.'available.cache';
  }

  function check() {
    if (!$this->owner->cacheFile('available core installations', sprintf('%s/available.php', $this->base), $this->cache)) {
      $this->owner->fatal('Unable to update available cache.');
      return false;
    }

    $cache = file_get_contents($this->cache);
    $lines = explode("\n", $cache);
    array_shift($lines);

    foreach ($lines as $line) {
      if ($line == "") continue;
      list($type, $version) = explode('-', $line);
      $this->available[$type][] = $version;
      $this->available[$type][$version] = true;
    }
    return true;
  }

  function exec($overwrite = false) {
    if (is_null($this->target) || is_null($this->url))
      return false;

    $dir = dirname($this->target);

    if (!is_dir($dir))              // Check if the parent directory exists
      if (!mkdir($dir, 0755, true)) // Attempt to create it
        return false;

    if (!is_writable($dir)) // Check that we can write here
      return false;

    if (file_exists($this->target) && !($overwrite))
      return true;

    if (!preg_match('|://|', $this->url))
      $this->url = $this->base .'/'. $this->url;

    if (($fd = fopen($this->target, 'w')) === false)
      return false;

    if (($buffer = $this->pipe()) === false) {
      fclose($fd);
      return false;
    }

    if (fwrite($fd, $buffer) === false) {
      fclose($fd);
      return false;
    }

    fclose($fd);

    $this->url = null;
    $this->target = null;

    return true;
  }

  function pipe($url = null) {
    if (!is_null($url))
      $this->url = $url;

    if (is_null($this->url))
      return false;

    if (!preg_match('|://|', $this->url))
      $url = $this->base .'/'. $this->url;
    else
      $url = $this->url;

    if (!$this->snoopy->fetch($url) || $this->snoopy->status != 200)
      return false;

    $this->url = null;
    $this->target = null;

    return $this->snoopy->results;
  }

  function set($URL, $target = null) {
    $this->url = $URL;
    $this->target = $target;
  }

  function get($software, $version, $type = "install", $filename = null, $pipe = false) {
    if (is_null($filename)) {
      $ext = '';
      switch ($type) {
        case 'checksum': $type = 'checksums';
        case 'checksums': $ext = '.md5.gz'; $mtype = $type; break;

        case 'install': $type = 'installs';
        case 'installs': $ext = '.tar.gz'; $mtype = 'installation'; break;
      }

      $filename = $type.'/'.$software.'/'.$software.'-'.$version.$ext;
      if (file_exists($target = $this->coretmp.'/'.$filename))
        return $target;

      $this->owner->message('Downloading',
        'Downloading '.ucfirst($software).' '.$version.' '.$mtype.'...');

      $this->set($this->base.'/'.$filename, $target);
    } else {
      $this->set(
        sprintf('%s/%s/%s/%s-%s/%s', $this->base, 'source', $software,
                $software, $version, $filename),
        (($filename[0] == '/') ? $filename : getcwd().'/'.$filename));
    }

    if ($pipe === false) {
      if ($this->exec())
        return $target;
    } else
      return $this->pipe();

    return false;
  }

  function testRepo($args) {
    array_shift($args);

    $vars = array(
      'host' => php_uname('n'),
      'addr' => trim(`hostname -i`, "\n"),
      'user' => ((array_key_exists('RUSER', $_ENV)) ? $_ENV['RUSER'] : SAK_SID),
      'path' => getcwd(),
      'name' => SAK_BASENAME,
      'args' => (($args) ? "'".implode("' '", $args)."'" : ""),
      'info' => "PHP-".phpversion()." ".php_sapi_name());
    $this->snoopy->submit(SAK_REPO_BASE."/software/ping.php", $vars);

    if ($this->snoopy->status == "200")
      return true;
    return false;
  }
}
