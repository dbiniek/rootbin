<?php

class VDetect {
  /** @var SwissArmyKnife */
  private $owner = null;

  public $url = null;
  public $sigurl = null;
  public $remote = true;

  public $bin = null;
  public $sig = null;

  public $paths = array();
  public $users = array();
  public $resellers = array();

  function VDetect(&$owner, $paths = array()) {
    $this->owner = $owner;
    $this->paths = $paths;

    $this->url = SAK_REPO_BASE.'/bin/vdetect.php';
    $this->sigurl = SAK_REPO_BASE.'/bin/signatures.php';

    $this->bin = $owner->path->system(SAK_PATH_BIN).DS.'vdetect.py';
    $this->sig = $owner->path->system(SAK_PATH_CACHE).DS.'signatures.xml';
  }

  /**
   * Run vdetect.
   */
  function run($recurse = false) {
    static $once = false;
    if ($once) return; else $once = true;

    if (!$this->owner->cacheFile('vdetect cache', $this->url, $this->bin, false, 21600, 1, '/^# (\d{10,})$/') ||
      !$this->owner->cacheFile('software signatures', $this->sigurl, $this->sig)) {
      $this->owner->fatal('Unable to update vdetect or signatures.');
      return false;
    }

    if ($this->remote)
      $args = array($_ENV["SAK_PYTHON"], $this->bin, "--sig-loc=".$this->sig, "--dups", "--csv");
    else
      $args = array("vdetect", "--dups", "--csv");

    if (!($recurse))
      $args[] = '--maxdepth=0';

    if (!($this->paths) && !($this->users) && !($this->resellers))
      $args[] = '--directory="."';
    else {
      foreach ($this->paths as $path)
        $args[] = '--directory="'.$path.'"';

      foreach ($this->users as $user)
        $args[] = '--user="'.$user.'"';

      foreach ($this->resellers as $reseller)
        $args[] = '--reseller="'.$reseller.'"';
    }

    $fd = array(0 => array("pipe", "r"), 1 => array("pipe", "w"), 2 => array("pipe", "w"));

    $cmd = implode(' ', $args);
    $proc = proc_open($cmd, $fd, $pipes);

    if (is_resource($proc)) {
      stream_set_blocking($pipes[2], 0);
      if ($err = stream_get_contents($pipes[2])) {
        fclose($pipes[0]);
        fclose($pipes[1]);
        fclose($pipes[2]);
        proc_close($proc);
        $this->owner->fatal('Could not run vdetect. Error:'. $err);
      }

      if ($this->remote) {
        //$this->owner->download->url = $this->url;
        //$vdetect = $this->owner->download->pipe();
        //fwrite($pipes[0], $vdetect);
      }
      fclose($pipes[0]);

      $buffer = stream_get_contents($pipes[1]);
      fclose($pipes[1]);

      $err = stream_get_contents($pipes[2]);
      fclose($pipes[2]);

      $ret = proc_close($proc);
      // TODO: Handle errors
    } else {
      $this->owner->fatal('Could not run vdetect.');
    }

    foreach (explode("\n", $buffer) as $line) {
      if ($line == "") continue;
      list($vuln, $soft, $path, $ver) = explode("\t", $line);
      $this->owner->install[] = new Core($this->owner, $soft, $ver, realpath($path), $vuln);
    }

    uasort($this->owner->install, array($this, 'natversort'));
  }

  /**
   * Used to sort vdetect output by software name, then version
   *
   * @param Core $a First item
   * @param Core $b Second item
   * @return int
   */
  function natversort($a, $b) {
    $n = strnatcasecmp($a->type, $b->type);
    $n = (($n != 0) ? $n : version_compare($a->version, $b->version));
    $n = (($n != 0) ? $n : strnatcasecmp($a->path, $b->path));
    return $n;
  }
}
