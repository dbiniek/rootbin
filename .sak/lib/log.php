<?php

class Log {
  /** @var SwissArmyKnife */
  private $owner = null;

  private $open = false;

  private $path = '';
  private $file = '';
  private $stamp = '';
  private $ext = '';

  function init(SwissArmyKnife $owner, $name, $type, $ts = true, $overwrite = false) {
    $this->owner = $owner;
    $this->path = $owner->path->guess($owner, SAK_PATH_LOG | SAK_PATH_USER);
    $this->stamp = date("Y-m-d_H-i-s");

    $i = 0;
    while (
      ($fullpath = $this->path . $this->file . $this->stamp . $this->ext) &&
      file_exists($fullpath)
    ) {
      $this->stamp = date("Y-m-d_H-i-s").'.'.getmypid().($i++>0?".$i":"");
    }
    if ($overwrite) {
      $handle = fopen($fullpath, 'w');
      fclose($handle);
    }
  }

  public function write($data, $ts = true) {

  }

  public function close() {

  }
}
