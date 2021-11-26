<?php

class Core {
  /** @var SwissArmyKnife */
  private $owner = null;
  /** @var Sofware */
  private $software = null;
  public $temp = null;

  public $vuln = null;
  public $path = null;
  public $type = null;
  public $version = null;

  public $available = null;
  public $local = false;

  public $package = null;   // Path to install file
  public $checksums = null; // Path to checksums

  function Core(SwissArmyKnife $owner, $type = null, $version = null, $path = null, $vuln = null) {
    $this->owner = $owner;
    $this->temp = $this->owner->path->system(SAK_PATH_CORETMP);

    $this->type = $type;
    $this->vuln = $vuln;
    $this->path = $path;
    $this->version = $version;

    if (!is_null($type) && !is_null($version))
      $this->check();
  }

  static public function pName($name, $exact = false) {
    switch (strtolower($name)) {
      case 'joomla':    return 'Joomla';
      case 'wordpress': return 'WordPress';
    }

    if ($exact) return false;

    return $name;
  }

  static public function pVuln($id) {
    switch ($id) {
      default:
      case -1: return  "\33[1m Unknown  \33[0m";
      case 0:  return "\33[32mUp-to-date\33[0m";
      case 1:  return "\33[34m Outdated \33[0m";
      case 2:  return "\33[31mVulnerable\33[0m";
    }
  }

  /**
   *  Check filename of this install.
   *
   *  Given any file or directory path either relative or absolute, determine if
   *  it is part of this installation. Return the real absolute (or relative)
   *  path.
   *
   *  Does not verify if filename is a core file.
   *
   *  @param string $name     File or directory path
   *  @param bool   $relative Set to true to return a relative path.
   *
   *  @return mixed The file path. False if not exists. 0 if not part of this install.
   */
  function filename($name, $relative = false) {
    $path = $this->path;
    $name = (substr($name, -1) == '/') ? substr($name, 0, -1) : $name;

    if ($name[0] == '/') {  // Absolute
      if (!file_exists($name)) return false;
      $name = realpath($name);
      if (strpos($name, $path) !== 0) return 0;   // Not in this install
    } else {                // Relative
      if (!file_exists($path.DS.$name)) return false;
      $name = realpath($path.DS.$name);
    }

    return ($relative) ? substr($name, strlen($path)+1) : $name;
  }

  function corefile($name) {
    $path = $this->path;
    $name = (substr($name, -1) == '/') ? substr($name, 0, -1) : $name;

    if ($name[0] == '/') {  // Absolute
      if (file_exists($name))
        $name = realpath($name);
      if (strpos($name, $path) !== 0) return 0;   // Not in this install
      substr($name, strlen($path)+1);
    } else                  // Relative
      if (file_exists($path.DS.$name))
        $name = substr(realpath($path.DS.$name), strlen($path)+1);

    return in_array($name, $this->filelist());
  }

  function software() {
    if (is_null($this->software)) {
      if (($class = self::pName($this->type, true)) === false)
        return false;

      $class = "Type_".$class;
      try {
        $this->software = new $class($this->owner, $this);
      } catch (Exception $e) {
        return false;
      }
    }

    return $this->software;
  }

  function download($force = false) {
    if (!$this->check())
      $this->owner->fatal('Core install and/or checksums are not available or could not be downloaded.');

    if ($this->package === false || $this->checksums === false)
      return false;

    if (!is_null($this->package) && !is_null($this->checksums))
      return true;

    $install = $this->owner->download->get($this->type, $this->version, 'install');
    $checksum = $this->owner->download->get($this->type, $this->version, 'checksum');

    $this->package = $install;
    $this->checksums = $checksum;

    if ($install === false || $checksum === false)
      $this->owner->fatal('Unable to download core install and/or checksums.');

    return true;
  }

  function get($filename) {
    return $this->owner->download->get($this->type, $this->version, "source", $filename, true);
  }

  function check() {
    if (!is_null($this->available)) return $this->available;

    if (is_null($this->type) || is_null($this->version)) return $this->available = false;

    if (!$this->owner->download->check()) return $this->available = false;

    if (in_array($this->type, array_keys($this->owner->download->available)) &&
        isset($this->owner->download->available[$this->type][$this->version]))
      return $this->available = true;

    return $this->available = false;
  }

  function filelist($dirs = false) {
    $this->download();
    $files = array();
    if ($dirs === false) {
      $sums = gzfile($this->checksums);

      foreach ($sums as $sum) {
        if ($sum == "") continue;
        $md5 = $file = "";
        sscanf($sum, "%s  %[^\n]", $md5, $file);
        $files[] = $file;
      }
    } else {
      $tar = new Archive_Tar($this->package, true);
      $tmp = $tar->listContent();
      foreach ($tmp as $file)
        $files[] = $file['filename'];
    }

    return $files;
  }

  function checksum() {
    $this->download();
    $this->owner->message('Checksum', 'Verifying core files...');
    $sums = gzfile($this->checksums);
    $files = array();
    $fail = 0;
    $miss = 0;

    foreach ($sums as $sum) {
      if ($sum == "") continue;

      $md5 = $file = "";
      sscanf($sum, "%s  %[^\n]", $md5, $file);
      if (file_exists($this->path.DS.$file)) {
        if ($md5 != md5_file($this->path.DS.$file)) {
          $files[$file] = false;
          $fail++;
        } else
          $files[$file] = true;
      } else {
        $files[$file] = null;
        $miss++;
      }
    }

    ksort($files);
    if ($fail || $miss)
      $this->owner->message('Checksum', sprintf('Checksum failed on %d file(s) with %d missing', $fail, $miss));
    $this->owner->message('Checksum', sprintf('Total files checked: %d', count($files)));
    return $files;
  }

  function backup($type = SAK_BAK_CORE, Array $source = array(), $basedir = null) {
    $this->download();
    $backup = new Backup($this->owner, $this);
    $backup->set($type, $source, $basedir);
    return $backup->exec();
  }

  function checkFiles() {
    $sums = $this->checksum();
    $files = array_keys($sums);

    $pass = 0;
    $miss = array();
    $fail = array();

    foreach ($files as $file)
      if ($sums[$file] === true)      $pass++;
      elseif (is_null($sums[$file]))  $miss[] = $file;
      elseif ($sums[$file] === false) $fail[] = $file;

    $output = sprintf(
      "\n\33[1mChecked %d total files.\n  %d files passed, %d failed, and %d missing.\33[0m\n\n",
      count($files), $pass, count($fail), count($miss));

    if ($miss)
      $output .= "\33[31mMissing Files:\33[0m\n". implode("\n", $miss)."\n\n";
    else
      $output .= "\33[31mNo missing files.\33[0m\n\n";

    if ($fail)
      $output .= "\33[33mChecksum Failed:\33[0m\n". implode("\n", $fail)."\n\n";
    else
      $output .= "\33[33mNo failed checksum files.\33[0m\n\n";

    return $output;
  }

  function diff($files = null, $coarse = true) {
    $realpath = realpath($this->path)."/";
    $all = (is_null($files) || count($files) == 0)?true:false;
    $sums = $this->checksum();
    $checked = array_keys($sums);
    if ($all) $files = array_keys($sums);
    $check_files = array();
    echo "\n";

    // Preliminary checks
    $miss = array();
    $fail = array();

    foreach ($files as $file) {
      if (!($all)) {
        if (!file_exists($this->path.DS.$file)) {
          $this->owner->message('Diff', "File does not exist: $file", SAK_LOG_ERROR);
          continue;
        }
        $filepath = realpath($this->path.DS.$file);
        if (strpos($filepath, $realpath) !== 0) {
          $this->owner->message('Diff', "Not relative to current path: $file", SAK_LOG_ERROR);
          continue;
        } else
          $file = substr($filepath, strlen($realpath));
      }
      if (!in_array($file, $checked)) {
        if (!is_file($this->path.DS.$file))
          $this->owner->message('Diff', "Not a file: $file", SAK_LOG_WARN);
        else
          $this->owner->message('Diff', "Not a core installation file: $file", SAK_LOG_WARN);
        continue;
      } else {
        if ($sums[$file] === true) {
          if (!($all))
            $this->owner->message('Diff', "No differences: $file");
          continue;
        }
        if (is_null($sums[$file])) {
          $miss[] = $file;
          continue;
        }
        if ($sums[$file] === false)
          $fail[] = $file;
      }
      if (!preg_match('/\.(?:css|html?|js|php|txt|xml)$/', $file)) {
        if (!($all))
          $this->owner->message('Diff', "Cannot generate diff for: $file", SAK_LOG_WARN);
        continue;
      }
      $check_files[] = $file;
    }

    if (!$check_files) return '';

    // Summary
    $output = '';
    if ($all) {
      $output .= sprintf("File differences for %s %s at %s\n\n", $this->type, $this->version, $this->path);
      $output .= "NOTE: Files that fail but do not show a diff only have changes in whitespace characters.\n\n";
      if ($miss) {
        $output .= "\33[31mMissing Files:\33[0m\n";
        $output .= implode("\n", $miss)."\n\n";
      }
      if ($fail) {
        $output .= "\33[33mChecksum Failed:\33[0m\n";
        $output .= implode("\n", $fail)."\n\n";
      }
    }
    $output .= "\33[34mFile differences:\33[0m\n";

    if ($all) {
      if ($coarse)
        $this->owner->message('Diff', "Generating unified diff");
      else
        $this->owner->message('Diff', "Generating detailed diff");
    }

    if (!($coarse) && count($check_files) > 2)
        $this->owner->message('Diff', "\33[1mWarning\33[0m: Detailed reports may be slow to create. You may press CTRL+C to abort at any time.\n", SAK_LOG_WARN);

    $callback = array('self', (($coarse)?'systemDiff':'fineDiff'));
    foreach ($check_files as $file) {
      $this->owner->message('Diff', "Processing file: $file");
      if (($source = $this->get($file)) === false) {
        $this->message('Diff', "Could not download source for `$file'", SAK_LOG_ERROR);
        continue;
      }

      if (($buffer = call_user_func($callback, $source, $file)) !== false)
        $output .= $buffer;
      else
        $this->fatal('Error during diff generation.');
    }

    return $output;
  }

  function orphans() {
    $this->download();

    $e = "\033[%sm";
    $colors = array('bd'=>'','di'=>'','cd'=>'','ln'=>'','or'=>'','so'=>'','pi'=>'',);
    if (!isset($_ENV['LS_COLORS']));
      $_ENV['LS_COLORS'] =
        'no=00:fi=00:di=01;34:ln=01;36:pi=40;33:so=01;35:do=01;35:bd=40;33;01:'.
        'cd=40;33;01:or=40;31;01:su=37;41:sg=30;43:tw=30;42:ow=34;42:st=37;44:'.
        'ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:'.
        '*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:'.
        '*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:'.
        '*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:'.
        '*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:'.
        '*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:'.
        '*.flac=01;35:*.mp3=01;35:*.mpc=01;35:*.ogg=01;35:*.wav=01;35:';

    foreach (explode(':', $_ENV['LS_COLORS']) as $item) {
      if (!$item) continue;
      list($n, $v) = @explode('=', $item);
      $colors[$n] = $v;
    }

    $tar = new Archive_Tar($this->package);
    $this->owner->message('Orphans', 'Reading core package...');
    $items = $tar->listContent();
    $orphans = array();
    $dirs = array('./');
    $files = array();
    foreach ($items as $item) {
      if ($item['typeflag'] == 5)
        $dirs[] = rtrim($item['filename'], '/');
      else
        $files[] = $item['filename'];
    }

    $l = array('l'=>2,'u'=>6,'g'=>6,'s'=>3);
    $this->owner->message('Orphans', 'Locating orphaned files...');
    foreach ($dirs as $dir) {
      if (!is_dir($dir)) continue;
      if ($fd = @opendir($dir)) {
        $dir = (($dir == './') ? $dir = '' : $dir.'/');
        while (($file = readdir($fd)) !== false) {
          if ($file == '.' || $file == '..' || ($dir == '' && is_dir($file)))
            continue;
          $fullname = $dir.$file;
          if (!is_dir($fullname) && in_array($fullname, $files) ||
              is_dir($fullname) && in_array($fullname, $dirs))
            continue;
          if (is_link($fullname)) {
            $info = array_merge(array('name'=>$fullname), lstat($fullname));
          } else
            $info = array_merge(array('name'=>$fullname), stat($fullname));

          $info['strmode'] = self::strMode($info['mode']);
          $u = posix_getpwuid($info['uid']);
          $g = posix_getgrgid($info['gid']);
          $info['user'] = $u['name'];
          $info['group'] = $g['name'];

          $orphans[] = $info;
          // Widths for format string below
          $ll = floor(log10($info['nlink']))+1;
          $lu = strlen($info['user']);
          $lg = strlen($info['group']);
          $ls = floor(log10($info['size']))+1;
          $l['l'] = ($ll>$l['l'])?$ll:$l['l'];
          $l['u'] = ($lu>$l['u'])?$lu:$l['u'];
          $l['g'] = ($lg>$l['g'])?$lg:$l['g'];
          $l['s'] = ($ls>$l['s'])?$ls:$l['s'];
        }
        closedir($fd);
      }
    }

    if (!$orphans) {
      $this->owner->message('Orphans', 'No orphaned files found.');
      return;
    }

    uasort($orphans, array('self', 'fileSort'));

    $fmt = "%s %{$l['l']}d %-{$l['u']}s %-{$l['g']}s %{$l['s']}d %s %s\n";
    echo "\n";
    foreach ($orphans as $file) {
      $filename = $file['name'];
      $mode = $file['strmode'];
      $c = $this->getFileColor($mode, basename($filename), $colors);

      $filename = sprintf($e, $c) .$file['name']. sprintf($e, '0');
      if ($mode[0] == 'l') {
        $link = readlink(basename($file['name']));
        $c = $this->getFileColor('f', $link, $colors);
        $filename = sprintf('%s -> %s', $filename, sprintf($e, $c) .$link. sprintf($e, '0'));
      }

      if ($c)
        $filename = sprintf('%s', sprintf($e, $v) .$filename. sprintf($e, '0'));

      printf($fmt,
        $mode, $file['nlink'], $file['user'], $file['group'], $file['size'], date("Y-m-d H:i:s", $file['mtime']), $filename);
    }
  }

  function getFileColor($mode, $filename, $colors) {
    switch ($mode[0]) {
      case 'b': return $colors['bd'];
      case 'd': return $colors['di'];
      case 'c': return $colors['cd'];
      case 'l': if (file_exists(readlink($filename)))
                  return $colors['ln'];
                else
                  return $colors['or'];
      case 's': return $colors['so'];
      case 'p': return $colors['pi'];
      case 'f':
      case '-': $r = '';
                foreach ($colors as $n => $v)
                  if ($n[0] == '*' && fnmatch($n, $filename))
                    $r = $v;
                return $r;
    }
  }

  public static function massReplace(SwissArmyKnife $owner, $args = array()) {
    $defaced = false;
    $os = "Dh";
    $ol = array("defacements","help");

    // TODO: Probably does not need KEEP
    $mask = (SAK_GETOPT_QUIET | SAK_GETOPT_ARGS_KEEP | SAK_GETOPT_ARGS_LOWERCASE);
    $getopt = $owner->getopt;

    if ($getopt->parse($args, $owner->name, $os, $ol, $mask) === false)
      $owner->stop(1);

    while (true) {
      switch ($arg = $args[0]) {
        case '-D':
        case '--defacements':
          $defaced = true;
          break;
        case '-h':
        case '--help':
          break;
        case '--': array_shift($args); break 2;
        default:
          $owner->fatal("Unknown argument `$arg'");
          break 2;
      }
      array_shift($args);
    }

    $installs = $owner->install;
    $skip = array();
    foreach ($installs as $i => $install)
      if (($dupes = $owner->findDupe($i)) !== false)
        foreach ($dupes as $n)
          $skip[$n] = true;

    echo "\n";
    $title = "\e[1;33mMass Replace\e[0m";
    $owner->message($title, sprintf('Found %d potential installations.', count($installs)));
    if ($skip) {
      echo "\n";
      $owner->message('Warning', 'Duplicate installations to be skipped:', SAK_LOG_WARN);
      $owner->listing(array_keys($skip));
      foreach ($skip as $i => $g)
        unset($installs[$i]);

      echo "\n";
      $message =
        sprintf("Replace %d total installations? (\e[4mY\e[0mes/\e[4mN\e[0mo/\e[4mL\e[0misting) [y/n/L] ", count($installs));
    } else
      $message = "Continue? (\e[4mY\e[0mes/\e[4mN\e[0mo/\e[4mL\e[0misting) [y/n/L] ";

    while (true) {
      $answer = strtolower($owner->prompt($title, $message, '/^[yYnNqQlL]?$/'));
      switch($answer) {
        case 'n':
        case 'q':
          $owner->message($title, 'Exiting without making any changes.');
          echo "\n";
          $owner->stop();
          break;
        case 'l':
        default:
          echo "\n";
          $owner->message('Replace', 'The following installs were found:');
          $owner->listing(array_keys($installs));
          echo "\n";
          $message = "Continue? (\e[4mY\e[0mes/\e[4mN\e[0mo/\e[4mL\e[0misting) [y/n/L] ";
          break;
        case 'y':
          echo "\n";
          break 2;
      }
    }

    foreach ($owner->install as $i => $install) {
      if (isset($skip[$i])) continue;
      echo "\n\n";
      $owner->message($title, sprintf("\e[1mSwitching to %s version %s at %s\e[0m", Core::pName($install->type), $install->version, $install->path));
      $install->replace(array(), $defaced);
    }
    echo "\n";
    $owner->message($title, 'Complete.');
  }

  function replace($args = array(), $defacements = false) {
    $user = $group = '';
    $mode = 0644;
    $names = array();
    $defaced = $yes = false;
    $os = "Dghjm:n:t:u:v:wy";
    $ol = array("defacements","help","group:","joomla","mode:","named:","schema:","type:","user:","version:","wordpress","yes");

    $mask = (SAK_GETOPT_QUIET | SAK_GETOPT_ARGS_KEEP | SAK_GETOPT_ARGS_LOWERCASE);
    $getopt = $this->owner->getopt;

    if ($getopt->parse($args, $this->owner->name, $os, $ol, $mask) === false)
      $this->owner->stop(1);

    while (true && !($defacements)) {
      switch ($arg = $args[0]) {
        case '-u':
        case '--user': array_shift($args);
          $user = $args[0];
          if (posix_getpwnam($user) === false)
            $this->owner->fatal("Not a valid user name: $user");
          break;
        case '-g':
        case '--group': array_shift($args);
          $group = $args[0];
          if (posix_getgrnam($group) === false)
            $this->owner->fatal("Not a valid group name: $group");
          break;
        case '-m':
        case '--mode': array_shift($args);
          $mode = trim($args[0]);
          if (!is_numeric($mode) || !is_octal($mode))
            $this->owner->fatal("Mode not a number or not octal: $mode");
          else
            $mode = octdec($mode);

          if ($mode > 0777)
            $this->owner->fatal(sprintf("Mode %04o is above max value of 0777.", $mode));

          if (!($mode & 0400))
            $this->owner->fatal(sprintf("Mode %04o must at least include user+read (0400).", $mode));
          break;
        case '-w':
        case '--wordpress':
          $this->type = 'wordpress';
          $this->available = null;
          break;
        case '-j':
        case '--joomla':
          $this->type = 'joomla';
          $this->available = null;
          break;
        case '-t':
        case '--type': array_shift($args);
          $this->type = strtolower($args[0]);
          if (!array_key_exists($this->type, $this->owner->download->available))
            $this->owner->fatal(sprintf("Not a valid/supported software type: `%s'", $this->type));

          $this->available = null;
          break;
        case '-v':
        case '--version': array_shift($args);
          $this->version = $args[0];
          if (strpos($this->version, '.') === false)
            $this->owner->fatal(sprintf("Not a valid version number: `%s'", $this->version));

          $this->available = null;
          break;
        case '--schema': array_shift($args);
          if ($this->type != 'wordpress')
            $this->owner->fatal('Schema argument is only valid for WordPress software.');

          $schema = trim($args[0]);
          if (!is_numeric($schema))
            $this->owner->fatal(sprintf("Schema argument is not a valid number: `%s'", $schema));

          $schema = (int)$schema;
          $this->owner->message('Replace', 'Querying repository for versions based on schema...');
          $result = $this->owner->download->pipe(
            sprintf(SAK_REPO_BASE.'/software/installs/wordpress/ver_lookup.php?schema=%d', $schema));

          if ($result === false || $result == '')
            $this->owner->fatal(sprintf("Could not determine supported version based on schema %d", $schema));

          $version = explode(' ', $result);
          $this->version = $version[0];
          $this->owner->message('Replace', sprintf('%d versions found for schema %d', count($version), $schema));
          $this->owner->message('Replace', sprintf('Selecting version %s', $this->version));
          break;
        case '-n':
        case '--named': array_shift($args);
          $names[] = $args[0];
          break;
        case '-D':
        case '--defacements':
          $defaced = true;
          break;
        case '-y':
        case '--yes':
          $yes = true;
          break;
        case '-h':
        case '--help':
          break;
        case '--': array_shift($args); break 2;
        default:
          $this->owner->fatal("Unknown argument `$arg'");
          break 2;
      }
      array_shift($args);
    }

    if (is_null($this->type) || is_null($this->version))
      $this->owner->fatal('No supported software was found and/or software information not provided.');

    if (!array_key_exists($this->version, $this->owner->download->available[$this->type]))
      $this->owner->fatal(sprintf("Not a valid/supported software version: `%s-%s'", Core::pName($this->type), $this->version));

    if (empty($user)) {
      if (preg_match('|^/home\d*/\S+|', $this->path))
        list($g, $g, $user, $g) = explode('/', $this->path, 4);
      else
        $user = fileowner($this->path);
    }

    if (empty($group) || posix_getgrnam($group) === false) {
      $uinfo = posix_getpwnam($user);
      $ginfo = posix_getgrgid($uinfo['gid']);
      $group = $ginfo['name'];
    }

    $files = $this->filelist();
    if ($defacements) {
      $args = array();
      $defaced = true;
      $yes = true;
    }

    if ($names)
      foreach ($files as $file)
        foreach ($names as $match)
          if (fnmatch($match, preg_replace('|^.*/|', '', $file)))
            $args[] = $file;

    if ($defaced) {
      $config = $this->owner->path->system(SAK_PATH_CACHE).DS.'replace.conf';
      if (!$this->owner->cacheFile('defacement signatures', SAK_REPO_BASE_SOFT.'/replace.conf', $config, false, 21600, null))
        $this->owner->fatal('Unable to update defacement information.');

      $sect = '';
      $regex = array();
      $lines = file($config, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
      foreach ($lines as $line) {
        if (trim($line) == '') continue;
        if (preg_match('/\[(\S+)\]/', $line, $subs)) {
          $sect = $subs[1];
          continue;
        }
        if ($sect == $this->type) $regex[] = str_replace('/', '\/', $line);
      }

      foreach ($files as $file)
        foreach ($regex as $re)
          if (preg_match("/$re/", $file))
            $args[] = $file;
    }

    if ($this->owner->verbose(0)) echo "\n";

    if (!$args) {
      if (!$this->backup())
        $this->owner->fatal('Backup failed.');

      $this->owner->message('Replace', "Replacing ".count($files)." files.", SAK_LOG_INFO, 0);
      return $this->replaceAllFiles($user, $group, $mode);
    } else
      $args = array_unique($args);

    if (!($yes) && ($names || $defaced)) {
      $this->owner->message('Replace', count($args).' files to be replaced.');
      if (count($args) <= 10) {
        $this->owner->message('Replace', 'The following files are marked for replacement:');
        $this->owner->message('File', $args);
      }
      while (true) {
        $answer = strtolower($this->owner->prompt('Replace',
          "Continue? (\e[4mY\e[0mes/\e[4mN\e[0mo/\e[4mL\e[0misting) [y/n/L] ", '/^[yYnNqQlL]?$/'));
        switch($answer) {
          case 'n':
          case 'q':
            $this->owner->message('Replace', 'Exiting without making any changes.');
            echo "\n";
            $this->owner->stop();
            break;
          case 'l':
          default:
            echo "\n";
            $this->owner->message('Replace', 'The following files are marked for replacement:');
            $this->owner->message("\e[1;33mFile\e[0m", $args);
            echo "\n";
            break;
          case 'y':
            echo "\n";
            break 2;
        }
      }
    }

    return $this->replaceFiles($args, $user, $group, $mode);
  }

  function replaceFiles($files = array(), $owner = '', $group = '', $mode = 0644) {
    $rfiles = $efiles = array();
    $path = $this->path;
    foreach ($files as $file) {
      $result = $this->filename($file, true);
      if ($result === 0) {
        $this->owner->message('Replace', "Not relative to this install: $file", SAK_LOG_WARN);
        continue;
      }

      if (!$this->corefile($result)) {
        $this->owner->message('Replace', "Not a core file: $file", SAK_LOG_WARN);
        continue;
      }

      if (is_string($result))
        $efiles[] = $result;

      $rfiles[] = $file;
    }

    // Make a backup of the files before replace
    $this->backup(SAK_BAK_FILE, $efiles);
    $this->owner->message('Replace', "Replacing ".count($rfiles)." files.", SAK_LOG_INFO, 0);

    // Replace individual files
    foreach ($rfiles as $replace)
      $this->replaceSingleFile($replace);

    $this->owner->message('Replace', 'Complete.');
  }

  function replaceSingleFile($file, $owner = '', $group = '', $mode = 0644) {
    $path = $this->path;
    $exists = file_exists($path.DS.$file);

    // Download file content
    if (($cache = $this->get($file)) === false)
      $this->owner->fatal('Could not download file contents from repository: '.$file);

    $this->owner->message('Replacing', "$file  (".strlen($cache).")", SAK_LOG_INFO, 2);
    $dir = dirname($file);

    // Create any subdirectories
    if ($exists === false && $dir != '.' && $dir != '..')
      // Add +x to any +r, e.g. 0640 becomes 0750
      mkdir($path.DS.$dir, (((0444 & $mode) >> 2) | $mode), true);

    // Write data
    file_put_contents($path.DS.$file, $cache);

    // Update ownership and perms only if file didn't exist
    if ($exists === false) {
      $this->owner->message('Replace', "Correcting permissions of $file", SAK_LOG_INFO, 2);
      chmod($path.DS.$file, $mode);
      chown($path.DS.$file, $owner);
      chgrp($path.DS.$file, $group);
    }
  }

  function replaceAllFiles($user = '', $group = '', $mode = 0644) {
    $corefiles = $this->filelist(true);
    $path = $this->path;
    $info = array();

    // Store stat info about the files we're replacing
    foreach ($corefiles as $index => $file) {
      if (file_exists($path.DS.$file))
        $info[$index] = array(
          'u' => fileowner($path.DS.$file),
          'g' => filegroup($path.DS.$file),
          'm' => fileperms($path.DS.$file));
      else
        $info[$index] = array(
          'u' => $user,
          'g' => $group,
          'm' => ($file[(strlen($file)-1)] == '/') ?
            // Directories: Add +x to any +r, e.g. 0640 becomes 0750
            (((0444 & $mode) >> 2) | $mode) : $mode);
    }

    // Extract directly over our install path
    $tar = new Archive_Tar($this->package, true);
    $tar->extract($path);

    // Correct ownership and perms
    $this->owner->message('Replace', "Correcting file permissions.", SAK_LOG_INFO);
    foreach ($corefiles as $index => $file) {
      $this->owner->message('Replace', "Correcting permissions of $file", SAK_LOG_INFO, 2);
      chown($path.DS.$file, $info[$index]['u']);
      chgrp($path.DS.$file, $info[$index]['g']);
      chmod($path.DS.$file, $info[$index]['m']);
    }
    $this->owner->message('Replace', 'Complete.');
  }

  static function fineDiff($source, $file) {
    include_once 'finediff.php';
    static $diff = null;
    if (is_null($diff)) $diff = new FineDiff();

    $buffer = "\33[33m!!! $file\t".date("Y-m-d H:i:s O", filemtime($file))."\33[0m\n";
    $text = file_get_contents($file);
    $diff->doDiff(str_replace("\r", "",$source), str_replace("\r", "", $text), FineDiff::$codeGranularity);
    $lines = explode("\n", $diff->renderDiffToText());

    $w = floor(log10(count($lines)))+1;
    $ext = 0;
    $esc = '';
    $back = array();
    $block = false;

    foreach ($lines as $l => $line) {
      if (preg_match("/\33\\[[34]/", $line) || ($block)) {
        if ($back) $buffer .= implode("", array_slice($back, -3));

        if (($block) && preg_match("/\33\\[0m/", $line))
          $block = false;

        if (!($block))
          $block = preg_match("/\33\\[[34][^\33]*$/", $line);

        $buffer .= sprintf("\33[0;34m% {$w}s\33[0m! $esc", $l++).$line."\n";

        if (!($block))
          $esc = '';
        elseif ($esc == '')
          $esc = preg_replace("/.*(\33\\[[34][^m]+m)[^\33]*$/", '\\1', $line);

        $back = array();
        $ext = 3;
      } else {
        if ($ext) {
          $buffer .= sprintf("% {$w}s  %s\n", ($l + 1), $line);
          if (--$ext == 0) $buffer .= str_repeat(' ', $w)."...\n";
        } else
          $back[] = sprintf("% {$w}s  %s\n", ($l + 1), $line);
      }
    }
    return $buffer;
  }

  static function systemDiff($source, $file) {
    $fd = array(0 => array("pipe", "r"), 1 => array("pipe", "w"), 2 => array("pipe", "w"));
    $args = array("diff", "-uBw", "-", $file);
    $cmd = implode(' ', $args);
    $proc = proc_open($cmd, $fd, $pipes);

    if (is_resource($proc)) {
      stream_set_blocking($pipes[2], 0);
      if ($err = stream_get_contents($pipes[2])) {
        fclose($pipes[0]);
        fclose($pipes[1]);
        fclose($pipes[2]);
        proc_close($proc);
        return false;
      }

      fwrite($pipes[0], $source);
      fclose($pipes[0]);

      $buffer = stream_get_contents($pipes[1]);
      fclose($pipes[1]);

      $err = stream_get_contents($pipes[2]);
      fclose($pipes[2]);

      $ret = proc_close($proc);
    } else
      return false;

    $buffer = preg_replace('/^(-.*)/m', "\33[32m\\1\33[0m", $buffer);
    $buffer = preg_replace('/^(\+.*)/m', "\33[31m\\1\33[0m", $buffer);
    return $buffer;
  }

  static function fileType($mode) {
    if (($mode & S_IFMT) == S_IFREG)  return '-';
    if (($mode & S_IFMT) == S_IFDIR)  return 'd';
    if (($mode & S_IFMT) == S_IFBLK)  return 'b';
    if (($mode & S_IFMT) == S_IFCHR)  return 'c';
    if (($mode & S_IFMT) == S_IFLNK)  return 'l';
    if (($mode & S_IFMT) == S_IFIFO)  return 'p';
    if (($mode & S_IFMT) == S_IFSOCK) return 's';
  }

  static function strMode($mode) {
    $m = self::fileType($mode);

    $m .= ( $mode & S_IRUSR) ? 'r' : '-';
    $m .= ( $mode & S_IWUSR) ? 'w' : '-';
    $m .= (($mode & S_ISUID)
        ? (($mode & S_IXUSR) ? 's' : 'S')
        : (($mode & S_IXUSR) ? 'x' : '-'));

    $m .= ( $mode & S_IRGRP) ? 'r' : '-';
    $m .= ( $mode & S_IWGRP) ? 'w' : '-';
    $m .= (($mode & S_ISUID)
        ? (($mode & S_IXGRP) ? 's' : 'S')
        : (($mode & S_IXGRP) ? 'x' : '-'));

    $m .= ( $mode & S_IROTH) ? 'r' : '-';
    $m .= ( $mode & S_IWOTH) ? 'w' : '-';
    $m .= (($mode & S_ISVTX)
        ? (($mode & S_IXOTH) ? 't' : 'T')
        : (($mode & S_IXOTH) ? 'x' : '-'));

    return $m;
  }

  static function fileSort($a, $b) {
    if (($a['mode'] & S_IFDIR)) {
      if (!($b['mode'] & S_IFDIR))
        return -1;
    } elseif (($b['mode'] & S_IFDIR))
      return 1;

    $a = $a['name'];
    $b = $b['name'];
    $an = strrpos($a, '.');
    $bn = strrpos($b, '.');

    if (($aext = substr($a, $an + 1)) !== false)
      $a = substr($a, 0, $an);
    if (($bext = substr($b, $bn + 1)) !== false)
      $b = substr($b, 0, $bn);

    if ($an === false) {
      if ($bn !== false)
        return -1;
    } elseif ($bn === false)
      return 1;

    $n = strnatcasecmp($aext, $bext);
    $n = (($n != 0) ? $n : strnatcasecmp($a, $b));
    return $n;
  }
}
