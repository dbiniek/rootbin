#!/bin/bash
############################################################
# Help                                                     #
############################################################
Help()
{
    cat <<- EOF    
        CWD - Change Working Directory
        
        Syntax: scriptTemplate [-h]
        options:
        h     Print this Help.

EOF
}

############################################################
############################################################
# Main program                                             #
############################################################
############################################################

# Set variables
domain="$1"
docroot="awk -F":" '$1 == "$domain" {print $1}' /etc/userdatadomains"


############################################################
# Process the input options.        #
############################################################
# Get the options
while getopts ":h:" option; do
   case $option in
      h) # display Help
         Help
         exit;;
     \?) # Invalid option
         echo "Error: Invalid option"
         exit;;
   esac
done
echo $domain

#cd $(/usr/bin/docroot.py $1)

awk -F":" '$1 == "$domain" {print $1}' /etc/userdatadomains


