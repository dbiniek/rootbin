<?php

//##########
// dump.php
// Used to dump a database from a host that doesn't provide another way of obtaining a database dump.
// Wiki: https://gatorwiki.hostgator.com/Migrations/TransferDump-php
// Gitorious: http://git.toolbox.hostgator.com/dumdbphp
// Please submit all bug reports at bugs.hostgator.com
//
//##########

/*---------------------------------------------------+
| Based on mysqldump.php
+----------------------------------------------------+
| Copyright 2006 Huang Kai
| hkai@atutility.com
| http://atutility.com/
+----------------------------------------------------+
| Released under the terms & conditions of v2 of the
| GNU General Public License. For details refer to
| the included gpl.txt file or visit http://gnu.org
+----------------------------------------------------*/
/*
change log:
2006-10-16 Huang Kai
---------------------------------
initial release

2006-10-18 Huang Kai
---------------------------------
fixed bugs with delimiter
add paramter header to add field name as CSV file header.

2006-11-11 Huang Kia
Tested with IE and fixed the <button> to <input>
*/

set_time_limit(0);

$print_form = 1; //Determine whether or not to print the html form (1=Yes, 0=No)

// Some simple sanity checking of our inputs.
$db_host     = $_REQUEST['db_host'];
$db_name     = $_REQUEST['db_name'];
$db_user     = $_REQUEST['db_user'];
$db_password = $_REQUEST['db_password'];
$action      = $_REQUEST['action'];
$db_table    = $_REQUEST['db_table'];
if (strlen($db_host) > 99) {
     print "Database host name is invalid.\n";
     exit(1);
}
if (strlen($db_name) > 99) {
     print "Database name is invalid.\n";
     exit(1);
}
if (strlen($db_user) > 16) {
     print "Database username is invalid.\n";
     exit(1);
}
if (strlen($db_password) > 99) {
     print "Database password is invalid.\n";
     exit(1);
}
if (strlen($action) > 99) {
     print "Invalid form input.\n";
     exit(1);
}
if (strlen($db_table) > 99) {
     print "Invalid form input.\n";
     exit(1);
}



// Decide what to do based on what form button was clicked.
switch ($action) {

     case "Test Connection": // Test connection using mysql_connect link.
          $link = mysql_login($db_host,$db_name, $db_user, $db_password);
          if ($link) {
               print "<b>Connection test successful!</b><br />";
               mysql_close($link);
          } 
          break;

     case "List Databases": // List databases using mysql_connect link.
          $link = @mysql_connect($db_host, $db_user, $db_password);
          if ($link) {
               print "Databases:<br />\n";
               list_databases($link);
               mysql_close($link);
          }else{
               show_error_info($db_host, "N/A", $db_user, $db_password);
          } 
          break;

     case "List Tables": // List tables using mysql_connect link.
          $link = mysql_login($db_host,$db_name, $db_user, $db_password);
          if ($link) {
               print "Tables:<br />\n";
               list_tables($link);
               mysql_close($link);
          }
          break;

     case "Export Using MySQLDump": // Export to client using passthru to mysqldump
          $link = mysql_login($db_host,$db_name, $db_user, $db_password);
          if ($link) {
               $print_form=0;
               mysql_close($link); //Close the connection since it was just a test and mysqldump will open its own connection.
               send_database_dump($db_host, $db_name, $db_user, $db_password);
          } 
          break;

     case "Export Table Using MySQLDump": // Export to client using passthru to mysqldump
          $link = mysql_login($db_host,$db_name, $db_user, $db_password);
          if ($link) {
               $print_form=0;
               mysql_close($link); //Close the connection since it was just a test and mysqldump will open its own connection.
               send_table_dump($db_host, $db_name, $db_user, $db_password, $db_table);
          } 
          break;

     case "Export Using MySQLDump, Save File On Server": # Export to server using passthru to mysqldump.
          $link = mysql_login($db_host,$db_name, $db_user, $db_password);
          if ($link) {
               $print_form=0;
               mysql_close($link); //Close the connection since it was just a test and mysqldump will open its own connection.
               save_dump_on_server($db_host, $db_name, $db_user, $db_password);
          } 
          break;

     case "Export Using SQL": // Export to client using passthru to mysqldump
          $link = mysql_login($db_host,$db_name, $db_user, $db_password);
          if ($link) {
               $print_form=0;
               send_database_dump_sql($link, $db_host, $db_name);
          } 
          break;

     case "Export Table Using SQL": // Export to client using passthru to mysqldump
          $link = mysql_login($db_host,$db_name, $db_user, $db_password);
          if ($link) {
               $print_form=0;
               send_table_dump_sql($link, $db_host, $db_name, $db_table);
          } 
          break;

     case "View Dump": //Send dump to the screen using mysql_connect link.
          $link = mysql_login($db_host, $db_name, $db_user, $db_password);
          if ($link) {
               $print_form=0;
               view_dump($link, $db_host, $db_name);
          } 
          break;

}

// Log into MySQL.
// Input:  Host, database, User, password
// Output: Logs into MySQL, setch utf8 and returns the MySQL link handle.
//         If login fails, it prints error info and returns false.
function mysql_login($db_host, $db_name, $db_user, $db_password)
    {
        $link = @mysql_connect($db_host, $db_user, $db_password);
        if ($link) {
     	     $db_selected = @mysql_select_db($db_name, $link);
             if ($db_selected) {
                  mysql_query("SET NAMES utf8;", $link);
             }else{
                  show_error_info($db_host, $db_name, $db_user, $db_password);
                  mysql_close($link);
                  $link = FALSE;
             }
         }else{
             show_error_info($db_host, $db_name, $db_user, $db_password);
         }
         return $link;
    }

// Show MySQL error information.
// Shows login information along with the MySQL error.
// This is called after a failed login and makes use of the mysql_error() function.
function show_error_info($db_host, $db_name, $db_user, $db_password)
    {
         print "<b>MySQL connection failed.<br />\n";
         print mysql_error();
         print "</b><br />\n";
         printf("Login information used:<br />\nhost: %s<br />database: %s<br />user:%s<br />password: %s<br />", $db_host, $db_name, $db_user, $db_password);
    }

////////////////////////////////////////////////////////////////////////////////
function send_database_dump($db_host, $db_name, $db_user, $db_password) 
    {
    $dumpname = $db_host."_".$db_name."-".date("Y\.m\.d\_H\.i\.s").".sql";
    header('Content-type: text/plain;charset=UTF-8');
    header('Content-Disposition: attachment; filename="'.$dumpname.'"');
    passthru("mysqldump --opt -u'".$db_user."' -p'".$db_password."' -h'".$db_host."' '".$db_name."'");
    }

////////////////////////////////////////////////////////////////////////////////
function send_table_dump($db_host, $db_name, $db_user, $db_password, $table) 
    {
    if (!$table) {
         print "<b>Please select a table.</b>\n";
         return;
    }
    $dumpname = $db_host."_".$db_name.".".$table."-".date("Y\.m\.d\_H\.i\.s").".sql";
    header('Content-type: text/plain;charset=UTF-8');
    header('Content-Disposition: attachment; filename="'.$dumpname.'"');
    passthru("mysqldump --opt -u'".$db_user."' -p'".$db_password."' -h'".$db_host."' '".$db_name."' '".$table."'");
    }

////////////////////////////////////////////////////////////////////////////////
function save_dump_on_server($db_host, $db_name, $db_user, $db_password) 
    {
    $dumpname = $db_host."_".$db_name."-".date("Y\.m\.d\_H\.i\.s").".sql";
    echo "<p>Saving dump to ".$dumpname."</p>";
    passthru("mysqldump --opt -u'".$db_user."' -p'".$db_password."' -h'".$db_host."' '".$db_name."' > ".$dumpname);
    }

////////////////////////////////////////////////////////////////////////////////
function send_database_dump_sql($link, $db_host, $db_name) 
    {
    $dumpname = $db_host."_".$db_name."-".date("Y\.m\.d\_H\.i\.s").".sql";
    header('Content-type: text/plain;charset=UTF-8');
    header('Content-Disposition: attachment; filename="'.$dumpname.'"');
    mysqldump($link, $db_host, $db_name);
    }

////////////////////////////////////////////////////////////////////////////////
function send_table_dump_sql($link, $db_host, $db_name, $table) 
    {
    if (!$table) {
         print "<b>Please select a table.</b>\n";
         return;
    }
    $dumpname = $db_host."_".$db_name.".".$table."-".date("Y\.m\.d\_H\.i\.s").".sql";
    header('Content-type: text/plain;charset=UTF-8');
    header('Content-Disposition: attachment; filename="'.$dumpname.'"');
    mysqldump_table($link, $db_host, $db_name, $table);
    }

////////////////////////////////////////////////////////////////////////////////
function view_dump($link, $db_host, $db_name) 
    {
    header('Content-type: text/plain;charset=UTF-8');
    mysqldump($link, $db_host, $db_name);
    }

////////////////////////////////////////////////////////////////////////////////

function list_databases($link)
    {
    $sql    = "SHOW DATABASES;";
    $result = mysql_query($sql, $link);
    if ($result)
        {
        while ($row = mysql_fetch_row($result))
            {
                print $row[0] . "<br />\n";
            }
        }   
    }

function list_tables($link)
    {
    $sql    = "SHOW TABLES;";
    $result = mysql_query($sql, $link);
    if ($result)
        {
        while ($row = mysql_fetch_row($result))
            {
                print $row[0] . "<br />\n";
            }
        }   
    }

////////////////////////////////////////////////////////////////////////////////
// Mostly original mysqldump.php functions
////////////////////////////////////////////////////////////////////////////////
function mysqldump($link, $db_host, $db_name) 

    {
    printf("-- Host: %s\n".
	   "-- Database: %s\n".
	   "\n".
	   "/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;\n".
	   "/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;\n".
	   "/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;\n".
	   "/*!40101 SET NAMES utf8 */;\n".
	   "/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;\n".
	   "/*!40103 SET TIME_ZONE='+00:00' */;\n".
	   "/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;\n".
	   "/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;\n".
	   "/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;\n".
	   "/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;".
	   "\n\n\n", $db_host, $db_name);
    
    $sql = "SHOW TABLES;";
    $result = mysql_query($sql, $link);
    if ($result) 
	{
	while ($row = mysql_fetch_row($result)) 
	    {
	    mysqldump_table_structure($link, $row[0]);
	    mysqldump_table_data($link, $row[0]);
	    }
	} 
    else 
	{
	printf("-- no tables in database \n");
	}
    mysql_free_result($result);

    printf("\n\n\n".
	   "/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;\n".
	   "/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;\n".
	   "/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;\n".
	   "/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;\n".
	   "/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;\n".
	   "/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;\n".
	   "/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;\n".
	   "/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;\n");
    }


////////////////////////////////////////////////////////////////////////////////
function mysqldump_table($link, $db_host, $db_name, $table) 

    {
    printf("-- Host: %s\n".
	   "-- Database: %s\n".
	   "\n".
	   "/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;\n".
	   "/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;\n".
	   "/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;\n".
	   "/*!40101 SET NAMES utf8 */;\n".
	   "/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;\n".
	   "/*!40103 SET TIME_ZONE='+00:00' */;\n".
	   "/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;\n".
	   "/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;\n".
	   "/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;\n".
	   "/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;".
	   "\n\n\n", $db_host, $db_name);
    
    mysqldump_table_structure($link, $table);
    mysqldump_table_data($link, $table);

    printf("\n\n\n".
	   "/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;\n".
	   "/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;\n".
	   "/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;\n".
	   "/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;\n".
	   "/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;\n".
	   "/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;\n".
	   "/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;\n".
	   "/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;\n");
    }


////////////////////////////////////////////////////////////////////////////////
function mysqldump_table_structure($link, $table) 
    {
    echo "-- Table structure for table ".$table." \n";
    echo "DROP TABLE IF EXISTS `".$table."`;\n\n";
    $sql = "SHOW CREATE TABLE `".$table."`; ";
    $result=mysql_query($sql, $link);
    if ($result) 
	{
	if ($row= mysql_fetch_assoc($result)) 
	    {
	    echo $row['Create Table'].";\n\n";
	    }
	}
    mysql_free_result($result);
    }

////////////////////////////////////////////////////////////////////////////////
function mysqldump_table_data($link, $table) 
    {
    $sql = "SELECT * FROM `".$table."`;";
    $result = mysql_query($sql, $link);
    if ($result) 
	{
	$num_rows = mysql_num_rows($result);
	$num_fields = mysql_num_fields($result);
	
	if ($num_rows > 0) 
	    {
	    printf("-- dumping data for table %s\n".
		   "LOCK TABLES `%s` WRITE;\n".
		   "/*!40000 ALTER TABLE `%s` DISABLE KEYS */;\n", 
		   $table, $table, $table);;
	    
	    $field_type = array();
	    $i = 0;
	    while ($i < $num_fields) 
		{
		$meta = mysql_fetch_field($result, $i);
		array_push($field_type, $meta->type);
		$i++;
		}
	    
	    printf("INSERT INTO `%s` VALUES\n", $table);;
	    $index = 0;
	    while ($row = mysql_fetch_row($result)) 
		{
		echo "(";
		for ($i = 0; $i < $num_fields; $i++) 
		    {
		    if (is_null ($row[$i]))
		       echo "null";
		    else 
			{
			switch ($field_type[$i])
			    {
			    case 'int':
			    echo $row[$i];
			    break;
			    case 'string':
			    case 'blob' :
			    default:
			    printf("'%s'", mysql_real_escape_string($row[$i]));
			    }
			}
		    if ($i < $num_fields-1)
		       echo ",";
		    }
		echo ")";
		
		if ($index < $num_rows-1)
		   echo ",";
		else
		   echo ";";
		echo "\n";
		
		$index++;
		}
	    printf("/*!40000 ALTER TABLE `%s` ENABLE KEYS */;\n".
		   "UNLOCK TABLES;\n", 
		   $table);
	    }
	}
    mysql_free_result($result);
    echo "\n";
    }


////////////////////////////////////////////////////////////////////////////////
// The actual web page.
////////////////////////////////////////////////////////////////////////////////

if ($print_form > 0)
    {
?>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">

<html>
<head>
<title>dump.php</title>
</head>

<body>
<hr />
<form action="" method="post">
MySQL connection parameters:
<table border="0">
  <tr>
    <td>Host:</td>
    <td><input  name="db_host" value="<?php if(isset($_REQUEST['db_host']))echo $_REQUEST['db_host']; else echo 'localhost';?>"  /></td>
  </tr>
  <tr>
    <td>Database:</td>
    <td><input  name="db_name" value="<?php echo $_REQUEST['db_name']; ?>"  /></td>
  </tr>
  <tr>
    <td>Username:</td>
    <td><input  name="db_user" value="<?php echo $_REQUEST['db_user']; ?>"  /></td>
  </tr>
  <tr>
    <td>Password:</td>
    <td><input  name="db_password" value="<?php echo $_REQUEST['db_password']; ?>"  /></td>
  </tr>
</table>
<input type="submit" name="action"  value="Test Connection"> &nbsp;
<input type="submit" name="action"  value="List Databases"> &nbsp;
<input type="submit" name="action"  value="Export Using MySQLDump"> &nbsp;
<input type="submit" name="action"  value="Export Using MySQLDump, Save File On Server"> &nbsp;
<input type="submit" name="action"  value="Export Using SQL"> &nbsp;
<input type="submit" name="action"  value="View Dump"><br />
<hr />
Table specific parameters:<br />
Table:&nbsp; <input name="db_table" />
<input type="submit" name="action"  value="List Tables"> &nbsp; 
<input type="submit" name="action"  value="Export Table Using MySQLDump"> &nbsp;
<input type="submit" name="action"  value="Export Table Using SQL"> &nbsp;
<hr />
</form>
</body>
</html>

<?php
    }
?>

