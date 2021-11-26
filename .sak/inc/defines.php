<?php

/** Script name */
if (!function_exists('sak_env_define') || !sak_env_define('SAK_SELF', null, null, true)) {
  fprintf(STDERR, "This script cannot be invoked directly.\n");
  exit(1);
}

sak_env_define('SAK_BASENAME', 'sak');
sak_env_define('SAK_DIR', '/root/bin/.sak');

sak_env_define('SAK_PHP');
sak_env_define('SAK_PYTHON');

sak_env_define('SAK_VER');
sak_env_define('SAK_TS');

sak_env_define('SAK_SID_STRING');

define('DS', DIRECTORY_SEPARATOR);

define('SAK_SID', substr(md5(SAK_SID_STRING), 0, 12));

define('SAK_REPO_BASE', 'http://sak.dev.gatorsec.net');
define('SAK_REPO_BASE_SOFT', 'http://sak.dev.gatorsec.net/software');

define('SAK_REQ_PHPVER', 5);
define('SAK_REQ_PHPEXT', 'pcre mysql posix zlib sockets');

// Logging
define('SAK_LOG_INFO',  1);
define('SAK_LOG_MESG',  2);
define('SAK_LOG_WARN',  3);
define('SAK_LOG_ERROR', 4);
define('SAK_LOG_DEBUG', 5);

define('SAK_PHPOPT_VARIABLE', 1);
define('SAK_PHPOPT_DEFINE',   2);

// Path
define('SAK_PATH_BIN',          0x001);
define('SAK_PATH_TMP',          0x002);
define('SAK_PATH_LOGS',         0x004);
define('SAK_PATH_CACHE',        0x008);
define('SAK_PATH_CORETMP',      0x010);

define('SAK_PATH_LOG',          0x020);
define('SAK_PATH_BACKUP',       0x040);
define('SAK_PATH_BACKUP_DB',    0x080);
define('SAK_PATH_BACKUP_FILE',  0x100);

define('SAK_PATH_FAILSAFE_STOR',  0x1000);

// Backup
define('SAK_BAK_CORE',      0x01);
define('SAK_BAK_FILE',      0x02);
define('SAK_BAK_DIR',       0x04);
define('SAK_BAK_DB',        0x08);
define('SAK_BAK_DB_TABLE',  0x10);

// From linux/stat.h
define('S_IFMT',  0170000);
define('S_IFSOCK',0140000);
define('S_IFLNK', 0120000);
define('S_IFREG', 0100000);

define('S_IFBLK', 0060000);
define('S_IFDIR', 0040000);
define('S_IFCHR', 0020000);
define('S_IFIFO', 0010000);
define('S_ISUID', 0004000);
define('S_ISGID', 0002000);
define('S_ISVTX', 0001000);

define('S_IRWXU', 00700);
define('S_IRUSR', 00400);
define('S_IWUSR', 00200);
define('S_IXUSR', 00100);

define('S_IRWXG', 00070);
define('S_IRGRP', 00040);
define('S_IWGRP', 00020);
define('S_IXGRP', 00010);

define('S_IRWXO', 00007);
define('S_IROTH', 00004);
define('S_IWOTH', 00002);
define('S_IXOTH', 00001);
