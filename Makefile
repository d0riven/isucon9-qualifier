include creds.mk

PHP_ROOT := /home/isucon/local/php
NR_APPNAME := isucon9-qualify
ULIMIT := 65536
NGINX_ERROR_LOG := /var/log/nginx/error.log

nr_install_path = $(PHP_ROOT)/bin/
nr_ini = $(PHP_ROOT)/etc/conf.d/newrelic.ini
hostname = $(shell hostname)
# TODO: dbnane置き換え
dbname := isucari

show:
	: $(NEWRELIC_LICENSE_KEY)
	: $(PATH)

.PHONY: deploy checkout composer systemctl/restart kparam/apply
# deploy: checkout composer _files/sync kparam/apply systemctl/restart systemctl/stop/$(hostname)
deploy: checkout composer _files/sync kparam/apply systemctl/restart
checkout: BRANCH := $(shell git name-rev --name-only HEAD)
checkout:
	git checkout ./ && git fetch && git checkout $(BRANCH) && git pull origin $(BRANCH)
composer:
	: $(MAKE) -C php deps
kparam/apply:
	sudo sysctl -p && sudo sysctl --system
	sudo -s bash -c 'ulimit -Hn $(ULIMIT) && sudo -s ulimit -Sn $(ULIMIT)'
systemctl/stop/isu01 systemctl/stop/isu02:
	sudo systemctl stop mysql
	sudo systemctl stop redis-server
systemctl/stop/isu03:
	sudo systemctl stop nginx
	sudo systemctl stop isubata.php
systemctl/restart:
	sudo systemctl daemon-reload
	sudo systemctl restart nginx
	sudo systemctl restart isucari.php
	sudo systemctl restart mysql
	# sudo systemctl restart redis-server
	# newrelic-daemonはsystemctlからいじると何故か起動しないためinit.d経由で起動している
	# そもそも自動起動モードで動かすべきでdaemonを動かす必要すらないらしい https://qiita.com/Ping/items/803085f1751a43abc04f
	# sudo /etc/init.d/newrelic-daemon restart

.PHONY: _files/add _files/sync
_files/add: t := ''
_files/add:
	mkdir -p _files/common$(dir $(abspath $(t)))
	cp $(abspath $(t)) _files/common$(abspath $(t))
	git add _files/common$(abspath $(t))

_files/sync:
	sudo rsync -av _files/common /
	# sudo rsync -av _files/$(hostname) /

kataribe/analyze: /tmp/kataribe.toml
	sudo cat /var/log/nginx/access.log | /tmp/kataribe  -f $<

mysql:
	mysql -u isucari -pisucari $(dbname)

redis:
	redis-cli -h localhost

taillog:
	sudo tailf $(NGINX_ERROR_LOG)

clean: newrelic/uninstall
newrelic/uninstall:
	sudo sh -c 'NR_INSTALL_KEY=$(NEWRELIC_LICENSE_KEY) NR_INSTALL_PATH=$(nr_install_path) NR_INSTALL_SILENT=true newrelic-install uninstall'
	sudo apt remove -y newrelic-php5
	sudo rm /etc/apt/sources.list.d/newrelic.list
	rm $(nr_ini)

.PHONY: init newrelic/install netdata/install kataribe/install pt-query-digest/install
init: update newrelic/install netdata/install kataribe/install pt-query-digest/install
update:
	sudo apt update
newrelic/install: /etc/init.d/newrelic-daemon
	# newrelicをインストールすると勝手にnewrelic-daemonが起動するが自動起動モードならそもそもnewrelic-daemonが動いている必要ないので止める
	sudo $< stop
	# アプリケーションを動かすユーザ(今回であればisucon:isucon)が書き込めないと自動起動できないので777にしてしまう
	sudo chmod -R 777 /var/log/newrelic
	# インストール時に勝手にrootで作られるがアプリケーションユーザで書き込めないと自動起動できないので消してしまう
	# これ順当にインストールできれば作られないかもなのでこの行は不要かも？
	-sudo rm /tmp/.newrelic.sock
/etc/init.d/newrelic-daemon: /etc/apt/sources.list.d/newrelic.list
	sudo apt update
	sudo apt install -y newrelic-php5
	sudo sh -c 'NR_INSTALL_KEY=$(NEWRELIC_LICENSE_KEY) NR_INSTALL_PATH=$(nr_install_path) NR_INSTALL_SILENT=true newrelic-install install'
	sed -i -e 's/newrelic.appname = \"PHP Application\"/newrelic.appname = \"$(NR_APPNAME)\"/g' $(nr_ini)
	sudo touch $@
/etc/apt/sources.list.d/newrelic.list:
	wget -O - https://download.newrelic.com/548C16BF.gpg | sudo apt-key add -
	sudo sh -c 'echo "deb http://apt.newrelic.com/debian/ newrelic non-free" | sudo tee $@'

# kickstart.sh経由だとnone zeroを返すので||trueを指定している
netdata/install: /lib/systemd/system/netdata.service
/lib/systemd/system/netdata.service: /tmp/kickstart.sh
	bash $< --dont-wait --non-interactive || true
/tmp/kickstart.sh:
	curl -Ssf https://my-netdata.io/kickstart.sh -o $@

# TODO: log_formatをkataribe用に変更する方法
kataribe/install: /tmp/kataribe.toml
# これは別で設定を使いまわしたいとかありそうなのであとからコピーとかでも良さそうではある
/tmp/kataribe.toml: /tmp/kataribe
	cd $(@D) && $< -generate
/tmp/kataribe: /tmp/linux_amd64.zip /usr/bin/unzip
	unzip $< $(@F) -d $(@D)
	# これをやらないと何度もこのターゲットを実行してしまう（zipファイル内の更新日時は変更されないため)
	touch $@
/tmp/linux_amd64.zip:
	curl -SsfL https://github.com/matsuu/kataribe/releases/download/v0.3.3/linux_amd64.zip -o $@
/usr/bin/unzip:
	sudo apt install unzip
	sudo touch $@

pt-query-digest/install: /usr/bin/pt-query-digest
/usr/bin/pt-query-digest: /tmp/percona-release_latest.$(shell lsb_release -sc)_all.deb
	sudo dpkg -i $<
	sudo apt -y update
	sudo apt -y install percona-toolkit
	sudo touch $@
/tmp/percona-release_latest.$(shell lsb_release -sc)_all.deb:
	wget -O $@ 'https://repo.percona.com/apt/percona-release_latest.$(shell lsb_release -sc)_all.deb'

mysql/upgrade: /tmp/mysql-apt-config_0.8.10-1_all.deb
	# これは場合によっては必要ないかもしれない
	sudo apt-key adv --keyserver keys.gnupg.net --recv-keys 8C718D3B5072E1F5
	# mysql
	sudo dpkg -i $< && sudo apt update
	# backup (TODO: ここらへんはもっと汎用的にかけるはず)
	sudo cp -r /var/lib/mysql ~/
	cp /etc/mysql/mysql.conf.d/mysqld.cnf ~/
	# 選択肢が出てくるの
	# mysql-serverはmysql8.0を選択すること
	# passwordの形式は互換性の観点から mysql_native_password にすること
	# 設定ファイルはdiffを確認しておくこと
	sudo apt -y install mysql-server
/tmp/mysql-apt-config_0.8.10-1_all.deb:
	wget -O $@ 'https://dev.mysql.com/get/mysql-apt-config_0.8.10-1_all.deb'

# 参考: https://www.server-world.info/query?os=Ubuntu_16.04&p=redis&f=9
php-redis/install: $(PHP_ROOT)/etc/conf.d/redis.ini
$(PHP_ROOT)/etc/conf.d/redis.ini:
	$(PHP_ROOT)/bin/pecl install redis
	echo 'extension=redis.so' > $@

redis/install: /lib/systemd/system/redis-server.service
/lib/systemd/system/redis-server.service:
	sudo apt -y install redis-server
	# pidを置くディレクトリが作られなくて起動時に怒られるので事前に作成。いい感じにできないものか
	#sudo mkdir -p /var/run/redis && sudo chown redis:redis /var/run/redis
	sudo touch $@
