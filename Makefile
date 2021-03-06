DB_TYPE     ?= sqlite3
DB_FILE     ?= learning-golang.db
DB_SOURCE   ?= $(PWD)/db/$(DB_FILE)
SERVER_PORT ?= 3000
GOARCH      := amd64
GOOS        := linux
CGO_ENABLED := 0
TAG         := latest
SEED_DATA_SOURCE := $(PWD)/db/seed.json
PROJECT := github.com/tjmaynes/learning-golang
REGISTRY_USERNAME := tjmaynes
IMAGE_NAME := learning-golang

install_dependencies:
	go get github.com/amacneil/dbmate@v1.6.0
	go get github.com/jstemmer/go-junit-report
	go get github.com/matryer/moq
	go get github.com/axw/gocov/gocov
	go get github.com/AlekSi/gocov-xml
	go get github.com/matm/gocov-html

generate_mocks:
	moq -out pkg/cart/repository_mock.go pkg/cart Repository

generate_seed_data:
	go run ./cmd/lggenseeddata \
	--seed-data-destination=$(SEED_DATA_SOURCE) \
	--item-count=100 \
	--manufacturer-count=5

test:
	DB_TYPE=$(DB_TYPE) \
	DB_SOURCE=$(DB_SOURCE) \
	SERVER_PORT=$(SERVER_PORT) \
	SEED_DATA_SOURCE=$(SEED_DATA_SOURCE) \
	go test -race -v -coverprofile=coverage.txt ./...

ci_test:
	make test 2>&1 | go-junit-report > report.xml
	gocov convert coverage.txt > coverage.json    
	gocov-xml < coverage.json > coverage.xml
	(mkdir -p coverage || true) && gocov-html < coverage.json > coverage/index.html

run_migrations:
	DATABASE_URL=sqlite:///$(DB_SOURCE) dbmate up

seed_db:
	go run ./cmd/lgseed \
	--db-type=$(DB_TYPE) \
	--db-source=$(DB_SOURCE) \
	--seed-data-source=$(SEED_DATA_SOURCE)

build_server:
	go build -o dist/lgserver ./cmd/lgserver

run_server: build_server
	DB_TYPE=$(DB_TYPE) \
	DB_SOURCE=$(DB_SOURCE) \
	SERVER_PORT=$(SERVER_PORT) \
	./dist/lgserver

build_image: guard-TAG
	docker build -t $(REGISTRY_USERNAME)/$(IMAGE_NAME):$(TAG) .

run_image:
	docker run --rm \
	 --env DB_TYPE=$(DB_TYPE) \
	 --env DB_SOURCE=/db/$(DB_FILE) \
	 --env SERVER_PORT=$(SERVER_PORT) \
	 --volume $(PWD)/db:/db \
	 --publish $(SERVER_PORT):$(SERVER_PORT) \
	 $(REGISTRY_USERNAME)/$(IMAGE_NAME):$(TAG)

push_image: guard-REGISTRY_PASSWORD guard-TAG
	docker login --username "$(REGISTRY_USERNAME)" --password "$(REGISTRY_PASSWORD)"
	docker push $(REGISTRY_USERNAME)/$(IMAGE_NAME):$(TAG)

clean:
	rm -rf dist/ vendor/ coverage* report.xml

guard-%:
	@ if [ "${${*}}" = "" ]; then \
		echo "Environment variable $* not set!"; \
		exit 1; \
	fi
