#!/bin/bash
#
# StackScript Bash Library
#
# Copyright (c) 2010 Linode LLC / Christopher S. Aker <caker@linode.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, 
# are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice, this
# list of conditions and the following disclaimer in the documentation and/or
# other materials provided with the distribution.
#
# * Neither the name of Linode LLC nor the names of its contributors may be
# used to endorse or promote products derived from this software without specific prior
# written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
# SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
# DAMAGE.

###########################################################
# System
###########################################################

function system_update {
        sudo apt-get update
        sudo apt-get -y install aptitude
        sudo aptitude -y full-upgrade
}

function system_primary_ip {
        # returns the primary IP assigned to eth0
        echo $(ifconfig eth0 | awk -F: '/inet addr:/ {print $2}' | awk '{ print $1 }')
}

function get_rdns {
        # calls host on an IP address and returns its reverse dns

        if [ ! -e /usr/bin/host ]; then
                aptitude -y install dnsutils > /dev/null
        fi
        echo $(host $1 | awk '/pointer/ {print $5}' | sed 's/\.$//')
}

function get_rdns_primary_ip {
        # returns the reverse dns of the primary IP assigned to this system
        echo $(get_rdns $(system_primary_ip))
}

###########################################################
# niceties!
###########################################################
function goodstuff {
        # Installs the REAL vim, wget, less, and enables color root prompt and the "ll" list long alias
        echo 'Installing wget, vim, and less'

        sudo aptitude -y install wget vim less
        sudo sed -i -e 's/^#PS1=/PS1=/' /root/.bashrc # enable the colorful root bash prompt
        sudo sed -i -e "s/^#alias ll='ls -l'/alias ll='ls -al'/" /root/.bashrc # enable ll list long alias <3
        sudo sed -i -e "s/^#source ~/.bashrc" /root/.bash_profile #source bashrc so that alias's work upon login.
}

###########################################################
#Web Services
###########################################################

function webservices_install {
#wether or not to install vestaCP if not we will need to install Apache, MySQL, and PHP
echo 'Do you want to install VestaCP? (y or n)'
read installVesta
if [$installVesta -eq y] 
        then
            installVesta=1
        else
            installVesta=0
fi

if [installVesta -eq 1]
        then
                cd ~
                curl -O http://vestacp.com/pub/vst-install.sh
                bash vst-install.sh --nginx yes --apache yes --phpfpm no --named yes --remi yes --vsftpd yes --proftpd no --iptables yes --fai$
        else
                function apache_install {
                    # installs the system default apache2 MPM
                    echo 'Installing Apache2'
                    aptitude -y install apache2

                    echo 'Disabling default virtualhost.'
                    a2dissite default # disable the interfering default virtualhost

                    # clean up, or add the NameVirtualHost line to ports.conf
                    sed -i -e 's/^NameVirtualHost \*$/NameVirtualHost *:80/' /etc/apache2/ports.conf
                    if ! grep -q NameVirtualHost /etc/apache2/ports.conf; then
                            echo 'NameVirtualHost *:80' > /etc/apache2/ports.conf.tmp
                            cat /etc/apache2/ports.conf >> /etc/apache2/ports.conf.tmp
                            mv -f /etc/apache2/ports.conf.tmp /etc/apache2/ports.conf
                    fi

                    echo 'Apache2 has been installed.'
                }

                function apache_tune {
                        # Tunes Apache's memory to use the percentage of RAM you specify, defaulting to 40%

                        # $1 - the percent of system memory to allocate towards Apache

                        echo 'what percentage of system RAM do you wnat to allocate to Apache2? (digits ONLY) or press [ENTER] for default 40%'

                        read PERCENT
                        if [ ! -n "$1" ];
                                then PERCENT=40
                        fi

                        echo 'Calculating Max Clients with $PERCENT % memory allocated.'
                        aptitude -y install apache2-mpm-prefork
                        PERPROCMEM=10 # the amount of memory in MB each apache process is likely to utilize
                        MEM=$(grep MemTotal /proc/meminfo | awk '{ print int($2/1024) }') # how much memory in MB this system has
                        MAXCLIENTS=$((MEM*PERCENT/100/PERPROCMEM)) # calculate MaxClients
                        MAXCLIENTS=${MAXCLIENTS/.*} # cast to an integer
                        sed -i -e "s/\(^[ \t]*MaxClients[ \t]*\)[0-9]*/\1$MAXCLIENTS/" /etc/apache2/apache2.conf

                        echo 'with $PERCENT % system memory allocated you can support $MAXCLIENTS clients.'

                        touch /tmp/restart-apache2
                }
                
                function apache_virtualhost {
                    # Configures a VirtualHost

                    # $1 - required - the hostname of the virtualhost to create

                    echo 'do you want to create a virtual host now? ( y or n)'

                    read ANSWER

                    if [$ANSWER=y]
                        then
                            echo 'name of virtualhost'
                            read $VHOST

                            if [! $VHOST]
                                    then
                                    echo "apache_virtualhost() requires the hostname as the first argument"
                                    return 1;
                            fi
                            if [ -e "/etc/apache2/sites-available/$1" ]; then
                                    echo /etc/apache2/sites-available/$1 already exists
                                    return;
                            fi
                            mkdir -p /srv/www/$1/public_html /srv/www/$1/logs
                            echo "<VirtualHost *:80>" > /etc/apache2/sites-available/$1
                            echo "    ServerName $1" >> /etc/apache2/sites-available/$1
                            echo "    DocumentRoot /srv/www/$1/public_html/" >> /etc/apache2/sites-available/$1
                            echo "    ErrorLog /srv/www/$1/logs/error.log" >> /etc/apache2/sites-available/$1
                            echo "    CustomLog /srv/www/$1/logs/access.log combined" >> /etc/apache2/sites-available/$1
                            echo "</VirtualHost>" >> /etc/apache2/sites-available/$1
                            a2ensite $1
                            touch /tmp/restart-apache2
                        else
                            return 1;
                    fi
                }

                ###########################################################
                # mysql-server
                ###########################################################
                function mysql_install {
                        # $1 - the mysql root password
                        echo 'Enter the root password'
                        read passwd
                        
                        echo "mysql-server-5.1 mysql-server/root_password password $passwd" | debconf-set-selections
                        echo "mysql-server-5.1 mysql-server/root_password_again password $passwd" | debconf-set-selections
                        apt-get -y install mysql-server mysql-client
                        echo "Sleeping while MySQL starts up for the first time..."
                        sleep 5
                }
                function mysql_tune {
                # Tunes MySQL's memory usage to utilize the percentage of memory you specify, defaulting to 40%
                        # $1 - the percent of system memory to allocate towards MySQL
                        echo 'what percentage of system RAM do you wnat to allocate to MySQL (digits ONLY) or press [ENTER] for default 40%'

                        read PERCENT
                        if [ ! -n "$1" ];
                                then PERCENT=40
                        fi
                        echo 'Do you want to use innoDB? ( y or n)'
                        read ANSWER
                        if [$ANSWER=n] 
                                then
                                sed -i -e 's/^#skip-innodb/skip-innodb/' /etc/mysql/my.cnf # disable innodb - saves about 100M
                        fi

                        MEM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo) # how much memory in MB this system has
                        MYMEM=$((MEM*PERCENT/100)) # how much memory we'd like to tune mysql with
                        MYMEMCHUNKS=$((MYMEM/4)) # how many 4MB chunks we have to play with
                        # mysql config options we want to set to the percentages in the second list, respectively
                        OPTLIST=(innodb_buffer_pool_size sort_buffer_size read_buffer_size query_cache_type query_cache_size)
                        DISTLIST=(256 4 4 1 25)
                        for opt in ${OPTLIST[@]}; do
                                sed -i -e "/\[mysqld\]/,/\[.*\]/s/^$opt/#$opt/" /etc/mysql/my.cnf
                        done

                        for i in ${!OPTLIST[*]}; do
                                val=$(echo | awk "{print int((${DISTLIST[$i]} * $MYMEMCHUNKS/100))*4}")
                                if [ $val -lt 4 ]
                                        then val=4
                                fi
                                config="${config}\n${OPTLIST[$i]} = ${val}M"
                        done

                        sed -i -e "s/\(\[mysqld\]\)/\1\n$config\n/" /etc/mysql/my.cnf

                        touch /tmp/restart-mysql
                }

                function mysql_create_database {
                        # $1 - the mysql root password
                        # $2 - the db name to create

                        if [ ! -n "$1" ]; then
                                echo "mysql_create_database() requires the root pass as its first argument"
                                return 1;
                        fi
                        if [ ! -n "$2" ]; then
                                echo "mysql_create_database() requires the name of the database as the second argument"
                                return 1;
                        fi
                        echo "CREATE DATABASE $2;" | mysql -u root -p$1
                }
                function mysql_create_user {
                        # $1 - the mysql root password
                        # $2 - the user to create
                        # $3 - their password
                        if [ ! -n "$1" ]; then
                                echo "mysql_create_user() requires the root pass as its first argument"
                                return 1;
                        fi
                        if [ ! -n "$2" ]; then
                                echo "mysql_create_user() requires username as the second argument"
                                return 1;
                        fi
                        if [ ! -n "$3" ]; then
                                echo "mysql_create_user() requires a password as the third argument"
                                return 1;
                        fi
                        echo "CREATE USER '$2'@'localhost' IDENTIFIED BY '$3';" | mysql -u root -p$1
                }
                function mysql_grant_user {
                        # $1 - the mysql root password
                        # $2 - the user to bestow privileges
                        # $3 - the database
                        if [ ! -n "$1" ]; then
                                echo "mysql_create_user() requires the root pass as its first argument"
                                return 1;
                        fi
                        if [ ! -n "$2" ]; then
                                echo "mysql_create_user() requires username as the second argument"
                                return 1;
                        fi
                        if [ ! -n "$3" ]; then
                                echo "mysql_create_user() requires a database as the third argument"
                                return 1;
                        fi
                        echo "GRANT ALL PRIVILEGES ON $3.* TO '$2'@'localhost';" | mysql -u root -p$1
                        echo "FLUSH PRIVILEGES;" | mysql -u root -p$1
                }
                function start_mysql_slow_logging {
                        #$1 - mysql root user
                        #$2 - musql root password
                        echo 'SET GLOBAL slow_query_log="ON";SET GLOBAL long_query_time=1' | mysql -u$1 -p$2
                        echo 'Slow Query Logging has been enabled, creating symlink from log directory to home directory'
                        ln -s /var/lib/mysql/ /root/slow_logs/

                }
                ###########################################################
                # PHP functions
                ###########################################################
                function php_install_with_apache {
                        aptitude -y install php5 php5-mysql libapache2-mod-php5
                        touch /tmp/restart-apache2
                }
                function php_tune {
                        # Tunes PHP to utilize up to 32M per process
                        sed -i'-orig' 's/memory_limit = [0-9]\+M/memory_limit = 32M/' /etc/php5/apache2/php.ini
                        touch /tmp/restart-apache2
                }
fi

}





###########################################################
# utility functions
###########################################################

function restartServices {
        # restarts services that have a file in /tmp/needs-restart/

        for service in $(ls /tmp/restart-* | cut -d- -f2-10); do
                /etc/init.d/$service restart
                rm -f /tmp/restart-$service
        done
}

function randomString {
        if [ ! -n "$1" ];
                then LEN=20
                else LEN="$1"
        fi

        echo $(</dev/urandom tr -dc A-Za-z0-9 | head -c $LEN) # generate a random string
}

