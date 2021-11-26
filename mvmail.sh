#!/bin/bash

counter=0  #Limiting counter.  This is a safeguard to prevent us from filling the disk
           # if mvmail immediately returns 13 infinite times.

finished=0 #When an IMAP server dumps the connection, mvmail receives a SIGPIPE signal.
           # mvmail will catch the SIGPIPE and exit with a return code 13.
           # This bash script will restart mvmail if the return code is 13 or consider
           # the transfer as "finished" if the exit code is not 13.

echo -n "Start time: " > mvmail-log.txt # Log the start time.
date >> mvmail-log.txt

while [ $finished -eq 0 ] && [ $counter -lt 30 ] #Start mvmail if we're not finished and havent started it excessively.
do
  /root/bin/mvmail ${1} ${2} ${3} ${4} ${5} ${6} ${7} ${8} ${9}
  if [ $? -ne 13 ] # If mvmail didn't stop because of a sigpipe, then
  then
       finished=1  # we're finished.
  else
       date >> mvmail-log.txt # Otherwise log the time of the restart.
       sleep 30               # Wait 30 sec before restarting as another safeguard.
  fi
  ((counter++))
done
