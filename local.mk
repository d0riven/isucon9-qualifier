# 現在のブランチをデプロイ対象にする
BRANCH := $(shell git name-rev --name-only HEAD)
hosts := isu01 isu02 isu03
# TODO: torb置き換え
app_path := /home/isucon/isucari/webapp

# mysql containerの名前
cname := isucon9q-mysql
# TODO: DB名置き換え
database := isucari

# checkoutとdeployは個別でやっておかないと変更前のmakefileで動いてしまうのでそこをいい感じにしたい
deploys := $(hosts:%=deploy/%)
deploy: $(deploys)
deploy/%:
	scp ./creds.mk isucon@$(@F):$(app_path)/creds.mk
	ssh $(@F) make -C $(app_path) checkout BRANCH=$(BRANCH)
	ssh $(@F) make -C $(app_path) deploy BRANCH=$(BRANCH)

specialize/_files: t = ''
specialize/_files: tt = $(t:_files/common/%=%)
specialize/_files:
	mkdir -p _files/isu0{1,2,3}/$(dir $(tt))
	cp _files/common/$(tt) _files/isu01/$(tt)
	cp _files/common/$(tt) _files/isu02/$(tt)
	cp _files/common/$(tt) _files/isu03/$(tt)

# TODO: database
.PHONY: mysql/con mysql/up mysql/down
mysql/con:
	docker exec -it $(cname) mysql -u root -ppass torb
mysql/run:
	docker run --name $(cname) \
		-e MYSQL_DATABASE=$(database) \
		-e MYSQL_ROOT_PASSWORD=pass \
		-e MYSQL_ALLOW_EMPTY_PASSWORD=yes \
		-p 13306:3306 -d \
		mysql:5.6 --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
mysql/start:
	docker start $(cname)
mysql/stop:
	docker stop $(cname)
mysql/rm:
	docker rm $(cname)

initialize: initialize.json
	curl -X POST 'https://isucon9.catatsuy.org/initialize' \
	  -H 'Content-Type: application/json' \
	  -d @initialize.json
initialize.json:
	echo '{\
	  "payment_service_url":"https://payment.isucon9q.catatsuy.org",\
	  "shipment_service_url":"https://shipment.isucon9q.catatsuy.org"\
	}' > $@
