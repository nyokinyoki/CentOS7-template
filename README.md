# CentOS7 template

## What is it?
It's a bash script that sets up a fresh minimal installation of CentOS7 into something, that's easier to play with in a test environment. Keep in mind that it isn't anywhere near to being secure and you should **never use it in production**.

## What does it do?
### By default the script will:
* disable `firewalld`, `chronyd` services and `SELinux`
* add a new user to a newly created group
* enable root access without password to that group via `sudo su -`
* color the prompt of root and normal users with red and green color respectively
* install `ntp` and enable `epel-release` repository
* replace default NTP servers with the ones defined in script
* preform a `yum update`

### In addition it can
* set the hostname and add it to `/etc/hosts` by calling it with `-h <hostname>`
* install additional packages defined in `PACKAGES` variable

## Before you start
### Password hash
Generate a hash of the password you want to use for the new user. You can use Python 3 for that:  
`yum -y install epel-release`  
`yum -y install python36`  
`python36 -c 'import crypt; print(crypt.crypt("desired_password", crypt.mksalt(crypt.METHOD_SHA512)))'`

### Edit variables
Edit `PASS`, `USERNAME`, `GROUPNAME`, `NTPS` and optionally `PACKAGES` variables at the beginning of script. The password hash you generated in previous step goes into `PASS` variable.

## Running the script
Run it with root privileges.
- if you run it without switches it'll do the default stuff
- if you add `-h` switch, you can provide a hostname in the next argument
- yum output can be seen in the script directory with `.yumlog` extension
- yumlog gets overwritten every time you run the script
