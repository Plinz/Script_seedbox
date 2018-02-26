#!/bin/bash

declare -A users
declare -A unixpass
declare -A htpass

source script.conf

: '
	echo "[SCRIPT xmlrpc-c] BEGIN INSTALL"
	cd /tmp
	echo "[SCRIPT xmlrpc-c] svn checkout"
	svn checkout http://svn.code.sf.net/p/xmlrpc-c/code/stable xmlrpc-c
	cd xmlrpc-c/
	echo "[SCRIPT xmlrpc-c] ./configure"
	./configure
	echo "[SCRIPT xmlrpc-c] .make -j $(nproc)"
	make -j $(nproc)
	echo "[SCRIPT xmlrpc-c] .make install"
	make install
	echo "[SCRIPT xmlrpc-c] END INSTALL"

	echo "[SCRIPT libtorrent] BEGIN INSTALL"
	cd /tmp
	echo "[SCRIPT libtorrent] git clone"
	git clone https://github.com/rakshasa/libtorrent.git
	cd libtorrent
	echo "[SCRIPT libtorrent] git checkout"
	git checkout `git tag | tail -1`
	echo "[SCRIPT libtorrent] apply patch"
	git apply /root/conf/openssl.patch
	echo "[SCRIPT libtorrent] ./autogen.sh"
	./autogen.sh
	echo "[SCRIPT libtorrent] ./configure"
	./configure
	echo "[SCRIPT libtorrent] make -j $(nproc)"
	make -j $(nproc)
	echo "[SCRIPT libtorrent] make install"
	make install
	echo "[SCRIPT libtorrent] END INSTALL"

	echo "[SCRIPT rtorrent] BEGIN INSTALL"
	cd /tmp
	echo "[SCRIPT rtorrent] git clone"
	git clone https://github.com/rakshasa/rtorrent.git
	cd rtorrent
	echo "[SCRIPT rtorrent] git checkout"
	git checkout `git tag | tail -1`
	echo "[SCRIPT rtorrent] ./autogen.sh"
	./autogen.sh
	echo "[SCRIPT rtorrent] ./configure"
	./configure --with-xmlrpc-c
	echo "[SCRIPT rtorrent] make -j $(nproc)"
	make -j $(nproc)
	echo "[SCRIPT rtorrent] make install"
	make install
	echo "[SCRIPT rtorrent] END INSTALL"

	echo "[SCRIPT] ldconfig"
	ldconfig
'

echo "[SCRIPT users conf] BEGIN"
cp "seedbox" "conf/$serverName"
sed -i -e "s/seedbox/$serverName/g" conf/$serverName
for users_idx in ${!users[@]}; do
	echo "[SCRIPT users conf] BEGIN user=${users[$users_idx]} idx=$users_idx maj=${users[$users_idx]^^}"
	echo "[SCRIPT users conf] update $serverName"
	echo -e "\n location /${users[$users_idx]^^} {\n     include scgi_params;\n     scgi_pass 127.0.0.1:500$users_idx;\n     auth_basic \"Restricted Area\";\n     auth_basic_user_file \"/etc/nginx/auth/$serverName_auth ${users[$users_idx]}\";\n }\n">>"conf/$serverName"
	echo "[SCRIPT users conf] generate rtorrent.rc_${users[$users_idx]} file"
	cp ".rtorrent.rc" "conf/.rtorrent.rc_${users[$users_idx]}"
	content="$(<conf/.rtorrent.rc_${users[$users_idx]})"
	echo -en "scgi_port = 127.0.0.1:500$users_idx\n$content" >conf/.rtorrent.rc_${users[$users_idx]}
	sed -i -e "s/USERTEST/${users[$users_idx]}/g" conf/.rtorrent.rc_${users[$users_idx]}
	echo "[SCRIPT users conf] generate config.php_${users[$users_idx]} file"
	echo -e "<?php\n \n\$pathToExternals['curl'] = '/usr/bin/curl';\n\$topDirectory = '/home/${users[$users_idx]}';\n\$scgi_port = 500$users_idx;\n\$scgi_host = '127.0.0.1';\n\$XMLRPCMountPoint = '/${users[$users_idx]^^}';\n">"conf/config.php_${users[$users_idx]}"
	echo "[SCRIPT users conf] generate ${users[$users_idx]}-rtorrent file"
	cp "USERTEST-rtorrent" "conf/${users[$users_idx]}-rtorrent"
	sed -i -e "s/USERTEST/${users[$users_idx]}/g" conf/${users[$users_idx]}-rtorrent
done
echo "}">>"conf/$serverName"

scp -r "conf" "$serverIP:/root/"

ssh $serverIP << EOF
	DEBIAN_FRONTEND=noninteractive
	cp /root/conf/sources.list /etc/apt/
	wget --no-check-certificate https://www.dotdeb.org/dotdeb.gpg && apt-key add dotdeb.gpg
	wget http://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2016.8.1_all.deb
	dpkg -i deb-multimedia-keyring_2016.8.1_all.deb
	echo -e "#Dotdeb\ndeb http://packages.dotdeb.org stretch all\ndeb-src http://packages.dotdeb.org stretch all" > /etc/apt/sources.list.d/dotdeb.list
	echo -e "#Deb-Multimedia\ndeb http://www.deb-multimedia.org stretch main non-free" > /etc/apt/sources.list.d/deb-multimedia.list
	apt-get update
	apt-get -y install automake libcppunit-dev libtool build-essential pkg-config libssl-dev libcurl4-openssl-dev libsigc++-2.0-dev libncurses5-dev screen subversion apache2-utils
	apt-get -y install curl php7.0 php7.0-fpm php7.0-cli php7.0-curl php7.0-geoip git unzip unrar rar zip ffmpeg buildtorrent mediainfo zlib1g-dev apt-transport-https rtorrent sox

	echo "[SCRIPT rutorrent] BEGIN INSTALL"
	mkdir -p /var/www/html
	cd /var/www/html
	echo "[SCRIPT rutorrent] git clone rutorrent"
	git clone https://github.com/Novik/ruTorrent.git rutorrent
	cd rutorrent/plugins/
	echo "[SCRIPT rutorrent] git clone mobile plugin"
	git clone https://github.com/xombiemp/rutorrentMobile.git mobile
	echo "[SCRIPT rutorrent] chown -R www-data:www-data /var/www/html/rutorrent"
	chown -R www-data:www-data /var/www/html/rutorrent
	echo "[SCRIPT rutorrent] copy rutorrent conf.php"
	cp /root/conf/conf.php create/
	echo "[SCRIPT rutorrent] END INSTALL"

	echo "[SCRIPT php] copy php conf"
	cp /root/conf/php.ini /etc/php/7.0/fpm/
	echo "[SCRIPT php] service restart php"
	service php7.0-fpm restart
	
	echo "[SCRIPT nginx] BEGIN INSTALL"
	cd
	echo "[SCRIPT nginx] wget nginw key and add"
	wget http://nginx.org/keys/nginx_signing.key
	apt-key add nginx_signing.key
	rm nginx_signing.key
	echo "[SCRIPT nginx] add repository"
	echo -e "#NGinx Mainline\ndeb http://nginx.org/packages/debian/ stretch nginx\ndeb-src http://nginx.org/packages/debian/ stretch nginx" > /etc/apt/sources.list.d/nginx-mainline.list
	echo "[SCRIPT nginx] update"	
	apt-get update
	echo "[SCRIPT nginx] install nginx"
	apt-get -y install nginx

	echo "[SCRIPT nginx] BEGIN CONFIGURE nginx"
	cd /etc/nginx/
	rm conf.d/*.conf
	mkdir auth sites-enabled ssl
	echo "[SCRIPT nginx] cp nginx.conf"
	cp /root/conf/nginx.conf .
	echo "[SCRIPT nginx] cp $serverName"
	cp /root/conf/$serverName sites-enabled/
	touch auth/$serverName_auth
	echo "[SCRIPT nginx] SSL BEGIN"
	cd /etc/nginx/ssl/
	openssl ecparam -genkey -name secp384r1 -out $serverName.key
	openssl req -subj '/C=US/ST=Oregon/L=Portland/CN=LaGrosseBertha' -new -key $serverName.key -sha256 -out $serverName.csr
	openssl req -x509 -days 3650 -sha256 -key $serverName.key -in $serverName.csr -out $serverName.crt
	echo "[SCRIPT nginx] SSL chmod"
	chmod 644 /etc/nginx/ssl/*.crt
	chmod 640 /etc/nginx/ssl/*.key
	echo "[SCRIPT nginx] SSL END"
	echo "[SCRIPT nginx] END INSTALL"

	echo "[SCRIPT plex] BEGIN INSTALL"
	echo "[SCRIPT plex] source"
	echo -e "#PlexMediaServer\ndeb https://downloads.plex.tv/repo/deb ./public main" > /etc/apt/sources.list.d/old_plexmediaserver.list
	echo "[SCRIPT plex] curl key"
	curl https://downloads.plex.tv/plex-keys/PlexSign.key | apt-key add -
	echo "[SCRIPT plex] apt update"
	apt-get update
	echo "[SCRIPT plex] apt install plex"
	apt-get -y install plexmediaserver
	echo "[SCRIPT plex] service plex start"
	service plexmediaserver restart
	echo "[SCRIPT plex] END INSTALL"
EOF

for unixpass_idx in ${!unixpass[@]}; do
ssh $serverIP << EOF
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] BEGIN add user"
	useradd --shell /bin/bash --create-home ${users[$unixpass_idx]}
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] SET unix passwd"
	echo '${users[$unixpass_idx]}:${unixpass[$unixpass_idx]}' | chpasswd 
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] cp .rtorrent"
	cp /root/conf/.rtorrent.rc_${users[$unixpass_idx]} /home/${users[$unixpass_idx]}/.rtorrent.rc
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] mkdir filesys"
	mkdir /home/${users[$unixpass_idx]}/{torrents,perso,.session,watch}
	mkdir /home/${users[$unixpass_idx]}/torrents/{movies,series,musics}
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] chown and chmod"
	chown --recursive ${users[$unixpass_idx]}:${users[$unixpass_idx]} /home/${users[$unixpass_idx]}
	chmod 755 /home/${users[$unixpass_idx]}
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] htpasswd"
	htpasswd -b /etc/nginx/auth/$serverName_auth ${users[$unixpass_idx]} ${htpass[$unixpass_idx]}
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] chown and chmod for nginx"
	chmod 777 /etc/nginx/auth/$serverName_auth
	chown www-data:www-data /etc/nginx/auth/*
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] rutorrent config"
	mkdir /var/www/html/rutorrent/conf/users/${users[$unixpass_idx]}
	cp /root/conf/config.php_${users[$unixpass_idx]} /var/www/html/rutorrent/conf/users/${users[$unixpass_idx]}/config.php
	chown -R www-data:www-data /var/www/html
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] nginx restart"
	service nginx restart
	cp /root/conf/${users[$unixpass_idx]}-rtorrent /etc/init.d/
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] update service rtorrent"
	update-rc.d ${users[$unixpass_idx]}-rtorrent defaults
	echo "[SCRIPT CONF ${users[$unixpass_idx]}] start service rtorrent"
	service ${users[$unixpass_idx]}-rtorrent start
EOF
echo "PROCESS for ${users[$unixpass_idx]} done";
done

ssh $serverIP << EOF
	echo "[SCRIPT nginx] chow auth"
	chown www-data:www-data /etc/nginx/auth/*
	echo "[SCRIPT rtorrent] chow rtorrent"
	chown -R www-data:www-data /var/www/html
	echo "[SCRIPT nginx] service nginx restart"
	service nginx restart
EOF
